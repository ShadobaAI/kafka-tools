param(
    [string]$ArchivePath,
    [string]$Destination
)
$ErrorActionPreference = 'Stop'
$release = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'vanessa-release.json') -Encoding UTF8 | ConvertFrom-Json
if ($release.version -ne 1 -or $release.release -notmatch '^\d+(\.\d+)+$' -or $release.files.Count -ne 1) { throw 'Unsupported runtime release descriptor' }
if (-not $Destination) { $Destination = Join-Path $PSScriptRoot ('windows\vanessa\' + $release.release) }
$Destination = [IO.Path]::GetFullPath($Destination)
$binary = $release.files[0]
if ($binary.path -ne 'vanessa-automation-single.epf') { throw 'Unexpected runtime archive entry' }
$epfPath = Join-Path $Destination $binary.path
function Assert-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) { throw 'Runtime SHA-256 mismatch; existing files were preserved' }
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
if (Test-Path -LiteralPath $epfPath) {
    Assert-Hash $epfPath $binary.sha256
} else {
    if (-not $ArchivePath) {
        $ArchivePath = Join-Path $Destination ('vanessa-automation-single.' + $release.release + '.zip')
        if (-not (Test-Path -LiteralPath $ArchivePath)) {
            Invoke-WebRequest -UseBasicParsing -Uri $release.source.url -OutFile $ArchivePath
        }
    }
    Assert-Hash $ArchivePath $release.source.sha256
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
    try {
        $entry = $archive.GetEntry($binary.path)
        if (-not $entry -or $entry.Length -ne $binary.size) { throw 'Runtime archive entry missing or size mismatch' }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $epfPath)
    } finally { $archive.Dispose() }
    Assert-Hash $epfPath $binary.sha256
}
$licenseSource = Join-Path $PSScriptRoot 'vanessa-LICENSE'
$licenseTarget = Join-Path $Destination $release.licenseFile
if (Test-Path -LiteralPath $licenseTarget) {
    Assert-Hash $licenseTarget (Get-FileHash -LiteralPath $licenseSource -Algorithm SHA256).Hash.ToLowerInvariant()
} else { Copy-Item -LiteralPath $licenseSource -Destination $licenseTarget }
$encoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Destination 'manifest.json'), ($release | ConvertTo-Json -Depth 6), $encoding)
[pscustomobject]@{status='prepared';release=$release.release;epf=$epfPath;manifest=(Join-Path $Destination 'manifest.json')} | ConvertTo-Json -Compress
