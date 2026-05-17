$FILE  = ".\template.dt"

$CREDS  = "ghcr.io" | docker-credential-desktop get | ConvertFrom-Json
$OWNER  = $CREDS.Username
$NAMESPACE = $OWNER.ToLowerInvariant()
$IMAGE  = "ghcr.io/$NAMESPACE/kfk-tmpl-dt:latest"

# Логин в GHCR
$CREDS.Secret | oras login ghcr.io --username $OWNER --password-stdin

# Публикация артефакта
Push-Location (Split-Path $FILE)
oras push $IMAGE `
    --artifact-type "application/vnd.1c.dt" `
    --disable-path-validation `
    "$(Split-Path $FILE -Leaf):application/octet-stream"
Pop-Location

Write-Host "Pushed: $IMAGE"
