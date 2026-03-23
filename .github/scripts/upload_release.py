#!/usr/bin/env python3
"""
Загружает все файлы из output/ в GitHub Release через API.
Использование: upload_release.py --tag TAG --repo OWNER/REPO
Переменная окружения: GH_TOKEN
"""
import argparse
import json
import os
import pathlib
import urllib.parse
import urllib.request


def api(url, token, method='GET', data=None, content_type='application/json'):
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            'Authorization': f'token {token}',
            'Accept': 'application/vnd.github.v3+json',
            'Content-Type': content_type,
        },
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag',  required=True)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--dir',  default='output')
    args = parser.parse_args()

    token = os.environ['GH_TOKEN']

    release = api(
        f'https://api.github.com/repos/{args.repo}/releases/tags/{args.tag}',
        token,
    )
    upload_base = release['upload_url'].replace('{?name,label}', '')

    # Удаляем старые ассеты с тем же именем (--clobber)
    existing = {a['name']: a['id'] for a in release.get('assets', [])}

    for f in sorted(pathlib.Path(args.dir).iterdir()):
        if not f.is_file():
            continue

        if f.name in existing:
            urllib.request.urlopen(urllib.request.Request(
                f'https://api.github.com/repos/{args.repo}/releases/assets/{existing[f.name]}',
                method='DELETE',
                headers={'Authorization': f'token {token}'},
            ))

        url = f'{upload_base}?name={urllib.parse.quote(f.name)}'
        data = f.read_bytes()
        api(url, token, method='POST', data=data, content_type='application/octet-stream')
        print(f'  uploaded: {f.name}')


if __name__ == '__main__':
    main()
