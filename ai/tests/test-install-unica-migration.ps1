[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\install.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-unica-migration-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    foreach ($skill in @('edt-mcp', '1c-engineering', 'v8std-mcp', 'user-owned-skill')) {
        $skillRoot = Join-Path $temporaryCodexHome "skills\$skill"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $skillRoot 'SKILL.md'),
            "# $skill",
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    $legacyConfig = @'
[marketplaces.unica]
source_type = "git"
source = "https://github.com/IngvarConsulting/unica-marketplace.git"

[plugins."unica@unica"]
enabled = true

[plugins."unica@unica".mcp_servers.unica]
enabled = true
enabled_tools = ["unica.code.search"]

[mcp_servers.unrelated]
url = "http://127.0.0.1:9999/mcp"
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $temporaryCodexHome 'config.toml'),
        $legacyConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ReplaceConflictingCommonMcp | Out-Null
    $installedConfig = Get-Content -LiteralPath (Join-Path $temporaryCodexHome 'config.toml') -Raw
    if ($installedConfig -match '(?im)^\[(?:marketplaces\.unica|plugins\."unica@unica"(?:\.mcp_servers\.unica)?)\]') {
        throw 'Installer left a legacy Unica registration or MCP table in active config.'
    }
    if ($installedConfig -notmatch '\[mcp_servers\.code-index\]') {
        throw 'Installer did not install the managed code-index MCP table.'
    }
    if ($installedConfig -notmatch '\[mcp_servers\.unrelated\]') {
        throw 'Installer removed an unrelated MCP table during migration.'
    }
    foreach ($legacySkill in @('edt-mcp', '1c-engineering', 'v8std-mcp')) {
        if (Test-Path -LiteralPath (Join-Path $temporaryCodexHome "skills\$legacySkill")) {
            throw "Installer left legacy managed skill '$legacySkill'."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $temporaryCodexHome 'skills\user-owned-skill\SKILL.md'))) {
        throw 'Installer removed an unrelated user-owned skill.'
    }

    Write-Output 'install-unica-migration: legacy Unica and managed skills removed; unrelated config and skill preserved'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
