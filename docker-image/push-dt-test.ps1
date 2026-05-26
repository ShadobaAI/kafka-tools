$FILE  = Join-Path $PSScriptRoot "kfk-tmpl-test.dt"
$ORAS  = Get-Command oras -ErrorAction SilentlyContinue
if ($ORAS) {
    $ORAS = $ORAS.Source
} else {
    $ORAS = Join-Path $PSScriptRoot "..\bin\oras.exe"
    if (-not (Test-Path -LiteralPath $ORAS)) {
        throw "ORAS CLI not found. Install it or place oras.exe into tools\bin."
    }
}

$CREDS  = "ghcr.io" | docker-credential-desktop get | ConvertFrom-Json
$OWNER  = $CREDS.Username
$NAMESPACE = $OWNER.ToLowerInvariant()
$IMAGE  = "ghcr.io/$NAMESPACE/kfk-tmpl-test:latest"

# Логин в GHCR
$CREDS.Secret | & $ORAS login ghcr.io --username $OWNER --password-stdin

# Публикация артефакта
Push-Location (Split-Path $FILE)
& $ORAS push $IMAGE `
    --artifact-type "application/vnd.1c.dt" `
    --disable-path-validation `
    "$(Split-Path $FILE -Leaf):application/octet-stream"
Pop-Location

Write-Host "Pushed: $IMAGE"
