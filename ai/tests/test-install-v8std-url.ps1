[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\setup.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-v8std-" + [guid]::NewGuid().ToString('N'))
$publicUrl = 'https://ai.v8std.ru/mcp'
$localUrl = 'http://127.0.0.1:8766/mcp'

try {
    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    $config = Get-Content -LiteralPath $configPath -Raw

    if ($config -notmatch [regex]::Escape("url = `"$publicUrl`"")) {
        throw 'Fresh install did not configure the public v8std URL.'
    }
    if ($config -notmatch '"v8std_explain_snippet"') {
        throw 'Fresh install did not expose v8std_explain_snippet.'
    }
    $config = $config.Replace("url = `"$publicUrl`"", "url = `"$localUrl`"")
    [System.IO.File]::WriteAllText(
        $configPath,
        $config,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $reinstalledConfig = Get-Content -LiteralPath $configPath -Raw
    if ($reinstalledConfig -notmatch [regex]::Escape("url = `"$localUrl`"")) {
        throw 'Installer did not preserve the user-selected v8std URL.'
    }
    if ($reinstalledConfig -match [regex]::Escape("url = `"$publicUrl`"")) {
        throw 'Installer restored the default public URL over the user-selected URL.'
    }

    Write-Output 'install-v8std-url: default public URL and user override preservation passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
