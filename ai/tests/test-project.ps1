function Invoke-KafkaRoutingTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$conversionDataBasePath = 'conversion/' + [string][char]0x041A + [string][char]0x0414

$edtRoutes = @(
    @{ Config = 'adapter\adapter\.codex\config.toml'; Server = 'kfk-edt'; Port = 8765 },
    @{ Config = 'conversion\KFK\.codex\config.toml'; Server = 'conv-edt'; Port = 8767 },
    @{ Config = 'tests\unit\unit\.codex\config.toml'; Server = 'unit-edt'; Port = 8768 }
)

foreach ($route in $edtRoutes) {
    $configPath = Join-Path $workspaceRoot $route.Config
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Missing EDT-MCP config '$configPath'."
    }
    $config = Get-Content -LiteralPath $configPath -Raw
    $serverHeader = '[mcp_servers.' + $route.Server + ']'
    $serverUrl = 'url = "http://localhost:' + $route.Port + '/mcp"'
    if (-not $config.Contains($serverHeader) -or -not $config.Contains($serverUrl)) {
        throw "EDT-MCP route '$($route.Config)' does not bind $($route.Server) to port $($route.Port)."
    }
}

foreach ($forbiddenUnitConfig in @(
    'tests\unit\base\.codex\config.toml',
    'tests\unit\examples\.codex\config.toml',
    'tests\unit\yaxunit\.codex\config.toml'
)) {
    if (Test-Path -LiteralPath (Join-Path $workspaceRoot $forbiddenUnitConfig)) {
        throw "Unit EDT-MCP configuration must be owned only by tests/unit/unit: '$forbiddenUnitConfig'."
    }
}

$daemonTemplatePath = Join-Path $workspaceRoot 'tools\ai\code-index\daemon.toml.template'
$daemonTemplate = Get-Content -LiteralPath $daemonTemplatePath -Raw -Encoding UTF8
$expectedCodeIndexPaths = [ordered]@{
    'kfk' = 'adapter/adapter'
    'kfk-base' = 'adapter/base'
    'kfk-examples' = 'adapter/examples'
    'kfk-conv' = 'conversion/KFK'
    'kfk-conv-kd' = $conversionDataBasePath
    'kfk-unit' = 'tests/unit/unit'
    'kfk-yaxunit' = 'tests/unit/yaxunit'
}
foreach ($entry in $expectedCodeIndexPaths.GetEnumerator()) {
    $expectedBlock = 'alias = "' + $entry.Key + '"' + "`n" +
        'path = "__WORKSPACE_ROOT_FORWARD__/' + $entry.Value + '"'
    $normalizedTemplate = $daemonTemplate.Replace("`r`n", "`n")
    if (-not $normalizedTemplate.Contains($expectedBlock)) {
        throw "Missing code-index binding '$($entry.Key)' -> '$($entry.Value)'."
    }
}
$actualAliasCount = [regex]::Matches($daemonTemplate, '(?m)^alias = "').Count
if ($actualAliasCount -ne $expectedCodeIndexPaths.Count) {
    throw "Expected $($expectedCodeIndexPaths.Count) code-index bindings, got $actualAliasCount."
}
foreach ($forbidden in @(
    '__WORKSPACE_ROOT_FORWARD__/tests/unit/base',
    '__WORKSPACE_ROOT_FORWARD__/tests/unit/examples'
)) {
    if ($daemonTemplate.Contains($forbidden)) {
        throw "Forbidden duplicate code-index binding '$forbidden' is present."
    }
}

$distinctPorts = @($edtRoutes.Port | Sort-Object -Unique)
if ($distinctPorts.Count -ne 3) {
    throw "Expected three distinct EDT-MCP ports, got: $($distinctPorts -join ', ')."
}

Write-Output 'kafka-routing: EDT-MCP ports and code-index bindings match the workspace matrix'
}

function Invoke-RoutingGuardTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$guardPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\hooks\guard-1c-routing.ps1'))
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))

function Invoke-GuardCase {
    param(
        [Parameter(Mandatory)][hashtable]$Event,
        [Parameter(Mandatory)][bool]$ShouldDeny,
        [Parameter(Mandatory)][string]$Name
    )

    $json = $Event | ConvertTo-Json -Depth 10 -Compress
    $output = $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guardPath
    $denied = $false
    if (-not [string]::IsNullOrWhiteSpace(($output -join ''))) {
        $response = ($output -join '') | ConvertFrom-Json
        $denied = $response.hookSpecificOutput.permissionDecision -eq 'deny'
    }

    if ($denied -ne $ShouldDeny) {
        throw "Guard case '$Name' expected deny=$ShouldDeny but got deny=$denied."
    }
}

$adapterRoot = Join-Path $workspaceRoot 'adapter\adapter'

Invoke-GuardCase -Name 'allow config read' -ShouldDeny $false -Event @{
    tool_name = 'Bash'
    cwd = $adapterRoot
    tool_input = @{ command = "Get-Content -LiteralPath '.codex\config.toml' -Raw" }
}
Invoke-GuardCase -Name 'deny explicit src read' -ShouldDeny $true -Event @{
    tool_name = 'Bash'
    cwd = $adapterRoot
    tool_input = @{ command = "Get-Content -LiteralPath 'src\CommonModules\Example\Module.bsl' -Raw" }
}
Invoke-GuardCase -Name 'deny workspace-relative src read' -ShouldDeny $true -Event @{
    tool_name = 'exec_command'
    cwd = $workspaceRoot
    tool_input = @{ cmd = 'Get-Content adapter\adapter\src\CommonModules\Example\Module.bsl' }
}
Invoke-GuardCase -Name 'deny traversed src read' -ShouldDeny $true -Event @{
    tool_name = 'Bash'
    cwd = $adapterRoot
    tool_input = @{ command = 'Get-Content ..\..\adapter\adapter\src\CommonModules\Example\Module.bsl' }
}
Invoke-GuardCase -Name 'deny apply patch src target' -ShouldDeny $true -Event @{
    tool_name = 'apply_patch'
    cwd = $workspaceRoot
    tool_input = @{ patch = "*** Begin Patch`n*** Update File: adapter/adapter/src/CommonModules/Example/Module.bsl`n*** End Patch" }
}
Invoke-GuardCase -Name 'allow apply patch tooling target' -ShouldDeny $false -Event @{
    tool_name = 'apply_patch'
    cwd = $workspaceRoot
    tool_input = @{ patch = "*** Begin Patch`n*** Update File: tools/ai/README.md`n*** End Patch" }
}
Invoke-GuardCase -Name 'deny broad repository search' -ShouldDeny $true -Event @{
    tool_name = 'Bash'
    cwd = $adapterRoot
    tool_input = @{ command = 'rg -n "Procedure" .' }
}
Invoke-GuardCase -Name 'deny broad repository search through exec command' -ShouldDeny $true -Event @{
    tool_name = 'exec_command'
    cwd = $adapterRoot
    tool_input = @{ cmd = 'rg -n "Procedure" .' }
}
Invoke-GuardCase -Name 'allow read-only code-index' -ShouldDeny $false -Event @{
    tool_name = 'mcp__code_index__get_callers_bsl'
    cwd = $workspaceRoot
    tool_input = @{}
}
Invoke-GuardCase -Name 'deny unknown code-index tool' -ShouldDeny $true -Event @{
    tool_name = 'mcp__code_index__index_project'
    cwd = $workspaceRoot
    tool_input = @{}
}
Invoke-GuardCase -Name 'allow read-only BSL LS' -ShouldDeny $false -Event @{
    tool_name = 'mcp__bsl_ls__analyze_file'
    cwd = $workspaceRoot
    tool_input = @{}
}
Invoke-GuardCase -Name 'deny unknown BSL LS tool' -ShouldDeny $true -Event @{
    tool_name = 'mcp__bsl_ls__apply_fix'
    cwd = $workspaceRoot
    tool_input = @{}
}
Invoke-GuardCase -Name 'allow configured v8std snippet' -ShouldDeny $false -Event @{
    tool_name = 'mcp__v8std__v8std_explain_snippet'
    cwd = $workspaceRoot
    tool_input = @{}
}

Write-Output 'guard-1c-routing: 13 cases passed'
}

Invoke-KafkaRoutingTest
Invoke-RoutingGuardTest
