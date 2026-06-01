#!/usr/bin/env python3
from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

from ci_utils import EDT_PROJECT_ENTRIES, write_github_output


def zip_paths(root: Path, entries: list[str], destination: Path) -> None:
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for entry in entries:
            source = root / entry
            if source.is_dir():
                for file in sorted(source.rglob("*")):
                    if file.is_file():
                        archive.write(file, file.relative_to(root))
            elif source.is_file():
                archive.write(source, source.relative_to(root))


def zip_dir(source: Path, destination: Path) -> None:
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(source.rglob("*")):
            if file.is_file():
                archive.write(file, file.relative_to(source))


def package_zip(args: argparse.Namespace) -> None:
    source_dir = args.source_dir.resolve()
    output_file = args.output_file.resolve()
    output_file.parent.mkdir(parents=True, exist_ok=True)

    if (source_dir / ".project").is_file():
        edt_entries = [entry for entry in EDT_PROJECT_ENTRIES if (source_dir / entry).exists()]
        if not edt_entries:
            edt_entries = ["src"]
        zip_paths(source_dir, edt_entries, output_file)
    else:
        if not source_dir.is_dir():
            raise SystemExit(f"ERROR: source directory was not found: {source_dir}")
        zip_dir(source_dir, output_file)

    print(f"zip_file: {output_file}")
    write_github_output(zip_file=str(output_file))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-file", type=Path, required=True)

    args = parser.parse_args()
    package_zip(args)


if __name__ == "__main__":
    main()
