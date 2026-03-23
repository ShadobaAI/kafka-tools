#!/usr/bin/env python3
"""
Валидирует версию, определяет тип проекта (cf/cfe) и имя конфигурации.
Записывает в GITHUB_OUTPUT: project_type, build_type, cfg_name

Использование: detect_project.py --version X.X.X.X [--build-type cf|cfe]
"""
import argparse
import os
import re
import sys


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
        project_content = open('.project', encoding='utf-8').read()
    except FileNotFoundError:
        print('ERROR: .project не найден', file=sys.stderr)
        sys.exit(1)

    project_type = 'cfe' if 'V8ExtensionNature' in project_content else 'cf'
    build_type = args.build_type or project_type

    # Имя конфигурации из Configuration.mdo
    mdo_path = 'src/Configuration/Configuration.mdo'
    try:
        mdo_content = open(mdo_path, encoding='utf-8').read()
    except FileNotFoundError:
        print(f'ERROR: {mdo_path} не найден', file=sys.stderr)
        sys.exit(1)

    m = re.search(r'<name>([^<]+)</name>', mdo_content)
    if not m:
        print('ERROR: тег <name> не найден в Configuration.mdo', file=sys.stderr)
        sys.exit(1)
    cfg_name = m.group(1).strip()

    print(f'  project_type : {project_type}')
    print(f'  build_type   : {build_type}')
    print(f'  cfg_name     : {cfg_name}')

    github_output = os.environ.get('GITHUB_OUTPUT')
    if github_output:
        with open(github_output, 'a', encoding='utf-8') as f:
            f.write(f'project_type={project_type}\n')
            f.write(f'build_type={build_type}\n')
            f.write(f'cfg_name={cfg_name}\n')


if __name__ == '__main__':
    main()
