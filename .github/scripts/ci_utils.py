#!/usr/bin/env python3
import os

EDT_PROJECT_ENTRIES = ('.project', '.settings', 'DT-INF', 'src')
MDO_PATH = 'src/Configuration/Configuration.mdo'


def write_github_output(**kwargs):
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as f:
            for key, value in kwargs.items():
                f.write(f'{key}={value}\n')
    else:
        for key, value in kwargs.items():
            print(f'{key}={value}')
