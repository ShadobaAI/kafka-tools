#!/usr/bin/env python3
from __future__ import annotations

import argparse
import email.message
import html
import http.cookiejar
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import BinaryIO


RELEASES_BASE = "https://releases.1c.ru"
LOCAL_DISTR = Path("/distr")
CHUNK_SIZE = 1024 * 1024
REQUEST_TIMEOUT = 600
UNSUPPORTED_PLATFORM_ARCH_RE = re.compile(r"(^|[._\-\s])(arm|arm64|aarch64)([._\-\s]|$)", re.IGNORECASE)


class AnchorParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.anchors: list[tuple[str, str]] = []
        self._href: str | None = None
        self._parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        attr = dict(attrs)
        self._href = attr.get("href") or ""
        self._parts = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a" or self._href is None:
            return
        text = " ".join("".join(self._parts).split())
        self.anchors.append((self._href, html.unescape(text)))
        self._href = None
        self._parts = []


class ReleasesClient:
    def __init__(self, username: str, password: str) -> None:
        self.username = username
        self.password = password
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookie_jar))

    def request(self, url: str, *, data: bytes | None = None, headers: dict[str, str] | None = None):
        request_headers = {
            "User-Agent": "onec-ci-image-downloader/1.0",
            "Accept-Language": "ru,en;q=0.8",
        }
        if headers:
            request_headers.update(headers)
        request = urllib.request.Request(url, data=data, headers=request_headers)
        return self.opener.open(request, timeout=REQUEST_TIMEOUT)

    def get_text(self, url: str) -> tuple[str, str]:
        with self.request(url) as response:
            final_url = response.geturl()
            payload = response.read()
            charset = response.headers.get_content_charset()
        return final_url, decode_page(payload, charset)

    def get_authenticated_text(self, url: str) -> tuple[str, str]:
        final_url, text = self.get_text(url)
        if needs_login(final_url, text):
            final_url, text = self.login(final_url, text)
            if needs_login(final_url, text):
                raise RuntimeError("releases.1c.ru authentication failed")
            if not same_release_page(final_url, url):
                final_url, text = self.get_text(url)
        return final_url, text

    def login(self, login_url: str, login_page: str) -> tuple[str, str]:
        execution = required_input_value(login_page, "execution")
        post_data = urllib.parse.urlencode(
            {
                "inviteCode": "",
                "username": self.username,
                "password": self.password,
                "execution": execution,
                "_eventId": "submit",
                "geolocation": "",
                "submit": "Войти",
                "rememberMe": "on",
            }
        ).encode("utf-8")
        try:
            with self.request(
                login_url,
                data=post_data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            ) as response:
                final_url = response.geturl()
                payload = response.read()
                charset = response.headers.get_content_charset()
        except urllib.error.HTTPError as error:
            if error.code in {401, 403}:
                raise RuntimeError(
                    "releases.1c.ru authentication failed. Check ONEC_USERNAME/ONEC_PASSWORD "
                    "and make sure the password was quoted correctly in the shell."
                ) from error
            raise
        return final_url, decode_page(payload, charset)


def decode_page(payload: bytes, charset: str | None) -> str:
    encodings = [charset, "utf-8", "cp1251"]
    for encoding in encodings:
        if not encoding:
            continue
        try:
            return payload.decode(encoding)
        except UnicodeDecodeError:
            pass
    return payload.decode("utf-8", errors="replace")


def needs_login(url: str, text: str) -> bool:
    return "login.1c.ru/login" in url or 'name="execution"' in text or "id=\"loginForm\"" in text


def same_release_page(left: str, right: str) -> bool:
    return urllib.parse.urlparse(left).path == urllib.parse.urlparse(right).path


def required_input_value(text: str, name: str) -> str:
    pattern = rf'<input\b[^>]*\bname=["\']{re.escape(name)}["\'][^>]*\bvalue=["\']([^"\']+)["\']'
    match = re.search(pattern, text, flags=re.IGNORECASE)
    if not match:
        raise RuntimeError(f"login form field {name!r} was not found")
    return html.unescape(match.group(1))


def parse_anchors(text: str) -> list[tuple[str, str]]:
    parser = AnchorParser()
    parser.feed(text)
    return parser.anchors


def read_secret(*names: str) -> str | None:
    for name in names:
        path = Path("/run/secrets") / name
        if path.exists():
            value = path.read_text(encoding="utf-8").strip()
            if value:
                return value
        env_name = name.upper()
        value = os.environ.get(env_name)
        if value:
            return value.strip()
    return None


def local_candidates(kind: str, version: str) -> list[Path]:
    version_underscores = version.replace(".", "_")
    patterns: list[str]
    if kind == "edt":
        patterns = [f"1c_edt_distr_offline_{version}_*_linux_x86_64.tar.gz"]
    else:
        patterns = [f"setup-full-{version}-x86_64.run", f"setup-full-{version}.*-x86_64.run"]
        if kind == "platform":
            patterns.extend(
                [
                    f"server64_{version_underscores}.zip",
                    f"server64_{version_underscores}.tar.gz",
                    f"server64_{version_underscores}_*.zip",
                    f"server64_{version_underscores}_*.tar.gz",
                ]
            )
        elif kind == "platform-server":
            patterns.extend(
                [
                    f"deb64_{version_underscores}_*.zip",
                    f"deb64_{version_underscores}_*.tar.gz",
                    f"server_{version_underscores}_*.deb64.zip",
                    f"server_{version_underscores}_*.deb64.tar.gz",
                ]
            )
        else:
            patterns.extend(
                [
                    f"client_{version_underscores}_*.deb64.zip",
                    f"client_{version_underscores}_*.deb64.tar.gz",
                ]
            )
    result: list[Path] = []
    if LOCAL_DISTR.exists():
        for pattern in patterns:
            result.extend(
                candidate
                for candidate in sorted(LOCAL_DISTR.glob(pattern))
                if kind == "edt" or not is_unsupported_platform_arch(candidate.name)
            )
    return result


def is_unsupported_platform_arch(value: str) -> bool:
    return bool(UNSUPPORTED_PLATFORM_ARCH_RE.search(value))


def copy_local(kind: str, version: str, destination: Path) -> bool:
    candidates = local_candidates(kind, version)
    if not candidates:
        return False
    destination.mkdir(parents=True, exist_ok=True)
    source = candidates[-1]
    target = destination / source.name
    shutil.copy2(source, target)
    print(f"Using local distribution cache: {source.name}", flush=True)
    return True


def platform_nick(version: str) -> str:
    parts = version.split(".")
    if len(parts) < 2:
        raise RuntimeError(f"Platform version must start with major.minor: {version}")
    return f"Platform{parts[0]}{parts[1]}"


def release_nick(kind: str, version: str) -> str:
    if kind == "edt":
        return "DevelopmentTools10"
    return platform_nick(version)


def version_files_url(nick: str, version: str) -> str:
    query = urllib.parse.urlencode({"nick": nick, "ver": version})
    return f"{RELEASES_BASE}/version_files?{query}"


def project_url(nick: str) -> str:
    return f"{RELEASES_BASE}/project/{urllib.parse.quote(nick)}"


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def resolve_exact_version(client: ReleasesClient, nick: str, requested: str) -> str:
    if len(requested.split(".")) >= 4:
        return requested

    _, text = client.get_authenticated_text(project_url(nick))
    versions: set[str] = set()
    for href, _label in parse_anchors(text):
        parsed = urllib.parse.urlparse(urllib.parse.urljoin(RELEASES_BASE, href))
        if parsed.path != "/version_files":
            continue
        query = urllib.parse.parse_qs(parsed.query)
        if query.get("nick", [""])[0] != nick:
            continue
        version = query.get("ver", [""])[0]
        if version == requested or version.startswith(f"{requested}."):
            versions.add(version)

    versions.update(
        match.group(0)
        for match in re.finditer(rf"\b{re.escape(requested)}\.\d+\b", text)
    )

    if not versions:
        raise RuntimeError(
            f"Could not resolve {requested} to an exact {requested}.x release on releases.1c.ru. "
            f"Use an exact platform version or check account access to {project_url(nick)}."
        )
    exact = sorted(versions, key=version_key)[-1]
    if exact != requested:
        print(f"Resolved platform version {requested} -> {exact}", flush=True)
    return exact


def distribution_score(kind: str, label: str) -> int:
    normalized = label.lower()
    if "windows" in normalized or "rpm" in normalized or "macos" in normalized or "os x" in normalized:
        return -1
    if kind.startswith("platform") and is_unsupported_platform_arch(normalized):
        return -1

    if kind == "edt":
        patterns = [
            r"оффлайн.*1c:edt.*linux.*64",
            r"offline.*1c:edt.*linux.*64",
            r"1c:edt.*linux.*без интернета",
            r"1c:edt.*linux.*64",
            r"edt.*linux.*64",
        ]
    elif kind == "platform":
        patterns = [
            r"технологическая платформа.*1с:предприятия.*\(64-bit\).*linux",
            r"технологическая платформа.*1c:enterprise.*\(64-bit\).*linux",
            r"технологическая платформа.*64-bit.*linux",
            r"server64.*linux",
            r"server64",
        ]
    elif kind == "platform-server":
        patterns = [
            r"сервер.*1с:предприятия.*64-bit.*deb-based linux",
            r"сервер.*1c:enterprise.*64-bit.*deb-based linux",
            r"server.*x86[_-]?64.*linux",
            r"server.*64-bit.*deb-based linux",
            r"server.*64.*linux",
            r"сервер.*64.*linux",
        ]
    else:
        patterns = [
            r"клиент.*1с:предприятия.*64-bit.*deb-based linux",
            r"клиент.*1c:enterprise.*64-bit.*deb-based linux",
            r"client.*x86[_-]?64.*linux",
            r"client.*64-bit.*deb-based linux",
            r"client.*64.*linux",
            r"тонкий клиент.*64.*linux",
        ]

    for index, pattern in enumerate(patterns):
        if re.search(pattern, normalized, flags=re.IGNORECASE):
            return len(patterns) - index
    return -1


def find_distribution_page(kind: str, version_url: str, page_text: str) -> str:
    candidates: list[tuple[int, str, str]] = []
    for href, label in parse_anchors(page_text):
        score = distribution_score(kind, f"{label} {href}")
        if score >= 0:
            candidates.append((score, href, label))

    if not candidates:
        labels = [label for _href, label in parse_anchors(page_text) if label][:40]
        print("Available distributions:", file=sys.stderr)
        for label in labels:
            print(f"  - {label}", file=sys.stderr)
        raise RuntimeError(f"Linux distribution for {kind} was not found")

    score, href, label = sorted(candidates, key=lambda item: item[0])[-1]
    url = urllib.parse.urljoin(version_url, href)
    print(f"Selected distribution: {label}", flush=True)
    return url


def find_download_url(distribution_url: str, page_text: str) -> str:
    anchors = parse_anchors(page_text)
    for href, label in anchors:
        if "скачать дистрибутив" in label.lower():
            return urllib.parse.urljoin(distribution_url, href)
    for href, _label in anchors:
        if "/public/file/get/" in href or "/file/get/" in href:
            return urllib.parse.urljoin(distribution_url, href)
    raise RuntimeError("download link was not found on distribution page")


def filename_from_response(url: str, headers: email.message.Message, fallback: str) -> str:
    disposition = headers.get("Content-Disposition", "")
    match = re.search(r"filename\*=UTF-8''([^;]+)", disposition, flags=re.IGNORECASE)
    if match:
        return Path(urllib.parse.unquote(match.group(1))).name
    match = re.search(r'filename="?([^";]+)"?', disposition, flags=re.IGNORECASE)
    if match:
        return Path(match.group(1)).name
    path_name = Path(urllib.parse.urlparse(url).path).name
    return path_name or fallback


def stream_response(response: BinaryIO, target: Path) -> None:
    part = target.with_suffix(target.suffix + ".part")
    with part.open("wb") as output:
        while True:
            chunk = response.read(CHUNK_SIZE)
            if not chunk:
                break
            output.write(chunk)
    part.replace(target)


def download_url(client: ReleasesClient, url: str, destination: Path, fallback: str) -> Path:
    destination.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(1, 4):
        try:
            with client.request(url) as response:
                filename = filename_from_response(response.geturl(), response.headers, fallback)
                target = destination / filename
                stream_response(response, target)
                print(f"Downloaded: {target.name}", flush=True)
                return target
        except (OSError, urllib.error.URLError) as error:
            last_error = error
            print(f"Download attempt {attempt} failed: {error}", file=sys.stderr, flush=True)
            time.sleep(attempt * 3)
    raise RuntimeError(f"download failed: {last_error}")


def download_from_releases(kind: str, requested_version: str, destination: Path) -> None:
    username = read_secret("onec_user", "onec_username")
    password = read_secret("onec_password")
    if not username or not password:
        raise RuntimeError("ONEC_USERNAME/ONEC_USER and ONEC_PASSWORD secrets are required")

    client = ReleasesClient(username, password)
    nick = release_nick(kind, requested_version)
    version = resolve_exact_version(client, nick, requested_version) if kind.startswith("platform") else requested_version
    files_url = version_files_url(nick, version)
    final_url, page_text = client.get_authenticated_text(files_url)
    distribution_url = find_distribution_page(kind, final_url, page_text)
    final_distribution_url, distribution_text = client.get_authenticated_text(distribution_url)
    file_url = find_download_url(final_distribution_url, distribution_text)
    fallback = (
        f"1c_edt_distr_offline_{version}_linux_x86_64.tar.gz"
        if kind == "edt"
        else f"setup-full-{version}-x86_64.run"
    )
    download_url(client, file_url, destination, fallback)


def normalize_kind(kind: str) -> str:
    return kind


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download 1C distributions.")
    parser.add_argument("kind", choices=["edt", "platform", "platform-server", "platform-client"])
    parser.add_argument("version")
    parser.add_argument("destination", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    kind = normalize_kind(args.kind)
    local_kind = "edt" if kind == "edt" else "platform"
    if copy_local(local_kind, args.version, args.destination):
        return
    if kind == "edt":
        download_from_releases(kind, args.version, args.destination)
        return
    download_from_releases(kind, args.version, args.destination)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 - build logs need a concise failure reason.
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
