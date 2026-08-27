[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkspaceRoot,
    [Parameter(Mandatory)][string]$CodeIndexHome,
    [string]$Procedure = 'ЗапуститьПотоки'
)

$ErrorActionPreference = 'Stop'
$launcher = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-mcp.ps1'))
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$CodeIndexHome = [System.IO.Path]::GetFullPath($CodeIndexHome)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = 'powershell.exe'
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
$startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
$startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
$startInfo.CreateNoWindow = $true
foreach ($argument in @(
    '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', $launcher,
    '-CodeIndexHome', $CodeIndexHome
)) {
    $startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw 'Could not start the managed code-index MCP launcher.'
}

$requests = @(
    @{
        jsonrpc = '2.0'
        id = 1
        method = 'initialize'
        params = @{
            protocolVersion = '2025-03-26'
            capabilities = @{}
            clientInfo = @{ name = 'kafka-code-index-runtime-test'; version = '1.0' }
        }
    },
    @{ jsonrpc = '2.0'; method = 'notifications/initialized'; params = @{} },
    @{ jsonrpc = '2.0'; id = 2; method = 'tools/list'; params = @{} },
    @{
        jsonrpc = '2.0'
        id = 3
        method = 'tools/call'
        params = @{
            name = 'get_callers_bsl'
            arguments = @{ repo = 'kafka-adapter'; procedure = $Procedure; limit = 200 }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 4
        method = 'tools/call'
        params = @{
            name = 'get_callees_bsl'
            arguments = @{ repo = 'kafka-adapter'; procedure = $Procedure; limit = 200 }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 5
        method = 'tools/call'
        params = @{
            name = 'get_call_tree_bsl'
            arguments = @{ repo = 'kafka-adapter'; procedure = $Procedure; direction = 'callers'; max_depth = 3; max_nodes = 500 }
        }
    },
    @{ jsonrpc = '2.0'; id = 6; method = 'tools/call'; params = @{ name = 'health'; arguments = @{} } },
    @{
        jsonrpc = '2.0'
        id = 7
        method = 'tools/call'
        params = @{
            name = 'grep_code'
            arguments = @{ repo = 'kafka-adapter'; pattern = $Procedure; language = 'bsl'; limit = 10 }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 8
        method = 'tools/call'
        params = @{
            name = 'get_function'
            arguments = @{ repo = 'kafka-adapter'; name = $Procedure }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 9
        method = 'tools/call'
        params = @{
            name = 'get_register_writers'
            arguments = @{ repo = 'kafka-adapter'; object = 'InformationRegister.кфкИсходящиеСообщения' }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 10
        method = 'tools/call'
        params = @{
            name = 'get_callers_bsl'
            arguments = @{ repo = 'kafka-adapter'; procedure = $Procedure.ToLowerInvariant(); limit = 200 }
        }
    },
    @{
        jsonrpc = '2.0'
        id = 11
        method = 'tools/call'
        params = @{
            name = 'search_function'
            arguments = @{ repo = 'kafka-adapter'; query = $Procedure; limit = 10 }
        }
    }
)
foreach ($request in $requests) {
    $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 10 -Compress))
}
$process.StandardInput.Close()

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(30000)) {
    $process.Kill($true)
    throw 'Managed code-index MCP runtime smoke timed out.'
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($process.ExitCode -ne 0) {
    throw "Managed code-index MCP exited with $($process.ExitCode): $stderr"
}

$responses = @{}
foreach ($line in ($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $response = $line | ConvertFrom-Json -Depth 30
    if ($null -ne $response.id) {
        $responses[[int]$response.id] = $response
    }
}

$tools = @($responses[2].result.tools)
$toolNames = @($tools | ForEach-Object { $_.name })
foreach ($requiredTool in @('get_callers_bsl', 'get_callees_bsl', 'get_call_tree_bsl')) {
    if ($requiredTool -notin $toolNames) {
        throw "Runtime MCP surface is missing '$requiredTool'."
    }
}
if ($tools.Count -ne 34) {
    throw "Runtime MCP surface has $($tools.Count) tools instead of 34."
}
$writersTool = $tools | Where-Object { $_.name -eq 'get_register_writers' }
if ($writersTool.description -notmatch 'does not analyze programmatic') {
    throw 'Runtime MCP did not expose the corrected declarative register-writer coverage.'
}

$callers = $responses[3].result.content[0].text | ConvertFrom-Json -Depth 30
if ($callers.coverage.source -ne 'proc_call_graph') {
    throw 'get_callers_bsl did not report proc_call_graph as its source.'
}
if ($callers.callers.Count -eq 0) {
    throw "get_callers_bsl returned no indexed static callers for '$Procedure'."
}
$intermoduleEdges = @($callers.callers | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.callee_proc_key) -and
    ([string]$_.caller_proc_key -split '::', 2)[0] -ne ([string]$_.callee_proc_key -split '::', 2)[0]
}).Count
if ($Procedure -eq 'ЗапуститьПотоки' -and $intermoduleEdges -eq 0) {
    throw "get_callers_bsl did not recover the expected intermodule edge for '$Procedure'."
}

$callees = $responses[4].result.content[0].text | ConvertFrom-Json -Depth 30
if ($callees.coverage.source -ne 'proc_call_graph' -or $callees.callees.Count -eq 0) {
    throw "get_callees_bsl returned no static callees for '$Procedure'."
}
$tree = $responses[5].result.content[0].text | ConvertFrom-Json -Depth 30
if ($tree.coverage.source -ne 'proc_call_graph' -or $tree.edges.Count -eq 0) {
    throw "get_call_tree_bsl returned no static caller tree for '$Procedure'."
}

$health = $responses[6].result.content[0].text | ConvertFrom-Json -Depth 30
if (
    $health.daemon.status -ne 'online' -or
    $health.daemon.state -ne 'healthy' -or
    $health.daemon.endpoint_verified -ne $true
) {
    throw "Managed MCP health did not verify the daemon endpoint: $($responses[6].result.content[0].text)"
}
$expectedKafkaRepos = @(
    'kafka-adapter',
    'kafka-adapter-base',
    'kafka-adapter-examples',
    'kafka-adapter-conv',
    'kafka-adapter-tests-unit'
)
$reportedKafkaRepos = @($health.repos | Where-Object { $_.repo -in $expectedKafkaRepos })
$missingKafkaRepos = @($expectedKafkaRepos | Where-Object { $_ -notin $reportedKafkaRepos.repo })
$notReadyKafkaRepos = @($reportedKafkaRepos | Where-Object { $_.path_status.status -ne 'ready' })
if ($missingKafkaRepos.Count -ne 0 -or $notReadyKafkaRepos.Count -ne 0) {
    throw "Managed MCP health did not report all required Kafka repository paths as ready: $($responses[6].result.content[0].text)"
}
$grepText = [string]$responses[7].result.content[0].text
if ($grepText -match 'daemon_offline' -or $grepText -notmatch [regex]::Escape($Procedure)) {
    throw "grep_code did not return indexed source matches for '$Procedure': $grepText"
}
$functionText = [string]$responses[8].result.content[0].text
if ($functionText -match 'daemon_offline' -or $functionText -notmatch [regex]::Escape($Procedure)) {
    throw "get_function did not return indexed function content for '$Procedure': $functionText"
}
$writersText = [string]$responses[9].result.content[0].text
if ($writersText -match 'daemon_offline' -or $writersText -notmatch 'writers') {
    throw "get_register_writers did not return the declarative writer contract: $writersText"
}
$caseInsensitiveCallers = $responses[10].result.content[0].text | ConvertFrom-Json -Depth 30
if ($caseInsensitiveCallers.callers.Count -ne $callers.callers.Count) {
    throw "get_callers_bsl is not BSL-compatible case-insensitive for Cyrillic procedure '$Procedure'."
}
$searchFunctionText = [string]$responses[11].result.content[0].text
if ($searchFunctionText -match 'daemon_offline' -or $searchFunctionText -notmatch [regex]::Escape($Procedure)) {
    throw "search_function did not return daemon-backed function matches for '$Procedure': $searchFunctionText"
}

[pscustomobject]@{
    version = (& (Join-Path $CodeIndexHome 'bsl-indexer.exe') --version) -join ' '
    tools = $tools.Count
    procedure = $Procedure
    callers = $callers.callers.Count
    intermodule_edges = $intermoduleEdges
    callees = $callees.callees.Count
    caller_tree_edges = $tree.edges.Count
    resolved_edges = $callers.coverage.resolved_edges
    unresolved_edges = $callers.coverage.unresolved_edges
    target_resolution = $callers.coverage.target_resolution
    truncated = $callers.coverage.truncated
    daemon_status = $health.daemon.status
    daemon_endpoint_verified = $health.daemon.endpoint_verified
    grep_code_verified = $true
    get_function_verified = $true
    search_function_verified = $true
    repository_paths_ready = $health.repos.Count
    register_writer_coverage = 'declarative_metadata_only'
    cyrillic_case_insensitive = $true
} | ConvertTo-Json -Compress
