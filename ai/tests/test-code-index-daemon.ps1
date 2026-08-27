[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$launcher = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-daemon.ps1'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-daemon-" + [guid]::NewGuid().ToString('N'))
$runtimeHome = Join-Path $temporaryRoot 'runtime'

function Invoke-Launcher {
    param([Parameter(Mandatory)][string[]]$LauncherArguments)

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File $launcher @LauncherArguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        exit_code = $exitCode
        output = @($output) -join [Environment]::NewLine
    }
}

try {
    New-Item -ItemType Directory -Path $runtimeHome -Force | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeHome 'daemon.toml'),
        "[daemon]`r`nhttp_port = 0`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $fakeIndexer = Join-Path $runtimeHome 'bsl-indexer.exe'
    [System.IO.File]::WriteAllBytes($fakeIndexer, [byte[]](0))
    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeHome 'daemon.json'),
        '{"pid":2147483647,"version":"test","http_host":"127.0.0.1","http_port":9,"started_at":"test"}',
        [System.Text.UTF8Encoding]::new($false)
    )

    $status = Invoke-Launcher -LauncherArguments @(
        '-Action', 'status',
        '-CodeIndexHome', $runtimeHome,
        '-BslIndexerPath', $fakeIndexer,
        '-Json'
    )
    $statusJson = $status.output | ConvertFrom-Json
    if (
        $status.exit_code -eq 0 -or
        $statusJson.status -ne 'stale_runtime_info' -or
        $statusJson.process_alive -ne $false
    ) {
        throw 'Managed daemon status trusted stale daemon.json without a live PID and endpoint.'
    }

    $source = Get-Content -LiteralPath $launcher -Raw
    foreach ($requiredFragment in @(
        "`$env:CODE_INDEX_DAEMON_DETACHED = '1'",
        'Start-DetachedDaemonProcess',
        'New-StartupMutex',
        'Refusing to start a competing daemon',
        'bInheritHandles=false',
        'Get-DaemonProbe -RuntimePath $runtimePath',
        'did not become healthy within',
        'did not exit within 10 seconds after a successful stop command'
    )) {
        if (-not $source.Contains($requiredFragment)) {
            throw "Managed daemon launcher is missing required lifecycle guard: $requiredFragment"
        }
    }

    [System.IO.File]::WriteAllText(
        (Join-Path $runtimeHome 'daemon.json'),
        "{`"pid`":$PID,`"version`":`"test`",`"http_host`":`"127.0.0.1`",`"http_port`":9,`"started_at`":`"test`"}",
        [System.Text.UTF8Encoding]::new($false)
    )
    $unhealthy = Invoke-Launcher -LauncherArguments @(
        '-Action', 'run',
        '-CodeIndexHome', $runtimeHome,
        '-BslIndexerPath', $fakeIndexer,
        '-StartupTimeoutSeconds', '1'
    )
    if ($unhealthy.exit_code -eq 0 -or $unhealthy.output -notmatch 'Refusing to start a competing daemon') {
        throw 'Managed daemon launcher attempted to compete with an unhealthy live daemon process.'
    }

    Write-Output 'code-index-daemon: stale runtime, serialized startup, unhealthy-process refusal, and durable launch guards passed'
    $global:LASTEXITCODE = 0
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
