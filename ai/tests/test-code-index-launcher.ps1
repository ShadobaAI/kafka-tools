[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$launcher = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-mcp.ps1'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-launcher-" + [guid]::NewGuid().ToString('N'))
$codeIndexHome = Join-Path $temporaryRoot 'runtime'
$capturePath = Join-Path $temporaryRoot 'capture.txt'

try {
    New-Item -ItemType Directory -Path $codeIndexHome -Force | Out-Null
    $daemonConfig = Join-Path $codeIndexHome 'daemon.toml'
    [System.IO.File]::WriteAllText(
        $daemonConfig,
        "[daemon]`r`nhttp_port = 0`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $fakeIndexer = Join-Path $temporaryRoot 'fake-bsl-indexer.cmd'
    $fakeIndexerCommand = @'
@echo off
if "%1"=="--version" echo bsl-indexer 0.69.0
exit /b 0
'@
    [System.IO.File]::WriteAllText(
        $fakeIndexer,
        $fakeIndexerCommand,
        [System.Text.Encoding]::ASCII
    )
    $fakeNode = Join-Path $temporaryRoot 'fake-node.cmd'
    $fakeCommand = @'
@echo off
if "%1"=="--version" (
  echo v18.0.0
  exit /b 0
)
echo CODE_INDEX_HOME=%CODE_INDEX_HOME%>"%CODE_INDEX_CAPTURE%"
echo ARGS=%*>>"%CODE_INDEX_CAPTURE%"
exit /b 0
'@
    [System.IO.File]::WriteAllText($fakeNode, $fakeCommand, [System.Text.Encoding]::ASCII)

    $previousCapture = $env:CODE_INDEX_CAPTURE
    $env:CODE_INDEX_CAPTURE = $capturePath
    try {
        & $launcher `
            -CodeIndexHome $codeIndexHome `
            -BslIndexerPath $fakeIndexer `
            -NodePath $fakeNode `
            -SkipDaemonBootstrap
    }
    finally {
        $env:CODE_INDEX_CAPTURE = $previousCapture
    }

    $capture = Get-Content -LiteralPath $capturePath -Raw
    if ($capture -notmatch [regex]::Escape("CODE_INDEX_HOME=$codeIndexHome")) {
        throw 'Launcher did not bind CODE_INDEX_HOME for bsl-indexer serve.'
    }
    $proxyPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
    $expectedArguments = "ARGS=$proxyPath --indexer $fakeIndexer --config $daemonConfig"
    if ($capture -notmatch [regex]::Escape($expectedArguments)) {
        throw 'Launcher did not bind the compatibility proxy, bsl-indexer, and managed daemon.toml.'
    }

    $unsupportedNodeCommand = @'
@echo off
if "%1"=="--version" echo v17.9.0
exit /b 0
'@
    [System.IO.File]::WriteAllText($fakeNode, $unsupportedNodeCommand, [System.Text.Encoding]::ASCII)
    $unsupportedRejected = $false
    try {
        & $launcher `
            -CodeIndexHome $codeIndexHome `
            -BslIndexerPath $fakeIndexer `
            -NodePath $fakeNode `
            -SkipDaemonBootstrap
    }
    catch {
        $unsupportedRejected = $_.Exception.Message -match 'Node.js 17.9.0 is unsupported'
    }
    if (-not $unsupportedRejected) {
        throw 'Launcher did not reject an unsupported Node.js version.'
    }

    Write-Output 'code-index-launcher: versions, proxy, executable, CODE_INDEX_HOME, and managed daemon.toml passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
