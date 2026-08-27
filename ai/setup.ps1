[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$CodexHome = $env:CODEX_HOME,
    [string]$BslIndexerPath,
    [string]$BslLanguageServerJar,
    [string]$NodePath = $env:CODE_INDEX_NODE,
    [string]$JavaPath = $env:BSL_LANGUAGE_SERVER_JAVA,
    [switch]$SkipDaemonStart
)

$ErrorActionPreference = 'Stop'

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

    $output = @(& $Executable --version 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0 -or $output -notmatch '(?<version>\d+\.\d+\.\d+)') {
        throw "$Description version could not be determined from '$Executable --version': $output"
    }
    $actualVersion = [version]$Matches.version
    if ($actualVersion -lt $MinimumVersion) {
        throw "$Description $actualVersion is unsupported; version $MinimumVersion or newer is required."
    }
    return $actualVersion
}

function Resolve-FirstArtifact {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory)][string[]]$Candidates,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$MissingHint
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return Resolve-ExistingFile -Path $ExplicitPath -Description $Description
    }
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "$Description is missing. $MissingHint"
}

function Find-SingleJar {
    param([Parameter(Mandatory)][string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }
    $matches = @(Get-ChildItem -LiteralPath $Directory -File | Where-Object {
        $_.Name -eq 'bsl-language-server-exec.jar' -or
        $_.Name -match '^bsl-language-server-.*-exec\.jar$'
    })
    if ($matches.Count -gt 1) {
        throw "Multiple BSL Language Server JARs found in '$Directory'. Keep one artifact or pass -BslLanguageServerJar explicitly."
    }
    if ($matches.Count -eq 1) {
        return $matches[0].FullName
    }
    return $null
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

function Invoke-ManagedDaemon {
    param(
        [Parameter(Mandatory)][string]$Launcher,
        [Parameter(Mandatory)][ValidateSet('run', 'status', 'stop')][string]$Action,
        [Parameter(Mandatory)][string]$RuntimeHome,
        [Parameter(Mandatory)][string]$Indexer,
        [int]$StartupTimeoutSeconds = 60
    )

    $arguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $Launcher,
        '-Action', $Action,
        '-CodeIndexHome', $RuntimeHome,
        '-BslIndexerPath', $Indexer,
        '-StartupTimeoutSeconds', [string]$StartupTimeoutSeconds
    )
    $output = @(& powershell.exe @arguments 2>&1)
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $output
    }
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

$node = Resolve-CommandPath -RequestedPath $NodePath -CommandName 'node' -Description 'Node.js executable'
$nodeVersion = Assert-MinimumVersion -Executable $node -MinimumVersion ([version]'18.0.0') -Description 'Node.js'
$java = Resolve-CommandPath -RequestedPath $JavaPath -CommandName 'java' -Description 'Java executable'
$javaOutput = @(& $java -version 2>&1) -join ' '
if ($LASTEXITCODE -ne 0) {
    throw "Java runtime check failed for '$java': $javaOutput"
}

$runtimeSource = Join-Path $PSScriptRoot 'runtime\windows'
$managedIndexer = Join-Path $CodexHome 'code-index\bsl-indexer.exe'
$indexerCommand = Get-Command 'bsl-indexer' -CommandType Application -ErrorAction SilentlyContinue
$indexerCandidates = @(
    (Join-Path $runtimeSource 'bsl-indexer.exe'),
    $env:BSL_INDEXER_EXE,
    $managedIndexer,
    $(if ($null -ne $indexerCommand) { $indexerCommand.Source })
)
$indexer = Resolve-FirstArtifact `
    -ExplicitPath $BslIndexerPath `
    -Candidates @($indexerCandidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) `
    -Description 'bsl-indexer executable' `
    -MissingHint "Place bsl-indexer.exe in '$runtimeSource' or pass -BslIndexerPath."
$indexerVersion = Assert-MinimumVersion -Executable $indexer -MinimumVersion ([version]'0.69.0') -Description 'bsl-indexer'

$managedJar = Join-Path $CodexHome 'bsl-ls\bsl-language-server-exec.jar'
$jar = if (-not [string]::IsNullOrWhiteSpace($BslLanguageServerJar)) {
    Resolve-ExistingFile -Path $BslLanguageServerJar -Description 'BSL Language Server executable JAR'
}
else {
    $discoveredJar = Find-SingleJar -Directory $runtimeSource
    if ($null -eq $discoveredJar -and -not [string]::IsNullOrWhiteSpace($env:BSL_LANGUAGE_SERVER_JAR)) {
        $discoveredJar = Resolve-ExistingFile `
            -Path $env:BSL_LANGUAGE_SERVER_JAR `
            -Description 'BSL Language Server executable JAR'
    }
    if ($null -eq $discoveredJar) {
        $discoveredJar = Find-SingleJar -Directory (Split-Path -Parent $managedJar)
    }
    if ($null -eq $discoveredJar) {
        $discoveredJar = Find-SingleJar -Directory (Join-Path $WorkspaceRoot 'adapter\adapter')
    }
    if ($null -eq $discoveredJar) {
        throw "BSL Language Server executable JAR is missing. Place bsl-language-server-exec.jar in '$runtimeSource' or pass -BslLanguageServerJar."
    }
    $discoveredJar
}
if ([System.IO.Path]::GetExtension($jar) -ne '.jar' -or (Get-Item -LiteralPath $jar).Length -eq 0) {
    throw "BSL Language Server artifact is not a non-empty JAR file: '$jar'."
}

$installer = Join-Path $PSScriptRoot 'install.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Managed installer is missing: '$installer'."
}
& $installer `
    -WorkspaceRoot $WorkspaceRoot `
    -CodexHome $CodexHome `
    -ReplaceConflictingCommonMcp `
    -SuppressRestartNotice | Write-Output

$codeIndexHome = Join-Path $CodexHome 'code-index'
$daemonLauncher = Join-Path $PSScriptRoot 'mcp\code-index-daemon.ps1'
if (-not $SkipDaemonStart) {
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
        -Indexer $daemonControlIndexer
    if ($daemonStatus.ExitCode -eq 0) {
        $daemonStop = Invoke-ManagedDaemon `
            -Launcher $daemonLauncher `
            -Action stop `
            -RuntimeHome $codeIndexHome `
            -Indexer $daemonControlIndexer
        if ($daemonStop.ExitCode -ne 0) {
            throw "Managed code-index daemon could not be stopped before setup: $($daemonStop.Output -join ' ')"
        }
        Write-Output 'Stopped the existing managed code-index daemon before applying runtime/configuration updates.'
    }
}

$runtimeBackup = Join-Path $CodexHome ("backups\workspace-ai\{0}\runtime" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
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

Write-Output "Setup complete: Node.js $nodeVersion, bsl-indexer $indexerVersion, Java available."
Write-Output "Managed bsl-indexer: '$managedIndexer' (updated: $indexerInstalled)."
Write-Output "Managed BSL LS JAR: '$managedJar' (updated: $jarInstalled)."
if ($SkipDaemonStart) {
    Write-Output 'Daemon startup was skipped by request.'
}
Write-Output 'Restart Codex and open the required repository as the project root.'
