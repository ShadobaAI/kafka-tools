function Get-EmbeddedPowerShellSource {
    param([Parameter(Mandatory)][string]$InstallerPath)

    $installerSource = Get-Content -LiteralPath $InstallerPath -Raw
    $marker = '# __KAFKA_AI_POWERSHELL__'
    $markerIndex = $installerSource.LastIndexOf($marker, [System.StringComparison]::Ordinal)
    if ($markerIndex -lt 0) {
        throw 'install.cmd does not contain the embedded PowerShell marker.'
    }
    return $installerSource.Substring($markerIndex + $marker.Length).TrimStart([char[]](13, 10))
}

function Write-EmbeddedPowerShellScript {
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$Destination
    )

    [System.IO.File]::WriteAllText(
        $Destination,
        (Get-EmbeddedPowerShellSource -InstallerPath $InstallerPath),
        [System.Text.UTF8Encoding]::new($true)
    )
}

function Invoke-InstallerLauncherTest {
    $sourcePackage = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $installer = Join-Path $sourcePackage 'install.cmd'
    $source = Get-Content -LiteralPath $installer -Raw
    foreach ($requiredFragment in @(
        '# __KAFKA_AI_POWERSHELL__',
        '-File "%KAFKA_AI_EMBEDDED_SETUP%"',
        '-ToolkitRoot "%~dp0."',
        'LAUNCHER_DIRECTORY_NAME',
        'LAUNCHER_PARENT_NAME',
        'KAFKA_AI_NO_PAUSE'
    )) {
        if (-not $source.Contains($requiredFragment)) {
            throw "install.cmd is missing required launcher fragment: $requiredFragment"
        }
    }

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-invalid-launcher-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
        $invalidInstaller = Join-Path $temporaryRoot 'install.cmd'
        Copy-Item -LiteralPath $installer -Destination $invalidInstaller -Force
        $output = @(& $invalidInstaller 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            throw 'install.cmd accepted a launcher outside the fixed tools\ai directory.'
        }
        if (($output -join ' ') -notmatch 'fixed Kafka tools\\ai directory') {
            throw "install.cmd did not explain the invalid directory: $($output -join ' ')"
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }

    Write-Output 'install-launcher: embedded PowerShell and fixed tools\ai location passed'
}

function Invoke-SetupDaemonPolicyTest {
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer = Join-Path $workspaceRoot 'tools\ai\install.cmd'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-shared-daemon-" + [guid]::NewGuid().ToString('N'))
$temporaryWorkspaceRoot = Join-Path $temporaryCodexHome 'workspace'

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    New-Item -ItemType Directory -Path $temporaryWorkspaceRoot -Force | Out-Null
    $embeddedInstaller = Join-Path $temporaryCodexHome 'embedded-setup.ps1'
    Write-EmbeddedPowerShellScript -InstallerPath $installer -Destination $embeddedInstaller
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        ('conversion\' + [string][char]0x041A + [string][char]0x0414),
        'tests\unit\base',
        'tests\unit\examples',
        'tests\unit\unit',
        'tests\unit\yaxunit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryWorkspaceRoot $relativePath) -Force | Out-Null
    }
    $existingConfig = @'
#:schema https://developers.openai.com/codex/config-schema.json

[mcp_servers.unrelated]
url = "http://127.0.0.1:9999/mcp"
'@
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    [System.IO.File]::WriteAllText(
        $configPath,
        $existingConfig,
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
alias = "external-primary"
path = "C:/portable/external/primary"
language = "bsl"

[[paths]]
alias = "external-tests"
path = "C:/portable/external/tests"
language = "bsl"
'@
    [System.IO.File]::WriteAllText(
        $daemonConfigPath,
        $existingDaemonConfig,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $embeddedInstaller `
        -ToolkitRoot (Split-Path -Parent $installer) `
        -WorkspaceRoot $temporaryWorkspaceRoot `
        -CodexHome $temporaryCodexHome `
        -ConfigurationOnly | Out-Null

    $installedConfig = Get-Content -LiteralPath $configPath -Raw
    foreach ($required in @(
        'BEGIN SHARED-1C-AI MANAGED',
        'BEGIN KAFKA-AI GUARD',
        'url = "http://127.0.0.1:8766/mcp"',
        '[mcp_servers.unrelated]'
    )) {
        if (-not $installedConfig.Contains($required)) {
            throw "Installer did not preserve or install required config content '$required'."
        }
    }
    $installedDaemonConfig = Get-Content -LiteralPath $daemonConfigPath -Raw
    $expectedAliases = @(
        'external-primary',
        'external-tests',
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
    & $embeddedInstaller `
        -ToolkitRoot (Split-Path -Parent $installer) `
        -WorkspaceRoot $temporaryWorkspaceRoot `
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
$portablePackage = Join-Path $temporaryRoot 'tools\ai'
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

    $portableInstaller = Join-Path $portablePackage 'install.cmd'
    & $portableInstaller `
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
$portablePackage = Join-Path $temporaryRoot 'tools\ai'
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

    $portableInstaller = Join-Path $portablePackage 'install.cmd'
    $embeddedInstaller = Join-Path $temporaryRoot 'embedded-setup.ps1'
    Write-EmbeddedPowerShellScript -InstallerPath $portableInstaller -Destination $embeddedInstaller

    $output = @(& $portableInstaller `
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

    $secondOutput = @(& $portableInstaller `
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

    $setupSource = Get-EmbeddedPowerShellSource -InstallerPath $portableInstaller
    $bundledRuntimeIndex = $setupSource.IndexOf('$bundledRuntimeRoot = Join-Path $ToolkitRoot ''runtime\windows''')
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
        '$bundledJars = @(Get-ChildItem -LiteralPath $bundledRuntimeRoot -File',
        'Test-RuntimeUpdateRequired',
        'Bundled bsl-indexer $installedIndexerVersion is current',
        'Bundled BSL Language Server $installedJarVersion is current'
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
    foreach ($readinessFragment in @(
        '-ConfigPath $targetCodeIndexConfig',
        "Where-Object { `$_.Status -ne 'ready' }",
        "-RequiredTools @('health', 'get_function', 'get_object_structure')",
        "-RequiredTools @('analyze_file', 'document_symbols')",
        'Wait-HttpMcpServer -Uri $v8stdUrl'
    )) {
        if (-not $setupSource.Contains($readinessFragment)) {
            throw "Setup is missing post-install readiness fragment: $readinessFragment"
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

    . $embeddedInstaller `
        -ToolkitRoot $portablePackage `
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

    $programFilesRoot = Join-Path $temporaryRoot 'Program Files'
    $systemNode = Join-Path $programFilesRoot 'nodejs\node.exe'
    $explicitNode = Join-Path $temporaryRoot 'explicit-node.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $systemNode) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($systemNode, [byte[]](1))
    [System.IO.File]::WriteAllBytes($explicitNode, [byte[]](2))
    if ((Resolve-NodePath -ProgramFilesRoot $programFilesRoot) -ne $systemNode) {
        throw 'Node resolution did not prefer Program Files over PATH.'
    }
    if ((Resolve-NodePath -RequestedPath $explicitNode -ProgramFilesRoot $programFilesRoot) -ne $explicitNode) {
        throw 'Explicit NodePath did not override the Program Files candidate.'
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
$installer = Join-Path $workspaceRoot 'tools\ai\install.cmd'
$temporaryCodexHome = Join-Path ([System.IO.Path]::GetTempPath()) ("kafka-ai-v8std-" + [guid]::NewGuid().ToString('N'))
$temporaryWorkspaceRoot = Join-Path $temporaryCodexHome 'workspace'
$defaultUrl = 'http://127.0.0.1:8766/mcp'
$publicUrl = 'https://ai.v8std.ru/mcp'

try {
    New-Item -ItemType Directory -Path $temporaryCodexHome -Force | Out-Null
    $embeddedInstaller = Join-Path $temporaryCodexHome 'embedded-setup.ps1'
    Write-EmbeddedPowerShellScript -InstallerPath $installer -Destination $embeddedInstaller
    foreach ($relativePath in @(
        'adapter\adapter',
        'adapter\base',
        'adapter\examples',
        'conversion\KFK',
        ('conversion\' + [string][char]0x041A + [string][char]0x0414),
        'tests\unit\base',
        'tests\unit\examples',
        'tests\unit\unit',
        'tests\unit\yaxunit'
    )) {
        New-Item -ItemType Directory -Path (Join-Path $temporaryWorkspaceRoot $relativePath) -Force | Out-Null
    }
    & $embeddedInstaller -ToolkitRoot (Split-Path -Parent $installer) -WorkspaceRoot $temporaryWorkspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $configPath = Join-Path $temporaryCodexHome 'config.toml'
    $config = Get-Content -LiteralPath $configPath -Raw

    if ($config -notmatch [regex]::Escape("url = `"$defaultUrl`"")) {
        throw 'Fresh install did not configure the local v8std URL.'
    }
    if ($config -notmatch '"v8std_explain_snippet"') {
        throw 'Fresh install did not expose v8std_explain_snippet.'
    }
    $config = $config.Replace("url = `"$defaultUrl`"", "url = `"$publicUrl`"")
    [System.IO.File]::WriteAllText(
        $configPath,
        $config,
        [System.Text.UTF8Encoding]::new($false)
    )

    & $embeddedInstaller -ToolkitRoot (Split-Path -Parent $installer) -WorkspaceRoot $temporaryWorkspaceRoot -CodexHome $temporaryCodexHome -ConfigurationOnly | Out-Null
    $reinstalledConfig = Get-Content -LiteralPath $configPath -Raw
    if ($reinstalledConfig -notmatch [regex]::Escape("url = `"$publicUrl`"")) {
        throw 'Installer did not preserve the user-selected v8std URL.'
    }
    if ($reinstalledConfig -match [regex]::Escape("url = `"$defaultUrl`"")) {
        throw 'Installer restored the default local URL over the user-selected URL.'
    }

    Write-Output 'install-v8std-url: default local URL and public override preservation passed'
}
finally {
    if (Test-Path -LiteralPath $temporaryCodexHome) {
        Remove-Item -LiteralPath $temporaryCodexHome -Recurse -Force
    }
}
}

$previousNoPause = $env:KAFKA_AI_NO_PAUSE
try {
    $env:KAFKA_AI_NO_PAUSE = '1'
    Invoke-InstallerLauncherTest
    Invoke-SetupDaemonPolicyTest
    Invoke-InstallPortableTest
    Invoke-SetupPortableTest
    Invoke-InstallV8stdUrlTest
}
finally {
    if ($null -eq $previousNoPause) {
        Remove-Item Env:KAFKA_AI_NO_PAUSE -ErrorAction SilentlyContinue
    }
    else {
        $env:KAFKA_AI_NO_PAUSE = $previousNoPause
    }
}
