#!/usr/bin/env bash
set -Eeuo pipefail
IMAGE="ollama/ollama:latest"
VOLUME="ollama-models"
STATE_DIR="$HOME/.codex/ollama-gpu-standalone"
docker() { MSYS_NO_PATHCONV=1 command docker "$@"; }
finish() { local code=$?; trap - EXIT; if [[ -t 0 ]]; then printf '\nExit code: %s. Press Enter to close.\n' "$code"; read -r _ || true; fi; exit "$code"; }
trap finish EXIT
for program in docker cygpath; do command -v "$program" >/dev/null 2>&1 || { printf 'Missing program: %s\n' "$program" >&2; exit 1; }; done
mkdir -p "$STATE_DIR"
compose="$STATE_DIR/compose.yaml"
cat > "$compose" <<EOF
name: ollama-gpu
services:
  ollama:
    image: $IMAGE
    pull_policy: missing
    container_name: ollama
    restart: unless-stopped
    ports: ["11434:11434"]
    environment:
      OLLAMA_HOST: "0.0.0.0:11434"
      OLLAMA_MAX_LOADED_MODELS: "2"
      OLLAMA_KEEP_ALIVE: "30m"
      OLLAMA_NUM_PARALLEL: "1"
      OLLAMA_CONTEXT_LENGTH: "16384"
      OLLAMA_FLASH_ATTENTION: "1"
      OLLAMA_KV_CACHE_TYPE: "f16"
    volumes: ["$VOLUME:/root/.ollama"]
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["0"]
              capabilities: [gpu]
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
volumes:
  $VOLUME:
    external: true
    name: $VOLUME
EOF
compose_path=$(cygpath -m "$compose")
docker compose -f "$compose_path" config --quiet
docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null
docker compose -f "$compose_path" up -d --wait --wait-timeout 120
for model in qwen3-embedding:0.6b qwen3.5:4b; do
  if ! docker exec ollama ollama list | awk 'NR > 1 {print $1}' | grep -Fxq "$model"; then
    printf 'Downloading %s...\n' "$model"
    docker exec ollama ollama pull "$model"
  fi
done
docker exec ollama ollama list
printf 'Ollama is ready; check GPU placement with: docker exec ollama ollama ps\n'
