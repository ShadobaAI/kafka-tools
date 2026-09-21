$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\mcp\codex-project-trust.ps1')
$script:approvedCalls = 0
$script:prompts = 0
$script:alreadyTrusted = $true
$script:answer = 'n'
function Invoke-FakeNode {
    if ($args -contains '--approve') { $script:approvedCalls++; $global:LASTEXITCODE = 0 }
    elseif ($script:alreadyTrusted) { $global:LASTEXITCODE = 0 }
    else { $global:LASTEXITCODE = 10 }
}
function Read-Host { param($Prompt) $script:prompts++; return $script:answer }
Confirm-CodexProjectTrust -Node Invoke-FakeNode -ToolkitRoot $PSScriptRoot -ProjectRoots @($PSScriptRoot)
if ($script:prompts -ne 0 -or $script:approvedCalls -ne 0) { throw 'Trusted project must be a no-op.' }
$script:alreadyTrusted = $false
$refused = $false
try { Confirm-CodexProjectTrust -Node Invoke-FakeNode -ToolkitRoot $PSScriptRoot -ProjectRoots @($PSScriptRoot) }
catch { $refused = $_.Exception.Message -like '*not approved*' }
if (-not $refused -or $script:approvedCalls -ne 0) { throw 'Refusal must not write trust.' }
$script:answer = 'yes'
Confirm-CodexProjectTrust -Node Invoke-FakeNode -ToolkitRoot $PSScriptRoot -ProjectRoots @($PSScriptRoot)
if ($script:approvedCalls -ne 1) { throw 'Approval must perform exactly one write request.' }
Write-Output 'project-trust: existing trust skips prompt; refusal blocks writes; approval calls writer once'
