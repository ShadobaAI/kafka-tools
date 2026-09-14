# SonarQube — анализ BSL-кода

[← Все инструменты](../README.md)

> Команды выполняются из каталога `tools/sonarqube`. Пути к файлам в описаниях указаны относительно корня репозитория `tools`, если не оговорено иное.

## Содержание

- [Обновление BSL-плагина](#обновление-bsl-плагина)
- [Резервное копирование](#резервное-копирование-sonarqube)
- [Восстановление](#восстановление-sonarqube)
- [GitHub Actions runner](#github-actions-runner)
- [Ошибка доступа к Docker Hub](#ошибка-доступа-к-docker-hub)
- [Права на создание проектов и запуск анализа](#права-на-создание-проектов-и-запуск-анализа)

## Запуск

Локальный SonarQube Community Build для статического анализа BSL-кода. Окружение включает PostgreSQL, `sonar-bsl-plugin-community` и русский language pack для интерфейса.

```powershell
docker compose up -d --build
```

| Сервис | Адрес |
|--------|-------|
| SonarQube | http://localhost:9000 |
| GitHub Actions runner | `1c.github-runner`, labels: `self-hosted,linux,x64,sonar-docker` |
| PostgreSQL | внутренний сервис `db:5432` |

Настройки анализа проекта задаются в `sonar-project.properties` анализируемого репозитория.

## Обновление BSL-плагина

Перед обновлением сделать резервную копию PostgreSQL. Это обязательно, поскольку используемый в `sonarqube/Dockerfile` плавающий базовый образ `sonarqube:community` при пересборке может обновить не только BSL-плагин, но и сам SonarQube:

```powershell
bash backup-sonarqube.sh
docker compose build --no-cache sonarqube
docker compose up -d --no-deps --force-recreate sonarqube
docker compose logs -f sonarqube
```

Если после пересоздания отображается сообщение «SonarQube находится на обслуживании», проверить состояние:

```powershell
Invoke-RestMethod http://localhost:9000/api/system/status | ConvertTo-Json
Invoke-RestMethod http://localhost:9000/api/system/db_migration_status | ConvertTo-Json
```

Статусы `DB_MIGRATION_NEEDED` или `MIGRATION_REQUIRED` означают, что обновилась версия SonarQube и требуется миграция БД. Открыть `http://localhost:9000/setup`, запустить миграцию и дождаться статуса `UP`. Предупреждения Elasticsearch об inference/ML и `sun.misc.Unsafe` сами по себе не являются причиной режима обслуживания.

Проверить фактически запущенные версии SonarQube и BSL-плагина:

```powershell
docker compose logs sonarqube |
  Select-String "SonarQube Server /|Deploy 1C|Database needs to be migrated"
```

Версию плагина также можно проверить в SonarQube: `Administration → Marketplace → Installed`. Если требуется обновлять только плагин, базовый образ в `FROM` необходимо зафиксировать на точном совместимом теге SonarQube вместо `sonarqube:community`.

Данные PostgreSQL и результаты анализа сохраняются в Docker volumes. Не используйте `docker compose down -v`: эта команда удаляет volumes.

## Резервное копирование SonarQube

Скрипт `sonarqube/backup-sonarqube.sh` сохраняет полный дамп PostgreSQL в `sonarqube/backups/`. В дамп входят проекты, история анализов, настройки, пользователи и токены SonarQube. Контейнер `db` должен быть запущен.

```bash
bash backup-sonarqube.sh
```

## Восстановление SonarQube

Для восстановления используйте ту же версию SonarQube и плагинов. Команды ниже удаляют текущую БД:

```bash
docker compose stop sonarqube
docker compose up -d db
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' < backups/sonarqube_YYYYMMDD_HHMMSS/sonarqube.dump
docker compose up -d sonarqube
```

Тома `sonarqube_data` и `sonarqube_logs` восстанавливать не нужно: это кэш, индексы и журналы, они создаются заново.

## GitHub Actions runner

Перед запуском заполнить `sonarqube/.env`:

```env
GITHUB_ACCESS_TOKEN=github_pat_...
```

Используется Personal Access Token GitHub, а не registration token со страницы `Settings -> Actions -> Runners -> New self-hosted runner`. Registration token истекает примерно через час и после перезапуска Docker может приводить к ошибке `404 Not Found` на `actions/runner-registration`.

Для repo-runner к `https://github.com/ShadobaAI/kafka-adapter` PAT должен принадлежать пользователю с admin-доступом к репозиторию. Для classic PAT достаточно scope `repo` для приватного репозитория. Для fine-grained PAT выбрать репозиторий `ShadobaAI/kafka-adapter` и выдать repository permission `Administration: Read and write`.

Проверить, что `.env` заполнен и Compose видит токен:

```powershell
($line = Get-Content .env | Where-Object { $_ -like 'GITHUB_ACCESS_TOKEN=*' })
($line -replace '^GITHUB_ACCESS_TOKEN=', '').Trim().Length
docker compose config | Select-String 'ACCESS_TOKEN:'
```

Последняя команда покажет значение токена в открытом виде, не публиковать её вывод.

Проверить PAT напрямую через GitHub API:

```powershell
$env:GITHUB_ACCESS_TOKEN = '<github_pat_or_ghp>'
$headers = @{
  Accept = 'application/vnd.github+json'
  Authorization = "Bearer $env:GITHUB_ACCESS_TOKEN"
  'X-GitHub-Api-Version' = '2022-11-28'
}

Invoke-RestMethod -Method Post `
  -Headers $headers `
  -Uri 'https://api.github.com/repos/ShadobaAI/kafka-adapter/actions/runners/registration-token' |
  Select-Object expires_at
```

Если этот запрос не возвращает `expires_at`, runner в контейнере тоже не зарегистрируется.

Пересоздать только runner:

```powershell
docker compose up -d --force-recreate github-runner
docker compose logs -f github-runner
```

## Ошибка доступа к Docker Hub

Если сборка падает на `FROM sonarqube:community` с ошибкой вида `lookup registry-1.docker.io: no such host`, проблема не в `Dockerfile`, а в DNS/прокси Docker Desktop на машине с Docker.

Проверить доступ с Docker-хоста:

```powershell
nslookup registry-1.docker.io
Test-NetConnection registry-1.docker.io -Port 443
docker pull sonarqube:community
```

Если используется корпоративный прокси, указать его в Docker Desktop: `Settings -> Resources -> Proxies`, затем перезапустить Docker Desktop. Если проблема только в DNS, задать DNS в `Settings -> Docker Engine`, например:

```json
{
  "dns": ["8.8.8.8", "1.1.1.1"]
}
```

Если Docker-хост без доступа к Docker Hub, перенести базовый образ с другой машины:

```powershell
docker pull sonarqube:community
docker save sonarqube:community -o sonarqube-community.tar
```

На Docker-хосте:

```powershell
docker load -i sonarqube-community.tar
docker compose up -d --build
```

## Права на создание проектов и запуск анализа

После первого запуска можно разово выдать группе `Anyone` глобальные права `Create Projects` и, при необходимости, `Execute Analysis` через Web API:

```powershell
$sonarUrl = 'http://localhost:9000'
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('admin:admin'))
$headers = @{ Authorization = "Basic $auth" }

Invoke-RestMethod -Method Post -Headers $headers `
  -Uri "$sonarUrl/api/permissions/add_group" `
  -Body @{ groupName = 'Anyone'; permission = 'provisioning' }

Invoke-RestMethod -Method Post -Headers $headers `
  -Uri "$sonarUrl/api/permissions/add_group" `
  -Body @{ groupName = 'Anyone'; permission = 'scan' }
```

`provisioning` соответствует праву `Create Projects`, `scan` соответствует `Execute Analysis`. Второй вызов можно пропустить, если анонимный запуск анализа не нужен.
