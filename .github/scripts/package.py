#!/usr/bin/env python3
"""
Упаковывает артефакты сборки в ZIP-архивы и формирует итоговое имя.
Записывает в GITHUB_OUTPUT: base

Использование:
  package.py --name NAME --ext cf|cfe --version X.X.X.X
             [--suffix SUFFIX] [--output-dir output] [--xml-dir output-xml]
"""
import argparse
import os
import zipfile
from pathlib import Path


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
    parser.add_argument('--name',       required=True)
    parser.add_argument('--ext',        required=True, choices=['cf', 'cfe'])
    parser.add_argument('--version',    required=True)
    parser.add_argument('--suffix',     default='')
    parser.add_argument('--output-dir', default='output')
    parser.add_argument('--xml-dir',    default='output-xml')
    args = parser.parse_args()

    base = f'{args.name}-{args.suffix}-{args.version}' if args.suffix else f'{args.name}-{args.version}'
    out  = Path(args.output_dir)
    xml  = Path(args.xml_dir)
    out.mkdir(parents=True, exist_ok=True)

    # EDT zip — берём все существующие корневые папки/файлы проекта
    edt_candidates = ['.project', '.settings', 'DT-INF', 'src']
    edt_paths = [p for p in edt_candidates if Path(p).exists()]
    if not edt_paths:
        edt_paths = ['src']
    edt_zip = out / f'{base}-EDT.zip'
    zip_paths(edt_paths, edt_zip)
    print(f'  EDT : {edt_zip}  ({human(edt_zip)})')

    # XML zip
    xml_zip = out / f'{base}-XML.zip'
    zip_dir(xml, xml_zip)
    print(f'  XML : {xml_zip}  ({human(xml_zip)})')

    # CF/CFE — переименование
    src_artifact = out / f'config.{args.ext}'
    dst_artifact = out / f'{base}.{args.ext}'
    src_artifact.rename(dst_artifact)
    print(f'  {args.ext.upper():<3}: {dst_artifact}  ({human(dst_artifact)})')

    github_output = os.environ.get('GITHUB_OUTPUT')
    if github_output:
        with open(github_output, 'a', encoding='utf-8') as f:
            f.write(f'base={base}\n')
    else:
        print(f'base={base}')


if __name__ == '__main__':
    main()
