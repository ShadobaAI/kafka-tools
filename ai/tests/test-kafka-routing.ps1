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
foreach ($forbidden in @(
    'alias = "kafka-adapter"',
    'alias = "kafka-adapter-base"',
    'alias = "kafka-adapter-examples"',
    'alias = "kafka-adapter-conv"',
    'alias = "kafka-adapter-conv-kd"',
    'alias = "kafka-adapter-unit"',
    'alias = "kafka-adapter-yaxunit"',
    'kafka-adapter-tests-unit',
    '__WORKSPACE_ROOT_FORWARD__/tests/unit/base',
    '__WORKSPACE_ROOT_FORWARD__/tests/unit/examples'
)) {
    if ($daemonTemplate.Contains($forbidden)) {
        throw "Forbidden obsolete or duplicate code-index binding '$forbidden' is present."
    }
}

$distinctPorts = @($edtRoutes.Port | Sort-Object -Unique)
if ($distinctPorts.Count -ne 3) {
    throw "Expected three distinct EDT-MCP ports, got: $($distinctPorts -join ', ')."
}

Write-Output 'kafka-routing: EDT-MCP ports and code-index bindings match the workspace matrix'
