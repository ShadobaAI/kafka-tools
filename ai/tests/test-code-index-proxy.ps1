[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$proxy = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
$node = (Get-Command 'node' -CommandType Application -ErrorAction Stop).Source
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-proxy-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $daemonConfig = Join-Path $temporaryRoot 'daemon.toml'
    [System.IO.File]::WriteAllText(
        $daemonConfig,
        "[daemon]`r`nhttp_port = 0`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $fakeServer = Join-Path $temporaryRoot 'fake-code-index.mjs'
    $fakeServerSource = @'
import readline from "node:readline";

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.method === "initialize") {
    write({ jsonrpc: "2.0", id: message.id, result: { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "fake", version: "1" } } });
    return;
  }
  if (message.method === "tools/list") {
    write({ jsonrpc: "2.0", id: message.id, result: { tools: [
      { name: "bsl_sql", description: "fake", inputSchema: { type: "object" } },
      { name: "health", description: "fake health", inputSchema: { type: "object" } },
      { name: "get_register_writers", description: "fake writers", inputSchema: { type: "object" } }
    ] } });
    return;
  }
  if (message.method === "tools/call" && message.params.name === "health") {
    const payload = { mcp: { status: "ok", version: "fake", repos: ["kafka-adapter"] }, daemon: { status: "online" }, repos: [] };
    write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: JSON.stringify(payload) }], isError: false } });
    return;
  }
  if (message.method !== "tools/call" || message.params.name !== "bsl_sql") {
    write({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "unexpected request" } });
    return;
  }

  const sql = message.params.arguments.sql;
  let columns;
  let rows;
  if (sql.includes("WITH RECURSIVE")) {
    columns = ["caller_proc_key", "callee_proc_name", "callee_proc_key", "call_type", "depth"];
    rows = [
      ["CommonModules/A/Ext/Module.bsl::Старт", "ЗапуститьПотоки", "CommonModules/B/Ext/Module.bsl::ЗапуститьПотоки", "direct", 1],
      ["CommonModules/B/Ext/Module.bsl::ЗапуститьПотоки", "ЗапуститьПоток", "CommonModules/B/Ext/Module.bsl::ЗапуститьПоток", "direct", 2],
    ];
  } else if (sql.includes("callee_proc_key GLOB ?2")) {
    columns = ["caller_proc_key", "callee_proc_name", "callee_proc_key", "call_type"];
    rows = [
      ["CommonModules/A/Ext/Module.bsl::Старт", "B.ЗапуститьПотоки", "CommonModules/B/Ext/Module.bsl::ЗапуститьПотоки", "direct"],
      ["CommonModules/C/Ext/Module.bsl::Старт", "ЗапуститьПотоки", null, "direct"],
    ];
  } else {
    columns = ["caller_proc_key", "callee_proc_name", "callee_proc_key", "call_type"];
    rows = [["CommonModules/A/Ext/Module.bsl::Старт", "ЗапуститьПотоки", "CommonModules/B/Ext/Module.bsl::ЗапуститьПотоки", "direct"]];
  }
  const payload = { columns, rows, row_count: rows.length, truncated: false, limit: message.params.arguments.limit };
  write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: JSON.stringify(payload) }], isError: false } });
});
'@
    [System.IO.File]::WriteAllText($fakeServer, $fakeServerSource, [System.Text.UTF8Encoding]::new($false))

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $node
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.ArgumentList.Add($proxy)
    $startInfo.ArgumentList.Add('--indexer')
    $startInfo.ArgumentList.Add($node)
    $startInfo.ArgumentList.Add('--indexer-arg')
    $startInfo.ArgumentList.Add($fakeServer)
    $startInfo.ArgumentList.Add('--config')
    $startInfo.ArgumentList.Add($daemonConfig)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start code-index proxy test process.'
    }

    $requests = @(
        @{ jsonrpc = '2.0'; id = 0; method = 'initialize'; params = @{} },
        @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} },
        @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ repo = 'kafka-adapter'; procedure = 'ЗапуститьПотоки' } } },
        @{ jsonrpc = '2.0'; id = 3; method = 'tools/call'; params = @{ name = 'get_callees_bsl'; arguments = @{ repo = 'kafka-adapter'; procedure = 'CommonModules/A/Ext/Module.bsl::Старт' } } },
        @{ jsonrpc = '2.0'; id = 4; method = 'tools/call'; params = @{ name = 'get_call_tree_bsl'; arguments = @{ repo = 'kafka-adapter'; procedure = 'Старт'; direction = 'callees'; max_depth = 2 } } },
        @{ jsonrpc = '2.0'; id = 5; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ procedure = 'ЗапуститьПотоки' } } },
        @{ jsonrpc = '2.0'; id = 6; method = 'tools/call'; params = @{ name = 'health'; arguments = @{} } }
    )
    foreach ($request in $requests) {
        $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 8 -Compress))
    }
    $process.StandardInput.Close()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null
    if (-not $process.HasExited) {
        $process.Kill($true)
        throw 'Code-index proxy test timed out.'
    }
    if ($process.ExitCode -ne 0) {
        throw "Code-index proxy exited with $($process.ExitCode): $stderr"
    }

    $responses = @{}
    foreach ($line in ($stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $response = $line | ConvertFrom-Json -Depth 20
        $responses[[int]$response.id] = $response
    }

    $toolNames = @($responses[1].result.tools | ForEach-Object { $_.name })
    foreach ($requiredTool in @('get_callers_bsl', 'get_callees_bsl', 'get_call_tree_bsl')) {
        if ($requiredTool -notin $toolNames) {
            throw "Proxy did not expose '$requiredTool'."
        }
    }
    $healthTool = $responses[1].result.tools | Where-Object { $_.name -eq 'health' }
    if ($healthTool.description -notmatch 'actual code-index daemon endpoint') {
        throw 'Proxy did not replace the false-positive upstream health description.'
    }
    $writersTool = $responses[1].result.tools | Where-Object { $_.name -eq 'get_register_writers' }
    if ($writersTool.description -notmatch 'does not analyze programmatic') {
        throw 'Proxy did not clarify declarative register-writer coverage.'
    }

    $callers = ($responses[2].result.content[0].text | ConvertFrom-Json -Depth 20)
    if ($callers.callers.Count -ne 2 -or $callers.coverage.resolved_edges -ne 1 -or $callers.coverage.unresolved_edges -ne 1) {
        throw 'get_callers_bsl did not preserve resolved and unresolved edge coverage.'
    }
    if ($callers.coverage.project_call_coverage -ne 'static_only' -or $callers.coverage.static_graph_exhaustive -ne $true) {
        throw 'get_callers_bsl did not report static coverage explicitly.'
    }

    $callees = ($responses[3].result.content[0].text | ConvertFrom-Json -Depth 20)
    if ($callees.callees.Count -ne 1 -or $callees.coverage.target_resolution -ne 'exact_key') {
        throw 'get_callees_bsl did not use the exact procedure key.'
    }

    $tree = ($responses[4].result.content[0].text | ConvertFrom-Json -Depth 20)
    if ($tree.edges.Count -ne 2 -or $tree.coverage.max_depth -ne 2 -or $tree.direction -ne 'callees') {
        throw 'get_call_tree_bsl did not return the expected tree contract.'
    }
    if ($tree.coverage.target_resolution -ne 'unique_indexed_target') {
        throw 'get_call_tree_bsl treated downstream callees as ambiguous roots.'
    }
    if ($tree.coverage.static_graph_exhaustive -ne $false -or $tree.coverage.depth_boundary_reached -ne $true) {
        throw 'get_call_tree_bsl did not report the depth coverage boundary.'
    }

    if ($responses[5].error.code -ne -32602) {
        throw 'Proxy did not reject invalid custom tool arguments.'
    }

    $health = ($responses[6].result.content[0].text | ConvertFrom-Json -Depth 20)
    if (
        $health.daemon.status -ne 'offline' -or
        $health.daemon.state -ne 'runtime_info_missing' -or
        $health.daemon.endpoint_verified -ne $false
    ) {
        throw 'Managed health trusted an upstream online status without a live daemon endpoint.'
    }

    Write-Output 'code-index-proxy: health, writer coverage, callers, callees, tree, and validation passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
