#!/usr/bin/env python3
import os
import sys

EDT_PROJECT_ENTRIES = ('.project', '.settings', 'DT-INF', 'src')
MDO_PATH = 'src/Configuration/Configuration.mdo'


def get_project_type() -> str:
    try:
        with open('.project', encoding='utf-8') as f:
            project_content = f.read()
    except FileNotFoundError:
        print('ERROR: .project не найден', file=sys.stderr)
        sys.exit(1)

    return 'cfe' if 'V8ExtensionNature' in project_content else 'cf'


def write_github_output(**kwargs):
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as f:
            for key, value in kwargs.items():
                f.write(f'{key}={value}\n')
    else:
        for key, value in kwargs.items():
            print(f'{key}={value}')
