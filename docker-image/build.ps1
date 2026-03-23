$OWNER            = ""

$PLATFORM_VERSION = "8.3.27.2074"
$EDT_VERSION      = "2025.2.3"
$OSCRIPT_VERSION  = "2.0.1"
$PLATFORM_DEB_ZIP = "distr/deb64_8_3_27_2074.zip"
$EDT_DISTR_TGZ    = "distr/1c_edt_distr_offline_2025.2.3_30_linux_x86_64.tar.gz"
$OSCRIPT_ZIP      = "distr/OneScript-2.0.1-linux-x64.zip"
$IMAGE            = "ghcr.io/$OWNER/1c-build:latest"

$BUILD_DATE = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

docker build `
  --platform linux/amd64 `
  --provenance=false `
  --build-arg PLATFORM_VERSION="$PLATFORM_VERSION" `
  --build-arg EDT_VERSION="$EDT_VERSION" `
  --build-arg OSCRIPT_VERSION="$OSCRIPT_VERSION" `
  --build-arg PLATFORM_DEB_ZIP="$PLATFORM_DEB_ZIP" `
  --build-arg EDT_DISTR_TGZ="$EDT_DISTR_TGZ" `
  --build-arg OSCRIPT_ZIP="$OSCRIPT_ZIP" `
  --build-arg BUILD_DATE="$BUILD_DATE" `
  -t "$IMAGE" `
  "$PSScriptRoot"

if ($LASTEXITCODE -eq 0) {
  docker push "$IMAGE"
}
