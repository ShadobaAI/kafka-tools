#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_IMAGE = "ibcmd:latest"


def absolute(path: Path) -> Path:
    return path.expanduser().resolve()


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


def validate_xml_dir(xml_dir: Path) -> None:
    if not xml_dir.is_dir():
        sys.exit(f"ERROR: XML directory was not found: {xml_dir}")

    configuration_xml = xml_dir / "Configuration.xml"
    if not configuration_xml.is_file():
        sys.exit(f"ERROR: Configuration.xml was not found: {configuration_xml}")


def command_for_result(result_file: Path) -> str:
    suffix = result_file.suffix.lower()
    if suffix == ".cf":
        return "compile"
    if suffix == ".cfe":
        return "compileexttocfe"
    sys.exit(f"ERROR: result file extension must be .cf or .cfe: {result_file}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pack XML configuration sources to CF/CFE with the local ibcmd Docker image.",
        epilog="Docker image can be overridden with IBCMD_IMAGE environment variable.",
    )
    parser.add_argument("xml_dir", type=Path, help="Path to XML directory.")
    parser.add_argument("result_file", type=Path, help="Path to output .cf or .cfe file.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    xml_dir = absolute(args.xml_dir)
    result_file = absolute(args.result_file)
    result_dir = result_file.parent
    image = os.environ.get("IBCMD_IMAGE", DEFAULT_IMAGE)
    vrunner_command = command_for_result(result_file)

    validate_xml_dir(xml_dir)
    result_dir.mkdir(parents=True, exist_ok=True)

    if result_file.exists():
        result_file.unlink()

    print("== XML -> CF/CFE ==")
    print(f"  xml    : {xml_dir}")
    print(f"  result : {result_file}")
    print(f"  image  : {image}")

    run([
        "docker",
        "run",
        "--rm",
        "--mount",
        mount_arg(xml_dir, "/xml", readonly=True),
        "--mount",
        mount_arg(result_dir, "/out"),
        image,
        "vrunner",
        vrunner_command,
        "-s",
        "/xml",
        "-o",
        f"/out/{result_file.name}",
        "--ibcmd",
    ])

    if not result_file.is_file():
        sys.exit(f"ERROR: vrunner finished but result file was not created: {result_file}")

    size = result_file.stat().st_size
    print(f"\nDone: {result_file} ({size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
