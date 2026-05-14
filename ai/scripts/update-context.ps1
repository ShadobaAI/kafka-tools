[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Join-Lines {
    param($Lines)
    return ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-GeneratedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Lines
    )

    $content = Join-Lines $Lines
    if ((Test-Path -LiteralPath $Path) -and ((Get-Content -LiteralPath $Path -Raw) -eq $content)) {
        return $false
    }

    Set-Content -LiteralPath $Path -Value $content -Encoding utf8 -NoNewline
    return $true
}

function Get-RelativeWorkspacePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $rootWithSeparator = if ($Root.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $Root
    }
    else {
        $Root + [System.IO.Path]::DirectorySeparatorChar
    }

    $rootUri = [System.Uri]::new($rootWithSeparator)
    $pathUri = [System.Uri]::new($Path)
    $relativeUri = $rootUri.MakeRelativeUri($pathUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Test-GitRepository {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Test-Path -LiteralPath (Join-Path $Path '.git')
}

function Add-RecursiveFileList {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$ExcludedNames = @('.git', '.metadata', '.settings', 'node_modules', '.venv', 'venv')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $excludedPattern = '(^|[\\/])(' + (($ExcludedNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')([\\/]|$)'
    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch $excludedPattern } |
        Sort-Object FullName

    foreach ($file in $files) {
        $relative = Get-RelativeWorkspacePath -Path $file.FullName -Root $Root
        $Lines.Add(('- {0}' -f $relative))
    }
}

function Add-SourceRepositoryTree {
    param(
        [Parameter(Mandatory = $true)]$Lines,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$ExcludedNames = @('.git', '.metadata', '.settings', 'node_modules', '.venv', 'venv')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $items = Get-ChildItem -LiteralPath $Path -Force |
        Where-Object { $ExcludedNames -notcontains $_.Name } |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

    foreach ($item in $items) {
        $relative = Get-RelativeWorkspacePath -Path $item.FullName -Root $Root
        if ($item.PSIsContainer) {
            $Lines.Add(('- {0}\' -f $relative))

            if ($item.Name -eq 'src') {
                $srcItems = Get-ChildItem -LiteralPath $item.FullName -Force |
                    Where-Object { $ExcludedNames -notcontains $_.Name } |
                    Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name

                foreach ($srcItem in $srcItems) {
                    $srcRelative = Get-RelativeWorkspacePath -Path $srcItem.FullName -Root $Root
                    if ($srcItem.PSIsContainer) {
                        $Lines.Add(('  - {0}\' -f $srcRelative))
                    }
                    else {
                        $Lines.Add(('  - {0}' -f $srcRelative))
                    }
                }
            }
        }
        else {
            $Lines.Add(('- {0}' -f $relative))
        }
    }
}

function Get-MarkdownHeadings {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Level = 2
    )

    $escapedLevel = [Math]::Max(1, $Level)
    $pattern = ('^#{1,' + $escapedLevel + '}\s+(.+)$')
    $headings = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $lineNumber++
        if ($line -match $pattern) {
            $marker = ($line -split '\s+', 2)[0]
            $title = $Matches[1].Trim()
            if ($title) {
                $headings.Add([pscustomobject]@{
                    Level = $marker.Length
                    Line = $lineNumber
                    Title = $title
                })
            }
        }
    }

    return $headings
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path
$toolsRoot = (Resolve-Path -LiteralPath (Join-Path $aiRoot '..')).Path
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $toolsRoot '..')).Path
$generatedRoot = Join-Path $aiRoot 'generated'

New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null

$conversionKd = ([string][char]0x041A) + ([string][char]0x0414)

$knownLocations = @(
    @{ Path = 'adapter\adapter'; Role = 'primary'; Purpose = 'Main Kafka adapter project'; TreeMode = 'source' },
    @{ Path = 'tools'; Role = 'primary'; Purpose = 'Shared tooling and AI metadata'; TreeMode = 'files' },
    @{ Path = 'adapter\base'; Role = 'support'; Purpose = 'Base 1C configuration'; TreeMode = 'source' },
    @{ Path = 'adapter\tester'; Role = 'support'; Purpose = 'Tester extension and API examples'; TreeMode = 'source' },
    @{ Path = 'adapter\yaxunit'; Role = 'support'; Purpose = 'YAxUnit tests'; TreeMode = 'source' },
    @{ Path = 'conversion\KFK'; Role = 'support'; Purpose = 'Data Conversion 3.1 adaptation'; TreeMode = 'source' },
    @{ Path = ('conversion\{0}' -f $conversionKd); Role = 'support'; Purpose = 'Read-only base conversion reference'; TreeMode = 'source' }
)

$detected = [System.Collections.Generic.List[string]]::new()
$detected.Add('# Workspace Detected')
$detected.Add('')
$detected.Add('Generated by `tools\ai\scripts\update-context.ps1`.')
$detected.Add('')
$detected.Add(('Workspace root: `{0}`' -f $workspaceRoot))
$detected.Add('')
$detected.Add('| Location | Role | Status | Git repository | Purpose |')
$detected.Add('| --- | --- | --- | --- | --- |')

foreach ($location in $knownLocations) {
    $fullPath = Join-Path $workspaceRoot $location.Path
    if (Test-Path -LiteralPath $fullPath) {
        $exists = 'present'
        $isGit = if (Test-GitRepository -Path $fullPath) { 'yes' } else { 'no' }
    }
    else {
        $exists = 'missing optional'
        $isGit = 'n/a'
    }

    $label = if ($location.Purpose -like 'Read-only base conversion reference') {
        'base conversion reference under conversion'
    }
    else {
        $location.Path
    }

    $detected.Add(('| `{0}` | {1} | {2} | {3} | {4} |' -f $label, $location.Role, $exists, $isGit, $location.Purpose))
}

$detected.Add('')
$detected.Add('Ignore `builds`, `.settings`, `.metadata`, and generated output by default.')
$detected.Add('')
$detected.Add('Generated orientation only. Durable instructions are root `AGENTS.md`, `tools\ai\workspace-index.md`, and `tools\ai\repositories.md`.')

$workspaceDetectedPath = Join-Path $generatedRoot 'workspace-detected.md'
$workspaceDetectedChanged = Write-GeneratedFile -Path $workspaceDetectedPath -Lines $detected

$tree = [System.Collections.Generic.List[string]]::new()
$tree.Add('# Repository Tree')
$tree.Add('')
$tree.Add('Generated by `tools\ai\scripts\update-context.ps1`.')
$tree.Add('')
$tree.Add('All known repositories are listed. 1C repositories show root entries plus immediate `src\*` children. `tools` lists all files.')
$tree.Add('')

foreach ($location in $knownLocations) {
    $fullPath = Join-Path $workspaceRoot $location.Path
    $title = if ($location.Purpose -like 'Read-only base conversion reference') {
        'base conversion reference under conversion'
    }
    else {
        $location.Path
    }

    $tree.Add(('## `{0}`' -f $title))
    $tree.Add('')
    if (Test-Path -LiteralPath $fullPath) {
        if ($location.TreeMode -eq 'files') {
            Add-RecursiveFileList -Lines $tree -Root $workspaceRoot -Path $fullPath
        }
        else {
            Add-SourceRepositoryTree -Lines $tree -Root $workspaceRoot -Path $fullPath
        }
    }
    else {
        $tree.Add('Missing optional directory.')
    }
    $tree.Add('')
}

$repoTreePath = Join-Path $generatedRoot 'repo-tree.md'
$repoTreeChanged = Write-GeneratedFile -Path $repoTreePath -Lines $tree

$docsIndex = [System.Collections.Generic.List[string]]::new()
$docsIndex.Add('# Adapter Documentation Index')
$docsIndex.Add('')
$docsIndex.Add('Generated by `tools\ai\scripts\update-context.ps1` from `adapter\adapter\docs` markdown headings.')
$docsIndex.Add('')
$docsIndex.Add('Use this index to choose the smallest relevant documentation page before inspecting adapter source.')
$docsIndex.Add('')

$adapterDocsRoot = Join-Path $workspaceRoot 'adapter\adapter\docs'
if (Test-Path -LiteralPath $adapterDocsRoot) {
    $docFiles = Get-ChildItem -LiteralPath $adapterDocsRoot -Recurse -File -Filter '*.md' |
        Sort-Object FullName

    foreach ($file in $docFiles) {
        $relative = Get-RelativeWorkspacePath -Path $file.FullName -Root $workspaceRoot
        $headings = @(Get-MarkdownHeadings -Path $file.FullName -Level 2)
        $titleHeading = $headings | Where-Object { $_.Level -eq 1 } | Select-Object -First 1
        $title = if ($titleHeading) { $titleHeading.Title } else { $file.BaseName }
        $docsIndex.Add(('## `{0}`' -f $relative))
        $docsIndex.Add('')
        $docsIndex.Add(('- Title: {0}' -f $title))

        $sections = @($headings | Where-Object { $_.Level -eq 2 } | Select-Object -First 8)
        if ($sections.Count -gt 0) {
            $docsIndex.Add(('- Sections: {0}' -f (($sections | ForEach-Object { $_.Title }) -join '; ')))
        }

        $docsIndex.Add('')
    }
}
else {
    $docsIndex.Add('`adapter\adapter\docs` is missing.')
}

$adapterDocsIndexPath = Join-Path $generatedRoot 'adapter-docs-index.md'
$adapterDocsIndexChanged = Write-GeneratedFile -Path $adapterDocsIndexPath -Lines $docsIndex

Write-Host 'Generated context indexes:'
Write-Host ('  {0} [{1}]' -f $workspaceDetectedPath, $(if ($workspaceDetectedChanged) { 'updated' } else { 'unchanged' }))
Write-Host ('  {0} [{1}]' -f $repoTreePath, $(if ($repoTreeChanged) { 'updated' } else { 'unchanged' }))
Write-Host ('  {0} [{1}]' -f $adapterDocsIndexPath, $(if ($adapterDocsIndexChanged) { 'updated' } else { 'unchanged' }))
