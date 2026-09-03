@echo off
setlocal
title Kafka Codex toolkit setup

set "SETUP_EXIT_CODE=1"
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PSModulePath="
for %%I in ("%~dp0.") do set "LAUNCHER_DIRECTORY_NAME=%%~nxI"
for %%I in ("%~dp0..") do set "LAUNCHER_PARENT_NAME=%%~nxI"

if /I not "%LAUNCHER_DIRECTORY_NAME%"=="ai" (
    echo ERROR: install.cmd must be run from the fixed Kafka tools\ai directory.
    echo Current directory: %~dp0
    goto finish
)
if /I not "%LAUNCHER_PARENT_NAME%"=="tools" (
    echo ERROR: install.cmd must be run from the fixed Kafka tools\ai directory.
    echo Current directory: %~dp0
    goto finish
)

if not exist "%WINDOWS_POWERSHELL%" (
    echo ERROR: Windows PowerShell is not available at:
    echo %WINDOWS_POWERSHELL%
    goto finish
)

:select_embedded_setup
set "KAFKA_AI_EMBEDDED_SETUP=%TEMP%\kafka-codex-setup-%RANDOM%-%RANDOM%.ps1"
if exist "%KAFKA_AI_EMBEDDED_SETUP%" goto select_embedded_setup
set "KAFKA_AI_INSTALLER_PATH=%~f0"

echo Kafka Codex toolkit installer
echo.
"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$source = [System.IO.File]::ReadAllText($env:KAFKA_AI_INSTALLER_PATH); $marker = '# ' + '__KAFKA_AI_POWERSHELL__'; $markerIndex = $source.IndexOf($marker, [System.StringComparison]::Ordinal); if ($markerIndex -lt 0) { throw 'Embedded PowerShell marker is missing.' }; $body = $source.Substring($markerIndex + $marker.Length).TrimStart([char[]](13, 10)); [System.IO.File]::WriteAllText($env:KAFKA_AI_EMBEDDED_SETUP, $body, [System.Text.UTF8Encoding]::new($true))"
if errorlevel 1 (
    echo ERROR: Could not extract the embedded PowerShell installer.
    goto finish
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%KAFKA_AI_EMBEDDED_SETUP%" -ToolkitRoot "%~dp0." %*
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%SETUP_EXIT_CODE%"=="0" (
    echo Installer finished without errors. See the result above.
) else (
    echo Installation failed. See the error above. Exit code: %SETUP_EXIT_CODE%.
)

:finish
if defined KAFKA_AI_EMBEDDED_SETUP if exist "%KAFKA_AI_EMBEDDED_SETUP%" del /q "%KAFKA_AI_EMBEDDED_SETUP%" >nul 2>&1
echo.
if /I not "%KAFKA_AI_NO_PAUSE%"=="1" pause
exit /b %SETUP_EXIT_CODE%

# __KAFKA_AI_POWERSHELL__
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ToolkitRoot,
    [string]$WorkspaceRoot,
    [string]$CodexHome = $env:CODEX_HOME,
    [string]$BslIndexerPath,
    [string]$BslLanguageServerJar,
    [string]$NodePath = $env:CODE_INDEX_NODE,
    [string]$JavaPath = $env:BSL_LANGUAGE_SERVER_JAVA,
    [switch]$ConfigurationOnly,
    [switch]$SkipDaemonStart,
    [ValidateRange(60, 3600)][int]$IndexReadyTimeoutSeconds = 1800,
    [ValidateRange(60, 3600)][int]$McpReadyTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'

trap {
    Write-Output ''
    Write-Output ("[ERROR] Installation did not complete: {0}" -f $_.Exception.Message)
    exit 1
}

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

function Resolve-BundledRuntimeFile {
    param(
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
        return $null
    }
    $candidates = @(Get-ChildItem -LiteralPath $RuntimeRoot -Filter $Filter -File)
    if ($candidates.Count -gt 1) {
        $candidatePaths = ($candidates.FullName | Sort-Object) -join "', '"
        throw "Multiple bundled $Description files were found: '$candidatePaths'. Pass an explicit path to install.cmd."
    }
    if ($candidates.Count -eq 1) {
        return $candidates[0].FullName
    }
    return $null
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
    $commands = @(Get-Command $CommandName -CommandType Application -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        throw "$Description is missing. Install it or pass its executable path to install.cmd."
    }
    return Resolve-ExistingFile -Path ([string]$commands[0].Source) -Description $Description
}

function Resolve-NodePath {
    param(
        [string]$RequestedPath,
        [string]$ProgramFilesRoot = [Environment]::GetEnvironmentVariable('ProgramFiles')
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return Resolve-ExistingFile -Path $RequestedPath -Description 'Node.js executable'
    }
    if (-not [string]::IsNullOrWhiteSpace($ProgramFilesRoot)) {
        $systemNode = Join-Path $ProgramFilesRoot 'nodejs\node.exe'
        if (Test-Path -LiteralPath $systemNode -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($systemNode)
        }
    }
    return Resolve-CommandPath `
        -CommandName 'node' `
        -Description 'Node.js executable'
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

function Get-SemanticVersion {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Value -notmatch '(?<![0-9A-Za-z])v?(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)(?![0-9A-Za-z.-])') {
        throw "$Description does not contain a semantic version: '$Value'."
    }
    return $Matches.version
}

function Get-NativeSemanticVersion {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$ArgumentList = @('--version'),
        [Parameter(Mandatory)][string]$Description,
        [string]$VersionPattern = '(?<![0-9A-Za-z])(?<version>\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?)(?![0-9A-Za-z.-])'
    )

    $result = Invoke-NativeCommand -Executable $Executable -ArgumentList $ArgumentList
    $output = $result.Output -join ' '
    if ($result.ExitCode -ne 0) {
        throw "$Description version command failed with exit code $($result.ExitCode): $output"
    }
    $versionMatch = [regex]::Match($output, $VersionPattern)
    if (-not $versionMatch.Success -or -not $versionMatch.Groups['version'].Success) {
        throw "$Description version output does not match the expected format: '$output'."
    }
    return $versionMatch.Groups['version'].Value
}

function Test-RuntimeUpdateRequired {
    param(
        [AllowNull()]$InstalledVersion,
        [Parameter(Mandatory)][string]$AvailableVersion
    )

    return $null -eq $InstalledVersion -or -not ([string]$InstalledVersion).Equals(
        $AvailableVersion,
        [System.StringComparison]::OrdinalIgnoreCase
    )
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

function Save-VerifiedRuntimeFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourcePath = Resolve-ExistingFile -Path $Source -Description 'Validated runtime source'
    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    $destinationRoot = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    $stagedPath = Join-Path $destinationRoot ('.{0}.{1}.tmp' -f (Split-Path -Leaf $destinationPath), [guid]::NewGuid().ToString('N'))

    try {
        Copy-Item -LiteralPath $sourcePath -Destination $stagedPath -Force
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
        $stagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedPath).Hash
        if ($sourceHash -ne $stagedHash) {
            throw "Runtime cache copy failed SHA-256 verification for '$destinationPath'."
        }
        Move-Item -LiteralPath $stagedPath -Destination $destinationPath -Force
        return Resolve-ExistingFile -Path $destinationPath -Description 'Cached runtime file'
    }
    finally {
        if (Test-Path -LiteralPath $stagedPath -PathType Leaf) {
            Remove-Item -LiteralPath $stagedPath -Force
        }
    }
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

$ToolkitRoot = [System.IO.Path]::GetFullPath($ToolkitRoot)
if (-not (Test-Path -LiteralPath $ToolkitRoot -PathType Container)) {
    throw "Toolkit root does not exist: '$ToolkitRoot'."
}
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $ToolkitRoot '..\..'))
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

$conversionDataBaseRelativePath = 'conversion\' + [string][char]0x041A + [string][char]0x0414
$requiredWorkspacePaths = @(
    'adapter\adapter',
    'adapter\base',
    'adapter\examples',
    'conversion\KFK',
    $conversionDataBaseRelativePath,
    'tests\unit\base',
    'tests\unit\examples',
    'tests\unit\unit',
    'tests\unit\yaxunit'
)
if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    throw "Workspace root does not exist: '$WorkspaceRoot'."
}
foreach ($relativePath in $requiredWorkspacePaths) {
    $workspacePath = Join-Path $WorkspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $workspacePath -PathType Container)) {
        throw "Required workspace path is missing: '$workspacePath'. Create the complete Kafka workspace structure before setup."
    }
}

$downloadRoot = $null
try {
if (-not $ConfigurationOnly) {
    $node = Resolve-NodePath -RequestedPath $NodePath
    $nodeVersion = Assert-MinimumVersion -Executable $node -MinimumVersion ([version]'18.0.0') -Description 'Node.js'
    $java = Resolve-CommandPath -RequestedPath $JavaPath -CommandName 'java' -Description 'Java executable'
    $javaResult = Invoke-NativeCommand -Executable $java -ArgumentList @('-version')
    $javaOutput = $javaResult.Output -join ' '
    if ($javaResult.ExitCode -ne 0) {
        throw "Java runtime check failed for '$java': $javaOutput"
    }

    $managedIndexer = Join-Path $CodexHome 'code-index\bsl-indexer.exe'
    $managedJar = Join-Path $CodexHome 'bsl-ls\bsl-language-server-exec.jar'
    $bundledRuntimeRoot = Join-Path $ToolkitRoot 'runtime\windows'
    New-Item -ItemType Directory -Path $bundledRuntimeRoot -Force | Out-Null
    $bundledIndexer = Resolve-BundledRuntimeFile `
        -RuntimeRoot $bundledRuntimeRoot `
        -Filter 'bsl-indexer.exe' `
        -Description 'bsl-indexer executable'
    $bundledJars = @(Get-ChildItem -LiteralPath $bundledRuntimeRoot -File | Where-Object {
        $_.Name -eq 'bsl-language-server-exec.jar' -or
        $_.Name -match '^bsl-language-server-.*-exec\.jar$'
    })
    if ($bundledJars.Count -gt 1) {
        $candidatePaths = ($bundledJars.FullName | Sort-Object) -join "', '"
        throw "Multiple bundled BSL Language Server JAR files were found: '$candidatePaths'. Pass an explicit path to install.cmd."
    }

    if (-not [string]::IsNullOrWhiteSpace($BslIndexerPath)) {
        $indexer = Resolve-ExistingFile -Path $BslIndexerPath -Description 'bsl-indexer executable'
    }
    else {
        $release = Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'
        $availableIndexerVersion = Get-SemanticVersion `
            -Value ([string]$release.tag_name) `
            -Description 'Latest bsl-indexer release tag'
        $installedIndexerVersion = $null
        if (-not [string]::IsNullOrWhiteSpace($bundledIndexer)) {
            try {
                $installedIndexerVersion = Get-NativeSemanticVersion `
                    -Executable $bundledIndexer `
                    -Description 'Bundled bsl-indexer' `
                    -VersionPattern '(?i)\b(?:bsl-indexer|code-index)\s+(?<version>\d+\.\d+\.\d+(?:-[0-9a-z]+(?:\.[0-9a-z]+)*)?)'
            }
            catch {
                Write-Warning "Bundled bsl-indexer could not be versioned and will be replaced: $($_.Exception.Message)"
            }
        }
        if (-not (Test-RuntimeUpdateRequired `
            -InstalledVersion $installedIndexerVersion `
            -AvailableVersion $availableIndexerVersion)) {
            $indexer = $bundledIndexer
            Write-Output "Bundled bsl-indexer $installedIndexerVersion is current (latest release $($release.tag_name))."
        }
        else {
            if ($null -eq $downloadRoot) {
                $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-codex-runtime-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
            }
            $asset = Get-GitHubReleaseAsset `
                -Release $release `
                -NamePattern '^bsl-indexer-windows-x64\.zip$' `
                -Description 'bsl-indexer for Windows x64'
            $archive = Join-Path $downloadRoot $asset.name
            $archiveHash = Save-GitHubReleaseAsset -Asset $asset -Destination $archive
            $extractRoot = Join-Path $downloadRoot 'bsl-indexer'
            Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
            $downloadedIndexer = Resolve-ExistingFile `
                -Path (Join-Path $extractRoot 'bsl-indexer.exe') `
                -Description 'Downloaded bsl-indexer executable'
            $downloadedIndexerVersion = Get-NativeSemanticVersion `
                -Executable $downloadedIndexer `
                -Description 'Downloaded bsl-indexer' `
                -VersionPattern '(?i)\b(?:bsl-indexer|code-index)\s+(?<version>\d+\.\d+\.\d+(?:-[0-9a-z]+(?:\.[0-9a-z]+)*)?)'
            if ($downloadedIndexerVersion -ne $availableIndexerVersion) {
                throw "Downloaded bsl-indexer reports $downloadedIndexerVersion; release '$($release.tag_name)' requires $availableIndexerVersion."
            }
            $indexer = Save-VerifiedRuntimeFile `
                -Source $downloadedIndexer `
                -Destination (Join-Path $bundledRuntimeRoot 'bsl-indexer.exe')
            Write-Output "Downloaded bsl-indexer $($release.tag_name), asset SHA-256 $archiveHash. Cached executable in '$indexer'."
        }
    }
    $indexerVersion = Assert-MinimumVersion -Executable $indexer -MinimumVersion ([version]'0.69.0') -Description 'bsl-indexer'

    if (-not [string]::IsNullOrWhiteSpace($BslLanguageServerJar)) {
        $jar = Resolve-ExistingFile -Path $BslLanguageServerJar -Description 'BSL Language Server executable JAR'
    }
    else {
        $release = Get-GitHubLatestRelease `
            -Repository '1c-syntax/bsl-language-server' `
            -RequireStable
        $availableJarVersion = Get-SemanticVersion `
            -Value ([string]$release.tag_name) `
            -Description 'Latest BSL Language Server release tag'
        $installedJarVersion = $null
        if ($bundledJars.Count -eq 1) {
            try {
                $installedJarVersion = Get-NativeSemanticVersion `
                    -Executable $java `
                    -ArgumentList @('-jar', $bundledJars[0].FullName, '--version') `
                    -Description 'Bundled BSL Language Server' `
                    -VersionPattern '(?i)\bversion\s*:\s*(?<version>\d+\.\d+\.\d+)'
            }
            catch {
                Write-Warning "Bundled BSL Language Server could not be versioned and will be replaced: $($_.Exception.Message)"
            }
        }
        if (-not (Test-RuntimeUpdateRequired `
            -InstalledVersion $installedJarVersion `
            -AvailableVersion $availableJarVersion)) {
            $jar = $bundledJars[0].FullName
            Write-Output "Bundled BSL Language Server $installedJarVersion is current (latest stable release $($release.tag_name))."
        }
        else {
            if ($null -eq $downloadRoot) {
                $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-codex-runtime-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
            }
            $asset = Get-GitHubReleaseAsset `
                -Release $release `
                -NamePattern '^bsl-language-server-.*-exec\.jar$' `
                -Description 'BSL Language Server executable JAR'
            $downloadedJar = Join-Path $downloadRoot $asset.name
            $jarHash = Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedJar
            $downloadedJarVersion = Get-NativeSemanticVersion `
                -Executable $java `
                -ArgumentList @('-jar', $downloadedJar, '--version') `
                -Description 'Downloaded BSL Language Server' `
                -VersionPattern '(?i)\bversion\s*:\s*(?<version>\d+\.\d+\.\d+)'
            if ($downloadedJarVersion -ne $availableJarVersion) {
                throw "Downloaded BSL Language Server reports $downloadedJarVersion; release '$($release.tag_name)' requires $availableJarVersion."
            }
            $jarDestination = Join-Path $bundledRuntimeRoot $asset.name
            $jar = Save-VerifiedRuntimeFile -Source $downloadedJar -Destination $jarDestination
            foreach ($supersededJar in @($bundledJars | Where-Object {
                -not $_.FullName.Equals($jar, [System.StringComparison]::OrdinalIgnoreCase)
            })) {
                Remove-Item -LiteralPath $supersededJar.FullName -Force
            }
            Write-Output "Downloaded stable BSL Language Server $($release.tag_name), SHA-256 $jarHash. Cached JAR in '$jar'."
        }
    }
    if ([System.IO.Path]::GetExtension($jar) -ne '.jar' -or (Get-Item -LiteralPath $jar).Length -eq 0) {
        throw "BSL Language Server artifact is not a non-empty JAR file: '$jar'."
    }
}

$ReplaceConflictingCommonMcp = $true
$SuppressRestartNotice = $true
$sourceRoot = $ToolkitRoot
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

function Get-CodeIndexConfiguredPaths {
    param([Parameter(Mandatory)][string]$ConfigPath)

    $content = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $entries = foreach ($pathBlock in Get-CodeIndexPathBlocks -Content $content) {
        $pathMatch = [regex]::Match(
            $pathBlock.Value,
            '(?m)^[ \t]*path[ \t]*=[ \t]*"(?<path>[^"]+)"[ \t]*\r?$'
        )
        if (-not $pathMatch.Success) {
            throw "A code-index [[paths]] entry has no simple quoted path: $($pathBlock.Value)"
        }
        [pscustomobject]@{
            Alias = Get-CodeIndexPathAlias -Block $pathBlock.Value
            Path = [System.IO.Path]::GetFullPath($pathMatch.Groups['path'].Value.Replace('/', '\'))
        }
    }
    if (@($entries).Count -eq 0) {
        throw "Code-index configuration has no registered paths: '$ConfigPath'."
    }
    return @($entries)
}

function ConvertTo-NativeArgumentString {
    param([string[]]$ArgumentList = @())

    return ($ArgumentList | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }) -join ' '
}

function Read-McpResponse {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][int]$RequestId,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$RequestName
    )

    $startedAt = [DateTime]::UtcNow
    $deadline = $startedAt.AddSeconds($TimeoutSeconds)
    $lastProgressAt = 0
    while ([DateTime]::UtcNow -lt $deadline) {
        $readTask = $Process.StandardOutput.ReadLineAsync()
        while (-not $readTask.Wait(1000)) {
            if ($Process.HasExited) {
                throw "$Description exited before answering MCP $RequestName."
            }
            $elapsedSeconds = [int]([DateTime]::UtcNow - $startedAt).TotalSeconds
            if ($elapsedSeconds -ge $TimeoutSeconds) {
                throw "$Description did not answer MCP $RequestName within $TimeoutSeconds seconds."
            }
            if ($elapsedSeconds -ge ($lastProgressAt + 15)) {
                [Console]::Out.WriteLine("    Waiting for $Description to answer ${RequestName}: $elapsedSeconds of $TimeoutSeconds seconds...")
                $lastProgressAt = $elapsedSeconds
            }
        }
        $line = $readTask.Result
        if ($null -eq $line) {
            throw "$Description closed its output before answering MCP $RequestName."
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try { $message = $line | ConvertFrom-Json } catch { continue }
        if ($null -ne $message.id -and [int]$message.id -eq $RequestId) {
            return $message
        }
    }
    throw "$Description did not answer MCP $RequestName within $TimeoutSeconds seconds."
}

function Test-StdioMcpServer {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Description,
        [string[]]$RequiredTools = @(),
        [ValidateRange(5, 3600)][int]$TimeoutSeconds = 60
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.Arguments = ConvertTo-NativeArgumentString -ArgumentList $ArgumentList
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $processStarted = $false
    $stderrTask = $null
    $stderrText = ''
    $failure = $null
    $toolCount = $null
    try {
        if (-not $process.Start()) {
            throw "$Description process could not be started."
        }
        $processStarted = $true
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $initializeRequest = @{
            jsonrpc = '2.0'; id = 1; method = 'initialize'
            params = @{
                protocolVersion = '2025-06-18'; capabilities = @{}
                clientInfo = @{ name = 'kafka-codex-installer'; version = '1.0.0' }
            }
        }
        $process.StandardInput.WriteLine(($initializeRequest | ConvertTo-Json -Depth 10 -Compress))
        $initializeResponse = Read-McpResponse -Process $process -RequestId 1 `
            -TimeoutSeconds $TimeoutSeconds -Description $Description -RequestName 'initialize'
        if ($null -ne $initializeResponse.error -or $null -eq $initializeResponse.result) {
            throw "$Description rejected MCP initialize: $($initializeResponse | ConvertTo-Json -Depth 10 -Compress)"
        }
        $process.StandardInput.WriteLine((@{
            jsonrpc = '2.0'; method = 'notifications/initialized'; params = @{}
        } | ConvertTo-Json -Depth 5 -Compress))
        $process.StandardInput.WriteLine((@{
            jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{}
        } | ConvertTo-Json -Depth 5 -Compress))
        $toolsResponse = Read-McpResponse -Process $process -RequestId 2 `
            -TimeoutSeconds $TimeoutSeconds -Description $Description -RequestName 'tools/list'
        if ($null -ne $toolsResponse.error -or $null -eq $toolsResponse.result.tools) {
            throw "$Description did not return an MCP tool list: $($toolsResponse | ConvertTo-Json -Depth 10 -Compress)"
        }
        $toolNames = @($toolsResponse.result.tools | ForEach-Object { [string]$_.name })
        foreach ($requiredTool in $RequiredTools) {
            if ($requiredTool -notin $toolNames) {
                throw "$Description is missing required MCP tool '$requiredTool'."
            }
        }
        $toolCount = $toolNames.Count
    }
    catch { $failure = $_.Exception }
    finally {
        if ($processStarted) { try { $process.StandardInput.Close() } catch {} }
        if ($processStarted -and -not $process.HasExited) {
            if (-not $process.WaitForExit(5000)) {
                $process.Kill()
                $process.WaitForExit(5000) | Out-Null
            }
        }
        if ($null -ne $stderrTask -and $stderrTask.Wait(2000)) {
            $stderrText = $stderrTask.Result.Trim()
        }
        $process.Dispose()
    }
    if ($null -ne $failure) {
        $detail = if ([string]::IsNullOrWhiteSpace($stderrText)) { '' } else {
            " Server log: $(@($stderrText -split "`r?`n" | Select-Object -Last 20) -join ' | ')"
        }
        throw "$($failure.Message)$detail"
    }
    return $toolCount
}

function Get-DaemonProbeFromOutput {
    param(
        [Parameter(Mandatory)]$CommandResult,
        [Parameter(Mandatory)][string]$Description
    )

    foreach ($line in @($CommandResult.Output | Select-Object -Last 20)) {
        try {
            $probe = $line | ConvertFrom-Json
            if ($null -ne $probe.status) { return $probe }
        }
        catch {}
    }
    throw "$Description did not return a readable daemon status: $($CommandResult.Output -join ' ')"
}

function ConvertTo-ComparablePath {
    param([Parameter(Mandatory)][string]$Path)

    $value = $Path
    if ($value.StartsWith('\\?\', [System.StringComparison]::Ordinal)) {
        $value = $value.Substring(4)
    }
    return [System.IO.Path]::GetFullPath($value).TrimEnd('\')
}

function Wait-CodeIndexReady {
    param(
        [Parameter(Mandatory)][string]$Launcher,
        [Parameter(Mandatory)][string]$RuntimeHome,
        [Parameter(Mandatory)][string]$Indexer,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $expected = @(Get-CodeIndexConfiguredPaths -ConfigPath $ConfigPath)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastSummary = $null
    do {
        $status = Invoke-ManagedDaemon -Launcher $Launcher -Action status -RuntimeHome $RuntimeHome -Indexer $Indexer -Json
        $probe = Get-DaemonProbeFromOutput -CommandResult $status -Description 'Code-index readiness check'
        if ($probe.status -ne 'online' -or $null -eq $probe.health) {
            throw "Code-index daemon is not healthy: $($probe.status): $($probe.error)"
        }
        $states = foreach ($entry in $expected) {
            $expectedPath = ConvertTo-ComparablePath -Path $entry.Path
            $pathState = @($probe.health.paths | Where-Object {
                (ConvertTo-ComparablePath -Path ([string]$_.path)).Equals($expectedPath, [System.StringComparison]::OrdinalIgnoreCase)
            }) | Select-Object -First 1
            if ($null -eq $pathState) {
                [pscustomobject]@{ Alias = $entry.Alias; Path = $entry.Path; Status = 'not reported'; Error = $null }
            }
            else {
                [pscustomobject]@{ Alias = $entry.Alias; Path = $entry.Path; Status = ([string]$pathState.status).ToLowerInvariant(); Error = $pathState.error }
            }
        }
        $failed = @($states | Where-Object { $_.Status -in @('error', 'stale', 'incomplete', 'degraded') })
        if ($failed.Count -gt 0) {
            throw "Code-index path '$($failed[0].Alias)' is $($failed[0].Status): $($failed[0].Error)"
        }
        if (@($states | Where-Object { $_.Status -ne 'ready' }).Count -eq 0) {
            return $states.Count
        }
        $summary = ($states | ForEach-Object { "$($_.Alias)=$($_.Status)" }) -join ', '
        if ($summary -ne $lastSummary) {
            [Console]::Out.WriteLine("    Indexing: $summary")
            $lastSummary = $summary
        }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Code-index did not make all $($expected.Count) registered paths ready within $TimeoutSeconds seconds. Last state: $lastSummary"
}

function Get-McpServerUrl {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$ServerName
    )

    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $table = [regex]::Match($config, "(?ms)^\[mcp_servers\.$([regex]::Escape($ServerName))\]\r?\n.*?(?=^\[|\z)")
    if (-not $table.Success) {
        throw "MCP server '$ServerName' is missing from '$ConfigPath'."
    }
    $urlMatch = [regex]::Match($table.Value, '(?m)^[ \t]*url[ \t]*=[ \t]*"(?<url>[^"]+)"[ \t]*\r?$')
    if (-not $urlMatch.Success) {
        throw "MCP server '$ServerName' has no simple quoted URL in '$ConfigPath'."
    }
    return $urlMatch.Groups['url'].Value
}

function Wait-HttpMcpServer {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = $null
    $startedAt = [DateTime]::UtcNow
    $lastProgressAt = 0
    do {
        try {
            $body = @{
                jsonrpc = '2.0'; id = 1; method = 'initialize'
                params = @{
                    protocolVersion = '2025-06-18'; capabilities = @{}
                    clientInfo = @{ name = 'kafka-codex-installer'; version = '1.0.0' }
                }
            } | ConvertTo-Json -Depth 10 -Compress
            $response = Invoke-WebRequest -Method Post -Uri $Uri -UseBasicParsing -TimeoutSec 5 `
                -ContentType 'application/json' -Headers @{ Accept = 'application/json, text/event-stream' } -Body $body
            $content = [string]$response.Content
            $json = $content
            if ($content -match '(?m)^data:\s*(\{.+\})\s*$') { $json = $Matches[1] }
            $message = $json | ConvertFrom-Json
            if ($null -eq $message.error -and $null -ne $message.result) { return }
            $lastError = 'initialize returned no successful result'
        }
        catch { $lastError = $_.Exception.Message }
        $elapsedSeconds = [int]([DateTime]::UtcNow - $startedAt).TotalSeconds
        if ($elapsedSeconds -ge ($lastProgressAt + 15)) {
            [Console]::Out.WriteLine("    Waiting for ${Description}: $elapsedSeconds of $TimeoutSeconds seconds...")
            $lastProgressAt = $elapsedSeconds
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "$Description did not answer MCP initialize within $TimeoutSeconds seconds: $lastError"
}

New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null

$targetConfig = Join-Path $CodexHome 'config.toml'
$managedConfig = Get-Content -LiteralPath $sourceConfig -Raw -Encoding UTF8
$blockPattern = '(?ms)^\# BEGIN SHARED-1C-AI MANAGED\r?\n.*?^\# END SHARED-1C-AI MANAGED\r?\n?'
$guardBlockPattern = '(?ms)^\# BEGIN KAFKA-AI GUARD\r?\n.*?^\# END KAFKA-AI GUARD\r?\n?'
$existingConfig = if (Test-Path -LiteralPath $targetConfig) {
    Get-Content -LiteralPath $targetConfig -Raw -Encoding UTF8
}
else {
    ''
}

$existingV8stdTable = [regex]::Match(
    $existingConfig,
    '(?ms)^\[mcp_servers\.v8std\]\r?\n.*?(?=^\[|\z)'
)
$preservedV8stdBaseSettings = if ($existingV8stdTable.Success) {
    @([regex]::Matches(
        $existingV8stdTable.Value,
        '(?m)^[ \t]*(?:url|bearer_token_env_var|http_headers|env_http_headers)[ \t]*=[^\r\n]*\r?$'
    ) | ForEach-Object { $_.Value.Trim() })
}
else {
    @()
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
    $updatedV8stdTable = [regex]::Replace(
        $updatedV8stdTable,
        '(?m)^[ \t]*(?:url|bearer_token_env_var|http_headers|env_http_headers)[ \t]*=[^\r\n]*(?:\r?\n|$)',
        ''
    )
    $tableHeader = [regex]::Match($updatedV8stdTable, '^\[mcp_servers\.v8std\]\r?\n')
    if (-not $tableHeader.Success) {
        throw "Managed v8std table header is invalid in '$sourceConfig'."
    }
    $preservedSettings = $preservedV8stdBaseSettings -join "`r`n"
    $updatedV8stdTable = $updatedV8stdTable.Insert(
        $tableHeader.Index + $tableHeader.Length,
        "$preservedSettings`r`n"
    )
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
$conflictingGroups = @(
    @{ Header = '[mcp_servers.v8std]'; Pattern = '(?ms)^\[mcp_servers\.v8std(?:\.[^\]]+)?\]\r?\n.*?(?=^\[|\z)' },
    @{ Header = '[mcp_servers.code-index]'; Pattern = '(?ms)^\[mcp_servers\.code-index(?:\.[^\]]+)?\]\r?\n.*?(?=^\[|\z)' }
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
$managedCodeIndexConfig = (Get-Content -LiteralPath $sourceCodeIndexConfig -Raw -Encoding UTF8).Replace(
    '__WORKSPACE_ROOT_FORWARD__',
    $WorkspaceRoot.Replace('\', '/')
)
if ($managedCodeIndexConfig.Contains('__WORKSPACE_ROOT_FORWARD__')) {
    throw "Managed code-index path placeholder was not resolved in '$sourceCodeIndexConfig'."
}
$existingCodeIndexConfig = if (Test-Path -LiteralPath $targetCodeIndexConfig -PathType Leaf) {
    Get-Content -LiteralPath $targetCodeIndexConfig -Raw -Encoding UTF8
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
    $currentAgents = Get-Content -LiteralPath $targetWorkspaceAgents -Raw -Encoding UTF8
    $nextAgents = Get-Content -LiteralPath $sourceAgents -Raw -Encoding UTF8
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
    Write-Output 'Configuration-only setup complete. MCP readiness was not checked. Restart Codex to reload managed configuration.'
    return
}

$codeIndexHome = Join-Path $CodexHome 'code-index'
$daemonLauncher = Join-Path $ToolkitRoot 'mcp\code-index-daemon.ps1'
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
$daemonStartedBySetup = $false
$readyIndexCount = 0
$codeIndexToolCount = 0
$bslLsToolCount = 0
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
        $daemonStartedBySetup = $true

        Write-Output "Waiting up to $IndexReadyTimeoutSeconds seconds for every path registered in '$targetCodeIndexConfig'."
        $readyIndexCount = Wait-CodeIndexReady `
            -Launcher $daemonLauncher `
            -RuntimeHome $codeIndexHome `
            -Indexer $managedIndexer `
            -ConfigPath $targetCodeIndexConfig `
            -TimeoutSeconds $IndexReadyTimeoutSeconds
        Write-Output "All registered code-index paths are ready: $readyIndexCount."

        $codeIndexToolCount = Test-StdioMcpServer `
            -Executable (Join-Path $PSHOME 'powershell.exe') `
            -ArgumentList @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $ToolkitRoot 'mcp\code-index-mcp.ps1'),
                '-CodeIndexHome', $codeIndexHome,
                '-BslIndexerPath', $managedIndexer,
                '-NodePath', $node,
                '-SkipDaemonBootstrap'
            ) `
            -WorkingDirectory $WorkspaceRoot `
            -Description 'code-index MCP' `
            -RequiredTools @('health', 'get_function', 'get_object_structure') `
            -TimeoutSeconds $McpReadyTimeoutSeconds
        Write-Output "code-index MCP is ready ($codeIndexToolCount tools)."

        $adapterRoot = Join-Path $WorkspaceRoot 'adapter\adapter'
        $bslLsProxy = Join-Path $adapterRoot '.codex\mcp\bsl-ls-proxy.mjs'
        $bslLsConfiguration = Join-Path $adapterRoot '.bsl-language-server.json'
        foreach ($requiredBslLsPath in @($bslLsProxy, $bslLsConfiguration)) {
            if (-not (Test-Path -LiteralPath $requiredBslLsPath -PathType Leaf)) {
                throw "Required BSL LS source is missing: '$requiredBslLsPath'."
            }
        }
        $bslLsToolCount = Test-StdioMcpServer `
            -Executable $node `
            -ArgumentList @(
                $bslLsProxy,
                '--root', $adapterRoot,
                '--configuration', $bslLsConfiguration,
                '--jar', $managedJar,
                '--java', $java
            ) `
            -WorkingDirectory $adapterRoot `
            -Description 'BSL LS MCP' `
            -RequiredTools @('analyze_file', 'document_symbols') `
            -TimeoutSeconds $McpReadyTimeoutSeconds
        Write-Output "BSL LS MCP is ready ($bslLsToolCount tools)."

        $v8stdUrl = Get-McpServerUrl -ConfigPath $targetConfig -ServerName 'v8std'
        Wait-HttpMcpServer -Uri $v8stdUrl -Description 'v8std MCP' -TimeoutSeconds $McpReadyTimeoutSeconds
        Write-Output 'v8std MCP is ready.'
    }
    else {
        Write-Output 'MCP readiness was not checked because daemon startup was skipped (-SkipDaemonStart).'
    }
}
catch {
    $setupFailure = $_.Exception.Message
    $rollbackErrors = @()
    if ($daemonStartedBySetup) {
        try {
            $daemonStop = Invoke-ManagedDaemon `
                -Launcher $daemonLauncher `
                -Action stop `
                -RuntimeHome $codeIndexHome `
                -Indexer $managedIndexer
            if ($daemonStop.ExitCode -ne 0) {
                $rollbackErrors += "Could not stop the new daemon before rollback: $($daemonStop.Output -join ' ')"
            }
        }
        catch {
            $rollbackErrors += "Could not stop the new daemon before rollback: $($_.Exception.Message)"
        }
    }
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
else {
    Write-Output "Readiness confirmed: $readyIndexCount code-index paths, $codeIndexToolCount code-index tools, $bslLsToolCount BSL LS tools, v8std available."
}
Write-Output 'Restart Codex and open the required repository as the project root.'
}
finally {
    if ($null -ne $downloadRoot -and (Test-Path -LiteralPath $downloadRoot -PathType Container)) {
        Remove-Item -LiteralPath $downloadRoot -Recurse -Force
    }
}
