[CmdletBinding()]
param(
    [string]$V8stdRoot = $env:V8STD_ROOT,
    [string]$PythonCommand = 'python',
    [ValidateRange(1, 65535)][int]$Port = 8766,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($V8stdRoot)) {
    throw 'Specify -V8stdRoot or set V8STD_ROOT to a local v8std checkout.'
}

$V8stdRoot = [System.IO.Path]::GetFullPath($V8stdRoot)
$server = Join-Path $V8stdRoot 'scripts\v8std_mcp_server.py'
$pages = Join-Path $V8stdRoot 'docs\ai\pages.jsonl'
$vectors = Join-Path $V8stdRoot 'docs\ai\search-vectors.jsonl'

foreach ($requiredPath in @($server, $pages, $vectors)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Local v8std artifact is missing: $requiredPath"
    }
}

if ($ValidateOnly) {
    Write-Output "Local v8std prerequisites found in '$V8stdRoot'; configured port: $Port."
    exit 0
}

Push-Location $V8stdRoot
try {
    & $PythonCommand $server --pages $pages --vectors $vectors --host 127.0.0.1 --port $Port
    if ($LASTEXITCODE -ne 0) {
        throw "Local v8std exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
