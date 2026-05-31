#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None


ROOT = Path(__file__).resolve().parents[1]
IMAGES_YML = ROOT / "images.yml"
DEFAULT_REGISTRY = "ghcr.io/<org>"
LOCAL_DISTR = ROOT / "distr"
BUILD_CONTEXT_ROOT = ROOT / ".build-context"
PROFILES = ("edtcli", "ibcmd", "client")
PLATFORM_PROFILES = ("ibcmd", "client")
OSCRIPT_PROFILES = ("ibcmd", "client")


class RussianArgumentParser(argparse.ArgumentParser):
    def format_usage(self) -> str:
        return super().format_usage().replace("usage:", "использование:", 1)

    def format_help(self) -> str:
        return super().format_help().replace("usage:", "использование:", 1)

    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(2, f"{self.prog}: ошибка: {message}\n")


class CompactHelpFormatter(argparse.RawDescriptionHelpFormatter):
    def __init__(self, prog: str):
        super().__init__(prog, max_help_position=36, width=120)


def load_manifest() -> dict[str, Any]:
    if yaml is not None:
        return yaml.safe_load(IMAGES_YML.read_text(encoding="utf-8"))

    raise SystemExit("PyYAML is required. Install it or run with Python environment that includes yaml.")


def image_name(manifest: dict[str, Any], profile: str, edt_version: str | None, platform_version: str | None) -> str:
    defaults = manifest["defaults"]
    template = manifest["profiles"][profile]["image"]
    return template.format(
        registry=resolve_registry(defaults["registry"]),
        revision=defaults["revision"],
        edt_version=edt_version or "",
        platform_version=platform_version or "",
    )


def git_remote_owner() -> str | None:
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

    remote = result.stdout.strip()
    patterns = [
        r"github\.com[:/](?P<owner>[^/]+)/[^/]+(?:\.git)?$",
        r"ghcr\.io/(?P<owner>[^/]+)/",
    ]
    for pattern in patterns:
        match = re.search(pattern, remote, flags=re.IGNORECASE)
        if match:
            return match.group("owner").lower()
    return None


def resolve_registry(default_registry: str = DEFAULT_REGISTRY) -> str:
    explicit = os.environ.get("IMAGE_REGISTRY")
    if explicit:
        return explicit.rstrip("/").lower()

    if "<org>" not in default_registry:
        return default_registry.rstrip("/").lower()

    owner = os.environ.get("GITHUB_REPOSITORY_OWNER") or git_remote_owner()
    if owner:
        return f"ghcr.io/{owner.lower()}"

    return default_registry


def run(command: list[str], *, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def local_distribution_patterns(profile: str, version: str) -> list[str]:
    version_underscores = version.replace(".", "_")
    if profile == "edtcli":
        return [f"1c_edt_distr_offline_{version}_*_linux_x86_64.tar.gz"]
    if profile == "ibcmd":
        return [
            f"deb64_{version_underscores}_*.zip",
            f"deb64_{version_underscores}_*.tar.gz",
            f"setup-full-{version}-x86_64.run",
            f"setup-full-{version}.*-x86_64.run",
        ]
    if profile == "client":
        return [
            f"client_{version_underscores}_*.deb64.zip",
            f"client_{version_underscores}_*.deb64.tar.gz",
            f"client_{version_underscores}.deb64.zip",
            f"client_{version_underscores}.deb64.tar.gz",
        ]
    raise ValueError(f"Unsupported profile: {profile}")


def prepare_distr_context(profile: str, edt_version: str | None, platform_version: str | None) -> Path:
    version = edt_version if profile == "edtcli" else platform_version
    if not version:
        raise ValueError(f"Version is required for {profile}")

    matches: list[Path] = []
    for pattern in local_distribution_patterns(profile, version):
        matches.extend(path for path in LOCAL_DISTR.glob(pattern) if path.is_file())

    if not matches:
        patterns = ", ".join(local_distribution_patterns(profile, version))
        raise SystemExit(
            f"Local distribution for {profile} {version} was not found in {LOCAL_DISTR}. "
            f"Download it before building. Expected patterns: {patterns}"
        )

    source = sorted(matches, key=lambda path: path.name)[-1]
    target_dir = BUILD_CONTEXT_ROOT / "distr" / profile
    if target_dir.exists():
        shutil.rmtree(target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / source.name
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)
    return target_dir


def link_or_copy(source: Path, target: Path) -> None:
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def ensure_oscript_archive() -> Path:
    existing = sorted(LOCAL_DISTR.glob("OneScript-*-linux-x64.zip"), key=lambda path: path.name)
    if existing:
        return existing[-1]

    raise SystemExit(
        f"OneScript linux x64 distribution was not found in {LOCAL_DISTR}. "
        "Download OneScript-<version>-linux-x64.zip before building ibcmd/client."
    )


def prepare_oscript_context() -> Path:
    source = ensure_oscript_archive()
    target_dir = BUILD_CONTEXT_ROOT / "oscript"
    if target_dir.exists():
        shutil.rmtree(target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    link_or_copy(source, target_dir / source.name)
    return target_dir


def build(args: argparse.Namespace) -> str:
    manifest = load_manifest()
    profile = args.profile

    if profile == "edtcli":
        if not args.version:
            raise SystemExit("EDT version is required. Use edtcli:<version>.")
        if not args.edt_platform_support:
            raise SystemExit("--edt-platform-support is required for edtcli.")
        edt_version = args.version
        platform_version = None
    elif profile in PLATFORM_PROFILES:
        if not args.version:
            raise SystemExit(f"Platform version is required. Use {profile}:<version>.")
        edt_version = None
        platform_version = args.version
    else:
        raise SystemExit(f"Unsupported profile: {profile}")

    image = args.image or image_name(manifest, profile, edt_version, platform_version)
    local_image = args.local_tag or f"{profile}:latest"
    use_local_tag = args.local and not args.push
    distr_context = (
        prepare_distr_context(profile, edt_version, platform_version).relative_to(ROOT).as_posix()
        if profile in ("edtcli", *PLATFORM_PROFILES)
        else None
    )
    oscript_context = prepare_oscript_context().relative_to(ROOT).as_posix() if profile in OSCRIPT_PROFILES else None

    command = [
        "docker",
        "buildx",
        "build",
        "--platform",
        manifest["defaults"].get("platform", "linux/amd64"),
        "--provenance=false",
        "--file",
        "docker/Dockerfile",
    ]
    if distr_context:
        command.extend(["--build-context", f"distr={distr_context}"])
    if oscript_context:
        command.extend(["--build-context", f"oscript={oscript_context}"])

    command.extend([
        "--target",
        profile,
        "--build-arg",
        f"REVISION={manifest['defaults']['revision']}",
        "--tag",
        local_image if use_local_tag else image,
    ])

    if edt_version:
        command.extend(["--build-arg", f"EDT_VERSION={edt_version}"])
        command.extend(["--build-arg", f"EDT_PLATFORM_SUPPORT={args.edt_platform_support}"])
    if platform_version:
        command.extend(["--build-arg", f"PLATFORM_VERSION={platform_version}"])
    if args.no_cache:
        command.append("--no-cache")

    if args.push:
        command.append("--push")
    else:
        command.append("--load")

    command.append(".")

    env = os.environ.copy()
    env["DOCKER_BUILDKIT"] = "1"
    env["BUILDKIT_PROGRESS"] = args.progress
    run(command, env=env)

    return local_image if use_local_tag else image


def resolve(args: argparse.Namespace) -> str:
    manifest = load_manifest()
    edt_version = args.version if args.profile == "edtcli" else None
    platform_version = args.version if args.profile in PLATFORM_PROFILES else None
    return image_name(manifest, args.profile, edt_version, platform_version)


def apply_target(args: argparse.Namespace, parser: argparse.ArgumentParser) -> None:
    if not args.target:
        parser.error("target обязателен, например edtcli:2025.2.6")
    if ":" not in args.target:
        parser.error("target должен быть в формате <profile>:<version>, например edtcli:2025.2.6")
    profile, version = args.target.split(":", 1)
    if profile not in PROFILES:
        parser.error(f"неподдерживаемый profile в target: {profile}. Доступны: {', '.join(PROFILES)}")
    if not version:
        parser.error("version в target не должна быть пустой")
    args.profile = profile
    args.version = version


def parse_args() -> argparse.Namespace:
    parser = RussianArgumentParser(
        description="Сборка Docker-образов 1C CI локально или с публикацией в GHCR.",
        add_help=False,
        formatter_class=CompactHelpFormatter,
    )
    parser._positionals.title = "позиционные аргументы"
    parser._optionals.title = "опции"
    parser.add_argument("-h", "--help", action="help", help="Показать справку и выйти.")
    parser.add_argument(
        "target",
        help="Цель: edtcli:<edt-version>, ibcmd:<platform-version> или client:<platform-version>.",
    )
    parser.add_argument("--image", help="Имя registry-образа вместо images.yml.")
    parser.add_argument("--registry", help="Registry, например ghcr.io/my-org.")
    parser.add_argument("--local-tag", help="Локальный тег вместо <profile>:latest.")
    parser.add_argument(
        "--local",
        action="store_true",
        default=True,
        help="Собрать локально; включено по умолчанию.",
    )
    parser.add_argument("--push", action="store_true", help="Опубликовать в registry.")
    parser.add_argument(
        "--edt-platform-support",
        metavar="VERSION",
        help="[edtcli] Минимальная версия поддержки платформы 1С.",
    )
    parser.add_argument("--no-cache", action="store_true", help="Собрать без кеша Docker.")
    parser.add_argument("--progress", default="plain", choices=["auto", "plain", "tty"], help="Вывод buildx.")
    parser.add_argument("--print-image", action="store_true", help="Вывести имя registry-образа и выйти.")
    args = parser.parse_args()
    apply_target(args, parser)
    return args


def main() -> None:
    started = dt.datetime.now(dt.UTC)
    args = parse_args()
    if args.registry:
        os.environ["IMAGE_REGISTRY"] = args.registry
    if args.print_image:
        print(resolve(args))
        return
    image = build(args)
    elapsed = dt.datetime.now(dt.UTC) - started
    print(f"Built {image} in {elapsed}.", flush=True)


if __name__ == "__main__":
    main()
