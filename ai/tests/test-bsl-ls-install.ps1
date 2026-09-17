$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\install.cmd'
$text = Get-Content -LiteralPath $installer -Raw
$marker = '# __KAFKA_AI_POWERSHELL__'
$source = $text.Substring($text.LastIndexOf($marker) + $marker.Length)
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-BslLsLaunchConfiguration', 'Assert-BslLsJavaVersion')) {
    $definition = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | Where-Object Name -eq $name
    if (@($definition).Count -ne 1) { throw "Missing unique helper $name" }
    Invoke-Expression $definition.Extent.Text
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected rejection: $Message"
}
$config = @'
[mcp_servers.bsl-ls]
command = "node"
args = [
  "C:/workspace with spaces/.codex/mcp/bsl-ls-proxy.mjs",
  "--root", "C:/workspace with spaces",
  "--java", "C:/Java 25/bin/java.exe",
]
cwd = "C:/workspace with spaces"
enabled = true
required = false
[mcp_servers.other]
command = "unrelated"
'@
$launch = Get-BslLsLaunchConfiguration -Content $config
if ($launch.Arguments.Count -ne 5 -or $launch.Java -ne 'C:/Java 25/bin/java.exe' -or
    $launch.Command -ne 'node' -or $launch.Root -ne $launch.WorkingDirectory) {
    throw 'Configured command or arguments were not preserved.'
}
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('cwd = "C:/workspace with spaces"', 'cwd = "."')) } 'must be absolute'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('C:/workspace with spaces/.codex/mcp/bsl-ls-proxy.mjs', '.codex/mcp/bsl-ls-proxy.mjs')) } 'must be absolute'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('"--root", "C:/workspace with spaces"', '"--root", "."')) } 'must be an absolute path'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('  "--java", "C:/Java 25/bin/java.exe",', '')) } 'requires explicit --java'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('enabled = true', 'enabled = false')) } 'must be enabled'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('cwd = "C:/workspace with spaces"', 'cwd = "C:/other"')) } 'must match --root'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('cwd = "C:/workspace with spaces"', 'cwd = "C:relative"')) } 'must be absolute'
Assert-Rejected { Get-BslLsLaunchConfiguration ($config.Replace('"--root", "C:/workspace with spaces"', '"--root", "/relative-to-drive"')) } 'must be an absolute path'
function Invoke-NativeCommand {
    param($Executable, $ArgumentList)
    if ($ArgumentList[0] -ne '-version') { throw 'Wrong Java version argument' }
    return @{ ExitCode = 0; Output = @('openjdk version "' + $Executable + '"') }
}
Assert-Rejected { Assert-BslLsJavaVersion '17.0.12' } 'requires Java 25'
Assert-Rejected { Assert-BslLsJavaVersion '24.0.2' } 'requires Java 25'
Assert-Rejected { Assert-BslLsJavaVersion 'unknown' } 'could not be determined'
foreach ($version in @('25', '25.0.2', '26-ea')) {
    if ((Assert-BslLsJavaVersion $version) -lt 25) { throw 'Supported Java rejected' }
}
if ($source -notmatch '-Executable \$bslLsLaunch.Command' -or
    $source -notmatch '-ArgumentList \$bslLsLaunch.Arguments' -or
    $source -notmatch 'Push-Location \(\[IO.Path\]::GetTempPath\(\)\)') {
    throw 'Readiness must use the repository registration from a foreign parent cwd.'
}
Write-Output 'bsl-ls-install: parser, exact launch arguments, absolute paths, Java 17/24 rejection and Java 25+ passed'
