#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import os
import re
import subprocess

import yaml


ROOT = Path(__file__).resolve().parents[1]


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

    match = re.search(r"github\.com[:/]([^/]+)/[^/]+(?:\.git)?$", result.stdout.strip(), flags=re.IGNORECASE)
    return match.group(1).lower() if match else None


def resolve_registry(default_registry: str) -> str:
    explicit = os.environ.get("IMAGE_REGISTRY")
    if explicit:
        return explicit.rstrip("/").lower()
    if "<org>" not in default_registry:
        return default_registry.rstrip("/").lower()
    owner = os.environ.get("GITHUB_REPOSITORY_OWNER") or git_remote_owner()
    return f"ghcr.io/{owner.lower()}" if owner else default_registry


def main() -> None:
    manifest = yaml.safe_load((ROOT / "images.yml").read_text(encoding="utf-8"))
    defaults = manifest["defaults"]
    defaults["registry"] = resolve_registry(defaults["registry"])

    for profile_name in manifest["profiles"]:
        profile = manifest["profiles"][profile_name]
        print(profile["image"].format(**defaults, edt_version="", platform_version=""))


if __name__ == "__main__":
    main()
