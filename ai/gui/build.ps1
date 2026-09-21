param([string]$Python = (Join-Path $PSScriptRoot '.venv\Scripts\python.exe'), [switch]$ReplaceBuild)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    throw 'Create gui/.venv and install gui/requirements.txt first (see README.md).'
}
& $Python -c "import tkinter; root = tkinter.Tk(); root.withdraw(); root.destroy()"
if ($LASTEXITCODE -ne 0) { throw 'Tk cannot initialize. Build from a desktop session with working Tcl/Tk.' }
& $Python -m unittest discover -s $PSScriptRoot -p test_gui.py
if ($LASTEXITCODE -ne 0) { throw 'Offline GUI adapter tests failed.' }
# Keep generated files within this component. No toolkit/runtime files are bundled.
$env:PYINSTALLER_CONFIG_DIR = Join-Path $PSScriptRoot 'build\cache'
$replaceArguments = @()
if ($ReplaceBuild) { $replaceArguments = @('--noconfirm') }
& $Python -m PyInstaller --clean --onefile --windowed --name KafkaAI --noupx `
    @replaceArguments `
    --collect-all customtkinter `
    --distpath (Join-Path $PSScriptRoot 'dist') `
    --workpath (Join-Path $PSScriptRoot 'build') `
    --specpath (Join-Path $PSScriptRoot 'build') `
    (Join-Path $PSScriptRoot 'app.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller build failed.' }
& $Python (Join-Path $PSScriptRoot 'verify_build.py') `
    (Join-Path $PSScriptRoot 'dist\KafkaAI.exe') `
    (Join-Path $PSScriptRoot '.checks\build-verification.json') `
    --publish (Join-Path $PSScriptRoot '..\KafkaAI.exe')
if ($LASTEXITCODE -ne 0) { throw 'GUI verification or publication failed. See the error above.' }
Write-Output ('Application: ' + [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\KafkaAI.exe')))
