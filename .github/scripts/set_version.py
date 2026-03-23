#!/usr/bin/env python3
"""
Заменяет плейсхолдер версии 9.9.9.9 на реальную версию в указанных файлах.

Использование: set_version.py VERSION file1 [file2 ...]
"""
import sys

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
    if len(sys.argv) < 3:
        print('Использование: set_version.py VERSION file1 [file2 ...]', file=sys.stderr)
        sys.exit(1)
    set_version(sys.argv[1], sys.argv[2:])
