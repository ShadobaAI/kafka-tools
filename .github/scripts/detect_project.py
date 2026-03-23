#!/usr/bin/env python3
"""
Валидирует версию, определяет тип проекта (cf/cfe).
Записывает в GITHUB_OUTPUT: project_type, build_type

Использование: detect_project.py --version X.X.X.X [--build-type cf|cfe]
"""
import argparse
import re
import sys

from ci_utils import write_github_output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-type', default='')
    args = parser.parse_args()

    # Валидация версии
    if not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', args.version):
        print(f'ERROR: неверный формат версии "{args.version}". Ожидается X.X.X.X', file=sys.stderr)
        sys.exit(1)

    # Тип проекта из .project
    try:
        with open('.project', encoding='utf-8') as f:
            project_content = f.read()
    except FileNotFoundError:
        print('ERROR: .project не найден', file=sys.stderr)
        sys.exit(1)

    project_type = 'cfe' if 'V8ExtensionNature' in project_content else 'cf'
    build_type = args.build_type or project_type

    print(f'  project_type : {project_type}')
    print(f'  build_type   : {build_type}')

    write_github_output(project_type=project_type, build_type=build_type)


if __name__ == '__main__':
    main()
