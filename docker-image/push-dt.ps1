param(
    [string]$Token = "",           # GITHUB_TOKEN или PAT с правом packages:write
    [string]$Owner = "",
    [string]$Repo  = "kfk-tmpl-dt",
    [string]$Tag   = "latest",
    [string]$File  = "/template.dt"
)

$Image = "ghcr.io/$Owner/${Repo}:$Tag"

# Логин в GHCR
$Token | oras login ghcr.io --username $Owner --password-stdin

# Публикация артефакта
oras push $Image `
    --artifact-type "application/vnd.1c.dt" `
    --disable-path-validation `
    --annotation "org.opencontainers.image.source=https://github.com/$Owner/kafka-adapter" `
    "${File}:application/octet-stream"

Write-Host "Pushed: $Image"
