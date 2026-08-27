[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$CodexHome = $env:CODEX_HOME,
    [switch]$ReplaceConflictingCommonMcp,
    [switch]$SuppressRestartNotice
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}
else {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
}

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
else {
    $CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
}

$sourceRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    throw "Workspace root does not exist: '$WorkspaceRoot'."
}

$sourceConfig = Join-Path $sourceRoot '.codex\config.toml'
$sourceSkills = Join-Path $sourceRoot '.codex\skills'
$sourceAgents = Join-Path $sourceRoot 'AGENTS.md'
$sourceWorkspacePolicy = Join-Path $sourceRoot 'workspace-policy.json'
$sourceCodeIndexConfig = Join-Path $sourceRoot 'code-index\daemon.toml.template'
$sourceCodeIndexMcpFiles = @(
    (Join-Path $sourceRoot 'mcp\code-index-mcp.ps1'),
    (Join-Path $sourceRoot 'mcp\code-index-daemon.ps1'),
    (Join-Path $sourceRoot 'mcp\code-index-proxy.mjs')
)
foreach ($requiredPath in @(
    $sourceConfig,
    $sourceSkills,
    $sourceAgents,
    $sourceWorkspacePolicy,
    $sourceCodeIndexConfig
) + $sourceCodeIndexMcpFiles) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required source is missing: $requiredPath"
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $CodexHome "backups\workspace-ai\$timestamp"
$backupCreated = $false

function Backup-ManagedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RelativeBackupPath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    if (-not $script:backupCreated) {
        New-Item -ItemType Directory -Path $script:backupRoot -Force | Out-Null
        $script:backupCreated = $true
    }

    $destination = Join-Path $script:backupRoot $RelativeBackupPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
}

function Test-DirectoryContentEqual {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    if (-not (Test-Path -LiteralPath $Left) -or -not (Test-Path -LiteralPath $Right)) {
        return $false
    }

    $leftRoot = [System.IO.Path]::GetFullPath($Left).TrimEnd('\')
    $rightRoot = [System.IO.Path]::GetFullPath($Right).TrimEnd('\')
    $leftFiles = @(Get-ChildItem -LiteralPath $leftRoot -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($leftRoot.Length + 1)
    } | Sort-Object)
    $rightFiles = @(Get-ChildItem -LiteralPath $rightRoot -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($rightRoot.Length + 1)
    } | Sort-Object)

    if (($leftFiles -join "`n") -ne ($rightFiles -join "`n")) {
        return $false
    }

    foreach ($relativePath in $leftFiles) {
        $leftHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $leftRoot $relativePath)).Hash
        $rightHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $rightRoot $relativePath)).Hash
        if ($leftHash -ne $rightHash) {
            return $false
        }
    }

    return $true
}

function Get-CodeIndexPathBlocks {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    return @(
        [regex]::Matches(
            $Content,
            '(?ms)^\[\[paths\]\][ \t]*\r?\n.*?(?=^\[\[paths\]\][ \t]*\r?$|^\[(?!\[)[^\r\n]+\][ \t]*\r?$|\z)'
        )
    )
}

function Get-CodeIndexPathAlias {
    param([Parameter(Mandatory)][string]$Block)

    $aliasMatch = [regex]::Match(
        $Block,
        '(?m)^[ \t]*alias[ \t]*=[ \t]*"(?<alias>[^"]+)"[ \t]*\r?$'
    )
    if (-not $aliasMatch.Success) {
        throw "A code-index [[paths]] entry has no simple quoted alias: $Block"
    }
    return $aliasMatch.Groups['alias'].Value
}

New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null

$targetConfig = Join-Path $CodexHome 'config.toml'
$managedConfig = Get-Content -LiteralPath $sourceConfig -Raw
$blockPattern = '(?ms)^\# BEGIN SHARED-1C-AI MANAGED\r?\n.*?^\# END SHARED-1C-AI MANAGED\r?\n?'
$guardBlockPattern = '(?ms)^\# BEGIN KAFKA-AI GUARD\r?\n.*?^\# END KAFKA-AI GUARD\r?\n?'
$existingConfig = if (Test-Path -LiteralPath $targetConfig) {
    Get-Content -LiteralPath $targetConfig -Raw
}
else {
    ''
}

$preservedV8stdBaseSettings = [ordered]@{}
$preservedV8stdSettingNames = @(
    'url',
    'bearer_token_env_var',
    'http_headers',
    'env_http_headers'
)
$existingV8stdTable = [regex]::Match(
    $existingConfig,
    '(?ms)^\[mcp_servers\.v8std\]\r?\n.*?(?=^\[|\z)'
)
if ($existingV8stdTable.Success) {
    foreach ($settingName in $preservedV8stdSettingNames) {
        $existingSetting = [regex]::Match(
            $existingV8stdTable.Value,
            "(?m)^[ \t]*$([regex]::Escape($settingName))[ \t]*=[^\r\n]*$"
        )
        if ($existingSetting.Success) {
            $preservedV8stdBaseSettings[$settingName] = $existingSetting.Value.Trim()
        }
    }
}
$preservedV8stdNestedTables = @(
    [regex]::Matches(
        $existingConfig,
        '(?ms)^\[mcp_servers\.v8std\.[^\]]+\]\r?\n.*?(?=^\[|\z)'
    ) | ForEach-Object { $_.Value.Trim() }
)

$managedMatch = [regex]::Match($managedConfig, $blockPattern)
if (-not $managedMatch.Success) {
    throw "Shared managed markers are missing from '$sourceConfig'."
}
$managedBlock = $managedMatch.Value
$guardMatch = [regex]::Match($managedConfig, $guardBlockPattern)
if (-not $guardMatch.Success) {
    throw "Kafka guard markers are missing from '$sourceConfig'."
}
$guardBlock = $guardMatch.Value
$escapedSourceRoot = $sourceRoot.Replace('\', '\\').Replace('"', '\"')
$escapedWorkspaceRoot = $WorkspaceRoot.Replace('\', '\\').Replace('"', '\"')
$codeIndexHome = Join-Path $CodexHome 'code-index'
$escapedCodeIndexHome = $codeIndexHome.Replace('\', '\\').Replace('"', '\"')
$managedBlock = $managedBlock.Replace('__CODE_INDEX_HOME__', $escapedCodeIndexHome)
$guardBlock = $guardBlock.Replace('__AI_ROOT__', $escapedSourceRoot)
$guardBlock = $guardBlock.Replace('__WORKSPACE_ROOT__', $escapedWorkspaceRoot)
if ($managedBlock.Contains('__CODE_INDEX_HOME__') -or $guardBlock.Contains('__AI_ROOT__') -or $guardBlock.Contains('__WORKSPACE_ROOT__')) {
    throw "Managed path placeholders were not resolved in '$sourceConfig'."
}
if ($preservedV8stdBaseSettings.Count -gt 0 -or $preservedV8stdNestedTables.Count -gt 0) {
    $managedV8stdTable = [regex]::Match(
        $managedBlock,
        '(?ms)^\[mcp_servers\.v8std\]\r?\n.*?(?=^\[|\z)'
    )
    if (-not $managedV8stdTable.Success) {
        throw "Managed v8std table is missing from '$sourceConfig'."
    }
    $updatedV8stdTable = $managedV8stdTable.Value
    foreach ($settingName in $preservedV8stdBaseSettings.Keys) {
        $managedSetting = [regex]::Match(
            $updatedV8stdTable,
            "(?m)^[ \t]*$([regex]::Escape($settingName))[ \t]*=[^\r\n]*$"
        )
        if ($managedSetting.Success) {
            $updatedV8stdTable = $updatedV8stdTable.Remove(
                $managedSetting.Index,
                $managedSetting.Length
            ).Insert($managedSetting.Index, $preservedV8stdBaseSettings[$settingName])
        }
        else {
            $tableHeader = [regex]::Match($updatedV8stdTable, '^\[mcp_servers\.v8std\]\r?\n')
            if (-not $tableHeader.Success) {
                throw "Managed v8std table header is invalid in '$sourceConfig'."
            }
            $updatedV8stdTable = $updatedV8stdTable.Insert(
                $tableHeader.Index + $tableHeader.Length,
                "$($preservedV8stdBaseSettings[$settingName])`r`n"
            )
        }
    }
    $managedBlock = $managedBlock.Remove(
        $managedV8stdTable.Index,
        $managedV8stdTable.Length
    ).Insert($managedV8stdTable.Index, $updatedV8stdTable)

    if ($preservedV8stdNestedTables.Count -gt 0) {
        $updatedManagedV8stdTable = [regex]::Match(
            $managedBlock,
            '(?ms)^\[mcp_servers\.v8std\]\r?\n.*?(?=^\[|\z)'
        )
        $nestedTables = $preservedV8stdNestedTables -join "`r`n`r`n"
        $managedBlock = $managedBlock.Insert(
            $updatedManagedV8stdTable.Index + $updatedManagedV8stdTable.Length,
            "$nestedTables`r`n`r`n"
        )
    }
}

$unmanagedConfig = [regex]::Replace($existingConfig, $blockPattern, '').TrimEnd()
$unmanagedConfig = [regex]::Replace($unmanagedConfig, $guardBlockPattern, '').TrimEnd()
$legacyManagedBlockPatterns = @(
    '(?ms)^\# BEGIN CRM-AI MANAGED\r?\n.*?^\# END CRM-AI MANAGED\r?\n?',
    '(?ms)^\# BEGIN KAFKA-AI MANAGED\r?\n.*?^\# END KAFKA-AI MANAGED\r?\n?'
)
foreach ($legacyBlockPattern in $legacyManagedBlockPatterns) {
    if ([regex]::IsMatch($unmanagedConfig, $legacyBlockPattern)) {
        if (-not $ReplaceConflictingCommonMcp) {
            throw "Config '$targetConfig' contains a legacy managed Codex block. Re-run with -ReplaceConflictingCommonMcp to migrate it with backup."
        }
        $unmanagedConfig = [regex]::Replace($unmanagedConfig, $legacyBlockPattern, '').TrimEnd()
    }
}
$conflictingGroups = @(
    @{ Header = '[mcp_servers.v8std]'; Pattern = '(?ms)^\[mcp_servers\.v8std(?:\.[^\]]+)?\]\r?\n.*?(?=^\[|\z)' },
    @{ Header = '[mcp_servers.code-index]'; Pattern = '(?ms)^\[mcp_servers\.code-index(?:\.[^\]]+)?\]\r?\n.*?(?=^\[|\z)' },
    @{ Header = '[plugins."unica@unica".mcp_servers.unica]'; Pattern = '(?ms)^\[plugins\."unica@unica"\.mcp_servers\.unica(?:\.[^\]]+)?\]\r?\n.*?(?=^\[|\z)' },
    @{ Header = '[plugins."unica@unica"]'; Pattern = '(?ms)^\[plugins\."unica@unica"\]\r?\n.*?(?=^\[|\z)' },
    @{ Header = '[marketplaces.unica]'; Pattern = '(?ms)^\[marketplaces\.unica\]\r?\n.*?(?=^\[|\z)' }
)
foreach ($group in $conflictingGroups) {
    if ([regex]::IsMatch($unmanagedConfig, $group.Pattern)) {
        if (-not $ReplaceConflictingCommonMcp) {
            throw "Config '$targetConfig' already owns conflicting table $($group.Header) outside the managed block. Re-run with -ReplaceConflictingCommonMcp to migrate it with backup."
        }
        $unmanagedConfig = [regex]::Replace($unmanagedConfig, $group.Pattern, '').TrimEnd()
    }
}

$newConfig = if ([string]::IsNullOrWhiteSpace($unmanagedConfig)) {
    "#:schema https://developers.openai.com/codex/config-schema.json`r`n`r`n$($managedBlock.Trim())`r`n`r`n$($guardBlock.Trim())`r`n"
}
else {
    "$unmanagedConfig`r`n`r`n$($managedBlock.Trim())`r`n`r`n$($guardBlock.Trim())`r`n"
}
$normalizedExistingConfig = ($existingConfig -replace "`r`n", "`n").TrimEnd()
$normalizedNewConfig = ($newConfig -replace "`r`n", "`n").TrimEnd()
$targetHasUtf8Bom = $false
if (Test-Path -LiteralPath $targetConfig) {
    $configBytes = [System.IO.File]::ReadAllBytes($targetConfig)
    $targetHasUtf8Bom = $configBytes.Length -ge 3 -and
        $configBytes[0] -eq 0xEF -and
        $configBytes[1] -eq 0xBB -and
        $configBytes[2] -eq 0xBF
}
if ($normalizedExistingConfig -ne $normalizedNewConfig -or $targetHasUtf8Bom) {
    if (Test-Path -LiteralPath $targetConfig) {
        Backup-ManagedPath -Path $targetConfig -RelativeBackupPath 'config.toml'
    }
    [System.IO.File]::WriteAllText(
        $targetConfig,
        $newConfig,
        [System.Text.UTF8Encoding]::new($false)
    )
}

New-Item -ItemType Directory -Path $codeIndexHome -Force | Out-Null
$targetCodeIndexMcpRoot = Join-Path $codeIndexHome 'mcp'
New-Item -ItemType Directory -Path $targetCodeIndexMcpRoot -Force | Out-Null
foreach ($sourceMcpFile in $sourceCodeIndexMcpFiles) {
    $targetMcpFile = Join-Path $targetCodeIndexMcpRoot (Split-Path -Leaf $sourceMcpFile)
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceMcpFile).Hash
    $targetHash = if (Test-Path -LiteralPath $targetMcpFile -PathType Leaf) {
        (Get-FileHash -Algorithm SHA256 -LiteralPath $targetMcpFile).Hash
    }
    else {
        $null
    }
    if ($sourceHash -ne $targetHash) {
        if (Test-Path -LiteralPath $targetMcpFile -PathType Leaf) {
            Backup-ManagedPath -Path $targetMcpFile -RelativeBackupPath (Join-Path 'code-index\mcp' (Split-Path -Leaf $targetMcpFile))
        }
        Copy-Item -LiteralPath $sourceMcpFile -Destination $targetMcpFile -Force
    }
}

$targetCodeIndexConfig = Join-Path $codeIndexHome 'daemon.toml'
$managedCodeIndexConfig = (Get-Content -LiteralPath $sourceCodeIndexConfig -Raw).Replace(
    '__WORKSPACE_ROOT_FORWARD__',
    $WorkspaceRoot.Replace('\', '/')
)
if ($managedCodeIndexConfig.Contains('__WORKSPACE_ROOT_FORWARD__')) {
    throw "Managed code-index path placeholder was not resolved in '$sourceCodeIndexConfig'."
}
$existingCodeIndexConfig = if (Test-Path -LiteralPath $targetCodeIndexConfig -PathType Leaf) {
    Get-Content -LiteralPath $targetCodeIndexConfig -Raw
}
else {
    ''
}

$managedPathMatches = Get-CodeIndexPathBlocks -Content $managedCodeIndexConfig
if ($managedPathMatches.Count -eq 0) {
    throw "Managed code-index config '$sourceCodeIndexConfig' does not define any [[paths]] entries."
}
$managedAliases = @{}
$managedPathBlocks = foreach ($pathMatch in $managedPathMatches) {
    $alias = Get-CodeIndexPathAlias -Block $pathMatch.Value
    if ($managedAliases.ContainsKey($alias)) {
        throw "Managed code-index config contains duplicate alias '$alias'."
    }
    $managedAliases[$alias] = $true
    $pathMatch.Value.Trim()
}

$existingPathMatches = Get-CodeIndexPathBlocks -Content $existingCodeIndexConfig
$preservedPathBlocks = foreach ($pathMatch in $existingPathMatches) {
    $alias = Get-CodeIndexPathAlias -Block $pathMatch.Value
    if (-not $managedAliases.ContainsKey($alias)) {
        $pathMatch.Value.Trim()
    }
}

$codeIndexBase = $existingCodeIndexConfig
for ($index = $existingPathMatches.Count - 1; $index -ge 0; $index--) {
    $pathMatch = $existingPathMatches[$index]
    $codeIndexBase = $codeIndexBase.Remove($pathMatch.Index, $pathMatch.Length)
}
if (-not [regex]::IsMatch($codeIndexBase, '(?m)^\[daemon\][ \t]*$')) {
    $firstManagedPath = $managedPathMatches[0]
    $managedBase = $managedCodeIndexConfig.Substring(0, $firstManagedPath.Index).Trim()
    $codeIndexBase = if ([string]::IsNullOrWhiteSpace($codeIndexBase)) {
        $managedBase
    }
    else {
        $managedBase + [Environment]::NewLine + [Environment]::NewLine + $codeIndexBase.Trim()
    }
}
$allPathBlocks = @($preservedPathBlocks) + @($managedPathBlocks)
$mergedCodeIndexConfig = @(
    $codeIndexBase.Trim()
    $allPathBlocks
) -join ([Environment]::NewLine + [Environment]::NewLine)
$mergedCodeIndexConfig += [Environment]::NewLine

if (($existingCodeIndexConfig -replace "`r`n", "`n") -ne ($mergedCodeIndexConfig -replace "`r`n", "`n")) {
    if (Test-Path -LiteralPath $targetCodeIndexConfig -PathType Leaf) {
        Backup-ManagedPath -Path $targetCodeIndexConfig -RelativeBackupPath 'code-index\daemon.toml'
    }
    [System.IO.File]::WriteAllText(
        $targetCodeIndexConfig,
        $mergedCodeIndexConfig,
        [System.Text.UTF8Encoding]::new($false)
    )
}

$targetSkills = Join-Path $CodexHome 'skills'
New-Item -ItemType Directory -Path $targetSkills -Force | Out-Null

$managedSkills = @(Get-ChildItem -LiteralPath $sourceSkills -Directory -Force | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf
} | Sort-Object Name)
if ($managedSkills.Count -eq 0) {
    throw "No managed skills found in '$sourceSkills'."
}

$legacyManagedSkills = @('edt-mcp', '1c-engineering', 'v8std-mcp')
foreach ($legacySkill in $legacyManagedSkills) {
    $legacyTarget = Join-Path $targetSkills $legacySkill
    if (-not (Test-Path -LiteralPath $legacyTarget)) {
        continue
    }
    Backup-ManagedPath -Path $legacyTarget -RelativeBackupPath (Join-Path 'skills' $legacySkill)
    Remove-Item -LiteralPath $legacyTarget -Recurse -Force
}

foreach ($sourceSkillItem in $managedSkills) {
    $skill = $sourceSkillItem.Name
    $sourceSkill = $sourceSkillItem.FullName

    $targetSkill = Join-Path $targetSkills $skill
    if (Test-DirectoryContentEqual -Left $sourceSkill -Right $targetSkill) {
        continue
    }
    if (Test-Path -LiteralPath $targetSkill) {
        Backup-ManagedPath -Path $targetSkill -RelativeBackupPath (Join-Path 'skills' $skill)
        Remove-Item -LiteralPath $targetSkill -Recurse -Force
    }
    Copy-Item -LiteralPath $sourceSkill -Destination $targetSkill -Recurse -Force
}

$targetWorkspaceAgents = Join-Path $WorkspaceRoot 'AGENTS.md'
if (Test-Path -LiteralPath $targetWorkspaceAgents) {
    $currentAgents = Get-Content -LiteralPath $targetWorkspaceAgents -Raw
    $nextAgents = Get-Content -LiteralPath $sourceAgents -Raw
    if ($currentAgents -ne $nextAgents) {
        Backup-ManagedPath -Path $targetWorkspaceAgents -RelativeBackupPath 'workspace-AGENTS.md'
        Copy-Item -LiteralPath $sourceAgents -Destination $targetWorkspaceAgents -Force
    }
}
else {
    Copy-Item -LiteralPath $sourceAgents -Destination $targetWorkspaceAgents -Force
}

Write-Output "Installed Codex workspace policy into '$CodexHome'."
if ($backupCreated) {
    Write-Output "Previous managed files were backed up to '$backupRoot'."
}
if (-not $SuppressRestartNotice) {
    Write-Output 'Restart Codex so MCP configuration, hooks, skills, and AGENTS instructions are reloaded.'
}
