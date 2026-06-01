#!/usr/bin/env python3
"""
Проверяет версию релиза, определяет тип EDT-проекта и заменяет плейсхолдер 9.9.9.9.
MDO_PATH всегда включен автоматически.
Записывает в GITHUB_OUTPUT: project_type.

Использование: set_version.py VERSION [file2 ...]
"""
import re
import sys

from ci_utils import MDO_PATH, get_project_type, write_github_output

PLACEHOLDER = '9.9.9.9'
VERSION_RE = re.compile(r'\d+\.\d+\.\d+\.\d+')


def validate_version(version: str) -> None:
    if not VERSION_RE.fullmatch(version):
        print(
            f'ERROR: неверный формат версии "{version}". Ожидается X.X.X.X',
            file=sys.stderr,
        )
        sys.exit(1)


def set_version(version: str, paths: list[str]) -> None:
    validate_version(version)
    project_type = get_project_type()

    print(f'  project_type : {project_type}')
    write_github_output(project_type=project_type)

    for path in paths:
        try:
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            if PLACEHOLDER in content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content.replace(PLACEHOLDER, version))
                print(f'  патч: {path}')
            else:
                print(f'  пропуск (нет плейсхолдера): {path}')
        except FileNotFoundError:
            print(f'  WARN: файл не найден: {path}', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Использование: set_version.py VERSION [file2 ...]', file=sys.stderr)
        sys.exit(1)
    set_version(sys.argv[1], [MDO_PATH] + sys.argv[2:])
