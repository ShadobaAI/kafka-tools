#!/usr/bin/env bash
# Создаёт архив, достаточный для восстановления SonarQube из PostgreSQL.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_ROOT="${BACKUP_DIR:-${SCRIPT_DIR}/backups}"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR_PATH="${BACKUP_ROOT}/sonarqube_${TIMESTAMP}"

fail() {
  echo "Ошибка: $*" >&2
  exit 1
}

pause_before_exit() {
  if [[ -t 0 ]]; then
    read -r -p "Нажмите Enter для завершения..." || true
  fi
}

trap pause_before_exit EXIT

command -v docker >/dev/null 2>&1 || fail "Docker не найден."

[[ "$(docker inspect --format '{{.State.Running}}' db 2>/dev/null || true)" == 'true' ]] \
  || fail "Контейнер базы данных db не запущен. Запустите: docker compose up -d db"

echo "Ожидание готовности PostgreSQL..."
for _ in {1..30}; do
  if docker exec db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null \
  || fail "PostgreSQL не стал доступен за 60 секунд. Проверьте: docker compose logs db"

umask 077
mkdir -p -- "${BACKUP_DIR_PATH}"

echo "Создаётся дамп PostgreSQL..."
docker exec -i db sh -c \
  'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner --no-privileges' \
  > "${BACKUP_DIR_PATH}/sonarqube.dump"

echo "Готово: ${BACKUP_DIR_PATH}"
