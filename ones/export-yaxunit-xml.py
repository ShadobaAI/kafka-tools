#!/usr/bin/env python3
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


EDTCLI = '1cedtcli'
HEAP = '2g'

EXTENSION_TAGS = (
    'ObjectBelonging',
    'Extension',
    'KeepMappingToExtendedConfigurationObjectsByIDs',
    'NamePrefix',
    'ConfigurationExtensionPurpose',
    'ConfigurationExtensionCompatibilityMode',
)


def absolute(path: Path) -> Path:
    return path.expanduser().resolve()


def assert_can_recreate(path: Path) -> None:
    path = absolute(path)
    if path == Path(path.anchor):
        sys.exit(f'ERROR: refusing to recreate drive root: {path}')
    if path == Path.cwd().resolve():
        sys.exit(f'ERROR: refusing to recreate current directory: {path}')


def reset_dir(path: Path) -> None:
    assert_can_recreate(path)
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def find_edtcli(edtcli: str) -> str:
    edtcli_path = shutil.which(edtcli)
    if edtcli_path:
        return edtcli_path
    candidate = Path(edtcli)
    if candidate.is_file():
        return str(candidate)
    sys.exit(f'ERROR: 1cedtcli executable not found: {edtcli}')


def run(command: list[str]) -> None:
    print('  $ ' + ' '.join(str(part) for part in command))
    subprocess.run(command, check=True)


def patch_configuration_xml(path: Path) -> None:
    content = path.read_text(encoding='utf-8')
    for tag in EXTENSION_TAGS:
        content = re.sub(
            rf'\r?\n[ \t]*<{tag}(?:\s[^>]*)?/>',
            '',
            content,
            flags=re.IGNORECASE,
        )
        content = re.sub(
            rf'\r?\n[ \t]*<{tag}(?:\s[^>]*)?>.*?</{tag}>',
            '',
            content,
            flags=re.IGNORECASE | re.DOTALL,
        )
    path.write_text(content, encoding='utf-8', newline='')
    print(f'  patched: {path}')


def patch_application_module(path: Path) -> None:
    content = path.read_text(encoding='utf-8')

    content = re.sub(
        r'(?m)^[ \t]*//@skip-check not-allowed-pragma\r?\n'
        r'[ \t]*&После\("ПриНачалеРаботыСистемы"\)\r?\n'
        r'[ \t]*Процедура ЮТПриНачалеРаботыСистемы\(\)',
        'Процедура ПриНачалеРаботыСистемы()',
        content,
    )
    content = re.sub(
        r'(?m)^[ \t]*&После\("ПриНачалеРаботыСистемы"\)\r?\n'
        r'[ \t]*Процедура ЮТПриНачалеРаботыСистемы\(\)',
        'Процедура ПриНачалеРаботыСистемы()',
        content,
    )

    content = re.sub(
        r'(?ms)\r?\n[ \t]*&After\("OnStart"\)\r?\n'
        r'[ \t]*Procedure ЮТOnStart\(\).*?[ \t]*EndProcedure\r?\n',
        '\n',
        content,
    )

    content = re.sub(
        r'(?m)^[ \t]*&После\("ОбработкаОтображенияОшибки"\)\r?\n'
        r'[ \t]*Процедура ЮТОбработкаОтображенияОшибки\(([^\r\n]*)\)',
        r'Процедура ОбработкаОтображенияОшибки(\1)',
        content,
    )

    content = re.sub(
        r'(?ms)\r?\n[ \t]*&After\("ErrorDisplayProcessing"\)\r?\n'
        r'[ \t]*(?:Процедура|Procedure) ЮТErrorDisplayProcessing\(.*?\)'
        r'.*?[ \t]*(?:КонецПроцедуры|EndProcedure)\r?\n',
        '\n',
        content,
    )

    remaining = (
        '&После("ПриНачалеРаботыСистемы")',
        'Процедура ЮТПриНачалеРаботыСистемы()',
        '&After("OnStart")',
        'Procedure ЮТOnStart()',
        '&После("ОбработкаОтображенияОшибки")',
        'Процедура ЮТОбработкаОтображенияОшибки',
        '&After("ErrorDisplayProcessing")',
        'ЮТErrorDisplayProcessing',
    )
    found = [marker for marker in remaining if marker in content]
    if found:
        sys.exit(f'ERROR: failed to patch {path}; remaining markers: {", ".join(found)}')

    path.write_text(content, encoding='utf-8', newline='')
    print(f'  patched: {path}')


def zip_dir(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        destination.unlink()

    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(source.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(source))
    print(f'  zip: {destination}')


def validate_project(project: Path) -> None:
    if not project.is_dir():
        sys.exit(f'ERROR: EDT project directory not found: {project}')
    for marker in ('.project', 'src'):
        if not (project / marker).exists():
            sys.exit(f'ERROR: EDT project marker not found: {project / marker}')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Export YAxUnit EDT sources to patched XML zip.')
    parser.add_argument('project', type=Path, help='Path to EDT project.')
    parser.add_argument('zip_path', type=Path, help='Path to output XML zip file.')
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    project = absolute(args.project)
    zip_path = absolute(args.zip_path)
    edtcli = find_edtcli(EDTCLI)

    validate_project(project)

    with tempfile.TemporaryDirectory(prefix='yaxunit-xml-', dir=Path.cwd()) as temp_dir:
        temp_root = Path(temp_dir)
        xml_dir = temp_root / 'xml'
        workspace = temp_root / 'workspace'

        print('== YAxUnit EDT -> XML zip ==')
        print(f'  project  : {project}')
        print(f'  zip      : {zip_path}')
        print(f'  xml dir  : {xml_dir}')
        print(f'  workspace: {workspace}')

        print('\n-> Export EDT project to XML')
        reset_dir(xml_dir)
        reset_dir(workspace)
        run([
            edtcli,
            '-data', str(workspace),
            '-vmargs', f'-Xmx{HEAP}',
            '-command', 'export',
            '--project', str(project),
            '--configuration-files', str(xml_dir),
        ])

        configuration_xml = xml_dir / 'Configuration.xml'
        if not configuration_xml.is_file():
            sys.exit(f'ERROR: Configuration.xml was not exported: {configuration_xml}')

        print('\n-> Patch Configuration.xml')
        patch_configuration_xml(configuration_xml)

        print('\n-> Patch application modules')
        for module in (
            xml_dir / 'Ext' / 'ManagedApplicationModule.bsl',
            xml_dir / 'Ext' / 'OrdinaryApplicationModule.bsl',
        ):
            if not module.is_file():
                sys.exit(f'ERROR: application module was not exported: {module}')
            patch_application_module(module)

        print('\n-> Create XML zip')
        zip_dir(xml_dir, zip_path)

    print('\nDone.')


if __name__ == '__main__':
    main()
