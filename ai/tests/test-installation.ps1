function Invoke-SetupDaemonPolicyTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\setup.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-shared-daemon-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    $legacyConfig = @'
#:schema https://developers.openai.com/codex/config-schema.json

# BEGIN CRM-AI MANAGED
[mcp_servers.v8std]
url = "http://127.0.0.1:8766/mcp"
bearer_token_env_var = "V8STD_TOKEN"

[mcp_servers.code-index]
command = "powershell.exe"
args = ["C:\legacy-crm\code-index-mcp.ps1"]
# END CRM-AI MANAGED

[mcp_servers.unrelated]
url = "http://127.0.0.1:9999/mcp"
'@
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    [System.IO.File]::WriteAllText(
        $configPath,
        $legacyConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    $codeIndexHome = Join-Path $temporaryCodexHome 'code-index'
    New-Item -ItemType Directory -Path $codeIndexHome -Force | Out-Null
    $daemonConfigPath = Join-Path $codeIndexHome 'daemon.toml'
    $existingDaemonConfig = @'
[daemon]
http_port = 0
max_concurrent_initial = 3

[[paths]]
alias = "crm-production"
path = "C:/portable/crm/src"
language = "bsl"

[[paths]]
alias = "crm-yaxunit"
path = "C:/portable/crm/EDT.YAXUNIT"
language = "bsl"

[[paths]]
alias = "kafka-adapter"
path = "C:/obsolete/kafka-adapter"
language = "bsl"

[[paths]]
alias = "kafka-adapter-tests-unit"
path = "C:/obsolete/kafka-adapter-tests-unit"
language = "bsl"
'@
    [System.IO.File]::WriteAllText(
        $daemonConfigPath,
        $existingDaemonConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer `
        -WorkspaceRoot $workspaceRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null

    $installedConfig = Get-Content -LiteralPath $configPath -Raw
    foreach ($required in @(
        'BEGIN SHARED-1C-AI MANAGED',
        'BEGIN KAFKA-AI GUARD',
        'url = "http://127.0.0.1:8766/mcp"',
        'bearer_token_env_var = "V8STD_TOKEN"',
        '[mcp_servers.unrelated]'
    )) {
        if (-not $installedConfig.Contains($required)) {
            throw "Installer did not preserve or install required config content '$required'."
        }
    }
    foreach ($forbidden in @('BEGIN CRM-AI MANAGED', 'legacy-crm')) {
        if ($installedConfig.Contains($forbidden)) {
            throw "Installer left legacy CRM managed content '$forbidden'."
        }
    }

    $installedDaemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    $expectedAliases = @(
        'crm-production',
        'crm-yaxunit',
        'kfk',
        'kfk-base',
        'kfk-examples',
        'kfk-conv',
        'kfk-conv-kd',
        'kfk-unit',
        'kfk-yaxunit'
    )
    foreach ($alias in $expectedAliases) {
        if ($installedDaemonConfig -notmatch ('(?m)^alias = "' + [regex]::Escape($alias) + '"\r?$')) {
            throw "Installer did not preserve or add code-index alias '$alias'."
        }
    }
    if ($installedDaemonConfig -notmatch '(?m)^max_concurrent_initial = 3\r?$') {
        throw 'Installer did not preserve existing shared daemon settings.'
    }
    foreach ($legacyAlias in @('kafka-adapter', 'kafka-adapter-tests-unit')) {
        if ($installedDaemonConfig -match ('(?m)^alias = "' + [regex]::Escape($legacyAlias) + '"\r?$')) {
            throw "Installer preserved legacy Kafka alias '$legacyAlias'."
        }
    }

    & $installer `
        -WorkspaceRoot $workspaceRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null
    $reinstalledDaemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    foreach ($alias in $expectedAliases) {
        $aliasCount = [regex]::Matches(
            $reinstalledDaemonConfig,
            '(?m)^alias = "' + [regex]::Escape($alias) + '"\r?$'
        ).Count
        if ($aliasCount -ne 1) {
            throw "Repeated install produced $aliasCount entries for alias '$alias'."
        }
    }

    Write-Output 'install-shared-daemon: foreign aliases and daemon settings preserved; current Kafka aliases replaced idempotently'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
}

function Invoke-InstallPortableTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-ai-portable-" + [guid]::NewGuid().ToString('N'))
$portablePackage = Join-Path $temporaryRoot 'support\agent-kit'
$temporaryCodexHome = Join-Path $temporaryRoot 'codex-home'

try {
    $conversionDataBaseRelativePath = 'conversion\' + [string][char]0x041A + [string][char]0x0414
    New-Item -ItemType Directory -Path (Split-Path -Parent $portablePackage) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePackage -Destination $portablePackage -Recurse -Force
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        $conversionDataBaseRelativePath,
        'tests\unit\base',
        'tests\unit\examples',
        'tests\unit\unit',
        'tests\unit\yaxunit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryRoot $relativePath) -Force | Out-Null
    }

    $portableInstaller = Join-Path $portablePackage 'setup.ps1'
    & $portableInstaller `
        -WorkspaceRoot $temporaryRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null

    $installedConfigPath = Join-Path $temporaryCodexHome 'config.toml'
    $installedConfig = Get-Content -LiteralPath $installedConfigPath -Raw
    if (
        $installedConfig.Contains('__AI_ROOT__') -or
        $installedConfig.Contains('__WORKSPACE_ROOT__') -or
        $installedConfig.Contains('__CODE_INDEX_HOME__')
    ) {
        throw 'Installer left unresolved path placeholders in config.toml.'
    }
    $escapedPackagePath = $portablePackage.Replace('\', '\\')
    $escapedWorkspacePath = $temporaryRoot.Replace('\', '\\')
    if (-not $installedConfig.Contains($escapedPackagePath)) {
        throw 'Installed Kafka guard does not reference the portable package path.'
    }
    if (-not $installedConfig.Contains($escapedWorkspacePath)) {
        throw 'Installed Kafka guard does not reference the selected workspace root.'
    }
    $expectedCodeIndexHome = (Join-Path $temporaryCodexHome 'code-index').Replace('\', '\\')
    $expectedSharedLauncher = ($expectedCodeIndexHome + '\\mcp\\code-index-mcp.ps1')
    if (-not $installedConfig.Contains($expectedSharedLauncher)) {
        throw 'Installed code-index MCP does not reference the shared launcher in CODE_INDEX_HOME.'
    }
    foreach ($managedMcpFile in @(
        'code-index-mcp.ps1',
        'code-index-daemon.ps1',
        'code-index-proxy.mjs'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $temporaryCodexHome "code-index\mcp\$managedMcpFile") -PathType Leaf)) {
            throw "Installer did not install shared code-index MCP file '$managedMcpFile'."
        }
    }
    $daemonConfigPath = Join-Path $temporaryCodexHome 'code-index\daemon.toml'
    if (-not (Test-Path -LiteralPath $daemonConfigPath -PathType Leaf)) {
        throw 'Installer did not create the managed code-index daemon configuration.'
    }
    $daemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    if ($daemonConfig.Contains('__WORKSPACE_ROOT_FORWARD__')) {
        throw 'Installer left an unresolved workspace path in daemon.toml.'
    }
    if (-not $daemonConfig.Contains($temporaryRoot.Replace('\', '/'))) {
        throw 'Managed daemon.toml does not reference the selected workspace root.'
    }

    $installedAgents = Join-Path $temporaryRoot 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $installedAgents -PathType Leaf)) {
        throw 'Installer did not create workspace AGENTS.md.'
    }
    $sourceSkillCount = @(Get-ChildItem -LiteralPath (Join-Path $portablePackage '.codex\skills') -Directory).Count
    $installedSkillCount = @(Get-ChildItem -LiteralPath (Join-Path $temporaryCodexHome 'skills') -Directory).Count
    if ($installedSkillCount -ne $sourceSkillCount) {
        throw "Installer discovered $installedSkillCount skills; expected $sourceSkillCount."
    }

    Write-Output 'install-portable: package paths, code-index config, AGENTS, and skill discovery passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
}

function Invoke-SetupPortableTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-ai-setup-" + [guid]::NewGuid().ToString('N'))
$portablePackage = Join-Path $temporaryRoot 'support\agent-kit'
$temporaryCodexHome = Join-Path $temporaryRoot 'codex-home'

try {
    $conversionDataBaseRelativePath = 'conversion\' + [string][char]0x041A + [string][char]0x0414
    New-Item -ItemType Directory -Path (Split-Path -Parent $portablePackage) -Force | Out-Null
    Copy-Item -LiteralPath $sourcePackage -Destination $portablePackage -Recurse -Force
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        $conversionDataBaseRelativePath,
        'tests\unit\base',
        'tests\unit\examples',
        'tests\unit\unit',
        'tests\unit\yaxunit'
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
    $bundledRuntimeIndex = $setupSource.IndexOf('$bundledRuntimeRoot = Join-Path $PSScriptRoot ''runtime\windows''')
    $runtimeStagingIndex = $setupSource.IndexOf("Get-GitHubLatestRelease -Repository 'Regsorm/code-index-mcp'")
    if (
        $bundledRuntimeIndex -lt 0 -or
        $runtimeStagingIndex -lt 0 -or
        $bundledRuntimeIndex -gt $runtimeStagingIndex
    ) {
        throw 'Setup does not inspect bundled Windows runtime before downloading from GitHub.'
    }
    foreach ($bundledRuntimeFragment in @(
        "-Filter 'bsl-indexer.exe'",
        "-Filter 'bsl-language-server-*-exec.jar'",
        'Using bundled bsl-indexer executable',
        'Using bundled BSL Language Server JAR'
    )) {
        if (-not $setupSource.Contains($bundledRuntimeFragment)) {
            throw "Setup is missing bundled runtime selection fragment: $bundledRuntimeFragment"
        }
    }
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

    $commandLookupRoot = Join-Path $temporaryRoot 'command-lookup'
    $firstCommandRoot = Join-Path $commandLookupRoot 'first'
    $secondCommandRoot = Join-Path $commandLookupRoot 'second'
    New-Item -ItemType Directory -Path $firstCommandRoot, $secondCommandRoot -Force | Out-Null
    $firstCommand = Join-Path $firstCommandRoot 'kafka-ai-command.cmd'
    $secondCommand = Join-Path $secondCommandRoot 'kafka-ai-command.cmd'
    [System.IO.File]::WriteAllText($firstCommand, '@exit /b 0', [System.Text.Encoding]::ASCII)
    [System.IO.File]::WriteAllText($secondCommand, '@exit /b 0', [System.Text.Encoding]::ASCII)
    $previousPath = $env:PATH
    try {
        $env:PATH = "$firstCommandRoot;$secondCommandRoot;$previousPath"
        $resolvedCommand = Resolve-CommandPath `
            -CommandName 'kafka-ai-command' `
            -Description 'duplicate test command'
        if ($resolvedCommand -ne $firstCommand) {
            throw "Command resolution selected '$resolvedCommand'; expected first PATH match '$firstCommand'."
        }
    }
    finally {
        $env:PATH = $previousPath
    }

    $runtimeCacheTestRoot = Join-Path $temporaryRoot 'runtime-cache-test'
    $runtimeCacheSource = Join-Path $runtimeCacheTestRoot 'source.bin'
    $runtimeCacheDestination = Join-Path $runtimeCacheTestRoot 'runtime\windows\cached.bin'
    New-Item -ItemType Directory -Path $runtimeCacheTestRoot -Force | Out-Null
    [System.IO.File]::WriteAllBytes($runtimeCacheSource, [byte[]](10, 20, 30, 40))
    $cachedRuntimePath = Save-VerifiedRuntimeFile `
        -Source $runtimeCacheSource `
        -Destination $runtimeCacheDestination
    if ($cachedRuntimePath -isnot [string] -or $cachedRuntimePath -ne $runtimeCacheDestination) {
        throw "Runtime cache returned an invalid path: '$cachedRuntimePath'."
    }
    if (
        (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeCacheSource).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimeCacheDestination).Hash
    ) {
        throw 'Runtime cache file differs from its validated source.'
    }
    if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $runtimeCacheDestination) -Filter '*.tmp' -File).Count -ne 0) {
        throw 'Runtime cache left a staging file after successful persistence.'
    }

    $bundledRuntimeTestRoot = Join-Path $temporaryRoot 'bundled-runtime-test'
    New-Item -ItemType Directory -Path $bundledRuntimeTestRoot -Force | Out-Null
    $bundledIndexer = Join-Path $bundledRuntimeTestRoot 'bsl-indexer.exe'
    $bundledJar = Join-Path $bundledRuntimeTestRoot 'bsl-language-server-1.2.3-exec.jar'
    [System.IO.File]::WriteAllBytes($bundledIndexer, [byte[]](1))
    [System.IO.File]::WriteAllBytes($bundledJar, [byte[]](2))
    if (
        (Resolve-BundledRuntimeFile -RuntimeRoot $bundledRuntimeTestRoot -Filter 'bsl-indexer.exe' -Description 'indexer') -ne $bundledIndexer -or
        (Resolve-BundledRuntimeFile -RuntimeRoot $bundledRuntimeTestRoot -Filter 'bsl-language-server-*-exec.jar' -Description 'JAR') -ne $bundledJar
    ) {
        throw 'Bundled runtime files were not resolved from runtime/windows conventions.'
    }
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
}

function Invoke-InstallV8stdUrlTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\setup.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-v8std-" + [guid]::NewGuid().ToString('N'))
$publicUrl = 'https://ai.v8std.ru/mcp'
$localUrl = 'http://127.0.0.1:8766/mcp'

try {
    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    $config = Get-Content -LiteralPath $configPath -Raw

    if ($config -notmatch [regex]::Escape("url = `"$publicUrl`"")) {
        throw 'Fresh install did not configure the public v8std URL.'
    }
    if ($config -notmatch '"v8std_explain_snippet"') {
        throw 'Fresh install did not expose v8std_explain_snippet.'
    }
    $config = $config.Replace("url = `"$publicUrl`"", "url = `"$localUrl`"")
    [System.IO.File]::WriteAllText(
        $configPath,
        $config,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $reinstalledConfig = Get-Content -LiteralPath $configPath -Raw
    if ($reinstalledConfig -notmatch [regex]::Escape("url = `"$localUrl`"")) {
        throw 'Installer did not preserve the user-selected v8std URL.'
    }
    if ($reinstalledConfig -match [regex]::Escape("url = `"$publicUrl`"")) {
        throw 'Installer restored the default public URL over the user-selected URL.'
    }

    Write-Output 'install-v8std-url: default public URL and user override preservation passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
}

function Invoke-InstallUnicaMigrationTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\setup.ps1'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-unica-migration-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    foreach ($skill in @('edt-mcp', '1c-engineering', 'v8std-mcp', 'user-owned-skill')) {
        $skillRoot = Join-Path $temporaryCodexHome "skills\$skill"
        New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $skillRoot 'SKILL.md'),
            "# $skill",
            [System.Text.UTF8Encoding]::new($false)
        )
    }
    $legacyConfig = @'
[marketplaces.unica]
source_type = "git"
source = "https://github.com/IngvarConsulting/unica-marketplace.git"

[plugins."unica@unica"]
enabled = true

[plugins."unica@unica".mcp_servers.unica]
enabled = true
enabled_tools = ["unica.code.search"]

[mcp_servers.unrelated]
url = "http://127.0.0.1:9999/mcp"
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $temporaryCodexHome 'config.toml'),
        $legacyConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $installer -WorkspaceRoot $workspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $installedConfig = Get-Content -LiteralPath (Join-Path $temporaryCodexHome 'config.toml') -Raw
    if ($installedConfig -match '(?im)^\[(?:marketplaces\.unica|plugins\."unica@unica"(?:\.mcp_servers\.unica)?)\]') {
        throw 'Installer left a legacy Unica registration or MCP table in active config.'
    }
    if ($installedConfig -notmatch '\[mcp_servers\.code-index\]') {
        throw 'Installer did not install the managed code-index MCP table.'
    }
    if ($installedConfig -notmatch '\[mcp_servers\.unrelated\]') {
        throw 'Installer removed an unrelated MCP table during migration.'
    }
    foreach ($legacySkill in @('edt-mcp', '1c-engineering', 'v8std-mcp')) {
        if (Test-Path -LiteralPath (Join-Path $temporaryCodexHome "skills\$legacySkill")) {
            throw "Installer left legacy managed skill '$legacySkill'."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $temporaryCodexHome 'skills\user-owned-skill\SKILL.md'))) {
        throw 'Installer removed an unrelated user-owned skill.'
    }

    Write-Output 'install-unica-migration: legacy Unica and managed skills removed; unrelated config and skill preserved'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
}

Invoke-SetupDaemonPolicyTest
Invoke-InstallPortableTest
Invoke-SetupPortableTest
Invoke-InstallV8stdUrlTest
Invoke-InstallUnicaMigrationTest
