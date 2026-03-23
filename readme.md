# 1С: Адаптер Kafka — Инструменты разработки

Вспомогательные скрипты и Docker-окружения для локальной разработки и тестирования [1С: Адаптер Kafka](https://github.com/ShadobaAI/kafka-adapter).

## Состав репозитория

| Каталог | Назначение |
|---------|------------|
| `docker-image/` | Docker-образ для сборки 1С: Платформа + EDT + OScript + vrunner |
| `.github/scripts/` | Скрипты для сборки 1С-проектов в CI/CD |
| `.github/workflows/` | GitHub Actions reusable workflows для сборки CF/CFE |
| `kafka/` | Apache Kafka — двухузловой кластер KRaft + Kafka UI |
| `kafka/scripts/` | Вспомогательные скрипты для тестирования Kafka |
| `elk/` | ELK-стек — Elasticsearch + Logstash + Kibana |
| `opensearch/` | Альтернатива ELK — OpenSearch + Dashboards + Fluent Bit |
| `mssql/` | MS SQL Server 2022 — скрипт запуска и утилитарные SQL-скрипты |
| `xdto/` | `asyncapi2xsd.py` — генератор XSD из AsyncAPI-спецификации |

---

## docker-image

Многоэтапный Docker-образ для CI/CD-сборки проектов на платформе 1С. Включает:

- **1С:Предприятие** (ibcmd) — только компоненты `common` + `server`
- **EDT** (1cedtcli, ring) — с bundled JRE
- **OneScript** (oscript, opm)
- **vanessa-runner**

**Актуальные версии** (заданы в `docker-image/build.ps1`):

| Компонент | Версия |
|-----------|--------|
| 1С:Платформа | `8.3.27.2074` |
| EDT | `2025.2.3` |
| OneScript | `2.0.1` |

**Предварительно** — разместить дистрибутивы в `docker-image/distr/` (см. [docker-image/distr/README.md](docker-image/distr/README.md)):

| Файл | Описание |
|------|----------|
| `deb64_*.zip` | 1С:Предприятие — deb-пакеты для Linux x86_64 |
| `1c_edt_distr_offline_*_linux_x86_64.tar.gz` | EDT — офлайн-дистрибутив для Linux x86_64 |
| `OneScript-*-linux-x64.zip` | OneScript для Linux x64 |

Сборка и публикация в GHCR:

```powershell
.\docker-image\build.ps1
```

После успешной сборки образ автоматически пушится в `ghcr.io/<owner>/1c-build:latest`.
`$OWNER` определяется автоматически из учётных данных Docker Desktop (ghcr.io).

### docker-image/push-dt.ps1 — публикация шаблона базы (.dt)

Публикует файл `.dt` как OCI-артефакт в GHCR через [ORAS](https://oras.land/).

Перед запуском задать `$TOKEN` в начале скрипта (GitHub PAT с правом `packages:write`), затем:

```powershell
.\docker-image\push-dt.ps1
```

`$OWNER` и `$IMAGE` определяются автоматически из учётных данных Docker Desktop (ghcr.io).

| Переменная | Описание | По умолчанию |
|------------|----------|:---:|
| `$TOKEN` | GitHub PAT с правом `packages:write` | — |
| `$FILE` | Путь к `.dt`-файлу | `.\template.dt` |
| `$IMAGE` | Целевой образ в GHCR | `ghcr.io/<owner>/kfk-tmpl-dt:latest` |

Получить артефакт: `oras pull ghcr.io/<owner>/kfk-tmpl-dt:latest`

---

## .github

### .github/scripts/build.py — сборка CF / CFE

Собирает `.cf` или `.cfe` из EDT-проекта: EDT → XML → артефакт.
`BUILD_TYPE` определяется автоматически по `.project` (`V8ExtensionNature` → `cfe`, `V8ConfigurationNature` → `cf`).

| Переменная | Описание | По умолчанию |
|------------|----------|:---:|
| `VERSION` | Версия в формате X.X.X.X | — |
| `BUILD_TYPE` | `cf` или `cfe` (авто, если не задан) | — |
| `SRC_DIR` | Исходники EDT-проекта | `/src` |
| `OUTPUT_DIR` | Каталог результата | `/output` |

Заглушка версии в исходниках — `9.9.9.9` (подставляется скриптом `set_version.py` до запуска сборки).

Вспомогательные скрипты в `.github/scripts/`:

| Скрипт | Описание |
|--------|----------|
| `detect_project.py` | Валидирует версию, определяет тип проекта и имя конфигурации |
| `set_version.py` | Заменяет `9.9.9.9` на реальную версию в указанных файлах |
| `patch_mdo.py` | Вырезает атрибуты расширения при сборке CFE-проекта как CF |
| `package.py` | Упаковывает артефакты в ZIP и формирует итоговые имена файлов |
| `ci_utils.py` | Общие утилиты для CI-скриптов (`EDT_PROJECT_ENTRIES`, `MDO_PATH`, `write_github_output`) |

### .github/workflows/build.yml — reusable workflow: CF/CFE

Вызываемый workflow (`workflow_call`) для сборки `.cf` / `.cfe` по тегу релиза (формат `X.X.X.X`).
Поддерживает сборку CF из проекта расширения (cfe → cf): если `.project` содержит `V8ExtensionNature`, а `build_type: cf` — атрибуты расширения вырезаются автоматически.

Образ берётся из GHCR (`ghcr.io/shadobaai/1c-build:latest`). Загружает в GitHub Release три артефакта:
- `{name}-{version}.{cf|cfe}` — скомпилированный файл конфигурации / расширения
- `{name}-{version}-edt.zip` — исходники в формате EDT
- `{name}-{version}-XML.zip` — промежуточные XML-файлы

Имя `{name}` берётся из тега `<name>` в `src/Configuration/Configuration.mdo`.

| Входной параметр | Обязательный | Описание |
|-----------------|:---:|----------|
| `dockerhub_image` | да | Имя образа в GHCR (без префикса `ghcr.io/<owner>/`) |
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

## xdto/asyncapi2xsd.py

Конвертирует схемы из [AsyncAPI YAML](https://studio.asyncapi.com/) в XSD для импорта в XDTO-пакет 1С.

**Зависимости:** `pip install pyyaml lxml`

### Использование

```
python asyncapi2xsd.py <input.yaml> <output.xsd> -n <namespace> [--prefix <prefix>] [--suffix <suffix>]
```

| Аргумент | Обязательный | Описание |
|----------|:---:|----------|
| `input` | да | Путь к AsyncAPI YAML |
| `output` | да | Путь к выходному XSD |
| `-n`, `--namespace` | да | `targetNamespace` генерируемой схемы |
| `--prefix` | нет | Префикс адреса канала, отрезаемый при формировании имени типа |
| `--suffix` | нет | Суффикс адреса канала, отрезаемый при формировании имени типа |

```bash
# Без strip-правил — имя типа берётся напрямую из адреса канала
python asyncapi2xsd.py spec.yaml out.xsd -n http://example.com/ns

# С prefix/suffix — crm.someObject.changed → SomeObject
python asyncapi2xsd.py spec.yaml out.xsd \
  -n http://example.com/ns \
  --prefix crm. \
  --suffix .changed
```

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

Проект распространяется под лицензией MIT + Commons Clause.

**Разрешается:** свободное использование, модификация и внедрение в собственных и коммерческих решениях.

**Запрещается:** продажа подсистемы или её производных в качестве самостоятельного продукта.
