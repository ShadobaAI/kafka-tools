#!/usr/bin/env bash
# Полное восстановление PostgreSQL SonarQube с сохранением текущей БД.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SONAR_URL="${SONAR_URL:-http://localhost:9000}"
services_stopped=false

fail() {
  echo "Ошибка: $*" >&2
  exit 1
}

usage() {
  echo "Использование: bash $0 /путь/к/sonarqube.dump ВЕРСИЯ_SONARQUBE_БЭКАПА"
  echo "SONAR_URL задаёт URL проверки готовности (по умолчанию http://localhost:9000)."
}

on_exit() {
  local status=$?
  if (( status != 0 )) && [[ "$services_stopped" == true ]]; then
    echo "Восстановление не завершено. Runner и MCP оставлены остановленными." >&2
    echo "Проверьте БД и журналы; не возобновляйте CI до проверки состояния." >&2
  fi
  if [[ -t 0 ]]; then
    read -r -p "Нажми Enter для закрытия окна..." || true
  fi
  exit "$status"
}
trap on_exit EXIT

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  usage
  exit 0
fi
[[ $# == 2 && -n "$2" ]] || { usage >&2; exit 1; }
readonly BACKUP_VERSION="$2"
[[ -f "$1" && -s "$1" && -r "$1" ]] || fail "Дамп отсутствует, пуст или недоступен."
RESTORE_DUMP="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
readonly RESTORE_DUMP

command -v docker >/dev/null 2>&1 || fail "Docker не найден."
command -v curl >/dev/null 2>&1 || fail "curl не найден."
[[ -f "${SCRIPT_DIR}/docker-compose.yml" ]] || fail "docker-compose.yml не найден."
[[ -f "${SCRIPT_DIR}/backup-sonarqube.sh" ]] || fail "Скрипт резервного копирования не найден."
cd -- "$SCRIPT_DIR"
docker compose version >/dev/null
if ! CURRENT_VERSION="$(curl -fsS --connect-timeout 3 --max-time 10 "${SONAR_URL%/}/api/server/version")"; then
  fail "Не удалось проверить версию SonarQube. Восстановление не начато."
fi
readonly CURRENT_VERSION
[[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$BACKUP_VERSION" ]] \
  || fail "Версия бэкапа ($BACKUP_VERSION) отличается от запущенной ($CURRENT_VERSION). Этот скрипт восстанавливает только бэкап той же версии; для старой версии нужен отдельный план восстановления."

[[ "$(docker inspect --format '{{.State.Running}}' db 2>/dev/null || true)" == true ]] \
  || fail "Контейнер db должен быть запущен."
SONAR_IMAGE="$(docker inspect --format '{{.Image}}' sonarqube)"
readonly SONAR_IMAGE
docker exec db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null \
  || fail "PostgreSQL не готов."
docker exec -i db pg_restore --list < "$RESTORE_DUMP" >/dev/null \
  || fail "Дамп не читается установленным pg_restore."

echo "Будет заменена ВСЯ БД SonarQube, включая проекты, историю, настройки, пользователей и токены."
echo "Дамп: $RESTORE_DUMP"
echo "Существующий образ SonarQube: $SONAR_IMAGE"
echo "Проверена версия запущенного SonarQube: $CURRENT_VERSION"
echo "Версия бэкапа должна быть подтверждена по старым логам или образу, а не предположена."
echo "Убедись, что версии плагинов соответствуют бэкапу и текущие CI jobs завершены."
[[ -t 0 ]] || fail "Нужно интерактивное подтверждение; автоматический restore запрещён."
read -r -p "Для полного восстановления введи RESTORE: " confirmation
[[ "$confirmation" == RESTORE ]] || fail "Восстановление отменено."

services_stopped=true
docker compose stop github-runner sonarqube-mcp sonarqube

echo "Сохраняется текущая БД перед восстановлением..."
bash "${SCRIPT_DIR}/backup-sonarqube.sh" </dev/null

echo "Пересоздаётся БД SonarQube..."
docker exec db sh -c \
  'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'

echo "Восстанавливается дамп..."
docker exec -i db sh -c \
  'exec pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges --single-transaction' \
  < "$RESTORE_DUMP"

echo "Удаляются только Elasticsearch-индексы SonarQube..."
docker run --rm --pull never --network none --volumes-from sonarqube \
  --entrypoint sh "$SONAR_IMAGE" -c 'rm -rf /opt/sonarqube/data/es8'

echo "Запускается существующий контейнер SonarQube без пересборки и обновления образа..."
docker compose start sonarqube

for attempt in {1..120}; do
  response="$(curl -fsS --connect-timeout 3 --max-time 5 "${SONAR_URL%/}/api/system/status" 2>/dev/null || true)"
  if [[ "$response" =~ \"status\"[[:space:]]*:[[:space:]]*\"UP\" ]]; then
    echo "SonarQube готов. Проверь проекты, историю анализов и токены в интерфейсе."
    echo "Runner и MCP оставлены остановленными. После проверки запусти:"
    echo "  cd \"$SCRIPT_DIR\" && docker compose start sonarqube-mcp github-runner"
    exit 0
  fi
  if [[ "$response" == *DB_MIGRATION_NEEDED* || "$response" == *MIGRATION_REQUIRED* ]]; then
    fail "Восстановленная БД требует миграции. Проверь соответствие версии образа бэкапу."
  fi
  if (( attempt < 120 )); then
    sleep 5
  fi
done
fail "SonarQube не достиг UP. Проверь: docker compose logs sonarqube"

