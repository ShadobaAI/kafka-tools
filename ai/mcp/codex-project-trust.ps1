function Confirm-CodexProjectTrust {
    param([string]$Node, [string]$ToolkitRoot, [string[]]$ProjectRoots, [string]$ProfileHome)
    $trustScript = Join-Path $ToolkitRoot 'mcp\codex-project-trust.mjs'
    $trustArguments = @($ProjectRoots)
    if (-not [string]::IsNullOrWhiteSpace($ProfileHome)) { $trustArguments += @('--codex-home', $ProfileHome) }
    & $Node $trustScript @trustArguments
    $trustExit = $LASTEXITCODE
    if ($trustExit -eq 0) { return }
    if ($trustExit -ne 10) { throw 'Cannot check Codex project trust. No runtime/index changes were started.' }
    $answer = Read-Host 'Trust the listed projects in Codex? This updates only project trust in the user config. [y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') { throw 'Project trust was not approved. Setup stopped before runtime/index changes.' }
    & $Node $trustScript @trustArguments --approve
    if ($LASTEXITCODE -ne 0) { throw 'Cannot save/verify Codex project trust. Setup stopped before runtime/index changes.' }
}
