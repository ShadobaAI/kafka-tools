[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-ai-setup-" + [guid]::NewGuid().ToString('N'))
$portablePackage = Join-Path $temporaryRoot 'support\agent-kit'
$temporaryCodexHome = Join-Path $temporaryRoot 'codex-home'

try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $portablePackage) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePackage -Destination $portablePackage -Recurse -Force
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        'tests\unit\unit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryRoot $relativePath) -Force | Out-Null
    }

    $fakeNode = Join-Path $temporaryRoot 'node.cmd'
    [System.IO.File]::WriteAllText(
        $fakeNode,
        "@echo off`r`nif `"%1`"==`"--version`" echo v18.20.0`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeJava = Join-Path $temporaryRoot 'java.cmd'
    [System.IO.File]::WriteAllText(
        $fakeJava,
        "@echo off`r`necho openjdk version 21.0.0 1>&2`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeIndexer = Join-Path $temporaryRoot 'bsl-indexer.cmd'
    [System.IO.File]::WriteAllText(
        $fakeIndexer,
        "@echo off`r`nif `"%1`"==`"--version`" echo bsl-indexer 0.69.0`r`nexit /b 0`r`n",
        [System.Text.Encoding]::ASCII
    )
    $fakeJar = Join-Path $temporaryRoot 'bsl-language-server-exec.jar'
    [System.IO.File]::WriteAllBytes($fakeJar, [byte[]](0x50, 0x4b, 0x03, 0x04))

    $output = @(& (Join-Path $portablePackage 'setup.ps1') `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -BslIndexerPath $fakeIndexer `
        -BslLanguageServerJar $fakeJar `
        -NodePath $fakeNode `
        -JavaPath $fakeJava `
        -SkipDaemonStart) -join "`n"

    foreach ($managedFile in @(
        (Join-Path $temporaryCodexHome 'code-index\bsl-indexer.exe'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-mcp.ps1'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-daemon.ps1'),
        (Join-Path $temporaryCodexHome 'code-index\mcp\code-index-proxy.mjs'),
        (Join-Path $temporaryCodexHome 'bsl-ls\bsl-language-server-exec.jar'),
        (Join-Path $temporaryCodexHome 'code-index\daemon.toml'),
        (Join-Path $temporaryCodexHome 'config.toml')
    )) {
        if (-not (Test-Path -LiteralPath $managedFile -PathType Leaf)) {
            throw "Setup did not create '$managedFile'."
        }
    }
    if ($output -notmatch 'Setup complete: Node.js 18.20.0, bsl-indexer 0.69.0') {
        throw "Setup did not report verified runtime versions: $output"
    }
    if ($output -notmatch 'Daemon startup was skipped by request') {
        throw 'Setup did not report the explicitly skipped daemon startup.'
    }

    $secondOutput = @(& (Join-Path $portablePackage 'setup.ps1') `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -BslIndexerPath $fakeIndexer `
        -BslLanguageServerJar $fakeJar `
        -NodePath $fakeNode `
        -JavaPath $fakeJava `
        -SkipDaemonStart) -join "`n"
    if (
        $secondOutput -notmatch 'Managed bsl-indexer:.*updated: False' -or
        $secondOutput -notmatch 'Managed BSL LS JAR:.*updated: False'
    ) {
        throw "Repeated setup was not idempotent: $secondOutput"
    }

    $setupSource = Get-Content -LiteralPath (Join-Path $portablePackage 'setup.ps1') -Raw
    foreach ($releasePolicyFragment in @(
        "Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'",
        "-NamePattern '^bsl-indexer-windows-x64\.zip$'",
        "-Repository '1c-syntax/bsl-language-server'",
        '-RequireStable',
        'browser_download_url',
        'after 3 attempts'
    )) {
        if (-not $setupSource.Contains($releasePolicyFragment)) {
            throw "Setup is missing GitHub release policy fragment: $releasePolicyFragment"
        }
    }
    $runtimeStagingIndex = $setupSource.IndexOf("Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'")
    $persistentConfigIndex = $setupSource.IndexOf('$targetConfig = Join-Path $CodexHome')
    if (
        $runtimeStagingIndex -lt 0 -or
        $persistentConfigIndex -lt 0 -or
        $runtimeStagingIndex -gt $persistentConfigIndex
    ) {
        throw 'Setup does not stage and validate runtime before persistent configuration changes.'
    }

    . (Join-Path $portablePackage 'setup.ps1') `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null
    function Invoke-RestMethod {
        param($Method, $Uri, $Headers)

        $stableRelease = [pscustomobject]@{
            tag_name = 'v1.2.3'
            draft = $false
            prerelease = $false
            assets = @()
        }
        if ($Uri -like '*/latest') {
            return $stableRelease
        }
        return @(
            [pscustomobject]@{
                tag_name = 'v2.0.0-rc.1'
                draft = $false
                prerelease = $true
                assets = @()
            },
            $stableRelease
        )
    }
    $latestRelease = Get-GitHubLatestRelease -Repository 'example/repository'
    if ($latestRelease.tag_name -ne 'v2.0.0-rc.1') {
        throw 'Latest-release selection unexpectedly excluded a prerelease.'
    }
    $latestStableRelease = Get-GitHubLatestRelease -Repository 'example/repository' -RequireStable
    if ($latestStableRelease.tag_name -ne 'v1.2.3') {
        throw 'Stable release selection did not use the non-prerelease latest endpoint.'
    }

    function Invoke-WebRequest {
        param($Uri, $Headers, $OutFile, [switch]$UseBasicParsing)

        [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1, 2, 3))
    }
    $downloadedAsset = Join-Path $temporaryRoot 'mock-release-asset.bin'
    $expectedAssetHash = '039058C6F2C0CB492C533B0A4D14EF77CC0F78ABCCCED5287D84A1A2011CFB81'
    $asset = [pscustomobject]@{
        name = 'mock-release-asset.bin'
        browser_download_url = 'https://example.invalid/mock-release-asset.bin'
        size = 3
        digest = "sha256:$expectedAssetHash"
    }
    $actualAssetHash = Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedAsset
    if ($actualAssetHash -ne $expectedAssetHash) {
        throw "Downloaded asset SHA-256 differs: $actualAssetHash"
    }
    $asset.digest = 'sha256:0000000000000000000000000000000000000000000000000000000000000000'
    $digestRejected = $false
    try {
        Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedAsset | Out-Null
    }
    catch {
        $digestRejected = $_.Exception.Message -match 'SHA-256 mismatch'
    }
    if (-not $digestRejected) {
        throw 'Downloaded asset with a mismatched upstream digest was not rejected.'
    }
    $asset.digest = 'md5:unsupported'
    $unsupportedDigestRejected = $false
    try {
        Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedAsset | Out-Null
    }
    catch {
        $unsupportedDigestRejected = $_.Exception.Message -match 'Unsupported digest'
    }
    if (-not $unsupportedDigestRejected) {
        throw 'Downloaded asset with an unsupported upstream digest was not rejected.'
    }
    $asset.digest = $null
    $asset.size = 4
    $sizeMismatchRejected = $false
    try {
        Save-GitHubReleaseAsset -Asset $asset -Destination $downloadedAsset | Out-Null
    }
    catch {
        $sizeMismatchRejected = $_.Exception.Message -match 'Size mismatch'
    }
    if (-not $sizeMismatchRejected) {
        throw 'Downloaded asset with a mismatched upstream size was not rejected.'
    }

    $decisionIndex = $setupSource.IndexOf('Get-CodeIndexPreUpdateAction -Probe $daemonProbe')
    $runtimeUpdateIndex = $setupSource.IndexOf('Install-ManagedFile -Source $indexer')
    $unsafeSkipIndex = $setupSource.IndexOf('Runtime replacement with -SkipDaemonStart is unsafe')
    $rollbackIndex = $setupSource.LastIndexOf('Restore-ManagedFile `')
    $rollbackFailureIndex = $setupSource.IndexOf('Setup failed; previous runtime state was restored')
    if ($decisionIndex -lt 0 -or $decisionIndex -gt $runtimeUpdateIndex) {
        throw 'Setup does not decide daemon state before replacing runtime.'
    }
    if ($unsafeSkipIndex -lt $decisionIndex -or $unsafeSkipIndex -gt $runtimeUpdateIndex) {
        throw 'Setup does not reject live daemon replacement with -SkipDaemonStart.'
    }
    if ($rollbackIndex -lt $runtimeUpdateIndex -or $rollbackFailureIndex -lt $rollbackIndex) {
        throw 'Setup does not retain runtime rollback guards.'
    }

    Write-Output 'setup-portable: prerequisites, latest-release policy, daemon rollback, runtime installation, idempotency, managed config, and offline mode passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
