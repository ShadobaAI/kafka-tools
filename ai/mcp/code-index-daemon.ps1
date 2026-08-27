[CmdletBinding()]
param(
    [ValidateSet('run', 'status', 'reload', 'stop')]
    [string]$Action = 'status',
    [string]$CodeIndexHome,
    [string]$BslIndexerPath = $env:BSL_INDEXER_EXE,
    [switch]$Json,
    [ValidateRange(1, 120)]
    [int]$StartupTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

function Read-DaemonRuntimeInfo {
    param([Parameter(Mandatory)][string]$RuntimePath)

    if (-not (Test-Path -LiteralPath $RuntimePath -PathType Leaf)) {
        return $null
    }
    try {
        $runtime = Get-Content -LiteralPath $RuntimePath -Raw | ConvertFrom-Json
        if (
            $null -eq $runtime.pid -or
            [string]::IsNullOrWhiteSpace([string]$runtime.http_host) -or
            $null -eq $runtime.http_port
        ) {
            return $null
        }
        return $runtime
    }
    catch {
        return $null
    }
}

function Test-ProcessAlive {
    param([Parameter(Mandatory)][int]$ProcessId)

    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Get-DaemonProbe {
    param([Parameter(Mandatory)][string]$RuntimePath)

    $runtimeExists = Test-Path -LiteralPath $RuntimePath -PathType Leaf
    $runtime = Read-DaemonRuntimeInfo -RuntimePath $RuntimePath
    if ($null -eq $runtime) {
        return [pscustomobject]@{
            status = if ($runtimeExists) { 'stale_runtime_info' } else { 'offline' }
            process_alive = $false
            endpoint = $null
            runtime = $null
            health = $null
            error = if ($runtimeExists) { 'daemon.json is invalid' } else { 'daemon.json is missing' }
        }
    }

    $processAlive = Test-ProcessAlive -ProcessId ([int]$runtime.pid)
    $endpoint = "http://$($runtime.http_host):$($runtime.http_port)"
    try {
        $health = Invoke-RestMethod -Method Get -Uri "$endpoint/health" -TimeoutSec 2
        if ([string]$health.status -ne 'running') {
            throw "unexpected daemon status '$($health.status)'"
        }
        if ([int]$health.pid -ne [int]$runtime.pid) {
            throw "daemon PID mismatch: daemon.json=$($runtime.pid), /health=$($health.pid)"
        }
        return [pscustomobject]@{
            status = 'online'
            process_alive = $processAlive
            endpoint = $endpoint
            runtime = $runtime
            health = $health
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            status = if ($processAlive) { 'unhealthy' } else { 'stale_runtime_info' }
            process_alive = $processAlive
            endpoint = $endpoint
            runtime = $runtime
            health = $null
            error = $_.Exception.Message
        }
    }
}

function Write-DaemonStatus {
    param(
        [Parameter(Mandatory)]$Probe,
        [switch]$AsJson
    )

    if ($AsJson) {
        $Probe | ConvertTo-Json -Depth 20 -Compress
        return
    }
    if ($Probe.status -eq 'online') {
        Write-Output "bsl-indexer daemon is online: PID $($Probe.runtime.pid), $($Probe.endpoint)."
        return
    }
    Write-Output "bsl-indexer daemon is $($Probe.status): $($Probe.error)"
}

function Start-DetachedDaemonProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    if ($null -eq ('SharedCodeIndex.DetachedProcess' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace SharedCodeIndex
{
    public static class DetachedProcess
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public uint dwX;
            public uint dwY;
            public uint dwXSize;
            public uint dwYSize;
            public uint dwXCountChars;
            public uint dwYCountChars;
            public uint dwFillAttribute;
            public uint dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public uint dwProcessId;
            public uint dwThreadId;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CreateProcess(
            string lpApplicationName,
            StringBuilder lpCommandLine,
            IntPtr lpProcessAttributes,
            IntPtr lpThreadAttributes,
            bool bInheritHandles,
            uint dwCreationFlags,
            IntPtr lpEnvironment,
            string lpCurrentDirectory,
            ref STARTUPINFO lpStartupInfo,
            out PROCESS_INFORMATION lpProcessInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static uint Start(string executable, string arguments, string workingDirectory)
        {
            const uint DETACHED_PROCESS = 0x00000008;
            const uint CREATE_NO_WINDOW = 0x08000000;
            var startup = new STARTUPINFO();
            startup.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            var commandLine = new StringBuilder("\"" + executable.Replace("\"", "\\\"") + "\" " + arguments);
            PROCESS_INFORMATION process;
            if (!CreateProcess(
                executable,
                commandLine,
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                DETACHED_PROCESS | CREATE_NO_WINDOW,
                IntPtr.Zero,
                workingDirectory,
                ref startup,
                out process))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            CloseHandle(process.hThread);
            CloseHandle(process.hProcess);
            return process.dwProcessId;
        }
    }
}
'@
    }

    return [SharedCodeIndex.DetachedProcess]::Start($Executable, 'daemon run', $WorkingDirectory)
}

function New-StartupMutex {
    param([Parameter(Mandatory)][string]$RuntimeHome)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($RuntimeHome.ToLowerInvariant())
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
    return [System.Threading.Mutex]::new($false, "Local\SharedCodeIndex.Start.$hash")
}

if ([string]::IsNullOrWhiteSpace($CodeIndexHome)) {
    $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    }
    else {
        $env:CODEX_HOME
    }
    $CodeIndexHome = Join-Path $codexHome 'code-index'
}
$CodeIndexHome = [System.IO.Path]::GetFullPath($CodeIndexHome)
if (-not (Test-Path -LiteralPath (Join-Path $CodeIndexHome 'daemon.toml') -PathType Leaf)) {
    throw "Managed daemon configuration is missing in '$CodeIndexHome'. Run the workspace Codex installer first."
}

$candidates = @()
if (-not [string]::IsNullOrWhiteSpace($BslIndexerPath)) {
    $candidates += $BslIndexerPath
}
$candidates += (Join-Path $CodeIndexHome 'bsl-indexer.exe')
$executable = $candidates | ForEach-Object { [System.IO.Path]::GetFullPath($_) } | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
} | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($executable)) {
    $command = Get-Command 'bsl-indexer' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $executable = $command.Source
    }
}
if ([string]::IsNullOrWhiteSpace($executable)) {
    throw "bsl-indexer executable is missing. Set BSL_INDEXER_EXE or place bsl-indexer.exe in '$CodeIndexHome'."
}

$env:CODE_INDEX_HOME = $CodeIndexHome
$runtimePath = Join-Path $CodeIndexHome 'daemon.json'

if ($Action -eq 'status') {
    $probe = Get-DaemonProbe -RuntimePath $runtimePath
    Write-DaemonStatus -Probe $probe -AsJson:$Json
    if ($probe.status -ne 'online') {
        exit 1
    }
    exit 0
}

if ($Action -eq 'run') {
    $startupMutex = New-StartupMutex -RuntimeHome $CodeIndexHome
    $mutexAcquired = $false
    try {
        try {
            $mutexAcquired = $startupMutex.WaitOne([TimeSpan]::FromSeconds($StartupTimeoutSeconds + 5))
        }
        catch [System.Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw "Timed out waiting for another managed code-index daemon startup in '$CodeIndexHome'."
        }

        $existingProbe = Get-DaemonProbe -RuntimePath $runtimePath
        if ($existingProbe.status -eq 'online') {
            Write-DaemonStatus -Probe $existingProbe -AsJson:$Json
            exit 0
        }
        if ($existingProbe.status -eq 'unhealthy' -and $existingProbe.process_alive) {
            throw "bsl-indexer daemon process $($existingProbe.runtime.pid) is alive but its endpoint '$($existingProbe.endpoint)' is unhealthy: $($existingProbe.error). Refusing to start a competing daemon; inspect it and use the explicit stop action before retrying."
        }
        if ($existingProbe.status -eq 'stale_runtime_info') {
            Remove-Item -LiteralPath $runtimePath -Force -ErrorAction SilentlyContinue
        }

        $previousDetached = $env:CODE_INDEX_DAEMON_DETACHED
        $env:CODE_INDEX_DAEMON_DETACHED = '1'
        try {
            # CreateProcess is called with bInheritHandles=false. This is stronger than
            # stream redirection: the daemon cannot retain the MCP client's anonymous
            # stdio pipes and cannot later panic when those transient handles close.
            $daemonPid = Start-DetachedDaemonProcess `
                -Executable $executable `
                -WorkingDirectory $CodeIndexHome
            $process = Get-Process -Id $daemonPid -ErrorAction Stop
        }
        finally {
            $env:CODE_INDEX_DAEMON_DETACHED = $previousDetached
        }

        $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 250
            $probe = Get-DaemonProbe -RuntimePath $runtimePath
            if ($probe.status -eq 'online') {
                Write-DaemonStatus -Probe $probe -AsJson:$Json
                exit 0
            }
            $process.Refresh()
            if ($process.HasExited) {
                $probe = Get-DaemonProbe -RuntimePath $runtimePath
                if ($probe.status -eq 'online') {
                    Write-DaemonStatus -Probe $probe -AsJson:$Json
                    exit 0
                }
                throw "bsl-indexer daemon process $daemonPid exited before becoming healthy. Current state: $($probe.status): $($probe.error). Inspect the current daemon log in '$CodeIndexHome'."
            }
        } while ([DateTime]::UtcNow -lt $deadline)

        throw "bsl-indexer daemon did not become healthy within $StartupTimeoutSeconds seconds. Last state: $($probe.status): $($probe.error)"
    }
    finally {
        if ($mutexAcquired) {
            $startupMutex.ReleaseMutex()
        }
        $startupMutex.Dispose()
    }
}

$probeBeforeAction = Get-DaemonProbe -RuntimePath $runtimePath
$processIdBeforeStop = if ($Action -eq 'stop' -and $null -ne $probeBeforeAction.runtime) {
    [int]$probeBeforeAction.runtime.pid
}
else {
    $null
}
$arguments = @('daemon', $Action)
& $executable @arguments
$exitCode = $LASTEXITCODE
if ($Action -eq 'stop' -and $exitCode -eq 0 -and $null -ne $processIdBeforeStop) {
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 200
        $processAlive = Test-ProcessAlive -ProcessId $processIdBeforeStop
    } while ($processAlive -and [DateTime]::UtcNow -lt $deadline)
    if ($processAlive) {
        throw "bsl-indexer daemon process $processIdBeforeStop did not exit within 10 seconds after a successful stop command."
    }
}
exit $exitCode
