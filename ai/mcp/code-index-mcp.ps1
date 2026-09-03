[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CodeIndexHome,
    [string]$BslIndexerPath = $env:BSL_INDEXER_EXE,
    [string]$NodePath = $env:CODE_INDEX_NODE,
    [switch]$SkipDaemonBootstrap
)

$ErrorActionPreference = 'Stop'

function Resolve-BslIndexer {
    param(
        [string]$RequestedPath,
        [Parameter(Mandatory)][string]$RuntimeHome
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    $candidates += (Join-Path $RuntimeHome 'bsl-indexer.exe')

    foreach ($candidate in $candidates) {
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            return $fullPath
        }
    }

    $command = Get-Command 'bsl-indexer' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "bsl-indexer executable is missing. Set BSL_INDEXER_EXE or place bsl-indexer.exe in '$RuntimeHome'."
}

function Resolve-Node {
    param(
        [string]$RequestedPath,
        [string]$ProgramFilesRoot = [Environment]::GetEnvironmentVariable('ProgramFiles')
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $fullPath = [System.IO.Path]::GetFullPath($RequestedPath)
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            return $fullPath
        }
        throw "Node executable does not exist: '$fullPath'."
    }

    if (-not [string]::IsNullOrWhiteSpace($ProgramFilesRoot)) {
        $systemNode = Join-Path $ProgramFilesRoot 'nodejs\node.exe'
        if (Test-Path -LiteralPath $systemNode -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($systemNode)
        }
    }

    $command = @(Get-Command 'node' -CommandType Application -ErrorAction SilentlyContinue) |
        Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }

    throw 'Node executable is missing. Set CODE_INDEX_NODE or add node to PATH.'
}

function Assert-MinimumVersion {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][version]$MinimumVersion,
        [Parameter(Mandatory)][string]$Description
    )

    $versionOutput = @(& $Executable --version 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch '(?<version>\d+\.\d+\.\d+)') {
        throw "$Description version could not be determined from '$Executable --version': $versionOutput"
    }
    $actualVersion = [version]$Matches.version
    if ($actualVersion -lt $MinimumVersion) {
        throw "$Description $actualVersion is unsupported; version $MinimumVersion or newer is required."
    }
}

$CodeIndexHome = [System.IO.Path]::GetFullPath($CodeIndexHome)
if (-not (Test-Path -LiteralPath $CodeIndexHome -PathType Container)) {
    throw "CODE_INDEX_HOME does not exist: '$CodeIndexHome'. Run the workspace Codex installer first."
}

$daemonConfig = Join-Path $CodeIndexHome 'daemon.toml'
if (-not (Test-Path -LiteralPath $daemonConfig -PathType Leaf)) {
    throw "Managed code-index daemon configuration is missing: '$daemonConfig'."
}

$executable = Resolve-BslIndexer -RequestedPath $BslIndexerPath -RuntimeHome $CodeIndexHome
$node = Resolve-Node -RequestedPath $NodePath
Assert-MinimumVersion -Executable $node -MinimumVersion ([version]'18.0.0') -Description 'Node.js'
Assert-MinimumVersion -Executable $executable -MinimumVersion ([version]'0.69.0') -Description 'bsl-indexer'
$proxy = Join-Path $PSScriptRoot 'code-index-proxy.mjs'
if (-not (Test-Path -LiteralPath $proxy -PathType Leaf)) {
    throw "Managed code-index MCP proxy is missing: '$proxy'."
}
$env:CODE_INDEX_HOME = $CodeIndexHome
if (-not $SkipDaemonBootstrap) {
    $daemonLauncher = Join-Path $PSScriptRoot 'code-index-daemon.ps1'
    if (-not (Test-Path -LiteralPath $daemonLauncher -PathType Leaf)) {
        throw "Managed code-index daemon launcher is missing: '$daemonLauncher'."
    }
    $daemonArguments = @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $daemonLauncher,
        '-Action', 'run',
        '-CodeIndexHome', $CodeIndexHome,
        '-BslIndexerPath', $executable,
        '-StartupTimeoutSeconds', '30'
    )
    $bootstrapStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $bootstrapStartInfo.FileName = 'powershell.exe'
    $bootstrapStartInfo.WorkingDirectory = $CodeIndexHome
    $bootstrapStartInfo.UseShellExecute = $false
    $bootstrapStartInfo.CreateNoWindow = $true
    $bootstrapStartInfo.RedirectStandardOutput = $true
    $bootstrapStartInfo.RedirectStandardError = $true
    $bootstrapStartInfo.Arguments = ($daemonArguments | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }) -join ' '
    $bootstrap = [System.Diagnostics.Process]::new()
    $bootstrap.StartInfo = $bootstrapStartInfo
    if (-not $bootstrap.Start()) {
        throw 'Could not start the managed code-index daemon bootstrap process.'
    }
    if (-not $bootstrap.WaitForExit(40000)) {
        $bootstrap.Kill()
        throw "Managed code-index daemon bootstrap timed out. Check '$CodeIndexHome\daemon.stderr.log'."
    }
    if ($bootstrap.ExitCode -ne 0) {
        $daemonOutput = @(
            $bootstrap.StandardOutput.ReadToEnd()
            $bootstrap.StandardError.ReadToEnd()
        ) -join [Environment]::NewLine
        throw "Managed code-index daemon bootstrap failed with code $($bootstrap.ExitCode): $daemonOutput"
    }
}
& $node $proxy --indexer $executable --config $daemonConfig
exit $LASTEXITCODE
