[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-ai-setup-" + [guid]::NewGuid().ToString('N'))
$portablePackage = Join-Path $temporaryRoot 'support\agent-kit'
$temporaryCodexHome = Join-Path $temporaryRoot 'codex-home'

try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $portablePackage) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePackage -Destination $portablePackage -Recurse -Force
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        'tests\unit\unit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryRoot $relativePath) -Force | Out-Null
    }

    $fakeNode = Join-Path $temporaryRoot 'node.cmd'
    [System.IO.File]::WriteAllText(
        $fakeNode,
        "@echo off`r`nif `"%1`"==`"--version`" echo v18.20.0`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeJava = Join-Path $temporaryRoot 'java.cmd'
    [System.IO.File]::WriteAllText(
        $fakeJava,
        "@echo off`r`necho openjdk version 21.0.0 1>&2`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeIndexer = Join-Path $temporaryRoot 'bsl-indexer.cmd'
    [System.IO.File]::WriteAllText(
        $fakeIndexer,
        "@echo off`r`nif `"%1`"==`"--version`" echo bsl-indexer 0.69.0`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeJar = Join-Path $temporaryRoot 'bsl-language-server-exec.jar'
    [System.IO.File]::WriteAllBytes($fakeJar, [byte[]](0x50, 0x4b, 0x03, 0x04))

    $output = @(& (Join-Path $portablePackage 'setup.ps1') `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -BslIndexerPath $fakeIndexer `
        -BslLanguageServerJar $fakeJar `
        -NodePath $fakeNode `
        -JavaPath $fakeJava `
        -SkipDaemonStart) -join "`n"

    foreach ($managedFile in @(
        (Join-Path $temporaryCodexHome 'code-index\bsl-indexer.exe'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-mcp.ps1'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-daemon.ps1'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-proxy.mjs'),
        (Join-Path $temporaryCodexHome 'bsl-ls\bsl-language-server-exec.jar'),
        (Join-Path $temporaryCodexHome 'code-index\daemon.toml'),
        (Join-Path $temporaryCodexHome 'config.toml')
    )) {
        if (-not (Test-Path -LiteralPath $managedFile -PathType Leaf)) {
            throw "Setup did not create '$managedFile'."
        }
    }
    if ($output -notmatch 'Setup complete: Node.js 18.20.0, bsl-indexer 0.69.0') {
        throw "Setup did not report verified runtime versions: $output"
    }
    if ($output -notmatch 'Daemon startup was skipped by request') {
        throw 'Setup did not report the explicitly skipped daemon startup.'
    }

    $secondOutput = @(& (Join-Path $portablePackage 'setup.ps1') `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -BslIndexerPath $fakeIndexer `
        -BslLanguageServerJar $fakeJar `
        -NodePath $fakeNode `
        -JavaPath $fakeJava `
        -SkipDaemonStart) -join "`n"
    if (
        $secondOutput -notmatch 'Managed bsl-indexer:.*updated: False' -or
        $secondOutput -notmatch 'Managed BSL LS JAR:.*updated: False'
    ) {
        throw "Repeated setup was not idempotent: $secondOutput"
    }

    Write-Output 'setup-portable: prerequisites, runtime installation, idempotency, managed config, and offline mode passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
