#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Any


GITHUB_LATEST_RELEASE_API = "https://api.github.com/repos/oras-project/oras/releases/latest"
REGISTRY = "ghcr.io"
ARTIFACT_TYPE = "application/vnd.1c.dt"
MEDIA_TYPE = "application/octet-stream"

SCRIPT_DIR = Path(__file__).resolve().parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Push a .dt file to GHCR as an ORAS artifact."
    )
    parser.add_argument("file", type=Path, help="Path to the .dt file")
    return parser.parse_args()


def run_command(
    args: list[str],
    *,
    cwd: Path | None = None,
    input_text: str | None = None,
    capture_stdout: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE if capture_stdout else None,
        stderr=subprocess.PIPE if capture_stdout else None,
        check=True,
    )


def local_oras_path() -> Path:
    return SCRIPT_DIR / ("oras.exe" if platform.system() == "Windows" else "oras")


def platform_parts() -> tuple[str, str, str]:
    system_map = {
        "Windows": ("windows", ".zip"),
        "Linux": ("linux", ".tar.gz"),
        "Darwin": ("darwin", ".tar.gz"),
    }
    system = platform.system()
    if system not in system_map:
        raise RuntimeError(f"Unsupported OS for ORAS auto-download: {system}")

    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64"}:
        arch = "amd64"
    elif machine in {"arm64", "aarch64"}:
        arch = "arm64"
    else:
        raise RuntimeError(f"Unsupported CPU architecture for ORAS auto-download: {machine}")

    os_name, extension = system_map[system]
    return os_name, arch, extension


def request_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "push-dt"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def download_file(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "push-dt"})
    with urllib.request.urlopen(request, timeout=300) as response:
        with destination.open("wb") as output:
            shutil.copyfileobj(response, output)


def select_oras_asset(release: dict[str, Any]) -> dict[str, Any]:
    os_name, arch, extension = platform_parts()
    marker = f"_{os_name}_{arch}"

    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if marker in name and name.endswith(extension):
            return asset

    release_name = release.get("tag_name", "latest")
    raise RuntimeError(
        f"Cannot find ORAS {release_name} asset for {os_name}/{arch} in GitHub release."
    )


def extract_oras(archive: Path, destination: Path) -> None:
    destination_name = destination.name

    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zip_file:
            for member in zip_file.infolist():
                if Path(member.filename).name == destination_name:
                    with zip_file.open(member) as source, destination.open("wb") as output:
                        shutil.copyfileobj(source, output)
                    return
    elif archive.name.endswith(".tar.gz"):
        with tarfile.open(archive, "r:gz") as tar_file:
            for member in tar_file.getmembers():
                if Path(member.name).name == destination_name and member.isfile():
                    source = tar_file.extractfile(member)
                    if source is None:
                        continue
                    with source, destination.open("wb") as output:
                        shutil.copyfileobj(source, output)
                    destination.chmod(0o755)
                    return
    else:
        raise RuntimeError(f"Unsupported ORAS archive format: {archive.name}")

    raise RuntimeError(f"Cannot find {destination_name} inside {archive.name}.")


def ensure_oras() -> Path:
    oras = local_oras_path()
    if oras.exists():
        return oras

    print(f"{oras.name} not found next to the script. Downloading latest ORAS...")
    release = request_json(GITHUB_LATEST_RELEASE_API)
    asset = select_oras_asset(release)

    download_url = asset.get("browser_download_url")
    asset_name = asset.get("name")
    if not download_url or not asset_name:
        raise RuntimeError("GitHub release asset does not contain a download URL.")

    with tempfile.TemporaryDirectory(prefix="oras-download-") as temp_dir:
        archive = Path(temp_dir) / asset_name
        download_file(download_url, archive)
        extract_oras(archive, oras)

    print(f"Downloaded {asset_name} to {oras}")
    return oras


def read_ghcr_credentials() -> tuple[str, str]:
    try:
        result = run_command(
            ["docker-credential-desktop", "get"],
            input_text=REGISTRY,
            capture_stdout=True,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("docker-credential-desktop was not found in PATH.") from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        message = "Cannot read GHCR credentials from docker-credential-desktop."
        if stderr:
            message = f"{message} {stderr}"
        raise RuntimeError(message) from exc

    credentials = json.loads(result.stdout)
    username = credentials.get("Username")
    secret = credentials.get("Secret")
    if not username or not secret:
        raise RuntimeError("Docker credential helper returned incomplete GHCR credentials.")

    return username, secret


def push_dt(file_path: Path) -> str:
    file_path = file_path.expanduser().resolve()
    if not file_path.is_file():
        raise RuntimeError(f"File does not exist: {file_path}")

    oras = ensure_oras()
    owner, secret = read_ghcr_credentials()
    namespace = owner.lower()
    image_name = file_path.stem.lower()
    image = f"{REGISTRY}/{namespace}/{image_name}:latest"

    run_command(
        [str(oras), "login", REGISTRY, "--username", owner, "--password-stdin"],
        input_text=secret,
    )
    run_command(
        [
            str(oras),
            "push",
            image,
            "--artifact-type",
            ARTIFACT_TYPE,
            "--disable-path-validation",
            f"{file_path.name}:{MEDIA_TYPE}",
        ],
        cwd=file_path.parent,
    )

    return image


def main() -> int:
    args = parse_args()
    try:
        image = push_dt(args.file)
    except (RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    print(f"Pushed: {image}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
