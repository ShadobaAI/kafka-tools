#!/usr/bin/env python3
"""
Упаковывает артефакты сборки в ZIP-архивы и формирует итоговое имя.
Записывает в GITHUB_OUTPUT: base

Использование:
  package.py --repo-name REPO --ext cf|cfe
             [--suffix SUFFIX] [--output-dir output] [--xml-dir output-xml]

Итоговые имена файлов:
  <repo>.cf(e)
  <repo>-<suffix>-edt.zip  (без suffix: <repo>-edt.zip)
  <repo>-<suffix>-xml.zip  (без suffix: <repo>-xml.zip)
"""
import argparse
import zipfile
from pathlib import Path

from ci_utils import write_github_output, EDT_PROJECT_ENTRIES


def zip_paths(paths: list, dst: Path):
    """Упаковывает список файлов/директорий, сохраняя пути относительно CWD."""
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zf:
        for p in paths:
            p = Path(p)
            if p.is_dir():
                for file in sorted(p.rglob('*')):
                    if file.is_file():
                        zf.write(file, file)
            elif p.is_file():
                zf.write(p, p)


def zip_dir(src: Path, dst: Path):
    """Упаковывает содержимое директории, arcname — относительно src."""
    with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zf:
        for file in sorted(src.rglob('*')):
            if file.is_file():
                zf.write(file, file.relative_to(src))


def human(path: Path) -> str:
    size = path.stat().st_size
    return f'{size // 1024} KB' if size < 1024 * 1024 else f'{size / 1024 / 1024:.1f} MB'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo-name',  required=True)
    parser.add_argument('--ext',        required=True, choices=['cf', 'cfe'])
    parser.add_argument('--suffix',     default='')
    parser.add_argument('--output-dir', default='output')
    parser.add_argument('--xml-dir',    default='output-xml')
    args = parser.parse_args()

    repo = args.repo_name
    zip_base = f'{repo}-{args.suffix}' if args.suffix else repo
    out  = Path(args.output_dir)
    xml  = Path(args.xml_dir)
    out.mkdir(parents=True, exist_ok=True)

    # EDT zip — берём все существующие корневые папки/файлы проекта
    edt_paths = [p for p in EDT_PROJECT_ENTRIES if Path(p).exists()]
    if not edt_paths:
        edt_paths = ['src']
    edt_zip = out / f'{zip_base}-edt.zip'
    zip_paths(edt_paths, edt_zip)
    print(f'  EDT : {edt_zip}  ({human(edt_zip)})')

    # XML zip
    xml_zip = out / f'{zip_base}-xml.zip'
    zip_dir(xml, xml_zip)
    print(f'  XML : {xml_zip}  ({human(xml_zip)})')

    # CF/CFE — уже создан с правильным именем через build.py
    dst_artifact = out / f'{repo}.{args.ext}'
    print(f'  {args.ext.upper():<3}: {dst_artifact}  ({human(dst_artifact)})')

    write_github_output(base=zip_base)


if __name__ == '__main__':
    main()
