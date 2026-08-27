# 1С: Адаптер Kafka — Инструменты разработки

Вспомогательные скрипты и Docker-окружения для локальной разработки и тестирования [1С: Адаптер Kafka](https://github.com/ShadobaAI/kafka-adapter).

## Состав репозитория

| Каталог | Назначение |
|---------|------------|
| `ai/` | Общие инструкции и конфигурация AI-агентов для репозиториев workspace |
| `docker-image/` | Раздельные Docker-образы для CI: `edtcli`, `ibcmd`, `client` |
| `.github/scripts/` | Скрипты для сборки 1С-проектов в CI/CD |
| `.github/workflows/` | GitHub Actions reusable workflows для сборки CF/CFE |
| `kafka/` | Apache Kafka — двухузловой кластер KRaft + Kafka UI |
| `kafka/scripts/` | Вспомогательные скрипты для тестирования Kafka |
| `elk/` | ELK-стек — Elasticsearch + Logstash + Kibana |
| `opensearch/` | Альтернатива ELK — OpenSearch + Dashboards + Fluent Bit |
| `mssql/` | MS SQL Server 2022 — скрипт запуска и утилитарные SQL-скрипты |
| `sonarqube/` | SonarQube Community Build с PostgreSQL, BSL-плагином и русской локализацией |
| `xdto/` | `asyncapi2xsd.py` — генератор XSD; `viewer.html` — визуализатор AsyncAPI для Confluence |

---

## ai

Каталог `ai/` — версионируемый источник общих настроек AI-агентов для фиксированного workspace Kafka Adapter:

| Путь | Назначение |
|------|------------|
| `ai/AGENTS.md` | Общие инструкции workspace, на которые ссылаются локальные `AGENTS.md` репозиториев |
| `ai/.codex/config.toml` | Общий managed MCP block и отдельный Kafka guard block для `%USERPROFILE%\.codex\config.toml` |
| `ai/.codex/skills/1c-routing/` | Выбор authoritative route между EDT-MCP, code-index, BSL LS и v8std |
| `ai/.codex/skills/1c-code-change/` | Pipeline изменений 1С: inspect → EDT write → EDT validate |
| `ai/.codex/skills/1c-platform-docs/` | Project-aware проверка API и совместимости платформы через EDT |
| `ai/.codex/skills/1c-standards/` | Стандарты, diagnostics, patterns и snippet analysis через настроенный v8std |
| `ai/.codex/skills/1c-code-index/` | Broad read-only поиск, структура и графы по индексу проекта |
| `ai/.codex/skills/bsl-ls-mcp/` | Focused BSL diagnostics и semantic navigation |
| `ai/hooks/guard-1c-routing.ps1` | PreToolUse guard для MCP allowlists и прямого доступа к `src/**` |
| `ai/mcp/code-index-mcp.ps1` | Fail-fast запуск federated read-only `bsl-indexer serve` через managed proxy |
| `ai/mcp/code-index-proxy.mjs` | Read-only BSL callers/callees/tree, проверка реального daemon health и уточнение coverage инструментов |
| `ai/mcp/code-index-daemon.ps1` | Управляемый Windows-запуск единого daemon `bsl-indexer` с проверкой PID и HTTP health |
| `ai/code-index/daemon.toml.template` | Канонические aliases и paths общего индекса |
| `ai/workspace-policy.json` | Относительные пути 1С-репозиториев, защищаемых hook |
| `ai/setup.ps1` | Единый bootstrap prerequisites, runtime, policy и code-index daemon |
| `ai/install.ps1` | Идемпотентная установка common config и skills с backup заменяемых файлов |
| `ai/start-v8std.ps1` | Проверка и запуск локального endpoint v8std |

Codex не загружает `.codex` из соседнего репозитория автоматически. `tools/ai` является версионируемым источником, а installer переносит managed block и skills в пользовательский `CODEX_HOME`, сохраняя остальную конфигурацию. Repository-local `.codex/config.toml` содержит назначенный EDT-MCP и его risk policy; repository-local BSL LS добавляется только там, где есть собственная analyzer-конфигурация.

Bootstrap не запускается автоматически при открытии workspace. Его нужно выполнить один раз на каждой машине и повторять после обновления `ai/`. Пользователь может запустить команду самостоятельно; модель также может выполнить её по явному запросу, при необходимости запросив разрешение на запись в `CODEX_HOME`.

Внутренний поставочный комплект должен содержать неизменённые runtime-артефакты `tools/ai/runtime/windows/bsl-indexer.exe` версии `0.69.0` или новее и `tools/ai/runtime/windows/bsl-language-server-exec.jar`. После создания полной структуры `Kafka` установка выполняется одной командой из её корня:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1
```

Bootstrap проверяет Node.js 18+, Java, версию `bsl-indexer`, наличие всех пяти репозиториев; копирует runtime в `%CODEX_HOME%`; вызывает идемпотентный installer; обновляет только Kafka aliases в общем `daemon.toml`, сохраняя aliases других workspace и настройки daemon; перезапускает общий daemon и подтверждает его HTTP health. Сетевые загрузки во время установки не выполняются. Регистрация и readiness repository paths выполняются `bsl-indexer serve` после перезапуска Codex и проверяются инструментом `code-index.health`.

Если артефакты доставляются отдельно, их пути можно передать явно:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1 `
  -BslIndexerPath D:\distribution\bsl-indexer.exe `
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

После успешного завершения перезапустите Codex. `install.ps1` остаётся низкоуровневым идемпотентным установщиком policy/config без runtime prerequisites и используется тестами или при целевом обновлении только managed-конфигурации.

Installer:

- автоматически устанавливает все skills из `ai/.codex/skills/`;
- удаляет с backup только известные устаревшие managed skills `edt-mcp`, `1c-engineering` и `v8std-mcp`, не затрагивая пользовательские skills;
- обновляет общий block между `SHARED-1C-AI MANAGED` markers и отдельный
  Kafka guard block, не смешивая MCP registration с workspace policy;
- сохраняет выбранный пользователем `mcp_servers.v8std.url` при повторной установке;
- устанавливает общий MCP launcher в `%CODEX_HOME%\code-index\mcp`;
- обновляет в `%CODEX_HOME%\code-index\daemon.toml` только `kafka-*` aliases,
  сохраняя aliases других workspace и существующие настройки `[daemon]`;
- синхронизирует workspace `AGENTS.md`;
- подставляет абсолютные пути workspace и hook в установленную конфигурацию;
- сохраняет заменяемые файлы под `%CODEX_HOME%\backups\workspace-ai`;
- не читает и не копирует credentials, `.env` или `auth.json`.

Для переноса в другой workspace скопируйте каталог `ai/`, настройте его `AGENTS.md` и `workspace-policy.json`, добавьте runtime-артефакты, затем выполните:

```powershell
D:\path\to\ai\setup.ps1 -WorkspaceRoot D:\path\to\workspace
```

Расположение каталога `ai/` внутри workspace не фиксировано. Installer обнаруживает skills автоматически и генерирует рабочий hook command для фактических путей.

Hooks — lifecycle-обработчики Codex. `PreToolUse` вызывается перед подходящим tool call и может разрешить или отклонить его. В этой policy hook запускает `guard-1c-routing.ps1`, который блокирует code-index/BSL LS tools вне read-only allowlists, прямой filesystem-доступ к настроенным 1С `src/**` и EDT `git`/`ask_workmate`. Hook не является MCP и не выполняет диагностику или изменение 1С сам по себе.

MCP routing:

| Scope | MCP |
|---|---|
| `adapter/adapter`, `adapter/base`, `adapter/examples` | repository-owned `kfk-edt` |
| `tests/unit/unit`, generated `tests/unit/base` | repository-owned `kfk-unit-edt` |
| `conversion/KFK` | repository-owned `conv-edt` |
| Все канонические 1С-репозитории | общий federated `code-index`, только explicit read-only allowlist |
| `adapter/adapter` | repository-owned `bsl-ls` через `.codex/mcp/bsl-ls-proxy.mjs` |
| Standards, diagnostic codes и snippets | `v8std`; по умолчанию `https://ai.v8std.ru/mcp` |

Для полной 1С-surface требуются Node.js 18+, Java, Windows-сборка `bsl-indexer.exe` версии `0.69.0` или новее (не публичный npm-бинарник `code-index`) и executable JAR BSL LS. Bootstrap устанавливает оба артефакта в managed-каталоги `%CODEX_HOME%`. Один `CODE_INDEX_HOME` и daemon обслуживают все зарегистрированные workspace; coordination/log runtime хранится там, а индексы — в исключённых из Git `.code-index/` каталогах repository roots. Managed proxy добавляет `get_callers_bsl`, `get_callees_bsl` и `get_call_tree_bsl`; имена процедур ищутся регистронезависимо для латиницы и кириллицы, а coverage относится только к статическому графу. `get_register_writers` показывает только декларативные связи `RegisterRecords`, а не программную запись через `RecordSet`/`RecordManager`.

На Windows запускайте daemon через managed launcher. Он сериализует конкурентные старты для одного `CODE_INDEX_HOME`, отключает проблемный self-detach бинарника и создаёт процесс с `bInheritHandles=false`, поэтому daemon не удерживает stdio-pipes MCP-клиента и не падает после их закрытия. Успех возвращается только после проверки реального `GET /health`; основной журнал остаётся в `%CODEX_HOME%\code-index\daemon.log`:

```powershell
.\tools\ai\mcp\code-index-daemon.ps1 -Action run
```

Обычный запуск `code-index` MCP выполняет эту проверку и bootstrap автоматически. Ручная команда нужна для отдельной диагностики или предварительного запуска.

Проверка состояния:

```powershell
.\tools\ai\mcp\code-index-daemon.ps1 -Action status -Json
```

Статус `online` выдаётся только при совпадении PID из `daemon.json` с ответом `GET /health`. Устаревший runtime descriptor классифицируется как `stale_runtime_info`, а живой процесс без рабочего endpoint — как `unhealthy`. Launcher не запускает второй daemon поверх живого `unhealthy`-процесса: сначала исследуйте причину и используйте явный `-Action stop`.

Repository-local BSL LS config использует относительный `cwd` и не требует изменения путей на машинах команд. Proxy использует существующую `.bsl-language-server.json`, фиксирует repository root и отклоняет file-аргументы вне него. На Windows для не-ASCII file paths требуется доступный 8.3 short path; proxy сообщает явную compatibility error, если volume short names отключены.

Endpoint выбирает пользователь в `%USERPROFILE%\.codex\config.toml`. Для локального v8std замените только URL, сохранив имя MCP `v8std`:

```toml
[mcp_servers.v8std]
url = "http://127.0.0.1:8766/mcp"
```

Installer сохраняет выбранный URL при последующих обновлениях policy. Локальный v8std запускается из отдельного checkout на порту `8766`, поскольку `8765` занят EDT-MCP. Checkout должен содержать сгенерированные `docs/ai/pages.jsonl` и `docs/ai/search-vectors.jsonl` и установленные зависимости из upstream `requirements.txt`/`requirements-mcp.txt`:

```powershell
.\ai\start-v8std.ps1 -V8stdRoot C:\path\to\v8std
```

Не добавляйте в `ai/` `auth.json`, токены, пароли, локальные `.env`, данные сессий и другие персональные файлы Codex.

---

## docker-image

Многоэтапный Docker-образ для CI/CD-сборки проектов на платформе 1С. Включает:

- **1С:Предприятие** (ibcmd) — только компоненты `common` + `server`
- **EDT** (1cedtcli, ring) — с bundled JRE
- **OneScript** (oscript, opm)
- **vanessa-runner**

**Актуальные версии** для CI задаются в GitHub Actions Variables: `EDT` и `PLATFORM`.

| Компонент | Версия |
|-----------|--------|
| 1С:Платформа | `8.5.1` |
| EDT | `2025.2.6` |
| OneScript | `latest` из `https://oscript.io/downloads/latest` |

**Предварительно** — разместить дистрибутивы в `docker-image/distr/` (см. [docker-image/README.md](docker-image/README.md)):

| Файл | Описание |
|------|----------|
| `deb64_*.zip` | 1С:Предприятие — deb-пакеты для Linux x86_64 |
| `1c_edt_distr_offline_*_linux_x86_64.tar.gz` | EDT — офлайн-дистрибутив для Linux x86_64 |
| `OneScript-*-linux-x64.zip` | OneScript для Linux x64 |

Сборка и публикация в GHCR:

```powershell
python .\docker-image\scripts\build_image.py edtcli:2025.2.6 --edt-platform-support 8.3.27
python .\docker-image\scripts\build_image.py ibcmd:8.3.27
```

При публикации образы пушатся в `ghcr.io/<owner>/edtcli:latest` и `ghcr.io/<owner>/ibcmd:latest`.
`$OWNER` определяется автоматически из учётных данных Docker Desktop (ghcr.io).

## .github

### .github/scripts

Вспомогательные скрипты в `.github/scripts/`:

| Скрипт | Описание |
|--------|----------|
| `detect_project.py` | Валидирует версию, определяет тип проекта и имя конфигурации |
| `set_version.py` | Заменяет `9.9.9.9` на реальную версию в указанных файлах |
| `patch_mdo.py` | Вырезает атрибуты расширения при сборке CFE-проекта как CF |
| `convert_artifacts.py` | Упаковывает EDT/XML-каталоги в ZIP |
| `edt2xml.py` | Запускает образ `edtcli` и конвертирует EDT-проект в XML |
| `xml2cf.py` | Запускает образ `ibcmd` и собирает `.cf` или `.cfe` из XML |
| `ci_utils.py` | Общие утилиты для CI-скриптов (`EDT_PROJECT_ENTRIES`, `MDO_PATH`, `write_github_output`) |

### .github/workflows/release-1c-artifacts.yml — reusable workflow: 1C release artifacts

Вызываемый workflow (`workflow_call`) для сборки `.cf` / `.cfe` по тегу релиза (формат `X.X.X.X`).
Поддерживает сборку CF из проекта расширения (cfe → cf): если `.project` содержит `V8ExtensionNature`, а `build_type: cf` — атрибуты расширения вырезаются автоматически.

Образы берутся из GHCR (`ghcr.io/shadobaai/edtcli:latest` и `ghcr.io/shadobaai/ibcmd:latest`). Загружает в GitHub Release три артефакта:
- `{name}-{version}.{cf|cfe}` — скомпилированный файл конфигурации / расширения
- `{name}-{version}-edt.zip` — исходники в формате EDT
- `{name}-{version}-XML.zip` — промежуточные XML-файлы

Имя `{name}` берётся из тега `<name>` в `src/Configuration/Configuration.mdo`.

| Входной параметр | Обязательный | Описание |
|-----------------|:---:|----------|
| `build_type` | нет | `cf` или `cfe`; авто, если не задан |
| `name_suffix` | нет | Суффикс имени файлов: `{name}-{suffix}-{version}-edt.zip` и т.д. |
| `version_files` | нет | Доп. файлы для замены версии (через пробел, относительно корня) |
| `pre_script` | нет | Скрипт (`.py` или `.sh`) для выполнения на EDT-исходниках до сборки |

Использует `GITHUB_TOKEN` (встроен автоматически) для публикации в Release и GHCR.

---

## kafka

Двухузловой кластер Apache Kafka в режиме KRaft (без ZooKeeper) + веб-интерфейс Kafka UI.

```
cd kafka
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| Kafka node1 (внешний) | `localhost:29091` |
| Kafka node2 (внешний) | `localhost:29092` |
| Kafka UI | http://localhost:8081 |

Bootstrap-серверы для адаптера: `localhost:29091,localhost:29092`

### kafka/scripts/kafka_sender.py

Генератор нагрузки для тестирования адаптера — отправляет случайные JSON-сообщения в топики Kafka.

**Зависимости:** `pip install kafka-python`

Скрипт отправляет сообщения двух типов:

| Топик | Описание |
|-------|----------|
| `1c.test-register` | Сообщение регистра (событие, UUID, число, строка, дата, булево) |
| `1c.test-catalog` | Сообщение справочника (ref, наименование, перечисление, табличная часть) |

Параметры задаются в секции `data` внутри скрипта:

| Параметр | Описание |
|----------|----------|
| `total` | Количество сообщений |
| `speed` | Скорость (msg/sec); `0` — максимальная |
| `topic` | `"register"`, `"catalog"` или `None` (оба топика) |

```bash
python kafka/scripts/kafka_sender.py
```

---

## elk

ELK-стек для централизованного логирования истории обмена адаптера.

```
cd elk
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| Elasticsearch | http://localhost:9200 |
| Kibana | http://localhost:5601 |
| Logstash (HTTP input) | http://localhost:8082 |

Конфигурация Logstash — `elk/config/logstash.conf`.
Резервное копирование данных — `elk/backup.ps1`.

---

## opensearch

Альтернативный стек логирования на базе OpenSearch с агрегатором Fluent Bit.

```
cd opensearch
docker compose up -d
```

| Сервис | Адрес |
|--------|-------|
| OpenSearch | http://localhost:9201 |
| OpenSearch Dashboards | http://localhost:5602 |
| Fluent Bit (HTTP input) | http://localhost:9880 |

Конфигурация — `opensearch/config/`.

---

## mssql

MS SQL Server 2022 с кириллической сортировкой (`Cyrillic_General_CI_AS`) и русской локалью.

```powershell
.\mssql\docker_run_mssql.ps1
```

| Параметр | Значение |
|----------|----------|
| Порт | `1433` |
| Логин | `sa` |
| Пароль | `Qwerty123!` |
| Сортировка | `Cyrillic_General_CI_AS` |
| Резервные копии (том) | `C:\docker-backups\mssql` |

Дополнительно в каталоге `mssql/`:
- `Очистка кэша.sql` — сброс кешей плана запросов и буферного пула;
- `Статистика индексов.sql` — анализ фрагментации индексов.

---

## sonarqube

Локальный SonarQube Community Build для статического анализа BSL-кода. Окружение включает PostgreSQL, `sonar-bsl-plugin-community` и русский language pack для интерфейса.

```powershell
cd sonarqube
docker compose up -d --build
```

| Сервис | Адрес |
|--------|-------|
| SonarQube | http://localhost:9000 |
| GitHub Actions runner | `1c.github-runner`, labels: `self-hosted,linux,x64,sonar-docker` |
| PostgreSQL | внутренний сервис `db:5432` |

Настройки анализа проекта задаются в `sonar-project.properties` анализируемого репозитория.

### Обновление BSL-плагина

Перед обновлением сделать резервную копию PostgreSQL. Это обязательно, поскольку используемый в `sonarqube/Dockerfile` плавающий базовый образ `sonarqube:community` при пересборке может обновить не только BSL-плагин, но и сам SonarQube:

```powershell
cd sonarqube
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

### Резервное копирование SonarQube

Скрипт `sonarqube/backup-sonarqube.sh` сохраняет полный дамп PostgreSQL в `sonarqube/backups/`. В дамп входят проекты, история анализов, настройки, пользователи и токены SonarQube. Контейнер `db` должен быть запущен.

```bash
cd sonarqube
bash backup-sonarqube.sh
```

Для восстановления используйте ту же версию SonarQube и плагинов. Команды ниже удаляют текущую БД:

```bash
cd sonarqube
docker compose stop sonarqube
docker compose up -d db
docker compose exec -T db sh -c 'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' < backups/sonarqube_YYYYMMDD_HHMMSS/sonarqube.dump
docker compose up -d sonarqube
```

Тома `sonarqube_data` и `sonarqube_logs` восстанавливать не нужно: это кэш, индексы и журналы, они создаются заново.

### GitHub Actions runner

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
cd sonarqube
docker compose up -d --force-recreate github-runner
docker compose logs -f github-runner
```

### Ошибка доступа к Docker Hub

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
cd sonarqube
docker compose up -d --build
```

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

---

## xdto/viewer.html

Самодостаточный HTML-визуализатор AsyncAPI-спецификации для HTML macro Confluence. Загружает attachment `asyncapi.yaml` с текущей страницы без фиксации версии attachment и не зависит от внешнего CDN или backend-приложения.

Возможности:

- обязательный выбор Kafka-топика с сохранением адреса в URL hash;
- компактная информация о топике, формате и количестве полей;
- табличное представление properties с поддержкой вложенных объектов и массивов;
- разрешение локальных `$ref`, включая enum, `allOf` и защиту от циклов;
- отображение `x-topics`, ограничений, `pattern`, `default`, examples и пользовательских `x-*`;
- поиск внутри выбранного топика и фильтры `Required` / `Deprecated`;
- раскрытие и сворачивание вложенных полей;
- экспорт текущего отфильтрованного представления в CSV с UTF-8 BOM.

### Подключение к Confluence

1. Прикрепить к странице файл с точным именем `asyncapi.yaml`.
2. Поместить содержимое [`xdto/viewer.html`](xdto/viewer.html) в HTML macro на этой же странице.
3. Если `pageId` не определяется из контекста Confluence автоматически, указать его в константе `PAGE_ID` внутри `viewer.html`.

При обновлении спецификации достаточно заменить attachment; изменять HTML macro не требуется.

---

## xdto/asyncapi2xsd.py

Конвертирует схемы из [AsyncAPI YAML](https://studio.asyncapi.com/) в XSD для импорта в XDTO-пакет 1С.

Требуется Python 3.10 или новее. Установка зависимостей:

```powershell
python -m pip install pyyaml lxml
```

### Использование

```powershell
python .\xdto\asyncapi2xsd.py <input.yaml> <output.xsd> -n <namespace> [--prefix <prefix>] [--suffix <suffix>]
```

| Аргумент | Обязательный | Описание |
|----------|:---:|----------|
| `input` | да | Путь к AsyncAPI YAML |
| `output` | да | Путь к выходному XSD |
| `-n`, `--namespace` | да | `targetNamespace` генерируемой схемы |
| `--prefix` | нет | Префикс адреса канала, отрезаемый при формировании имени типа |
| `--suffix` | нет | Суффикс адреса канала, отрезаемый при формировании имени типа |

Готовый пример спецификации: [`xdto/asyncapi_example.yaml`](xdto/asyncapi_example.yaml). Соответствующий результат: [`xdto/asyncapi_example.xsd`](xdto/asyncapi_example.xsd).

```powershell
python .\xdto\asyncapi2xsd.py `
  .\xdto\asyncapi_example.yaml `
  .\xdto\asyncapi_example.generated.xsd `
  --namespace http://example.com/xdto `
  --prefix 1c. `
  --suffix .changed
```

Параметры `--prefix` и `--suffix` применяются к адресам каналов. Например, из адреса `1c.test-document.changed` будет сформировано имя типа `TestDocument`. Если канал для схемы не найден, используется имя схемы из `components.schemas`.

### Поддерживаемые схемы

| AsyncAPI / JSON Schema | XSD |
|------------------------|-----|
| `string` | `xs:string` |
| `string` + `uuid` | `tns:UUID` с проверкой формата |
| `string` + `date`, `date-time`, `time` | `xs:date`, `xs:dateTime`, `xs:time` |
| `integer` | `xs:integer` |
| `integer` + `int32`, `int64` | `xs:int`, `xs:long` |
| `number` | `xs:decimal` |
| `number` + `float`, `double` | `xs:float`, `xs:double` |
| `boolean` | `xs:boolean` |
| `object` | именованный `xs:complexType` |
| `array` | повторяющийся элемент с границами из `minItems` и `maxItems` |
| `enum` | `xs:simpleType` с ограничениями `xs:enumeration` |

Генератор поддерживает:

- вложенные объекты и массивы примитивов, объектов, перечислений и ссылочных типов;
- массивы верхнего уровня;
- локальные ссылки вида `#/components/schemas/<имя>`, включая циклические зависимости;
- строковые ограничения `minLength`, `maxLength`, `pattern`;
- числовые ограничения `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`;
- `multipleOf`, если значение точно представимо через `fractionDigits`: `0.1`, `0.01` и аналогичные десятичные шаги; для целых чисел поддерживается `1`;
- обязательность свойств через `required`; необязательные скалярные свойства формируются с `nillable="true"`.

Внешние `$ref`, логические схемы (`oneOf`, `anyOf`, `allOf`) и `boolean enum` не поддерживаются. При неизвестной ссылке или несовместимом ограничении генератор завершает работу с ошибкой, содержащей путь к проблемному свойству.

---

## Справочник команд Docker

### Запуск и остановка

| Команда | Описание |
|---------|----------|
| `docker compose up -d` | Поднять сервисы в фоне |
| `docker compose up -d --build` | Пересобрать образы и запустить |
| `docker compose down` | Остановить и удалить контейнеры и сети |
| `docker compose down -v` | То же + удалить тома |

### Логи и отладка

| Команда | Описание |
|---------|----------|
| `docker compose logs -f` | Поток логов всех сервисов |
| `docker compose logs -f <service>` | Логи конкретного сервиса |
| `docker compose exec <service> sh` | Shell внутри контейнера |

### Состояние окружения

| Команда | Описание |
|---------|----------|
| `docker ps` | Активные контейнеры |
| `docker ps -a` | Все контейнеры, включая остановленные |
| `docker images` | Локальные образы |

### Очистка

| Команда | Описание |
|---------|----------|
| `docker system prune -a --volumes` | Удалить неиспользуемые контейнеры, образы, кеш и тома |
| `docker volume prune` | Удалить неиспользуемые тома |

---

## Лицензия

Проект распространяется под лицензией [Apache License 2.0](LICENSE).

**Разрешается:** использование, модификация и распространение — в том числе в коммерческих проектах — без ограничений.
