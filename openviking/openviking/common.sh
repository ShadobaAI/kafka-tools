#!/usr/bin/env bash
# Shared settings for the standalone OpenViking installation.
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || fail "Required program not found: $1"; }
finish() {
  local code=${1:-$?}
  trap - EXIT
  if [[ -t 0 ]]; then
    printf '\nExit code: %s. Press Enter to close.\n' "$code"
    read -r _ || true
  elif [[ -t 1 ]] && [[ -e /dev/tty ]]; then
    printf '\nExit code: %s. Press Enter to close.\n' "$code"
    read -r _ < /dev/tty || true
  fi
  exit "$code"
}
trap finish EXIT

STATE_DIR="$HOME/.openviking"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../adapter/adapter" && pwd -P)" || fail 'Cannot locate adapter/adapter relative to openviking/openviking.'
OLLAMA_URL="http://iA11:11434"
OPENVIKING_IMAGE="ghcr.io/volcengine/openviking:v0.5.1"
OPENVIKING_VERSION="0.5.1"
OPENVIKING_URL="http://127.0.0.1:1933"
NAMESPACE="viking://resources/kafka-git/kafka-adapter"
VOLUME="kafka-openviking_openviking-data"
# Docker arguments such as container mount paths must not be rewritten by Git Bash.
docker() { MSYS_NO_PATHCONV=1 command docker "$@"; }

request() {
  local keyfile=$1 method=$2 endpoint=$3 output=$4
  shift 4
  curl --silent --show-error --fail-with-body --max-time 630 \
    --config "$(cygpath -m "$keyfile")" -X "$method" "$OPENVIKING_URL$endpoint" "$@" >"$output"
}

check_ready() {
  local health ready
  health=$(curl --silent --show-error --fail --max-time 15 "$OPENVIKING_URL/health") || fail 'OpenViking health check failed.'
  ready=$(curl --silent --show-error --fail --max-time 15 "$OPENVIKING_URL/ready") || fail 'OpenViking readiness check failed.'
  jq -e --arg v "$OPENVIKING_VERSION" '.status == "ok" and .healthy == true and (.version | ltrimstr("v")) == $v' <<<"$health" >/dev/null || fail 'Unexpected OpenViking version or health.'
  jq -e '.status == "ready" and .checks.embedding == "ok" and .checks.vectordb == "ok" and .checks.agfs.status == "ok" and .checks.agfs.checks.filesystem == "ok" and ((.checks.agfs.checks.multiwrite_sync // "ok") | . == "ok" or . == "not_supported")' <<<"$ready" >/dev/null || fail 'OpenViking semantic readiness is incomplete.'
}
