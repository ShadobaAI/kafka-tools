function Invoke-CodeIndexDaemonTest {
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
}

function Invoke-CodeIndexLauncherTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$launcher = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-mcp.ps1'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-launcher-" + [guid]::NewGuid().ToString('N'))
$codeIndexHome = Join-Path $temporaryRoot 'runtime'
$capturePath = Join-Path $temporaryRoot 'capture.txt'

try {
    New-Item -ItemType Directory -Path $codeIndexHome -Force | Out-Null
    $daemonConfig = Join-Path $codeIndexHome 'daemon.toml'
    [System.IO.File]::WriteAllText(
        $daemonConfig,
        "[daemon]`r`nhttp_port = 0`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $fakeIndexer = Join-Path $temporaryRoot 'fake-bsl-indexer.cmd'
    $fakeIndexerCommand = @'
@echo off
if "%1"=="--version" echo bsl-indexer 0.69.0
exit /b 0
'@
    [System.IO.File]::WriteAllText(
        $fakeIndexer,
        $fakeIndexerCommand,
        [System.Text.Encoding]::ASCII
    )
    $fakeNode = Join-Path $temporaryRoot 'fake-node.cmd'
    $fakeCommand = @'
@echo off
if "%1"=="--version" (
  echo v18.0.0
  exit /b 0
)
echo CODE_INDEX_HOME=%CODE_INDEX_HOME%>"%CODE_INDEX_CAPTURE%"
echo ARGS=%*>>"%CODE_INDEX_CAPTURE%"
exit /b 0
'@
    [System.IO.File]::WriteAllText($fakeNode, $fakeCommand, [System.Text.Encoding]::ASCII)

    $previousCapture = $env:CODE_INDEX_CAPTURE
    $env:CODE_INDEX_CAPTURE = $capturePath
    try {
        & $launcher `
            -CodeIndexHome $codeIndexHome `
            -BslIndexerPath $fakeIndexer `
            -NodePath $fakeNode `
            -SkipDaemonBootstrap
    }
    finally {
        $env:CODE_INDEX_CAPTURE = $previousCapture
    }

    $capture = Get-Content -LiteralPath $capturePath -Raw
    if ($capture -notmatch [regex]::Escape("CODE_INDEX_HOME=$codeIndexHome")) {
        throw 'Launcher did not bind CODE_INDEX_HOME for bsl-indexer serve.'
    }
    $proxyPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
    $expectedArguments = "ARGS=$proxyPath --indexer $fakeIndexer --config $daemonConfig"
    if ($capture -notmatch [regex]::Escape($expectedArguments)) {
        throw 'Launcher did not bind the compatibility proxy, bsl-indexer, and managed daemon.toml.'
    }

    $unsupportedNodeCommand = @'
@echo off
if "%1"=="--version" echo v17.9.0
exit /b 0
'@
    [System.IO.File]::WriteAllText($fakeNode, $unsupportedNodeCommand, [System.Text.Encoding]::ASCII)
    $unsupportedRejected = $false
    try {
        & $launcher `
            -CodeIndexHome $codeIndexHome `
            -BslIndexerPath $fakeIndexer `
            -NodePath $fakeNode `
            -SkipDaemonBootstrap
    }
    catch {
        $unsupportedRejected = $_.Exception.Message -match 'Node.js 17.9.0 is unsupported'
    }
    if (-not $unsupportedRejected) {
        throw 'Launcher did not reject an unsupported Node.js version.'
    }

    Write-Output 'code-index-launcher: versions, proxy, executable, CODE_INDEX_HOME, and managed daemon.toml passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
}

function Invoke-CodeIndexProxyTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$proxy = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
$node = @(Get-Command 'node' -CommandType Application -ErrorAction Stop)[0].Source
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("code-index-proxy-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    $daemonConfig = Join-Path $temporaryRoot 'daemon.toml'
    $readyPath = $temporaryRoot.Replace('\', '/')
    $missingPath = (Join-Path $temporaryRoot 'missing').Replace('\', '/')
    [System.IO.File]::WriteAllText(
        $daemonConfig,
        "[daemon]`r`nhttp_port = 0`r`n`r`n[[paths]]`r`nalias = `"kfk`"`r`npath = `"$readyPath`"`r`nlanguage = `"bsl`"`r`n`r`n[[paths]]`r`nalias = `"kfk-broken`"`r`npath = `"$missingPath`"`r`nlanguage = `"bsl`"`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $fakeServer = Join-Path $temporaryRoot 'fake-code-index.mjs'
    $fakeServerSource = @'
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import readline from "node:readline";

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

const configIndex = process.argv.indexOf("--config");
const configPath = process.argv[configIndex + 1];
const rootPath = path.dirname(configPath);
const healthServer = http.createServer((request, response) => {
  response.setHeader("content-type", "application/json");
  response.end(JSON.stringify({ status: "running", pid: process.pid, version: "fake", paths: [{ path: rootPath, status: "ready" }] }));
});

healthServer.listen(0, "127.0.0.1", () => {
  const address = healthServer.address();
  fs.writeFileSync(path.join(rootPath, "daemon.json"), JSON.stringify({ pid: process.pid, version: "fake", http_host: "127.0.0.1", http_port: address.port, started_at: "test" }));
  const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  input.on("close", () => healthServer.close());
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
    const payload = { mcp: { status: "ok", version: "fake", repos: ["kfk"] }, daemon: { status: "online" }, repos: [] };
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
      ["CommonModules/A/Ext/Module.bsl::\u0421\u0442\u0430\u0440\u0442", "\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "CommonModules/B/Ext/Module.bsl::\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "direct", 1],
      ["CommonModules/B/Ext/Module.bsl::\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a", "CommonModules/B/Ext/Module.bsl::\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a", "direct", 2],
    ];
  } else if (sql.includes("callee_proc_key GLOB ?2")) {
    columns = ["caller_proc_key", "callee_proc_name", "callee_proc_key", "call_type"];
    rows = [
      ["CommonModules/A/Ext/Module.bsl::\u0421\u0442\u0430\u0440\u0442", "B.\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "CommonModules/B/Ext/Module.bsl::\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "direct"],
      ["CommonModules/C/Ext/Module.bsl::\u0421\u0442\u0430\u0440\u0442", "\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", null, "direct"],
    ];
  } else {
    columns = ["caller_proc_key", "callee_proc_name", "callee_proc_key", "call_type"];
    rows = [["CommonModules/A/Ext/Module.bsl::\u0421\u0442\u0430\u0440\u0442", "\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "CommonModules/B/Ext/Module.bsl::\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c\u041f\u043e\u0442\u043e\u043a\u0438", "direct"]];
  }
  const payload = { columns, rows, row_count: rows.length, truncated: false, limit: message.params.arguments.limit };
  write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text: JSON.stringify(payload) }], isError: false } });
  });
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
    $proxyArguments = @(
        $proxy,
        '--indexer', $node,
        '--indexer-arg', $fakeServer,
        '--config', $daemonConfig
    )
    $startInfo.Arguments = ($proxyArguments | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }) -join ' '

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Could not start code-index proxy test process.'
    }

    $startProcedure = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0KHRgtCw0YDRgg=='))
    $runThreadsProcedure = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('0JfQsNC/0YPRgdGC0LjRgtGM0J/QvtGC0L7QutC4'))
    $initializeRequest = @{ jsonrpc = '2.0'; id = 0; method = 'initialize'; params = @{} }
    $process.StandardInput.WriteLine(($initializeRequest | ConvertTo-Json -Depth 8 -Compress))
    $initializeResponse = $process.StandardOutput.ReadLine()
    $requests = @(
        @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} },
        @{ jsonrpc = '2.0'; id = 6; method = 'tools/call'; params = @{ name = 'health'; arguments = @{} } },
        @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ repo = 'kfk'; procedure = $runThreadsProcedure } } },
        @{ jsonrpc = '2.0'; id = 3; method = 'tools/call'; params = @{ name = 'get_callees_bsl'; arguments = @{ repo = 'kfk'; procedure = "CommonModules/A/Ext/Module.bsl::$startProcedure" } } },
        @{ jsonrpc = '2.0'; id = 4; method = 'tools/call'; params = @{ name = 'get_call_tree_bsl'; arguments = @{ repo = 'kfk'; procedure = $startProcedure; direction = 'callees'; max_depth = 2 } } },
        @{ jsonrpc = '2.0'; id = 5; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ procedure = $runThreadsProcedure } } },
        @{ jsonrpc = '2.0'; id = 7; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ repo = 'kfk-broken'; procedure = $runThreadsProcedure } } },
        @{ jsonrpc = '2.0'; id = 8; method = 'tools/call'; params = @{ name = 'get_callers_bsl'; arguments = @{ repo = 'foreign'; procedure = $runThreadsProcedure } } }
    )
    foreach ($request in $requests) {
        $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 8 -Compress))
    }
    $process.StandardInput.Close()

    $stdout = $initializeResponse + [Environment]::NewLine + $process.StandardOutput.ReadToEnd()
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
        $response = $line | ConvertFrom-Json
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

    $callers = ($responses[2].result.content[0].text | ConvertFrom-Json)
    if ($callers.callers.Count -ne 2 -or $callers.coverage.resolved_edges -ne 1 -or $callers.coverage.unresolved_edges -ne 1) {
        throw 'get_callers_bsl did not preserve resolved and unresolved edge coverage.'
    }
    if ($callers.coverage.project_call_coverage -ne 'static_only' -or $callers.coverage.static_graph_exhaustive -ne $true) {
        throw 'get_callers_bsl did not report static coverage explicitly.'
    }

    $callees = ($responses[3].result.content[0].text | ConvertFrom-Json)
    if ($callees.callees.Count -ne 1 -or $callees.coverage.target_resolution -ne 'exact_key') {
        throw 'get_callees_bsl did not use the exact procedure key.'
    }

    $tree = ($responses[4].result.content[0].text | ConvertFrom-Json)
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

    $health = ($responses[6].result.content[0].text | ConvertFrom-Json)
    if (
        $health.mcp.status -ne 'ok' -or
        $health.daemon.status -ne 'online' -or
        $health.daemon.state -ne 'healthy' -or
        $health.daemon.endpoint_verified -ne $true -or
        ($health.repos | Where-Object { $_.repo -eq 'kfk' }).path_status.status -ne 'ready'
    ) {
        throw 'Managed health did not verify the live daemon and ready repository path.'
    }
    if ($responses[7].error.message -notmatch "repo 'kfk-broken'.*path status is 'unknown'.*No corpus-dependent request") {
        throw 'Proxy did not fail closed for a configured repository path that is not ready.'
    }
    if ($responses[8].error.message -notmatch "repo 'foreign'.*alias is not configured.*No corpus-dependent request") {
        throw 'Proxy did not fail closed for an unknown repository alias.'
    }

    Write-Output 'code-index-proxy: readiness gate, health, writer coverage, callers, callees, tree, and validation passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
}

function Invoke-CodeIndexProxyLifecycleTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$proxy = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mcp\code-index-proxy.mjs'))
$node = @(Get-Command 'node' -CommandType Application -ErrorAction Stop)[0].Source
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
}

Invoke-CodeIndexDaemonTest
Invoke-CodeIndexLauncherTest
Invoke-CodeIndexProxyTest
Invoke-CodeIndexProxyLifecycleTest
