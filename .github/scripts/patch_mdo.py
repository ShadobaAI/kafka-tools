#!/usr/bin/env python3
"""
Конвертирует CFE-проект в CF:
  - удаляет extension-теги из Configuration.mdo
  - заменяет природу проекта в .project
  - удаляет строку Base-Project из DT-INF/PROJECT.PMF
"""
import re
import sys

EXTENSION_TAGS = [
    'objectBelonging',
    'extension',
    'keepMappingToExtendedConfigurationObjectsByIDs',
    'namePrefix',
    'configurationExtensionPurpose',
    'configurationExtensionCompatibilityMode',
]

MDO_PATH     = 'src/Configuration/Configuration.mdo'
PROJECT_PATH = '.project'
PMF_PATH     = 'DT-INF/PROJECT.PMF'


def patch_mdo():
    with open(MDO_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    for tag in EXTENSION_TAGS:
        content = re.sub(rf'\s*<{tag}/>', '', content)
        content = re.sub(rf'\s*<{tag}>.*?</{tag}>', '', content, flags=re.DOTALL)
    with open(MDO_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'  patched: {MDO_PATH}')


def patch_project():
    with open(PROJECT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('V8ExtensionNature', 'V8ConfigurationNature')
    with open(PROJECT_PATH, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'  patched: {PROJECT_PATH}')


def patch_pmf():
    with open(PMF_PATH, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    lines = [l for l in lines if 'Base-Project' not in l]
    with open(PMF_PATH, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print(f'  patched: {PMF_PATH}')


if __name__ == '__main__':
    print('→ Конвертация CFE → CF...')
    patch_mdo()
    patch_project()
    patch_pmf()
    print('  готово.')
