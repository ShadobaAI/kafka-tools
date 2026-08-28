[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-ai-portable-" + [guid]::NewGuid().ToString('N'))
$portablePackage = Join-Path $temporaryRoot 'support\agent-kit'
$temporaryCodexHome = Join-Path $temporaryRoot 'codex-home'

try {
    $conversionDataBaseRelativePath = 'conversion\' + [string][char]0x041A + [string][char]0x0414
    New-Item -ItemType Directory -Path (Split-Path -Parent $portablePackage) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePackage -Destination $portablePackage -Recurse -Force
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        $conversionDataBaseRelativePath,
        'tests\unit\base',
        'tests\unit\examples',
        'tests\unit\unit',
        'tests\unit\yaxunit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryRoot $relativePath) -Force | Out-Null
    }

    $portableInstaller = Join-Path $portablePackage 'setup.ps1'
    & $portableInstaller `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null

    $installedConfigPath = Join-Path $temporaryCodexHome 'config.toml'
    $installedConfig = Get-Content -LiteralPath $installedConfigPath -Raw
    if (
        $installedConfig.Contains('__AI_ROOT__') -or
        $installedConfig.Contains('__WORKSPACE_ROOT__') -or
        $installedConfig.Contains('__CODE_INDEX_HOME__')
    ) {
        throw 'Installer left unresolved path placeholders in config.toml.'
    }
    $escapedPackagePath = $portablePackage.Replace('\', '\\')
    $escapedWorkspacePath = $temporaryRoot.Replace('\', '\\')
    if (-not $installedConfig.Contains($escapedPackagePath)) {
        throw 'Installed Kafka guard does not reference the portable package path.'
    }
    if (-not $installedConfig.Contains($escapedWorkspacePath)) {
        throw 'Installed Kafka guard does not reference the selected workspace root.'
    }
    $expectedCodeIndexHome = (Join-Path $temporaryCodexHome 'code-index').Replace('\', '\\')
    $expectedSharedLauncher = ($expectedCodeIndexHome + '\\mcp\\code-index-mcp.ps1')
    if (-not $installedConfig.Contains($expectedSharedLauncher)) {
        throw 'Installed code-index MCP does not reference the shared launcher in CODE_INDEX_HOME.'
    }
    foreach ($managedMcpFile in @(
        'code-index-mcp.ps1',
        'code-index-daemon.ps1',
        'code-index-proxy.mjs'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $temporaryCodexHome "code-index\mcp\$managedMcpFile") -PathType Leaf)) {
            throw "Installer did not install shared code-index MCP file '$managedMcpFile'."
        }
    }
    $daemonConfigPath = Join-Path $temporaryCodexHome 'code-index\daemon.toml'
    if (-not (Test-Path -LiteralPath $daemonConfigPath -PathType Leaf)) {
        throw 'Installer did not create the managed code-index daemon configuration.'
    }
    $daemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    if ($daemonConfig.Contains('__WORKSPACE_ROOT_FORWARD__')) {
        throw 'Installer left an unresolved workspace path in daemon.toml.'
    }
    if (-not $daemonConfig.Contains($temporaryRoot.Replace('\', '/'))) {
        throw 'Managed daemon.toml does not reference the selected workspace root.'
    }

    $installedAgents = Join-Path $temporaryRoot 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $installedAgents -PathType Leaf)) {
        throw 'Installer did not create workspace AGENTS.md.'
    }
    $sourceSkillCount = @(Get-ChildItem -LiteralPath (Join-Path $portablePackage '.codex\skills') -Directory).Count
    $installedSkillCount = @(Get-ChildItem -LiteralPath (Join-Path $temporaryCodexHome 'skills') -Directory).Count
    if ($installedSkillCount -ne $sourceSkillCount) {
        throw "Installer discovered $installedSkillCount skills; expected $sourceSkillCount."
    }

    Write-Output 'install-portable: package paths, code-index config, AGENTS, and skill discovery passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
