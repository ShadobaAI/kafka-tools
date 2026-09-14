@echo off
setlocal
title Kafka code-index update

set "SETUP_EXIT_CODE=1"
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PSModulePath="
for %%I in ("%~dp0.") do set "LAUNCHER_DIRECTORY_NAME=%%~nxI"
for %%I in ("%~dp0..") do set "LAUNCHER_PARENT_NAME=%%~nxI"

if /I not "%LAUNCHER_DIRECTORY_NAME%"=="ai" (
    echo ERROR: update-code-index.cmd must be run from the fixed Kafka tools\ai directory.
    echo Current directory: %~dp0
    goto finish
)
if /I not "%LAUNCHER_PARENT_NAME%"=="tools" (
    echo ERROR: update-code-index.cmd must be run from the fixed Kafka tools\ai directory.
    echo Current directory: %~dp0
    goto finish
)

if not exist "%WINDOWS_POWERSHELL%" (
    echo ERROR: Windows PowerShell is not available at:
    echo %WINDOWS_POWERSHELL%
    goto finish
)

:select_embedded_setup
set "KAFKA_AI_EMBEDDED_SETUP=%TEMP%\kafka-code-index-update-%RANDOM%-%RANDOM%.ps1"
if exist "%KAFKA_AI_EMBEDDED_SETUP%" goto select_embedded_setup
set "KAFKA_AI_UPDATER_PATH=%~f0"

echo Kafka code-index updater
echo.
"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$source = [System.IO.File]::ReadAllText($env:KAFKA_AI_UPDATER_PATH); $marker = '# ' + '__KAFKA_AI_POWERSHELL__'; $markerIndex = $source.IndexOf($marker, [System.StringComparison]::Ordinal); if ($markerIndex -lt 0) { throw 'Embedded PowerShell marker is missing.' }; $body = $source.Substring($markerIndex + $marker.Length).TrimStart([char[]](13, 10)); [System.IO.File]::WriteAllText($env:KAFKA_AI_EMBEDDED_SETUP, $body, [System.Text.UTF8Encoding]::new($true))"
if errorlevel 1 (
    echo ERROR: Could not extract the embedded PowerShell updater.
    goto finish
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%KAFKA_AI_EMBEDDED_SETUP%" -ToolkitRoot "%~dp0." %*
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%SETUP_EXIT_CODE%"=="0" (
    echo Updater finished without errors. See the result above.
) else (
    echo Update failed. See the error above. Exit code: %SETUP_EXIT_CODE%.
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
    [string]$NodePath = $env:CODE_INDEX_NODE,
    [ValidateRange(60, 3600)][int]$IndexReadyTimeoutSeconds = 1800,
    [ValidateRange(60, 3600)][int]$McpReadyTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
trap {
    Write-Output ''
    Write-Output ("[ERROR] Code-index update did not complete: {0}" -f $_.Exception.Message)
    exit 1
}

# Focused copies of installer helpers; this updater never executes install.cmd.

function Write-SetupStep {
    param([Parameter(Mandatory)][string]$Message)

    Write-Output ''
    Write-Output ("==> {0}" -f $Message)
}

function Write-SetupOk {
    param([Parameter(Mandatory)][string]$Message)

    Write-Output ("[OK] {0}" -f $Message)
}

function Write-SetupWarning {
    param([Parameter(Mandatory)][string]$Message)

    Write-Output ("[WARNING] {0}" -f $Message)
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
        throw "$Description is missing. Install it or pass its executable path to update-code-index.cmd."
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
        '(?m)^[ \t]*alias[ \t]*=[ \t]*(?<value>"(?:\\.|[^"\\])*")[ \t]*\r?$'
    )
    if (-not $aliasMatch.Success) {
        throw "A code-index [[paths]] entry has no simple quoted alias: $Block"
    }
    try {
        return $aliasMatch.Groups['value'].Value | ConvertFrom-Json
    }
    catch {
        throw "A code-index [[paths]] entry has an invalid quoted alias: $Block"
    }
}

function Get-CodeIndexConfiguredPaths {
    param([Parameter(Mandatory)][string]$ConfigPath)

    $content = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $entries = foreach ($pathBlock in Get-CodeIndexPathBlocks -Content $content) {
        $pathMatch = [regex]::Match(
            $pathBlock.Value,
            '(?m)^[ \t]*path[ \t]*=[ \t]*(?<value>"(?:\\.|[^"\\])*")[ \t]*\r?$'
        )
        if (-not $pathMatch.Success) {
            throw "A code-index [[paths]] entry has no simple quoted path: $($pathBlock.Value)"
        }
        try {
            $configuredPath = $pathMatch.Groups['value'].Value | ConvertFrom-Json
        }
        catch {
            throw "A code-index [[paths]] entry has an invalid quoted path: $($pathBlock.Value)"
        }
        $configuredAlias = Get-CodeIndexPathAlias -Block $pathBlock.Value
        try {
            $fullConfiguredPath = [System.IO.Path]::GetFullPath($configuredPath.Replace('/', '\'))
        }
        catch {
            throw "Code-index path '$configuredAlias' is not a valid filesystem path: $($_.Exception.Message)"
        }
        [pscustomobject]@{
            Alias = $configuredAlias
            Path = $fullConfiguredPath
        }
    }
    if (@($entries).Count -eq 0) {
        throw "Code-index configuration has no registered paths: '$ConfigPath'."
    }
    return @($entries)
}

function Remove-ManagedCodeIndexDirectories {
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][hashtable]$ManagedAliases,
        [Parameter(Mandatory)][string]$WorkspaceRoot
    )

    $workspacePath = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $workspacePrefix = $workspacePath + '\'
    $managedEntries = @(Get-CodeIndexConfiguredPaths -ConfigPath $ConfigPath | Where-Object {
        $ManagedAliases.ContainsKey($_.Alias)
    })
    if ($managedEntries.Count -ne $ManagedAliases.Count) {
        throw "Code-index cleanup resolved $($managedEntries.Count) managed paths; expected $($ManagedAliases.Count)."
    }

    $removed = @()
    foreach ($entry in $managedEntries) {
        $projectRoot = [System.IO.Path]::GetFullPath($entry.Path).TrimEnd('\')
        if (-not $projectRoot.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean code-index alias '$($entry.Alias)' outside the Kafka workspace."
        }
        $target = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.code-index')).TrimEnd('\')
        if (
            -not (Split-Path -Parent $target).Equals($projectRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $target).Equals('.code-index', [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            throw "Refusing to remove an unsafe code-index path for alias '$($entry.Alias)'."
        }
        $targetItem = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($null -eq $targetItem) {
            continue
        }
        if (
            -not $targetItem.PSIsContainer -or
            ($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw "Refusing to remove code-index alias '$($entry.Alias)': its .code-index target is not a regular directory."
        }
        $script:indexCleanupStarted = $true
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            try {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                break
            }
            catch {
                $nativeCode = $_.Exception.HResult -band 0xffff
                if ($nativeCode -notin @(32, 33) -or [DateTime]::UtcNow -ge $deadline) {
                    throw "Could not remove '$($entry.Alias)' at '$target'. Completed directories: $($removed.Count). This directory may be partially removed. Close code-index clients or the process holding the file and retry. Details: $($_.Exception.Message)"
                }
                [Console]::Out.WriteLine("    Waiting for file locks to be released: $target")
                Start-Sleep -Seconds 1
            }
        } while ($true)
        $removed += [pscustomobject]@{ Alias = $entry.Alias; Path = $target }
        [Console]::Out.WriteLine("[OK] Removed '$($entry.Alias)': $target")
    }

    return [pscustomobject]@{
        RegisteredCount = $managedEntries.Count
        Removed = @($removed)
    }
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

function Get-CodeIndexDaemonPathStatus {
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter(Mandatory)][string]$Path
    )

    $encodedPath = [System.Uri]::EscapeDataString($Path)
    return Invoke-RestMethod `
        -Method Get `
        -Uri "$Endpoint/path-status?path=$encodedPath" `
        -TimeoutSec 5
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
    $startedAt = [DateTime]::UtcNow
    $lastProgressAt = $startedAt
    do {
        $status = Invoke-ManagedDaemon -Launcher $Launcher -Action status -RuntimeHome $RuntimeHome -Indexer $Indexer -Json
        $probe = Get-DaemonProbeFromOutput -CommandResult $status -Description 'Code-index readiness check'
        if ($probe.status -ne 'online' -or $null -eq $probe.health) {
            throw "Code-index daemon is not healthy: $($probe.status): $($probe.error)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$probe.endpoint)) {
            throw 'Code-index daemon status did not include its HTTP endpoint.'
        }
        $states = foreach ($entry in $expected) {
            try {
                $pathState = Get-CodeIndexDaemonPathStatus -Endpoint ([string]$probe.endpoint) -Path $entry.Path
            }
            catch {
                throw "Code-index daemon did not return status for path '$($entry.Alias)': $($_.Exception.Message)"
            }
            [pscustomobject]@{
                Alias = $entry.Alias
                Path = $entry.Path
                Status = ([string]$pathState.status).ToLowerInvariant()
                Error = $pathState.error
            }
        }
        $failed = @($states | Where-Object { $_.Status -in @('error', 'stale', 'incomplete', 'degraded') })
        if ($failed.Count -gt 0) {
            throw "Code-index path '$($failed[0].Alias)' is $($failed[0].Status): $($failed[0].Error)"
        }
        if (@($states | Where-Object { $_.Status -ne 'ready' }).Count -eq 0) {
            foreach ($state in $states) { [Console]::Out.WriteLine("    [OK] $($state.Alias)=ready : $($state.Path)") }
            return $states.Count
        }
        $summary = ($states | ForEach-Object { "$($_.Alias)=$($_.Status)" }) -join ', '
        if ($summary -ne $lastSummary -or ([DateTime]::UtcNow - $lastProgressAt).TotalSeconds -ge 15) {
            [Console]::Out.WriteLine("    Indexing ($([int]([DateTime]::UtcNow - $startedAt).TotalSeconds)s): $summary")
            $lastSummary = $summary
            $lastProgressAt = [DateTime]::UtcNow
        }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Code-index did not make all $($expected.Count) registered paths ready within $TimeoutSeconds seconds. Last state: $lastSummary"
}

function Test-ManagedCodeIndexClient {
    param([Parameter(Mandatory)]$Process, [string]$Indexer, [string]$ConfigPath)

    if ([string]::IsNullOrWhiteSpace([string]$Process.ExecutablePath) -or
        -not ([string]$Process.ExecutablePath).Equals($Indexer, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $arguments = @([regex]::Matches([string]$Process.CommandLine, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
    if ($arguments.Count -lt 4 -or $arguments[1] -ne 'serve') { return $false }
    $configArguments = @(for ($i = 2; $i -lt $arguments.Count - 1; $i++) {
        if ($arguments[$i] -eq '--config') { $arguments[$i + 1] }
    })
    return $configArguments.Count -eq 1 -and $configArguments[0].Equals($ConfigPath, [StringComparison]::OrdinalIgnoreCase)
}

function Stop-ManagedCodeIndexClients {
    param([Parameter(Mandatory)][string]$Indexer, [Parameter(Mandatory)][string]$ConfigPath)

    # The proxy launches a separate SQLite reader: bsl-indexer serve --config ... .
    # daemon stop does not close these readers. Never stop processes by name alone.
    $clients = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'bsl-indexer.exe'" -ErrorAction Stop | Where-Object {
        Test-ManagedCodeIndexClient -Process $_ -Indexer $Indexer -ConfigPath $ConfigPath
    })
    foreach ($client in $clients) {
        $process = Get-Process -Id $client.ProcessId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        try {
            if (-not $process.Path.Equals($Indexer, [StringComparison]::OrdinalIgnoreCase) -or
                [math]::Abs(($process.StartTime.ToUniversalTime() - $client.CreationDate.ToUniversalTime()).TotalSeconds) -gt 0.1) {
                throw "Process identity changed for PID $($client.ProcessId); refusing to stop it."
            }
            Write-Output "    Stopping managed code-index MCP reader: PID $($client.ProcessId)"
            Stop-Process -InputObject $process -Force -ErrorAction Stop
            if (-not $process.WaitForExit(10000)) { throw "MCP reader PID $($client.ProcessId) did not exit within 10 seconds." }
            Write-SetupOk "Managed MCP reader PID $($client.ProcessId) exited."
        }
        finally { $process.Dispose() }
    }
    $remaining = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'bsl-indexer.exe'" -ErrorAction Stop | Where-Object {
        Test-ManagedCodeIndexClient -Process $_ -Indexer $Indexer -ConfigPath $ConfigPath
    })
    if ($remaining.Count -gt 0) { throw 'Managed MCP readers restarted during update. Disconnect code-index clients and retry.' }
    Write-SetupOk "Managed MCP readers stopped: $($clients.Count)."
}

function Assert-CodeIndexStopped {
    $status = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action status -RuntimeHome $codeIndexHome -Indexer $managedIndexer -Json
    $probe = Get-DaemonProbeFromOutput -CommandResult $status -Description 'Stopped daemon check'
    if ($probe.process_alive -eq $true -or $probe.status -notin @('offline', 'stale_runtime_info')) {
        throw "Code-index is not stopped: $($probe.status). Close active code-index clients and retry."
    }
}

Write-SetupStep '1/6. Checking code-index installation and registered paths'
$ToolkitRoot = [IO.Path]::GetFullPath($ToolkitRoot)
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = Join-Path $ToolkitRoot '..\..' }
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
if ([string]::IsNullOrWhiteSpace($CodexHome)) { $CodexHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
$CodexHome = [IO.Path]::GetFullPath($CodexHome)
$codeIndexHome = Join-Path $CodexHome 'code-index'
$managedIndexer = Resolve-ExistingFile -Path (Join-Path $codeIndexHome 'bsl-indexer.exe') -Description 'Installed bsl-indexer (run install.cmd first)'
$targetCodeIndexConfig = Resolve-ExistingFile -Path (Join-Path $codeIndexHome 'daemon.toml') -Description 'Installed daemon configuration'
$daemonLauncher = Resolve-ExistingFile -Path (Join-Path $ToolkitRoot 'mcp\code-index-daemon.ps1') -Description 'Daemon launcher'
$mcpLauncher = Resolve-ExistingFile -Path (Join-Path $ToolkitRoot 'mcp\code-index-mcp.ps1') -Description 'MCP launcher'
$node = Resolve-NodePath -RequestedPath $NodePath
$nodeVersion = Assert-MinimumVersion -Executable $node -MinimumVersion ([version]'18.0.0') -Description 'Node.js'
$entries = @(Get-CodeIndexConfiguredPaths -ConfigPath $targetCodeIndexConfig)
$templatePath = Join-Path $ToolkitRoot 'code-index\daemon.toml.template'
$template = [IO.File]::ReadAllText($templatePath).Replace('__WORKSPACE_ROOT_FORWARD__', $WorkspaceRoot.Replace('\', '/'))
$managedAliases = @{}
foreach ($block in Get-CodeIndexPathBlocks -Content $template) {
    $alias = Get-CodeIndexPathAlias -Block $block.Value
    $pathMatch = [regex]::Match($block.Value, '(?m)^path = (?<value>".*")\r?$')
    if (-not $pathMatch.Success -or $managedAliases.ContainsKey($alias)) { throw 'Invalid Kafka path template.' }
    $expectedPath = [IO.Path]::GetFullPath(($pathMatch.Groups['value'].Value | ConvertFrom-Json).Replace('/', '\')).TrimEnd('\')
    $registered = @($entries | Where-Object Alias -eq $alias)
    if ($registered.Count -ne 1 -or -not $registered[0].Path.TrimEnd('\').Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Alias '$alias' does not match the canonical Kafka path '$expectedPath'. Run install.cmd to repair configuration."
    }
    $managedAliases[$alias] = $true
}
if ($managedAliases.Count -eq 0) { throw 'Kafka template has no managed paths.' }
# Validate the entire deletion scope before stopping the daemon or deleting data.
foreach ($entry in $entries) {
    if (-not (Test-Path -LiteralPath $entry.Path -PathType Container)) { throw "Registered root is missing: $($entry.Alias) ($($entry.Path))" }
    if ($managedAliases.ContainsKey($entry.Alias)) {
        $candidate = Join-Path $entry.Path '.code-index'
        $cursor = $candidate
        while (-not [string]::IsNullOrWhiteSpace($cursor)) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
            if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing cleanup through a reparse point: '$cursor'." }
            $cursor = Split-Path -Parent $cursor
        }
        if ((Test-Path -LiteralPath $candidate) -and -not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Index target is not a directory: '$candidate'." }
    }
    Write-SetupOk "Registered path '$($entry.Alias)': $($entry.Path)"
}
Write-SetupOk "Node.js $nodeVersion; $($managedAliases.Count) Kafka indexes to rebuild, $($entries.Count) total paths to verify."
$configurationHash = (Get-FileHash -LiteralPath $targetCodeIndexConfig -Algorithm SHA256).Hash
$downloadRoot = $null
$daemonWasStopped = $false
$startAttempted = $false
$runtimeTouched = $false
$removedIndexCount = 0
$script:indexCleanupStarted = $false
$runtimeBackup = Join-Path $CodexHome ('backups\code-index-update\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
try {
    Write-SetupStep '2/6. Stopping the managed code-index daemon'
    $status = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action status -RuntimeHome $codeIndexHome -Indexer $managedIndexer -Json
    $probe = Get-DaemonProbeFromOutput -CommandResult $status -Description 'Pre-update status'
    if ((Get-CodeIndexPreUpdateAction -Probe $probe) -eq 'stop') {
        $stop = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action stop -RuntimeHome $codeIndexHome -Indexer $managedIndexer
        $stop.Output | Write-Output
        if ($stop.ExitCode -ne 0) { throw "Daemon stop failed: $($stop.Output -join ' ')" }
        $daemonWasStopped = $true
    }
    Assert-CodeIndexStopped
    Write-SetupOk 'Managed daemon is stopped.'
    Stop-ManagedCodeIndexClients -Indexer $managedIndexer -ConfigPath $targetCodeIndexConfig

    Write-SetupStep '3/6. Checking the latest bsl-indexer release and preparing runtime'
    $bundledRuntimeRoot = Join-Path $ToolkitRoot 'runtime\windows'
    $versionPattern = '(?i)\b(?:bsl-indexer|code-index)\s+(?<version>\d+\.\d+\.\d+(?:-[0-9a-z]+(?:\.[0-9a-z]+)*)?)'
    if (-not [string]::IsNullOrWhiteSpace($BslIndexerPath)) {
        $indexer = Resolve-ExistingFile -Path $BslIndexerPath -Description 'Explicit bsl-indexer'
        Write-SetupOk "Explicit runtime selected (GitHub check skipped): $indexer"
    }
    else {
        $release = Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'
        $availableVersion = Get-SemanticVersion -Value ([string]$release.tag_name) -Description 'Latest release'
        Write-SetupOk "Latest published release: $($release.tag_name)"
        $indexer = $null
        foreach ($candidate in @($managedIndexer, (Join-Path $bundledRuntimeRoot 'bsl-indexer.exe'))) {
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            try {
                $localVersion = Get-NativeSemanticVersion -Executable $candidate -Description 'Local bsl-indexer' -VersionPattern $versionPattern
                Write-Output "    Local version $localVersion : $candidate"
                if (-not (Test-RuntimeUpdateRequired -InstalledVersion $localVersion -AvailableVersion $availableVersion)) { $indexer = $candidate; break }
            }
            catch { Write-SetupWarning $_.Exception.Message }
        }
        if ($null -eq $indexer) {
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) ('kafka-code-index-update-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $downloadRoot | Out-Null
            $asset = Get-GitHubReleaseAsset -Release $release -NamePattern '^bsl-indexer-windows-x64\.zip$' -Description 'Windows x64 indexer'
            Write-Output "    Downloading $($asset.name) ($($asset.size) bytes)..."
            $archive = Join-Path $downloadRoot $asset.name
            $archiveHash = Save-GitHubReleaseAsset -Asset $asset -Destination $archive
            $extractRoot = Join-Path $downloadRoot 'extracted'
            Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot
            $downloaded = Resolve-ExistingFile -Path (Join-Path $extractRoot 'bsl-indexer.exe') -Description 'Downloaded executable'
            $downloadedVersion = Get-NativeSemanticVersion -Executable $downloaded -Description 'Downloaded bsl-indexer' -VersionPattern $versionPattern
            if ($downloadedVersion -ne $availableVersion) { throw "Downloaded version $downloadedVersion differs from release $availableVersion." }
            $indexer = Save-VerifiedRuntimeFile -Source $downloaded -Destination (Join-Path $bundledRuntimeRoot 'bsl-indexer.exe')
            Write-SetupOk "Downloaded and verified $downloadedVersion; asset SHA-256 $archiveHash. Cached: $indexer"
        }
        else { Write-SetupOk 'Latest release is already available locally; download is unnecessary.' }
    }
    $indexerVersion = Assert-MinimumVersion -Executable $indexer -MinimumVersion ([version]'0.69.0') -Description 'bsl-indexer'

    Write-SetupStep '4/6. Removing old Kafka .code-index directories and updating executable'
    Assert-CodeIndexStopped
    if ((Get-FileHash -LiteralPath $targetCodeIndexConfig -Algorithm SHA256).Hash -ne $configurationHash) { throw 'Daemon configuration changed during update; retry after configuration changes finish.' }
    Stop-ManagedCodeIndexClients -Indexer $managedIndexer -ConfigPath $targetCodeIndexConfig
    Assert-CodeIndexStopped
    $cleanup = Remove-ManagedCodeIndexDirectories -ConfigPath $targetCodeIndexConfig -ManagedAliases $managedAliases -WorkspaceRoot $WorkspaceRoot
    $removedIndexCount = @($cleanup.Removed).Count
    Write-SetupOk "Removed $removedIndexCount old index directories; checked $($cleanup.RegisteredCount) Kafka paths."
    $runtimeTouched = $true
    $updated = Install-ManagedFile -Source $indexer -Destination $managedIndexer -BackupRoot $runtimeBackup
    Write-SetupOk "Managed bsl-indexer $indexerVersion (updated: $updated): $managedIndexer"

    Write-SetupStep '5/6. Starting code-index and waiting for all registered paths'
    $startAttempted = $true
    $start = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action run -RuntimeHome $codeIndexHome -Indexer $managedIndexer -StartupTimeoutSeconds 60
    $start.Output | Write-Output
    if ($start.ExitCode -ne 0) { throw "Daemon startup failed: $($start.Output -join ' ')" }
    Write-Output "    Waiting up to $IndexReadyTimeoutSeconds seconds for indexing..."
    $readyCount = Wait-CodeIndexReady -Launcher $daemonLauncher -RuntimeHome $codeIndexHome -Indexer $managedIndexer -ConfigPath $targetCodeIndexConfig -TimeoutSeconds $IndexReadyTimeoutSeconds
    Write-SetupOk "All $readyCount registered paths are ready."

    Write-SetupStep '6/6. Checking code-index MCP and final readiness'
    $toolCount = Test-StdioMcpServer -Executable (Join-Path $PSHOME 'powershell.exe') -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $mcpLauncher,
        '-CodeIndexHome', $codeIndexHome, '-BslIndexerPath', $managedIndexer, '-NodePath', $node, '-SkipDaemonBootstrap'
    ) -WorkingDirectory $WorkspaceRoot -Description 'code-index MCP' -RequiredTools @('health', 'get_function', 'get_object_structure') -TimeoutSeconds $McpReadyTimeoutSeconds
    Write-SetupOk "code-index MCP is ready ($toolCount tools)."
    $readyCount = Wait-CodeIndexReady -Launcher $daemonLauncher -RuntimeHome $codeIndexHome -Indexer $managedIndexer -ConfigPath $targetCodeIndexConfig -TimeoutSeconds $IndexReadyTimeoutSeconds
    if ((Get-FileHash -LiteralPath $targetCodeIndexConfig -Algorithm SHA256).Hash -ne $configurationHash) { throw 'Daemon configuration changed during readiness checks.' }
    Write-Output ''
    Write-Output 'RESULT: code-index update completed successfully.'
    Write-Output "  - bsl-indexer: $indexerVersion (updated: $updated)"
    Write-Output "  - Old Kafka indexes removed: $removedIndexCount of $($managedAliases.Count)"
    Write-Output "  - All registered paths ready: $readyCount"
    Write-Output "  - code-index MCP tools available: $toolCount"
    Write-Output 'Reconnect code-index in Codex (or restart Codex) to recreate the stopped MCP readers.'
}
catch {
    $updateFailure = $_.Exception.Message
    if ($script:indexCleanupStarted) {
        Write-Output '[WARNING] Index cleanup started; removed or partially removed indexes must be rebuilt. Readiness is not confirmed.'
    }
    else { Write-Output '[WARNING] Update failed before index cleanup; index directories were not removed by this updater.' }
    try {
        if ($startAttempted) {
            $stop = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action stop -RuntimeHome $codeIndexHome -Indexer $managedIndexer
            if ($stop.ExitCode -ne 0) { throw 'Could not stop daemon for runtime rollback.' }
        }
        Assert-CodeIndexStopped
        if ($runtimeTouched) {
            Restore-ManagedFile -Destination $managedIndexer -BackupRoot $runtimeBackup -ExistedBefore $true
            Write-Output '[ROLLBACK] Previous managed executable restored; downloaded cache retained.'
        }
        if ($daemonWasStopped) {
            $restart = Invoke-ManagedDaemon -Launcher $daemonLauncher -Action run -RuntimeHome $codeIndexHome -Indexer $managedIndexer -StartupTimeoutSeconds 60
            $restart.Output | Write-Output
            if ($restart.ExitCode -ne 0) { throw 'Previous daemon could not be restarted.' }
            Write-Output '[ROLLBACK] Previous daemon restarted; indexing readiness has not been verified.'
        }
    }
    catch { $updateFailure += " Recovery failed: $($_.Exception.Message)" }
    throw $updateFailure
}
finally {
    if ($null -ne $downloadRoot) {
        $temporaryPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        $fullDownloadRoot = [IO.Path]::GetFullPath($downloadRoot)
        if (-not $fullDownloadRoot.StartsWith($temporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $fullDownloadRoot) -notlike 'kafka-code-index-update-*') { throw 'Unsafe temporary cleanup path.' }
        if (Test-Path -LiteralPath $fullDownloadRoot -PathType Container) { Remove-Item -LiteralPath $fullDownloadRoot -Recurse -Force }
    }
}