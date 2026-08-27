[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$proxy = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
$node = (Get-Command 'node' -CommandType Application -ErrorAction Stop).Source
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-proxy-lifecycle-" + [guid]::NewGuid().ToString('N'))
$process = $null

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $daemonConfig = Join-Path $temporaryRoot 'daemon.toml'
    [System.IO.File]::WriteAllText(
        $daemonConfig,
        "[daemon]`r`nhttp_port = 0`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )
    $exitingServer = Join-Path $temporaryRoot 'exiting-server.mjs'
    [System.IO.File]::WriteAllText(
        $exitingServer,
        'process.exit(7);',
        [System.Text.UTF8Encoding]::new($false)
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $node
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $arguments = @(
        $proxy,
        '--indexer', $node,
        '--indexer-arg', $exitingServer,
        '--config', $daemonConfig
    )
    $startInfo.Arguments = ($arguments | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }) -join ' '

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start code-index proxy lifecycle test process.'
    }
    if (-not $process.WaitForExit(5000)) {
        throw 'Code-index proxy stayed alive after its child exited while client stdin remained open.'
    }
    if ($process.ExitCode -ne 7) {
        throw "Code-index proxy did not propagate the child exit code; got $($process.ExitCode)."
    }

    Write-Output 'code-index-proxy-lifecycle: child exit terminates proxy with open client stdin'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        $process.Kill($true)
    }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
