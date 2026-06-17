#!/usr/bin/env python3
from __future__ import annotations

import argparse
import email.message
import html
import http.cookiejar
import json
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
OSCRIPT_BASE = "https://oscript.io"
COVERAGE41C_BASE = "https://github.com/1c-syntax/Coverage41C"
# Исторически локальный кэш проверяется в /distr. В CI рабочий каталог может
# отличаться, поэтому не смешиваем этот путь с destination для новых загрузок.
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


class InputParser(HTMLParser):
    # Атрибуты HTML не имеют гарантированного порядка, поэтому поле login form
    # читаем парсером, а не регулярным выражением по сырой строке.
    def __init__(self, name: str) -> None:
        super().__init__(convert_charrefs=True)
        self.name = name
        self.value: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "input":
            return
        attr = dict(attrs)
        if attr.get("name") == self.name and self.value is None:
            self.value = attr.get("value") or ""


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
        # releases.1c.ru может сначала вернуть страницу login. После успешного
        # входа повторно читаем исходную страницу дистрибутива.
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
                    "releases.1c.ru authentication failed. Check RELEASES_ONEC_USERNAME/RELEASES_ONEC_PASSWORD "
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
    # Для releases.1c.ru параметры query определяют конкретный файл/версию.
    # Одного path недостаточно: /version_file с другим query уже другая страница.
    left_parsed = urllib.parse.urlparse(left)
    right_parsed = urllib.parse.urlparse(right)
    return (
        left_parsed.path == right_parsed.path
        and urllib.parse.parse_qsl(left_parsed.query, keep_blank_values=True)
        == urllib.parse.parse_qsl(right_parsed.query, keep_blank_values=True)
    )


def required_input_value(text: str, name: str) -> str:
    parser = InputParser(name)
    parser.feed(text)
    if parser.value is None:
        raise RuntimeError(f"login form field {name!r} was not found")
    return parser.value


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


def local_candidates(kind: str, version: str, *roots: Path) -> list[Path]:
    version_underscores = version.replace(".", "_")
    patterns: list[str]
    if kind == "edt":
        patterns = [f"1c_edt_distr_offline_{version}_*_linux_x86_64.tar.gz"]
    elif kind == "oscript":
        patterns = ["OneScript-*-linux-x64.zip"] if version == "latest" else [f"OneScript-{version}-linux-x64.zip"]
    elif kind == "coverage41c":
        patterns = ["Coverage41C-*.zip"] if version == "latest" else [f"Coverage41C-{version}.zip"]
    else:
        if kind == "platform":
            # Короткая версия 8.3.27 в локальном кэше соответствует любому
            # полному релизу 8.3.27.x, например server64_8_3_27_2214.zip.
            if len(version.split(".")) >= 4:
                patterns = [f"server64_{version_underscores}.zip"]
            else:
                patterns = [f"server64_{version_underscores}_*.zip"]
        elif kind == "platform-server":
            # Для server-дистрибутива схема такая же: deb64_8_3_27_2214.zip
            # должен подходить под запрос короткой версии 8.3.27.
            if len(version.split(".")) >= 4:
                patterns = [f"deb64_{version_underscores}.zip"]
            else:
                patterns = [f"deb64_{version_underscores}_*.zip"]
        else:
            raise ValueError(f"Unsupported distribution kind: {kind}")
    result: list[Path] = []
    for root in roots or (LOCAL_DISTR,):
        if not root.exists():
            continue
        for pattern in patterns:
            result.extend(
                candidate
                for candidate in sorted(root.glob(pattern))
                if kind == "edt" or not is_unsupported_platform_arch(candidate.name)
            )
    return result


def is_unsupported_platform_arch(value: str) -> bool:
    return bool(UNSUPPORTED_PLATFORM_ARCH_RE.search(value))


def copy_local(kind: str, version: str, destination: Path) -> bool:
    # Повторный запуск должен видеть уже скачанный файл в destination,
    # а /distr остается внешним read-only кэшем для CI/локальных сборок.
    destination.mkdir(parents=True, exist_ok=True)
    candidates = local_candidates(kind, version, destination, LOCAL_DISTR)
    if not candidates:
        return False
    source = candidates[-1]
    target = destination / source.name
    if source.resolve() != target.resolve():
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


def oscript_archive_token(version: str) -> str:
    # API oscript.io использует token архива с подчеркиваниями: 2.0.2 -> 2_0_2.
    # latest оставляем как есть, потому что это отдельный стабильный endpoint.
    if version == "latest":
        return version
    return version.replace(".", "_")


def download_oscript(version_token: str, destination: Path) -> None:
    archive_token = oscript_archive_token(version_token)
    archive_url = f"{OSCRIPT_BASE}/api/archive/{urllib.parse.quote(archive_token)}"
    request = urllib.request.Request(
        archive_url,
        headers={
            "User-Agent": "onec-ci-image-downloader/1.0",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        files = json.loads(response.read().decode("utf-8"))

    for item in files:
        filename = item.get("filename", "")
        if item.get("id") == "scd-lin" and item.get("arch") == "x64" and filename.endswith("-linux-x64.zip"):
            url = item.get("link")
            if not url:
                continue
            client = ReleasesClient("", "")
            download_url(client, urllib.parse.urljoin(OSCRIPT_BASE, url), destination, filename)
            return

    names = ", ".join(item.get("filename", "") for item in files if item.get("filename"))
    raise RuntimeError(f"OneScript linux x64 distribution was not found in {archive_url}. Available files: {names}")


def download_coverage41c(version: str, destination: Path) -> None:
    if version == "latest":
        api_url = "https://api.github.com/repos/1c-syntax/Coverage41C/releases/latest"
        request = urllib.request.Request(
            api_url,
            headers={
                "User-Agent": "onec-ci-image-downloader/1.0",
                "Accept": "application/vnd.github+json",
            },
        )
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            release = json.loads(response.read().decode("utf-8"))

        for asset in release.get("assets", []):
            filename = asset.get("name", "")
            url = asset.get("browser_download_url", "")
            if filename.startswith("Coverage41C-") and filename.endswith(".zip") and url:
                client = ReleasesClient("", "")
                download_url(client, url, destination, filename)
                return

        names = ", ".join(asset.get("name", "") for asset in release.get("assets", []) if asset.get("name"))
        raise RuntimeError(f"Coverage41C zip asset was not found in latest release. Available files: {names}")

    filename = f"Coverage41C-{version}.zip"
    url = f"{COVERAGE41C_BASE}/releases/download/v{urllib.parse.quote(version)}/{filename}"
    client = ReleasesClient("", "")
    download_url(client, url, destination, filename)


def version_files_url(nick: str, version: str) -> str:
    query = urllib.parse.urlencode({"nick": nick, "ver": version})
    return f"{RELEASES_BASE}/version_files?{query}"


def version_file_url(nick: str, version: str, filename: str) -> str:
    version_path = version.replace(".", "_")
    query = urllib.parse.urlencode(
        {
            "nick": nick,
            "ver": version,
            "path": f"Platform\\{version_path}\\{filename}",
        }
    )
    return f"{RELEASES_BASE}/version_file?{query}"


def distribution_filename(kind: str, version: str) -> str:
    version_path = version.replace(".", "_")
    if kind == "platform":
        return f"server64_{version_path}.zip"
    if kind == "platform-server":
        return f"deb64_{version_path}.zip"
    raise ValueError(f"Unsupported distribution kind: {kind}")


def distribution_url(kind: str, nick: str, version: str, filename: str) -> str:
    return version_file_url(nick, version, filename)


def find_edt_distribution_page(version_url: str, page_text: str, version: str) -> tuple[str, str]:
    pattern = re.compile(
        rf"1c_edt_distr_offline_{re.escape(version)}_\d+_linux_x86_64\.tar\.gz",
        flags=re.IGNORECASE,
    )
    available: set[str] = set()
    for href, label in parse_anchors(page_text):
        text = urllib.parse.unquote(f"{label} {href}")
        available.update(
            match.group(0)
            for match in re.finditer(r"1c_edt_distr[^\s\"'<>]*linux_x86_64\.tar\.gz", text, flags=re.IGNORECASE)
        )
        match = pattern.search(text)
        if match:
            filename = match.group(0)
            return urllib.parse.urljoin(version_url, href), filename
    if available:
        names = ", ".join(sorted(available))
        raise RuntimeError(f"EDT offline Linux x86_64 distribution for {version} was not found. Available: {names}")
    raise RuntimeError(f"EDT offline Linux x86_64 distribution for {version} was not found")


def project_url(nick: str) -> str:
    return f"{RELEASES_BASE}/project/{urllib.parse.quote(nick)}?allUpdates=true"


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def resolve_exact_version(client: ReleasesClient, nick: str, requested: str) -> str:
    # Для platform допускаем короткую версию вида 8.3.27 и разворачиваем ее
    # в последний доступный полный релиз 8.3.27.x на releases.1c.ru.
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
    # Пишем через .part, чтобы оборванная загрузка не выглядела готовым архивом.
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
    # Это учетная запись только для releases.1c.ru. Developer credentials для
    # license activation не должны попадать в build и передаются уже в runtime.
    username = read_secret("releases_onec_username", "releases_onec_user", "onec_user", "onec_username")
    password = read_secret("releases_onec_password", "onec_password")
    if not username or not password:
        raise RuntimeError("RELEASES_ONEC_USERNAME and RELEASES_ONEC_PASSWORD secrets are required")

    client = ReleasesClient(username, password)
    nick = release_nick(kind, requested_version)
    version = resolve_exact_version(client, nick, requested_version) if kind.startswith("platform") else requested_version
    if kind == "edt":
        files_url = version_files_url(nick, version)
        final_url, page_text = client.get_authenticated_text(files_url)
        distribution_url_value, filename = find_edt_distribution_page(final_url, page_text, version)
    else:
        filename = distribution_filename(kind, version)
        distribution_url_value = distribution_url(kind, nick, version, filename)
    print(f"Selected distribution: {filename}", flush=True)
    final_distribution_url, distribution_text = client.get_authenticated_text(distribution_url_value)
    file_url = find_download_url(final_distribution_url, distribution_text)
    download_url(client, file_url, destination, filename)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download 1C distributions.")
    parser.add_argument("kind", choices=["edt", "platform", "platform-server", "oscript", "coverage41c"])
    parser.add_argument("version")
    parser.add_argument("destination", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    kind = args.kind
    # Перед сетевой загрузкой пробуем локальный кэш: это ускоряет локальные
    # сборки и позволяет запускать build без повторной авторизации на 1C.
    if copy_local(kind, args.version, args.destination):
        return
    if kind == "oscript":
        download_oscript(args.version, args.destination)
        return
    if kind == "coverage41c":
        download_coverage41c(args.version, args.destination)
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
