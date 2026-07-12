#!/usr/bin/env bash

# Выгружает исходный код в экземпляр SonarQube.
set -euo pipefail

wait_for_input() {
  read -r -p "Press Enter to exit..." _ || true
}
trap wait_for_input EXIT

# URL экземпляра SonarQube.
readonly SONAR_HOST_URL="http://localhost:9000"
# Ключ и отображаемое имя проекта в SonarQube.
readonly SONAR_PROJECT_KEY="kafka-adapter"
readonly SONAR_PROJECT_NAME="1С: Адаптер Kafka"
# Токен доступа экземпляра SonarQube.
readonly SONAR_TOKEN="squ_***"
# Номер анализируемого релиза.
readonly RELEASE_TAG="2.0.0.0"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_dir="${script_dir}"
cd "${repository_dir}"

if [[ -z "${SONAR_TOKEN}" ]]; then
  echo "Укажите токен SonarQube в константе SONAR_TOKEN." >&2
  exit 1
fi

if [[ ! -d src ]] || ! find src -type f -name '*.bsl' -print -quit | grep -q .; then
  echo "Не найдены BSL-исходники в каталоге src." >&2
  exit 1
fi

scanner_args=(
  "-Dproject.settings=sonar-project.properties"
  "-Dsonar.host.url=${SONAR_HOST_URL}"
  "-Dsonar.projectKey=${SONAR_PROJECT_KEY}"
  "-Dsonar.projectName=${SONAR_PROJECT_NAME}"
  "-Dsonar.projectVersion=${RELEASE_TAG}"
  "-Dsonar.token=${SONAR_TOKEN}"
)

# В проверке покрытие необязательно: не импортируем отсутствующие отчеты.
if [[ ! -f assets/unit/genericCoverage.xml || ! -f assets/ui/genericCoverage.xml ]]; then
  scanner_args+=("-Dsonar.coverageReportPaths=")
fi

if command -v sonar-scanner >/dev/null 2>&1; then
  sonar-scanner "${scanner_args[@]}" "$@"
elif command -v docker >/dev/null 2>&1; then
  docker_repository_dir="${repository_dir}"
  if command -v cygpath >/dev/null 2>&1; then
    docker_repository_dir="$(cygpath -w "${repository_dir}")"
  fi

  MSYS_NO_PATHCONV=1 docker run --rm --init \
    -v "${docker_repository_dir}:/usr/src" \
    -w /usr/src \
    sonarsource/sonar-scanner-cli:latest "${scanner_args[@]}" "$@"
else
  echo "Не найден sonar-scanner или Docker." >&2
  exit 1
fi
