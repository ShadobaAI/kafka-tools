#!/usr/bin/env python3
"""
Заменяет плейсхолдер версии 9.9.9.9 на реальную версию в указанных файлах.
MDO_PATH всегда включён автоматически.

Использование: set_version.py VERSION [file2 ...]
"""
import sys

from ci_utils import MDO_PATH

PLACEHOLDER = '9.9.9.9'


def set_version(version: str, paths: list):
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
            print(f'  WARN: файл не найден — {path}', file=sys.stderr)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Использование: set_version.py VERSION [file2 ...]', file=sys.stderr)
        sys.exit(1)
    set_version(sys.argv[1], [MDO_PATH] + sys.argv[2:])
