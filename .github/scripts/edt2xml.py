#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


DEFAULT_IMAGE = "edtcli:latest"
PROJECT_MARKERS = (".project", "src")


def absolute(path: Path) -> Path:
    return path.expanduser().resolve()


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def validate_project(project: Path) -> None:
    if not project.is_dir():
        sys.exit(f"ERROR: EDT project directory was not found: {project}")

    missing = [marker for marker in PROJECT_MARKERS if not (project / marker).exists()]
    if missing:
        markers = ", ".join(str(project / marker) for marker in missing)
        sys.exit(f"ERROR: EDT project markers were not found: {markers}")


def assert_safe_output_dir(output_dir: Path, project: Path) -> None:
    if output_dir == Path(output_dir.anchor):
        sys.exit(f"ERROR: refusing to use drive root as output directory: {output_dir}")

    cwd = Path.cwd().resolve()
    if output_dir == cwd:
        sys.exit(f"ERROR: refusing to clear current directory: {output_dir}")

    if output_dir == project:
        sys.exit(f"ERROR: output directory must be different from EDT project directory: {output_dir}")

    if is_relative_to(output_dir, project):
        sys.exit(f"ERROR: output directory must be outside EDT project directory: {output_dir}")

    if is_relative_to(project, output_dir):
        sys.exit(f"ERROR: output directory must not contain EDT project directory: {output_dir}")


def reset_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for item in path.iterdir():
        if item.is_symlink() or item.is_file():
            item.unlink()
        else:
            shutil.rmtree(item)


def mount_arg(source: Path, target: str, readonly: bool = False) -> str:
    parts = [
        "type=bind",
        f"source={source}",
        f"target={target}",
    ]
    if readonly:
        parts.append("readonly")
    return ",".join(parts)


def run(command: list[str]) -> None:
    print("+ " + " ".join(command), flush=True)
    result = subprocess.run(command)
    if result.returncode != 0:
        sys.exit(result.returncode)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert an EDT project to XML with the local EDT CLI Docker image.",
        epilog="Docker image can be overridden with EDTCLI_IMAGE environment variable.",
    )
    parser.add_argument("project", type=Path, help="Path to EDT project directory.")
    parser.add_argument("output_dir", type=Path, help="Output directory for XML files.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project = absolute(args.project)
    output_dir = absolute(args.output_dir)
    image = os.environ.get("EDTCLI_IMAGE", DEFAULT_IMAGE)

    validate_project(project)
    assert_safe_output_dir(output_dir, project)
    reset_dir(output_dir)

    print("== EDT -> XML ==")
    print(f"  project : {project}")
    print(f"  output  : {output_dir}")
    print(f"  image   : {image}")

    run([
        "docker",
        "run",
        "--rm",
        "--mount",
        mount_arg(project, "/src", readonly=True),
        "--mount",
        mount_arg(output_dir, "/xml"),
        image,
        "sh",
        "-c",
        "set -eu; "
        "rm -rf /tmp/project /tmp/edt-ws; "
        "mkdir -p /tmp/project /tmp/edt-ws; "
        "cp -a /src/. /tmp/project/; "
        "chmod -R u+rwX /tmp/project /tmp/edt-ws; "
        "1cedtcli -data /tmp/edt-ws -vmargs -Xmx2g "
        "-command export --project /tmp/project --configuration-files /xml",
    ])

    configuration_xml = output_dir / "Configuration.xml"
    if not configuration_xml.is_file():
        sys.exit(f"ERROR: EDT export finished but Configuration.xml was not created: {configuration_xml}")

    print("\nDone.")


if __name__ == "__main__":
    main()
