#!/usr/bin/env python3
"""
Конвертирует CFE-проект в CF:
  - удаляет extension-теги из Configuration.mdo
  - заменяет природу проекта в .project
  - удаляет строку Base-Project из DT-INF/PROJECT.PMF
"""
import re

from ci_utils import MDO_PATH

EXTENSION_TAGS = [
    'objectBelonging',
    'extension',
    'keepMappingToExtendedConfigurationObjectsByIDs',
    'namePrefix',
    'configurationExtensionPurpose',
    'configurationExtensionCompatibilityMode',
]

PROJECT_PATH = '.project'
PMF_PATH     = 'DT-INF/PROJECT.PMF'


def patch_file(path: str, transform):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = transform(content)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'  patched: {path}')


def patch_mdo():
    def transform(content):
        for tag in EXTENSION_TAGS:
            content = re.sub(rf'\s*<{tag}/>', '', content)
            content = re.sub(rf'\s*<{tag}>.*?</{tag}>', '', content, flags=re.DOTALL)
        return content
    patch_file(MDO_PATH, transform)


def patch_project():
    patch_file(PROJECT_PATH, lambda c: c.replace('V8ExtensionNature', 'V8ConfigurationNature'))


def patch_pmf():
    def transform(content):
        lines = [l for l in content.splitlines(keepends=True) if 'Base-Project' not in l]
        return ''.join(lines)
    patch_file(PMF_PATH, transform)


if __name__ == '__main__':
    print('→ Конвертация CFE → CF...')
    patch_mdo()
    patch_project()
    patch_pmf()
    print('  готово.')
