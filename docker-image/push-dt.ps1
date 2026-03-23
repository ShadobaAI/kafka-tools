$FILE  = ".\template.dt"

$OWNER  = ("ghcr.io" | docker-credential-desktop get | ConvertFrom-Json).Username
$IMAGE  = "ghcr.io/$OWNER/kfk-tmpl-dt:latest"

# Логин в GHCR
$TOKEN | oras login ghcr.io --username $OWNER --password-stdin

# Публикация артефакта
oras push $IMAGE `
    --artifact-type "application/vnd.1c.dt" `
    --disable-path-validation `
    "${FILE}:application/octet-stream"

Write-Host "Pushed: $IMAGE"
