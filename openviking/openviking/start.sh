#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
for program in docker curl jq openssl cygpath sha256sum; do require "$program"; done
umask 077
mkdir -p "$STATE_DIR"
docker info >/dev/null 2>&1 || fail 'Docker is unavailable.'
lock="$STATE_DIR/sync.lock"
mkdir "$lock" 2>/dev/null || fail 'Another start or synchronization is running, or its lock needs review.'
response=''
manifest=''
headers=''
preserve_response=0
cleanup() {
  local code=$?
  trap - EXIT
  if [[ -n "$response" ]]; then
    if (( preserve_response )); then
      printf 'Account creation result was retained privately at %s; inspect it securely before retrying.\n' "$response" >&2
    else
      rm -f -- "$response"
    fi
  fi
  [[ -z "$manifest" ]] || rm -f -- "$manifest"
  [[ -z "$headers" ]] || rm -f -- "$headers"
  rmdir -- "$lock"
  finish "$code"
}
trap cleanup EXIT
config="$STATE_DIR/ov.conf"
root_header="$STATE_DIR/root.curl"
tenant_header="$STATE_DIR/tenant.curl"
compose="$STATE_DIR/compose.yaml"

if [[ ! -f "$config" || ! -f "$root_header" ]]; then
  [[ ! -e "$config" && ! -e "$root_header" ]] || fail 'Incomplete credentials: restore the missing configuration or key from backup.'
  if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    fail 'Data volume already exists but credentials are missing. Restore the original credentials; no data was changed.'
  fi
  key=$(openssl rand -hex 32)
  printf 'header = "X-Api-Key: %s"\n' "$key" > "$root_header"
  jq -n --arg key "$key" --arg url "$OLLAMA_URL" '{server:{host:"0.0.0.0",port:1933,root_api_key:$key},storage:{workspace:"/var/lib/openviking"},embedding:{dense:{provider:"ollama",model:"qwen3-embedding:0.6b",api_base:($url+"/v1"),dimension:1024,input:"text"}},vlm:{provider:"litellm",model:"ollama/qwen3.5:4b",api_key:"no-key",api_base:$url,temperature:0,max_retries:2,extra_request_body:{num_ctx:16384,think:false}}}' > "$config"
  unset key
fi
jq -e --arg url "$OLLAMA_URL" '.embedding.dense.api_base == ($url + "/v1") and .embedding.dense.model == "qwen3-embedding:0.6b" and .embedding.dense.dimension == 1024 and .vlm.api_base == $url and .vlm.model == "ollama/qwen3.5:4b" and .storage.workspace == "/var/lib/openviking"' "$config" >/dev/null || fail 'Existing configuration differs from script settings. Review it before proceeding.'
curl --silent --show-error --fail --max-time 15 "$OLLAMA_URL/api/tags" | jq -e '[.models[].name] | index("qwen3-embedding:0.6b") != null and index("qwen3.5:4b") != null' >/dev/null || fail 'Ollama is unavailable or required models are missing.'

# Use the same verified GHCR-to-Docker-Hub fallback as the old harness.
# The image is persisted by digest; a restart never silently changes the image.
image_file="$STATE_DIR/image.ref"
resolved_image=''
if [[ -f "$image_file" ]]; then
  IFS= read -r resolved_image < "$image_file" || fail 'Cannot read saved image reference.'
  [[ "$resolved_image" =~ ^(ghcr\.io/volcengine/openviking|docker\.io/openviking/openviking)@sha256:[0-9a-f]{64}$ ]] || fail 'Invalid saved image reference.'
  if ! docker image inspect "$resolved_image" >/dev/null 2>&1; then docker pull "$resolved_image"; fi
elif docker pull "$OPENVIKING_IMAGE"; then
  resolved_image=$(docker image inspect "$OPENVIKING_IMAGE" --format '{{json .RepoDigests}}' | jq -er '[.[] | select(startswith("ghcr.io/volcengine/openviking@sha256:"))] | first // empty') || fail 'GHCR image digest is missing.'
  [[ "$resolved_image" =~ ^ghcr\.io/volcengine/openviking@sha256:[0-9a-f]{64}$ ]] || fail 'Invalid GHCR image digest.'
else
  printf 'GHCR pull failed; verifying its official manifest before trying Docker Hub.\n'
  case "$(docker info --format '{{.Architecture}}')" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) fail 'Unsupported Docker architecture for registry fallback.' ;;
  esac
  token=$(curl --silent --show-error --fail --max-time 30 'https://ghcr.io/token?service=ghcr.io&scope=repository:volcengine/openviking:pull' | jq -er '.token | select(type == "string" and length > 0)') || fail 'Cannot obtain anonymous GHCR access; verified fallback unavailable.'
  manifest=$(mktemp "$STATE_DIR/manifest.XXXXXX")
  headers=$(mktemp "$STATE_DIR/headers.XXXXXX")
  curl --silent --show-error --fail --max-time 30 -D "$(cygpath -m "$headers")" -o "$(cygpath -m "$manifest")" \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://ghcr.io/v2/volcengine/openviking/manifests/v$OPENVIKING_VERSION" || fail 'Official release manifest unavailable; verified fallback refused.'
  unset token
  actual="sha256:$(sha256sum "$manifest" | cut -d ' ' -f 1)"
  declared=$(tr -d '\r' < "$headers" | awk 'tolower($1) == "docker-content-digest:" {print $2}' | tail -n 1)
  [[ "$declared" == "$actual" ]] || fail 'Official manifest digest mismatch; verified fallback refused.'
  digest=$(jq -er --arg arch "$arch" '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch) | .digest] | select(length == 1) | .[0] | select(test("^sha256:[0-9a-f]{64}$"))' "$manifest") || fail 'Official release has no unambiguous platform digest.'
  resolved_image="docker.io/openviking/openviking@$digest"
  printf 'Pulling verified %s image from Docker Hub.\n' "$arch"
  docker pull "$resolved_image"
fi
installed=$(docker run --rm --entrypoint python "$resolved_image" -c 'import importlib.metadata; print(importlib.metadata.version("openviking"))') || fail 'Cannot inspect OpenViking image version.'
[[ "$installed" == "$OPENVIKING_VERSION" ]] || fail 'Image package version does not match the selected release.'
if [[ ! -f "$image_file" ]]; then printf '%s\n' "$resolved_image" > "$image_file"; fi
config_path=$(cygpath -m "$config")
CONFIG_PATH="$config_path" OPENVIKING_IMAGE="$resolved_image" OPENVIKING_VOLUME="$VOLUME" \
  jq -n '{name:"kafka-openviking",services:{openviking:{image:env.OPENVIKING_IMAGE,restart:"unless-stopped",entrypoint:["python","-m","openviking_cli.server_bootstrap"],command:["--config","/etc/openviking/ov.conf","--host","0.0.0.0","--port","1933"],ports:["127.0.0.1:1933:1933"],volumes:[(env.OPENVIKING_VOLUME+":/var/lib/openviking"),{type:"bind",source:env.CONFIG_PATH,target:"/etc/openviking/ov.conf",read_only:true}]}},volumes:{(env.OPENVIKING_VOLUME):{name:env.OPENVIKING_VOLUME}}}' > "$compose"
compose_path=$(cygpath -m "$compose")
docker compose -f "$compose_path" config --quiet
docker compose -f "$compose_path" up -d
printf 'Waiting for OpenViking readiness...\n'
ready=0
for ((i=0; i<60; i++)); do
  if (check_ready) 2>/dev/null; then ready=1; break; fi
  sleep 5
done
[[ $ready == 1 ]] || fail 'OpenViking did not become ready; inspect container logs.'
response=$(mktemp "$STATE_DIR/response.XXXXXX")
create_tenant=0
if [[ -f "$tenant_header" ]]; then
  status=$(curl --silent --show-error --max-time 15 --config "$(cygpath -m "$tenant_header")" \
    -o "$(cygpath -m "$response")" -w '%{http_code}' \
    "$OPENVIKING_URL/api/v1/fs/stat?uri=viking%3A%2F%2Fresources") || fail 'Could not check tenant access.'
  case "$status" in
    200) jq -e '.status == "ok" and .result.isDir == true' "$response" >/dev/null || fail 'Tenant resource scope is unavailable.' ;;
    401) create_tenant=1 ;;
    *) fail "Tenant access failed with HTTP $status; existing key was not changed." ;;
  esac
else
  create_tenant=1
fi
if (( create_tenant )); then
  request "$root_header" GET '/api/v1/admin/accounts?name=kafka' "$response" || fail 'Cannot list accounts.'
  jq -e '.status == "ok" and (.result | type == "array") and (any(.result[]; .account_id == "kafka") | not)' "$response" >/dev/null || fail 'Kafka account already exists or account list is invalid; restore its tenant key.'
  if [[ -f "$tenant_header" ]]; then
    previous_key="$STATE_DIR/tenant.previous.$(date +%Y%m%d%H%M%S).$$.curl"
    [[ ! -e "$previous_key" ]] || fail 'Previous tenant key backup already exists.'
    cp -- "$tenant_header" "$previous_key"
  fi
  # If creation succeeds but saving the key fails, keep the response for recovery.
  preserve_response=1
  request "$root_header" POST '/api/v1/admin/accounts' "$response" -H 'Content-Type: application/json' --data '{"account_id":"kafka","admin_user_id":"git-sync"}' || fail 'Account creation failed; check server state before retrying.'
  tenant=$(jq -er '.result.user_key | select(type == "string" and length > 0)' "$response") || fail 'Account was created but no key was returned; recover it before retrying.'
  new_header=$(mktemp "$STATE_DIR/tenant-new.XXXXXX")
  printf 'header = "X-Api-Key: %s"\n' "$tenant" > "$new_header"
  unset tenant
  mv -f -- "$new_header" "$tenant_header"
  preserve_response=0
  printf 'Created the Kafka account and its tenant key. Update any other clients that use the previous tenant key.\n'
fi
request "$tenant_header" GET '/api/v1/fs/stat?uri=viking%3A%2F%2Fresources' "$response" || fail 'Tenant access failed.'
jq -e '.status == "ok" and .result.isDir == true' "$response" >/dev/null || fail 'Tenant resource scope is unavailable.'
printf 'OpenViking is ready. Run update.sh to index committed documentation.\n'
