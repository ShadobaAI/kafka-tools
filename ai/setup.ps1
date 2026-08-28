[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$CodexHome = $env:CODEX_HOME,
    [string]$BslIndexerPath,
    [string]$BslLanguageServerJar,
    [string]$NodePath = $env:CODE_INDEX_NODE,
    [string]$JavaPath = $env:BSL_LANGUAGE_SERVER_JAVA,
    [switch]$ConfigurationOnly,
    [switch]$SkipDaemonStart
)

$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$ArgumentList = @()
    )

    # Windows PowerShell surfaces a native process's stderr as ErrorRecord objects.
    # Temporarily allow those records through because tools such as Java print
    # successful version output to stderr; the process exit code remains authoritative.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Executable @ArgumentList 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Resolve-ExistingFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "$Description does not exist: '$resolved'."
    }
    return $resolved
}

function Resolve-CommandPath {
    param(
        [string]$RequestedPath,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return Resolve-ExistingFile -Path $RequestedPath -Description $Description
    }
    $command = Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "$Description is missing. Install it or pass its executable path to setup.ps1."
    }
    return $command.Source
}

function Assert-MinimumVersion {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][version]$MinimumVersion,
        [Parameter(Mandatory)][string]$Description
    )

    $result = Invoke-NativeCommand -Executable $Executable -ArgumentList @('--version')
    $output = $result.Output -join ' '
    if ($result.ExitCode -ne 0 -or $output -notmatch '(?<version>\d+\.\d+\.\d+)') {
        throw "$Description version could not be determined from '$Executable --version': $output"
    }
    $actualVersion = [version]$Matches.version
    if ($actualVersion -lt $MinimumVersion) {
        throw "$Description $actualVersion is unsupported; version $MinimumVersion or newer is required."
    }
    return $actualVersion
}

function Get-GitHubLatestRelease {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [switch]$RequireStable
    )

    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'kafka-codex-setup'
    }
    $uri = if ($RequireStable) {
        "https://api.github.com/repos/$Repository/releases/latest"
    }
    else {
        "https://api.github.com/repos/$Repository/releases?per_page=20"
    }
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    }
    catch {
        throw "Could not resolve the latest GitHub release for '$Repository' from '$uri': $($_.Exception.Message)"
    }
    $release = if ($RequireStable) {
        $response
    }
    else {
        @($response | Where-Object { $_.draft -ne $true }) | Select-Object -First 1
    }
    if (
        $null -eq $release -or
        [string]::IsNullOrWhiteSpace([string]$release.tag_name) -or
        $release.draft -eq $true -or
        ($RequireStable -and $release.prerelease -eq $true)
    ) {
        throw "GitHub returned an invalid latest release for '$Repository'."
    }
    return $release
}

function Get-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$NamePattern,
        [Parameter(Mandatory)][string]$Description
    )

    $matches = @($Release.assets | Where-Object {
        [string]$_.name -match $NamePattern
    })
    if ($matches.Count -ne 1) {
        $assetNames = @($Release.assets | ForEach-Object { $_.name }) -join ', '
        throw "$Description asset is ambiguous or missing in release '$($Release.tag_name)'. Assets: $assetNames"
    }
    return $matches[0]
}

function Save-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )

    $headers = @{
        Accept = 'application/octet-stream'
        'User-Agent' = 'kafka-codex-setup'
    }
    $downloadError = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest `
                -Uri $Asset.browser_download_url `
                -Headers $headers `
                -UseBasicParsing `
                -OutFile $Destination
            $downloadError = $null
            break
        }
        catch {
            $downloadError = $_.Exception.Message
            if ($attempt -lt 3) {
                Start-Sleep -Seconds ([math]::Pow(2, $attempt))
            }
        }
    }
    if ($null -ne $downloadError) {
        throw "Could not download '$($Asset.name)' from '$($Asset.browser_download_url)' after 3 attempts: $downloadError"
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or (Get-Item -LiteralPath $Destination).Length -eq 0) {
        throw "Downloaded GitHub asset is empty: '$Destination'."
    }

    $downloadedLength = (Get-Item -LiteralPath $Destination).Length
    if ($null -ne $Asset.size -and [long]$Asset.size -gt 0 -and $downloadedLength -ne [long]$Asset.size) {
        throw "Size mismatch for downloaded asset '$($Asset.name)': expected $($Asset.size), received $downloadedLength bytes."
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
    if (-not [string]::IsNullOrWhiteSpace([string]$Asset.digest)) {
        if ([string]$Asset.digest -notmatch '^sha256:(?<hash>[0-9a-fA-F]{64})$') {
            throw "Unsupported digest for downloaded asset '$($Asset.name)': '$($Asset.digest)'."
        }
        if ($hash -ne $Matches.hash.ToUpperInvariant()) {
            throw "SHA-256 mismatch for downloaded asset '$($Asset.name)'."
        }
    }
    return $hash
}

function Install-ManagedFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupRoot
    )

    $sourcePath = [System.IO.Path]::GetFullPath($Source)
    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
    if ($sourcePath.Equals($destinationPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destinationPath).Hash
        if ($sourceHash -eq $destinationHash) {
            return $false
        }
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Copy-Item -LiteralPath $destinationPath -Destination (Join-Path $BackupRoot (Split-Path -Leaf $destinationPath)) -Force
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    return $true
}

function Restore-ManagedFile {
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][bool]$ExistedBefore
    )

    $backup = Join-Path $BackupRoot (Split-Path -Leaf $Destination)
    if ($ExistedBefore) {
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Copy-Item -LiteralPath $backup -Destination $Destination -Force
        }
        return
    }
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        Remove-Item -LiteralPath $Destination -Force
    }
}

function Restore-BackupFileIfPresent {
    param(
        [Parameter(Mandatory)][string]$Backup,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) {
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Backup -Destination $Destination -Force
}

function Invoke-ManagedDaemon {
    param(
        [Parameter(Mandatory)][string]$Launcher,
        [Parameter(Mandatory)][ValidateSet('run', 'status', 'stop')][string]$Action,
        [Parameter(Mandatory)][string]$RuntimeHome,
        [Parameter(Mandatory)][string]$Indexer,
        [int]$StartupTimeoutSeconds = 60,
        [switch]$Json
    )

    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $Launcher,
        '-Action', $Action,
        '-CodeIndexHome', $RuntimeHome,
        '-BslIndexerPath', $Indexer,
        '-StartupTimeoutSeconds', [string]$StartupTimeoutSeconds
    )
    if ($Json) {
        $arguments += '-Json'
    }
    return Invoke-NativeCommand -Executable 'powershell.exe' -ArgumentList $arguments
}

function Get-CodeIndexPreUpdateAction {
    param([Parameter(Mandatory)]$Probe)

    if (
        $Probe.status -eq 'online' -or
        ($Probe.status -eq 'unhealthy' -and $Probe.process_alive -eq $true)
    ) {
        return 'stop'
    }
    if ($Probe.status -in @('offline', 'stale_runtime_info')) {
        return 'continue'
    }
    throw "Managed code-index daemon is in an unsupported pre-update state '$($Probe.status)': $($Probe.error)"
}

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

$requiredRepositories = @(
    'adapter\adapter',
    'adapter\base',
    'adapter\examples',
    'conversion\KFK',
    'tests\unit\unit'
)
if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    throw "Workspace root does not exist: '$WorkspaceRoot'."
}
foreach ($relativePath in $requiredRepositories) {
    $repositoryPath = Join-Path $WorkspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $repositoryPath -PathType Container)) {
        throw "Required repository is missing: '$repositoryPath'. Create the complete Kafka workspace structure before setup."
    }
}

$downloadRoot = $null
try {
if (-not $ConfigurationOnly) {
    $node = Resolve-CommandPath -RequestedPath $NodePath -CommandName 'node' -Description 'Node.js executable'
    $nodeVersion = Assert-MinimumVersion -Executable $node -MinimumVersion ([version]'18.0.0') -Description 'Node.js'
    $java = Resolve-CommandPath -RequestedPath $JavaPath -CommandName 'java' -Description 'Java executable'
    $javaResult = Invoke-NativeCommand -Executable $java -ArgumentList @('-version')
    $javaOutput = $javaResult.Output -join ' '
    if ($javaResult.ExitCode -ne 0) {
        throw "Java runtime check failed for '$java': $javaOutput"
    }

    $managedIndexer = Join-Path $CodexHome 'code-index\bsl-indexer.exe'
    $managedJar = Join-Path $CodexHome 'bsl-ls\bsl-language-server-exec.jar'
    if (
        [string]::IsNullOrWhiteSpace($BslIndexerPath) -or
        [string]::IsNullOrWhiteSpace($BslLanguageServerJar)
    ) {
        $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-codex-runtime-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
    }

    $indexer = if (-not [string]::IsNullOrWhiteSpace($BslIndexerPath)) {
        Resolve-ExistingFile -Path $BslIndexerPath -Description 'bsl-indexer executable'
    }
    else {
        $release = Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'
        $asset = Get-GitHubReleaseAsset `
            -Release $release `
            -NamePattern '^bsl-indexer-windows-x64\.zip$' `
            -Description 'bsl-indexer for Windows x64'
        $archive = Join-Path $downloadRoot $asset.name
        $archiveHash = Save-GitHubReleaseAsset -Asset $asset -Destination $archive
        $extractRoot = Join-Path $downloadRoot 'bsl-indexer'
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
        $downloadedIndexer = Join-Path $extractRoot 'bsl-indexer.exe'
        Resolve-ExistingFile -Path $downloadedIndexer -Description 'Downloaded bsl-indexer executable'
        $executableHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadedIndexer).Hash
        Write-Output "Downloaded bsl-indexer $($release.tag_name): asset SHA-256 $archiveHash; executable SHA-256 $executableHash."
        $downloadedIndexer
    }
    $indexerVersion = Assert-MinimumVersion -Executable $indexer -MinimumVersion ([version]'0.69.0') -Description 'bsl-indexer'

    $jar = if (-not [string]::IsNullOrWhiteSpace($BslLanguageServerJar)) {
        Resolve-ExistingFile -Path $BslLanguageServerJar -Description 'BSL Language Server executable JAR'
    }
    else {
        $release = Get-GitHubLatestRelease `
            -Repository '1c-syntax/bsl-language-server' `
            -RequireStable
        $asset = Get-GitHubReleaseAsset `
            -Release $release `
            -NamePattern '^bsl-language-server-.*-exec\.jar$' `
            -Description 'BSL Language Server executable JAR'
        $downloadedJar = Join-Path $downloadRoot $asset.name
        $jarHash = Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedJar
        $jarVersionResult = Invoke-NativeCommand `
            -Executable $java `
            -ArgumentList @('-jar', $downloadedJar, '--version')
        $jarVersionOutput = $jarVersionResult.Output -join ' '
        if ([string]$release.tag_name -notmatch '(?<version>\d+\.\d+\.\d+)') {
            throw "Stable BSL Language Server release tag has no semantic version: '$($release.tag_name)'."
        }
        $expectedJarVersion = $Matches.version
        if (
            $jarVersionResult.ExitCode -ne 0 -or
            $jarVersionOutput -notmatch ('(?<!\d)' + [regex]::Escape($expectedJarVersion) + '(?!\d)')
        ) {
            throw "Downloaded BSL Language Server JAR did not report release version '$expectedJarVersion': $jarVersionOutput"
        }
        Write-Output "Downloaded stable BSL Language Server $($release.tag_name), SHA-256 $jarHash."
        $downloadedJar
    }
    if ([System.IO.Path]::GetExtension($jar) -ne '.jar' -or (Get-Item -LiteralPath $jar).Length -eq 0) {
        throw "BSL Language Server artifact is not a non-empty JAR file: '$jar'."
    }
}

$ReplaceConflictingCommonMcp = $true
$SuppressRestartNotice = $true
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

$backupId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), [guid]::NewGuid().ToString('N')
$backupRoot = Join-Path $CodexHome "backups\workspace-ai\$backupId"
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

if ($ConfigurationOnly) {
    Write-Output 'Configuration-only setup complete. Restart Codex to reload managed configuration.'
    return
}

$codeIndexHome = Join-Path $CodexHome 'code-index'
$daemonLauncher = Join-Path $PSScriptRoot 'mcp\code-index-daemon.ps1'
$daemonControlIndexer = if (Test-Path -LiteralPath $managedIndexer -PathType Leaf) {
    $managedIndexer
}
else {
    $indexer
}
$daemonStatus = Invoke-ManagedDaemon `
    -Launcher $daemonLauncher `
    -Action status `
    -RuntimeHome $codeIndexHome `
    -Indexer $daemonControlIndexer `
    -Json
try {
    $daemonProbe = ($daemonStatus.Output | Select-Object -Last 1) | ConvertFrom-Json
}
catch {
    throw "Managed code-index daemon returned an invalid status payload: $($daemonStatus.Output -join ' ')"
}
$preUpdateAction = Get-CodeIndexPreUpdateAction -Probe $daemonProbe
$daemonWasStopped = $false
if ($preUpdateAction -eq 'stop') {
    if ($SkipDaemonStart) {
        throw 'Managed code-index daemon is running. Runtime replacement with -SkipDaemonStart is unsafe; stop the daemon explicitly or run setup without this switch.'
    }
    $daemonStop = Invoke-ManagedDaemon `
        -Launcher $daemonLauncher `
        -Action stop `
        -RuntimeHome $codeIndexHome `
        -Indexer $daemonControlIndexer
    if ($daemonStop.ExitCode -ne 0) {
        throw "Managed code-index daemon could not be stopped before setup: $($daemonStop.Output -join ' ')"
    }
    $daemonWasStopped = $true
    Write-Output 'Stopped the existing managed code-index daemon before applying runtime/configuration updates.'
}

$runtimeBackupId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), [guid]::NewGuid().ToString('N')
$runtimeBackup = Join-Path $CodexHome "backups\workspace-ai\$runtimeBackupId\runtime"
$indexerExistedBefore = Test-Path -LiteralPath $managedIndexer -PathType Leaf
$jarExistedBefore = Test-Path -LiteralPath $managedJar -PathType Leaf
$indexerInstalled = $false
$jarInstalled = $false
try {
    $indexerInstalled = Install-ManagedFile -Source $indexer -Destination $managedIndexer -BackupRoot $runtimeBackup
    $jarInstalled = Install-ManagedFile -Source $jar -Destination $managedJar -BackupRoot $runtimeBackup

    if (-not $SkipDaemonStart) {
        $daemonStart = Invoke-ManagedDaemon `
            -Launcher $daemonLauncher `
            -Action run `
            -RuntimeHome $codeIndexHome `
            -Indexer $managedIndexer `
            -StartupTimeoutSeconds 60
        $daemonStart.Output | Write-Output
        if ($daemonStart.ExitCode -ne 0) {
            throw "Managed code-index daemon startup failed: $($daemonStart.Output -join ' ')"
        }
    }
}
catch {
    $setupFailure = $_.Exception.Message
    $rollbackErrors = @()
    foreach ($runtimeState in @(
        @{ Destination = $managedIndexer; ExistedBefore = $indexerExistedBefore },
        @{ Destination = $managedJar; ExistedBefore = $jarExistedBefore }
    )) {
        try {
            Restore-ManagedFile `
                -Destination $runtimeState.Destination `
                -BackupRoot $runtimeBackup `
                -ExistedBefore $runtimeState.ExistedBefore
        }
        catch {
            $rollbackErrors += "Could not restore '$($runtimeState.Destination)': $($_.Exception.Message)"
        }
    }
    $configurationBackups = @(
        @{
            Backup = Join-Path $backupRoot 'code-index\daemon.toml'
            Destination = $targetCodeIndexConfig
        }
    )
    foreach ($sourceMcpFile in $sourceCodeIndexMcpFiles) {
        $mcpFileName = Split-Path -Leaf $sourceMcpFile
        $configurationBackups += @{
            Backup = Join-Path $backupRoot "code-index\mcp\$mcpFileName"
            Destination = Join-Path $targetCodeIndexMcpRoot $mcpFileName
        }
    }
    foreach ($configurationBackup in $configurationBackups) {
        try {
            Restore-BackupFileIfPresent `
                -Backup $configurationBackup.Backup `
                -Destination $configurationBackup.Destination
        }
        catch {
            $rollbackErrors += "Could not restore '$($configurationBackup.Destination)': $($_.Exception.Message)"
        }
    }
    if ($daemonWasStopped -and $rollbackErrors.Count -eq 0) {
        try {
            $daemonRestart = Invoke-ManagedDaemon `
                -Launcher $daemonLauncher `
                -Action run `
                -RuntimeHome $codeIndexHome `
                -Indexer $managedIndexer `
                -StartupTimeoutSeconds 60
            if ($daemonRestart.ExitCode -ne 0) {
                $rollbackErrors += "Could not restart the previous daemon: $($daemonRestart.Output -join ' ')"
            }
        }
        catch {
            $rollbackErrors += "Could not restart the previous daemon: $($_.Exception.Message)"
        }
    }
    if ($rollbackErrors.Count -gt 0) {
        throw "Setup failed: $setupFailure Rollback errors: $($rollbackErrors -join ' | ')"
    }
    throw "Setup failed; previous runtime state was restored: $setupFailure"
}

Write-Output "Setup complete: Node.js $nodeVersion, bsl-indexer $indexerVersion, Java available."
Write-Output "Managed bsl-indexer: '$managedIndexer' (updated: $indexerInstalled)."
Write-Output "Managed BSL LS JAR: '$managedJar' (updated: $jarInstalled)."
if ($SkipDaemonStart) {
    Write-Output 'Daemon startup was skipped by request.'
}
Write-Output 'Restart Codex and open the required repository as the project root.'
}
finally {
    if ($null -ne $downloadRoot -and (Test-Path -LiteralPath $downloadRoot -PathType Container)) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force
    }
}
