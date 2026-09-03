[CmdletBinding()]
param(
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

function Deny-ToolCall {
    param([Parameter(Mandatory)][string]$Reason)

    @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = $Reason
        }
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

function Normalize-PolicyPath {
    param([Parameter(Mandatory)][string]$Path)

    return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') -replace '\\', '/').ToLowerInvariant()
}

function Get-ToolPayloadStrings {
    param($Value)

    if ($null -eq $Value) {
        return
    }
    if ($Value -is [string] -or $Value -is [ValueType]) {
        [string]$Value
        return
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) {
            Get-ToolPayloadStrings -Value $item
        }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            Get-ToolPayloadStrings -Value $item
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        Get-ToolPayloadStrings -Value $property.Value
    }
}

function Test-ProtectedSourceReference {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$CurrentDirectory,
        [Parameter(Mandatory)][string[]]$SourceRoots,
        [Parameter(Mandatory)][string[]]$WorkspaceRelativeSourceRoots
    )

    $normalizedText = ($Text -replace '\\', '/').ToLowerInvariant()
    foreach ($sourceRoot in $SourceRoots) {
        if ($normalizedText.Contains($sourceRoot)) {
            return $true
        }
    }
    foreach ($relativeSourceRoot in $WorkspaceRelativeSourceRoots) {
        if ($normalizedText -match "(^|[^\p{L}\p{N}_.-])(?:\./)?$([regex]::Escape($relativeSourceRoot))(?:/|\*|[^\p{L}\p{N}_.-]|$)") {
            return $true
        }
    }

    $pathPattern = '(?i)(?:[a-z]:[\\/]|(?:\.\.?|[\p{L}\p{N}_.-]+)[\\/])(?:[^\s''""`;|<>]+)'
    foreach ($match in [regex]::Matches($Text, $pathPattern)) {
        $candidate = $match.Value.TrimEnd(')', ']', '}', ',', ':')
        if ($candidate -match '[\r\n]') {
            continue
        }
        try {
            $resolved = if ([System.IO.Path]::IsPathRooted($candidate)) {
                Normalize-PolicyPath $candidate
            }
            else {
                Normalize-PolicyPath (Join-Path $CurrentDirectory $candidate)
            }
        }
        catch {
            continue
        }
        foreach ($sourceRoot in $SourceRoots) {
            if ($resolved -eq $sourceRoot -or $resolved.StartsWith("$sourceRoot/", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    exit 0
}

try {
    $event = $rawInput | ConvertFrom-Json
}
catch {
    Deny-ToolCall '1C routing guard could not parse the tool request.'
}

$policyPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workspace-policy.json'))
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Deny-ToolCall "1C routing policy file is missing: '$policyPath'."
}
try {
    $workspacePolicy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
}
catch {
    Deny-ToolCall "1C routing policy file is invalid: '$policyPath'."
}

$toolName = [string]$event.tool_name
$allowedCodeIndexTools = @(
    'mcp__code_index__search_function',
    'mcp__code_index__search_class',
    'mcp__code_index__get_function',
    'mcp__code_index__get_class',
    'mcp__code_index__get_callers',
    'mcp__code_index__get_callees',
    'mcp__code_index__get_callers_bsl',
    'mcp__code_index__get_callees_bsl',
    'mcp__code_index__find_path',
    'mcp__code_index__get_call_tree',
    'mcp__code_index__get_call_tree_bsl',
    'mcp__code_index__find_symbol',
    'mcp__code_index__get_imports',
    'mcp__code_index__get_file_summary',
    'mcp__code_index__get_stats',
    'mcp__code_index__search_text',
    'mcp__code_index__grep_body',
    'mcp__code_index__stat_file',
    'mcp__code_index__list_files',
    'mcp__code_index__read_file',
    'mcp__code_index__grep_text',
    'mcp__code_index__grep_code',
    'mcp__code_index__health',
    'mcp__code_index__get_object_structure',
    'mcp__code_index__get_form_handlers',
    'mcp__code_index__get_event_subscriptions',
    'mcp__code_index__find_path_bsl',
    'mcp__code_index__search_terms',
    'mcp__code_index__get_data_links',
    'mcp__code_index__find_data_path',
    'mcp__code_index__get_register_writers',
    'mcp__code_index__get_object_profile',
    'mcp__code_index__find_references',
    'mcp__code_index__bsl_sql'
)

$allowedBslLsTools = @(
    'mcp__bsl_ls__analyze_file',
    'mcp__bsl_ls__document_symbols',
    'mcp__bsl_ls__find_references',
    'mcp__bsl_ls__call_hierarchy',
    'mcp__bsl_ls__hover',
    'mcp__bsl_ls__definition',
    'mcp__bsl_ls__type_info',
    'mcp__bsl_ls__global_member_info',
    'mcp__bsl_ls__global_member_search',
    'mcp__bsl_ls__type_at_position'
)

if ($toolName -like 'mcp__code_index__*' -and $toolName -notin $allowedCodeIndexTools) {
    Deny-ToolCall "code-index tool '$toolName' is outside the explicit read-only allowlist."
}
if ($toolName -like 'mcp__code_index__*' -and $toolName -ne 'mcp__code_index__health') {
    $allowedAliases = @($workspacePolicy.codeIndexAliases.PSObject.Properties.Name)
    if ($allowedAliases.Count -eq 0) {
        Deny-ToolCall "1C routing policy has no codeIndexAliases: '$policyPath'."
    }
    $requestedAlias = [string]$event.tool_input.repo
    if ([string]::IsNullOrWhiteSpace($requestedAlias)) {
        Deny-ToolCall "code-index tool '$toolName' requires an explicit repository alias."
    }
    if ($requestedAlias -notin $allowedAliases) {
        Deny-ToolCall "code-index alias '$requestedAlias' is outside the configured Kafka workspace."
    }
}

if ($toolName -like 'mcp__bsl_ls__*' -and $toolName -notin $allowedBslLsTools) {
    Deny-ToolCall "BSL LS tool '$toolName' is outside the explicit read-only allowlist."
}

if ($toolName -match '^mcp__.*edt.*__(git|ask_workmate)$') {
    Deny-ToolCall "EDT tool '$toolName' is disabled by workspace policy."
}

if ($toolName -notin @('Bash', 'shell', 'exec_command', 'apply_patch', 'view_image')) {
    exit 0
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
}
$WorkspaceRoot = Normalize-PolicyPath $WorkspaceRoot
$protectedRepositoryRoots = @($workspacePolicy.protectedRepositoryRoots)
if ($protectedRepositoryRoots.Count -eq 0) {
    Deny-ToolCall "1C routing policy has no protectedRepositoryRoots: '$policyPath'."
}
$repositoryRoots = $protectedRepositoryRoots | ForEach-Object {
    Normalize-PolicyPath (Join-Path $WorkspaceRoot ([string]$_))
}
$sourceRoots = $repositoryRoots | ForEach-Object { "$_/src" }
$workspaceRelativeSourceRoots = $protectedRepositoryRoots | ForEach-Object {
    (([string]$_).Trim('/', '\') -replace '\\', '/').ToLowerInvariant() + '/src'
}
$cwd = if ([string]::IsNullOrWhiteSpace([string]$event.cwd)) { $workspaceRoot } else { Normalize-PolicyPath ([string]$event.cwd) }

$payloadStrings = @(Get-ToolPayloadStrings -Value $event.tool_input)
foreach ($payloadString in $payloadStrings) {
    if (Test-ProtectedSourceReference `
        -Text $payloadString `
        -CurrentDirectory $cwd `
        -SourceRoots $sourceRoots `
        -WorkspaceRelativeSourceRoots $workspaceRelativeSourceRoots) {
        Deny-ToolCall 'Direct filesystem access to protected 1C src/** is forbidden; use EDT-MCP or allowed read-only code-index/BSL LS tools.'
    }
}
$toolPayload = $payloadStrings -join [Environment]::NewLine
$normalizedPayload = ($toolPayload -replace '\\', '/').ToLowerInvariant()

$currentRepository = $repositoryRoots | Where-Object {
    $cwd -eq $_ -or $cwd.StartsWith("$_/", [System.StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1

if ($null -ne $currentRepository) {
    $explicitSourcePattern = '(?i)(^|[\s''"=:(])(?:\.\/)?src(?:[\/\\*]|[\s''"$]|$)'
    if ($normalizedPayload -match $explicitSourcePattern) {
        Deny-ToolCall 'Direct filesystem access to 1C src/** is forbidden; use EDT-MCP or allowed read-only code-index/BSL LS tools.'
    }

    $broadDiscoveryPattern = '(?i)(^|[;&|]\s*|\s)(rg|grep|find|tree|Get-ChildItem|gci|dir|ls|Select-String)(\.exe)?\b'
    $explicitNonSourceScope = '(?i)(\.codex[\/\\]|AGENTS\.md|README(?:\.md)?|docs[\/\\]|scripts[\/\\]|\.github[\/\\])'
    if ($toolName -in @('Bash', 'shell', 'exec_command') -and $normalizedPayload -match $broadDiscoveryPattern -and $normalizedPayload -notmatch $explicitNonSourceScope) {
        Deny-ToolCall 'Broad filesystem discovery from a 1C repository can traverse src/**; scope the command to a non-source path or use EDT-MCP/code-index.'
    }
}

exit 0
