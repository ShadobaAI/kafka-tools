#!/usr/bin/env python3
"""
EDT → XML → .cf или .cfe

Переменные окружения:
  BUILD_TYPE  — 'cf' или 'cfe' (обязательно, задаётся из detect_project.py)
  VERSION     — X.X.X.X (обязательно, версия уже проставлена в исходниках)
  SRC_DIR     — исходники EDT-проекта, по умолчанию /src
  OUTPUT_DIR  — куда сохранить результат, по умолчанию /output
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path


def copy_sources(src_dir: Path, project_dir: Path):
    print('→ Копирование исходников...')
    if project_dir.exists():
        shutil.rmtree(project_dir)
    project_dir.mkdir(parents=True)
    for entry in ('.project', '.settings', 'DT-INF', 'src'):
        src = src_dir / entry
        dst = project_dir / entry
        if src.is_dir():
            shutil.copytree(src, dst)
        elif src.is_file():
            shutil.copy2(src, dst)



def find_edtcli() -> Path:
    edtcli = shutil.which('1cedtcli')
    if edtcli:
        return Path(edtcli)
    for candidate in Path('/opt/1C/EDT').rglob('1cedtcli'):
        if candidate.is_file():
            return candidate
    sys.exit('ERROR: 1cedtcli не найден')


def run(cmd: list, **kwargs):
    print(f'  $ {" ".join(str(c) for c in cmd)}')
    result = subprocess.run(cmd, **kwargs)
    if result.returncode != 0:
        sys.exit(result.returncode)


def edt_to_xml(edtcli: Path, project_dir: Path, xml_dir: Path, edt_workspace: Path):
    print('→ EDT → XML...')
    for d in (xml_dir, edt_workspace):
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
    run([
        edtcli,
        '-data', edt_workspace,
        '-vmargs', '-Xmx2g',
        '-command', 'export',
        '--project', project_dir,
        '--configuration-files', xml_dir,
    ])


def xml_to_artifact(build_type: str, xml_dir: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    artifact = output_dir / f'config.{build_type}'
    if build_type == 'cf':
        print('→ XML → CF...')
        run(['vrunner', 'compile', '-s', xml_dir, '-o', artifact, '--ibcmd'])
    else:
        print('→ XML → CFE...')
        run(['vrunner', 'compileexttocfe', '-s', xml_dir, '-o', artifact, '--ibcmd'])
    size = artifact.stat().st_size
    print(f'\n=== Готово: {artifact}  ({size / 1024 / 1024:.1f} MB) ===')


def main():
    src_dir     = Path(os.environ.get('SRC_DIR',    '/src'))
    output_dir  = Path(os.environ.get('OUTPUT_DIR', '/output'))
    version    = os.environ.get('VERSION',    '')
    build_type = os.environ.get('BUILD_TYPE', '')

    if not version or not build_type:
        sys.exit('ERROR: VERSION и BUILD_TYPE обязательны')

    edt_workspace = Path('/tmp/edt-ws')
    project_dir   = Path('/tmp/project')
    xml_dir       = Path('/tmp/xml')

    print(f'=== Build {build_type.upper()} ===')
    print(f'  Version : {version}')
    print(f'  Sources : {src_dir}')
    print(f'  Output  : {output_dir}')
    print()

    copy_sources(src_dir, project_dir)
    edt_to_xml(find_edtcli(), project_dir, xml_dir, edt_workspace)
    xml_to_artifact(build_type, xml_dir, output_dir)


if __name__ == '__main__':
    main()
