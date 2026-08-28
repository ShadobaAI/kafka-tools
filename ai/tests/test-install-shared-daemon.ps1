[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\setup.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-shared-daemon-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    $legacyConfig = @'
#:schema https://developers.openai.com/codex/config-schema.json

# BEGIN CRM-AI MANAGED
[mcp_servers.v8std]
url = "http://127.0.0.1:8766/mcp"
bearer_token_env_var = "V8STD_TOKEN"

[mcp_servers.code-index]
command = "powershell.exe"
args = ["C:\legacy-crm\code-index-mcp.ps1"]
# END CRM-AI MANAGED

[mcp_servers.unrelated]
url = "http://127.0.0.1:9999/mcp"
'@
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    [System.IO.File]::WriteAllText(
        $configPath,
        $legacyConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    $codeIndexHome = Join-Path $temporaryCodexHome 'code-index'
    New-Item -ItemType Directory -Path $codeIndexHome -Force | Out-Null
    $daemonConfigPath = Join-Path $codeIndexHome 'daemon.toml'
    $existingDaemonConfig = @'
[daemon]
http_port = 0
max_concurrent_initial = 3

[[paths]]
alias = "crm-production"
path = "C:/portable/crm/src"
language = "bsl"

[[paths]]
alias = "crm-yaxunit"
path = "C:/portable/crm/EDT.YAXUNIT"
language = "bsl"

[[paths]]
alias = "kafka-adapter"
path = "C:/obsolete/kafka-adapter"
language = "bsl"

[[paths]]
alias = "kafka-adapter-tests-unit"
path = "C:/obsolete/kafka-adapter-tests-unit"
language = "bsl"
'@
    [System.IO.File]::WriteAllText(
        $daemonConfigPath,
        $existingDaemonConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer `
        -WorkspaceRoot $workspaceRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null

    $installedConfig = Get-Content -LiteralPath $configPath -Raw
    foreach ($required in @(
        'BEGIN SHARED-1C-AI MANAGED',
        'BEGIN KAFKA-AI GUARD',
        'url = "http://127.0.0.1:8766/mcp"',
        'bearer_token_env_var = "V8STD_TOKEN"',
        '[mcp_servers.unrelated]'
    )) {
        if (-not $installedConfig.Contains($required)) {
            throw "Installer did not preserve or install required config content '$required'."
        }
    }
    foreach ($forbidden in @('BEGIN CRM-AI MANAGED', 'legacy-crm')) {
        if ($installedConfig.Contains($forbidden)) {
            throw "Installer left legacy CRM managed content '$forbidden'."
        }
    }

    $installedDaemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    $expectedAliases = @(
        'crm-production',
        'crm-yaxunit',
        'kfk',
        'kfk-base',
        'kfk-examples',
        'kfk-conv',
        'kfk-conv-kd',
        'kfk-unit',
        'kfk-yaxunit'
    )
    foreach ($alias in $expectedAliases) {
        if ($installedDaemonConfig -notmatch ('(?m)^alias = "' + [regex]::Escape($alias) + '"\r?$')) {
            throw "Installer did not preserve or add code-index alias '$alias'."
        }
    }
    if ($installedDaemonConfig -notmatch '(?m)^max_concurrent_initial = 3\r?$') {
        throw 'Installer did not preserve existing shared daemon settings.'
    }
    foreach ($legacyAlias in @('kafka-adapter', 'kafka-adapter-tests-unit')) {
        if ($installedDaemonConfig -match ('(?m)^alias = "' + [regex]::Escape($legacyAlias) + '"\r?$')) {
            throw "Installer preserved legacy Kafka alias '$legacyAlias'."
        }
    }

    & $installer `
        -WorkspaceRoot $workspaceRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null
    $reinstalledDaemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    foreach ($alias in $expectedAliases) {
        $aliasCount = [regex]::Matches(
            $reinstalledDaemonConfig,
            '(?m)^alias = "' + [regex]::Escape($alias) + '"\r?$'
        ).Count
        if ($aliasCount -ne 1) {
            throw "Repeated install produced $aliasCount entries for alias '$alias'."
        }
    }

    Write-Output 'install-shared-daemon: foreign aliases and daemon settings preserved; current Kafka aliases replaced idempotently'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
