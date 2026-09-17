# Codex toolkit для Kafka Adapter

[← Все инструменты](../README.md)

Каталог `tools/ai` содержит общую AI-инфраструктуру фиксированного Kafka workspace:
установщик, `code-index`, общие 1С-skills, routing guard и regression-тесты.
Новый [policy subsystem](policy/README.md) содержит versioned exact-selector registry
и read-only MCP; штатный installer доставляет его декларацию вместе с OpenViking MCP.
Доставкой shared skills, MCP declarations и routing guard владеет `install.cmd`.
`node .\tools\ai\doctor.mjs` из корня Kafka выполняет fail-closed preflight без установки.
Doctor читает установленную конфигурацию через `codex mcp get --json`:
shared MCP — из пользовательского профиля (`CODEX_HOME`, если задан) с учётом
project overrides при выборе конкретного репозитория, EDT и
BSL LS — из каталогов назначенных владельцев. Требуется доступный в PATH Codex CLI.
Codex сам разбирает TOML и учитывает доверие к проекту; непризнанный или недоверенный
project config не подменяется guessed URL. Значения credentials и полный config
в отчёт не выводятся. Переменные `KAFKA_CODE_INDEX_HOME`,
`KAFKA_OPENVIKING_STATE_DIR` и `V8STD_MCP_URL` для doctor больше не обязательны:
используются command/args/env/URL установленного MCP.
Doctor принимает `--project-root <root>`: допустим корень workspace либо корень
любого отдельного Git-репозитория внутри него. Это соответствует открытию Codex
из `adapter/adapter`, `conversion/KFK`, `tests/unit/unit`, `tools` и других Kafka
repositories; установленные MCP-пути не зависят от текущего каталога.
Doctor выбирает только назначенный EDT-контур: adapter — `kfk-edt`, conversion —
`conv-edt`, unit — `unit-edt`. Workspace root требует все три контура; для
`tools`, `tasks`, `tests/reports` и `tests/ui` EDT не требуется. Неизвестный или
вложенный корень отклоняется до runtime-проверок. Наличие runtime-файлов и URL
не подтверждает readiness: выполняются MCP handshake и контрольные запросы.
Экспортируемый `checkCodeIndexHealth` проверяет managed MCP health contract,
единственную регистрацию каждого required alias и точное совпадение обоих
reported paths с canonical checkout. CLI вызывает `health` через установленный
managed stdio launcher из MCP args с `-SkipDaemonBootstrap`:
daemon не запускается и не перезапускается. Вся сессия ограничена 10–120 секундами
(по максимуму `startup_timeout_sec` и `tool_timeout_sec`) и
1 MiB ответа; ошибки transport/protocol, stale paths и неполные ответы дают
`error`. Для non-1C repositories code-index не требуется.
EDT проверяется через `get_server_status` и `list_projects`: назначенный порт,
точные пути, открытые проекты в состоянии `ready`. Для YAxUnit путь EDT-проекта —
`tests/unit/yaxunit/exts/yaxunit`; корень репозитория и code-index остаётся
`tests/unit/yaxunit`. BSL LS проверяется запросом
`global_member_search` в назначенном root, без анализа исходников. Дополнительный
`bsl-ls` учитывается, если он объявлен для выбранного проекта или владельца контура.
Для v8std читается контрольный документ через `v8std_get_summary`; policy выполняет
контрольный запрос selector. Для OpenViking отдельно проверяются MCP, runtime
`/health` и `/ready`, а также свежесть Git inventory по state-dir из MCP args.
Синхронизация, bootstrap и перезапуск сервисов не выполняются.
HTTP-клиент поддерживает Streamable HTTP с JSON/SSE ответами, configured headers
и bearer token из env; сохранённый OAuth Codex и legacy SSE transport не используются.
`ready` означает успех этих проверок MCP/runtime, а не полную приёмку продукта,
диагностику исходников или аудит всех установленных skills/hooks. Полная проверка
профиля остаётся в штатных installation tests.
Windows entrypoint `tools\ai\doctor.cmd` выводит результаты preflight с русскими
пояснениями, отдельно показывает ошибки настройки и непроверенные компоненты и ждёт нажатия
клавиши перед закрытием окна. Для автоматического запуска задайте
`KAFKA_AI_NO_PAUSE=1`; код завершения doctor сохраняется после паузы.
Для JSON используйте `node tools/ai/doctor.mjs`; для текстового отчёта —
`node tools/ai/doctor.mjs --human`. Статус `not-ready` означает, что готовность
не подтверждена, а `unverified` — что проверка не выполнена, а не отказ сервиса.
При запуске без аргументов из `tools\ai` (в том числе двойным щелчком в Проводнике)
проверяется корень Kafka workspace. Из других каталогов сохраняется текущий
каталог; явный `--project-root <root>` имеет приоритет. Полный
`install.cmd` проверяет последний стабильный OpenViking runtime, устанавливает обновление, проверяет provider через
официальный `doctor`, запускает локальный server, выполняет initial Git sync и только
после успешных MCP smoke checks устанавливает reconciliation hooks. При первом запуске
на новом ПК официальный `init` интерактивно запрашивает provider/model и credentials;
повторная установка использует существующую user-owned конфигурацию и runtime.
`tools\ai\update-openviking.cmd` по умолчанию обновляет производный Git-backed
index инкрементально: записывает только новые и изменённые документы committed HEAD
и удаляет исчезнувшие. Неизменённые документы повторно не индексируются.
Полная перестройка запускается явно: `tools\ai\update-openviking.cmd --rebuild`.
Если состояние отсутствует, осталось незавершённым после сбоя или несовместимо
с Git/runtime/manifest, обычный запуск останавливается до изменения индекса
и предлагает `--rebuild`. Runtime скрипт не устанавливает и не перезапускает.
Окно остаётся открытым до нажатия клавиши, в том числе при ошибке настройки.
Для автоматического запуска задайте `KAFKA_AI_NO_PAUSE=1`; код завершения сохраняется.
Hooks ставятся во все девять Kafka-owned repositories из workspace manifest;
upstream checkout `tests/unit/yaxunit` намеренно исключён.
EDT и BSL LS остаются repository-local и настраиваются в репозиториях-владельцах.

Навыки и политика EDT опираются на live API назначенного сервера и его `get_tool_guide`.
Рабочие контракты находятся в
[редактировании](.codex/skills/1c-code-change/references/edt-editing.md) и
[политике инструментов](.codex/skills/1c-routing/references/tool-policy.md).
Конфиги трёх контуров сохраняют свои endpoints и запрет `git`/`ask_workmate`;
новые инструменты доступны с явно заданными режимами подтверждения.
Параметры Codex соответствуют [документации MCP](https://developers.openai.com/codex/mcp).

## Установка

Структура каталогов Kafka фиксирована. Переносить можно весь workspace целиком;
меняется только абсолютный путь к его корню. Установщик должен находиться по пути
`<KAFKA_ROOT>\tools\ai\install.cmd`.

На Windows откройте `tools\ai` в Проводнике и дважды щёлкните `install.cmd` либо
запустите из корня Kafka:

```bat
.\tools\ai\install.cmd
```

Это один самодостаточный файл: CMD-часть извлекает встроенную PowerShell-часть во
временный файл, запускает её штатным Windows PowerShell 5.1 и удаляет временный файл.
Отдельный `setup.ps1` не используется. Git Bash и PowerShell 7 не требуются.

Для BSL LS источник параметров запуска — `adapter/adapter/.codex/config.toml`. Перед подготовкой runtime установщик требует абсолютные пути к proxy, `cwd`, `--root` и явно заданной `--java`; `cwd` и `--root` должны указывать на checkout адаптера. Проверяется Java 25 или новее именно из `--java`. Если передан `-JavaPath` или задан `BSL_LANGUAGE_SERVER_JAVA`, он должен совпадать с этим путём. Локальный конфиг не перезаписывается: ошибка сообщает, что требуется исправить владельцу репозитория.

Проверка BSL LS использует `command`, `args` и `cwd` из этой регистрации, начиная из постороннего каталога, и выполняет `initialize`/`tools/list`. Поддерживается явная форма с двойными кавычками и массивом строк `args` (в том числе многострочным); таблица `env` и неподдерживаемый синтаксис отклоняются, а не подменяются тестовыми настройками.

Установщик проверяет полную структуру Kafka, Node.js 18+ и Java 25+. Явный `-NodePath`
имеет высший приоритет; иначе сначала используется `%ProgramFiles%\nodejs\node.exe`,
и только затем первый `node` из `PATH`. Node.js здесь нужен
для локальных JavaScript proxy `code-index` и BSL LS; к Kafka broker он отношения не
имеет. Явно переданные runtime-пути используются без сетевого поиска. Иначе
установщик сравнивает версии `bsl-indexer` и BSL Language Server из
`runtime\windows` с canonical GitHub releases и загружает проверенный artifact,
только если локальный компонент отсутствует или отличается от опубликованного.
OpenViking и Ollama запускаются только в Docker Desktop (Linux containers + Compose).
Installer сверяет версию официального образа с latest-stable в PyPI и сохраняет
image digest. Windows Python и wheel-параметры больше не поддерживаются.
Локальное состояние находится в `<CodexHome>\openviking-docker`, данные и модели —
в отдельных Docker volumes. Перед загрузкой образов и моделей запрашивается
подтверждение с указанием моделей и их размеров. По умолчанию используется CPU;
`-OpenVikingGpu` включает NVIDIA GPU reservation (требуется доступ GPU из Docker).
API OpenViking публикуется только на loopback:1933; в локальном managed-режиме
Ollama не публикует порт на Windows.
Если Ollama уже работает на GPU физического хоста, передайте
`-OllamaUrl http://gpu-host:11434` (или `KAFKA_OLLAMA_URL`): в ВМ запускается только
OpenViking, модели и второй контейнер Ollama не скачиваются. Адрес сохраняется
для повторного запуска. Обе модели должны быть заранее установлены на хосте.
Пошаговая [установка в Hyper-V ВМ с Ollama на GPU физического хоста](openviking/INSTALL-WINDOWS-HYPERV.md)
включает запуск контейнера, модели, firewall, проверку GPU и команду установщика.
Подробности и команды диагностики — в [OpenViking README](openviking/README.md).
`-SkipOpenVikingRuntime` явно пропускает runtime, provider,
server, initial sync, OpenViking MCP smoke и Git hooks.

Для закрытого контура можно передать оба файла явно:

```bat
.\tools\ai\install.cmd ^
  -BslIndexerPath D:\distribution\bsl-indexer.exe ^
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

При полной установке проверяются readiness всех `[[paths]]` итогового общего
`daemon.toml` (включая aliases других workspace), MCP surface `code-index`,
repository-local BSL LS и доступность `v8std`. `-ConfigurationOnly` устанавливает
только конфигурацию. `-SkipDaemonStart` не запускает managed daemon. В этих режимах
полная runtime/readiness-проверка не выполняется.

Перед запуском daemon полная установка удаляет `.code-index` у всех Kafka-путей,
объявленных в `code-index\daemon.toml.template`, и строит их заново. Сохранённые
пути других workspace не удаляются. `-ConfigurationOnly` не меняет индексы;
`-SkipDaemonStart` удаляет старые Kafka-индексы, но оставляет их перестроение на
последующий запуск daemon.

Во время работы установщик показывает нумерованные этапы, отмечает успешные и
предупреждающие проверки префиксами `[OK]`/`[WARNING]`, сообщает ход rollback и
завершает выполнение сводкой `RESULT`.

После успешной установки перезапустите Codex и откройте нужный repository root.

## Обновление code-index

Для уже установленного code-index запустите отдельный скрипт:

```bat
.\tools\ai\update-code-index.cmd
```

`update-code-index.cmd` работает через Windows PowerShell 5.1 и не запускает
`install.cmd`. Сначала он проверяет установку и зарегистрированные пути, завершает
managed daemon и дожидается выхода процесса. Также завершает отдельные MCP-процессы
`bsl-indexer serve` с точным совпадением installed executable и `daemon.toml`:
они могут удерживать `index.db` после остановки daemon. Перед удалением проверка
повторяется; кратковременная блокировка файла ожидается до 10 секунд.
После обновления переподключите code-index или перезапустите Codex.
Затем скрипт проверяет последний опубликованный
release `Regsorm/code-index-mcp` (включая prerelease). Если нужной версии нет ни в
установленном runtime, ни в `runtime\windows`, скачивает Windows x64 artifact,
проверяет размер, SHA-256 и upstream digest при наличии, распаковку и версию executable.

Как установщик, скрипт удаляет все `.code-index` у Kafka-путей из
`code-index\daemon.toml.template`, запускает daemon и ждёт `ready` для **всех**
путей общего `daemon.toml`, включая другие workspace. Их индексы не удаляются.
Затем проверяет MCP `initialize`/`tools/list` и повторно подтверждает готовность
каждого пути. Конфигурация, BSL LS, skills и другие компоненты не обновляются.

Вывод содержит шесть нумерованных этапов, версии и пути, результаты удаления,
статусы всех aliases, прогресс ожидания не реже раза в 15 секунд между опросами,
`[OK]`, `[WARNING]`, `[ERROR]`, `[ROLLBACK]` и итоговый `RESULT`.
При ошибке возвращается ненулевой код; скрипт пытается восстановить прежний
managed executable и ранее работавший daemon. Удалённые индексы не восстанавливаются
из резервной копии: daemon должен построить их заново; готовность после rollback
не считается подтверждённой.

Поддерживаются `-WorkspaceRoot`, `-CodexHome`, `-NodePath`,
`-IndexReadyTimeoutSeconds` (по умолчанию 1800) и `-McpReadyTimeoutSeconds`
(по умолчанию 600). Для обновления из локального файла без GitHub-запросов:

```bat
.\tools\ai\update-code-index.cmd -BslIndexerPath D:\distribution\bsl-indexer.exe
```

Для запуска без заключительной паузы задайте `KAFKA_AI_NO_PAUSE=1`.

## Маршрутизация

| Контур | EDT-MCP | Code-index aliases | BSL LS |
| --- | --- | --- | --- |
| Adapter | `kfk-edt`, порт `8765` | `kfk`, `kfk-base`, `kfk-examples` | repository-local в `adapter/adapter` |
| Conversion | `conv-edt`, порт `8767` | `kfk-conv`, `kfk-conv-kd` | только когда явно настроен владельцем репозитория |
| Unit | `unit-edt`, порт `8768` | `kfk-unit`, `kfk-yaxunit`; переиспользует adapter aliases | только когда явно настроен владельцем репозитория |

Общий `code-index` daemon хранится в `%CODEX_HOME%\code-index`. Установщик сохраняет
зарегистрированные aliases других workspace и заменяет только Kafka-owned entries.
Для любых новых или изменённых BSL обязательны общие стандарты и дополнительная
рабочая политика из `v8std` по стабильным ID `corporate:work:*`.

В текущей установленной схеме контекст загружается по этапам: routing → нужный
skill → `1c-code-change/references/requirements.md` → применимые подразделы v8std.
Canonical thin skills в `.codex/skills` используют policy MCP с detector/selector
и compliance ledger. Installer доставляет их и read-only custom agent
`.codex/agents/kafka-reviewer.toml`; отдельного staged layout больше нет.
Установка новой конфигурации не доказывает live-приёмку SPEC-0012.
Селектор используется до выбора решения: через `1c-standards` для дизайна и
нормативного анализа, через `1c-code-change` для изменений. Учитываются тип
артефакта, операция и фактические механизмы; чистому поиску нормы не нужны.
Перед записью проверяется применение требований, включая окружающую структуру,
и догружается только разница; после записи используется тот же набор. Полные правила не
копируются в skills. Подразделы выбираются через `v8std_get_section`, полные
короткие документы — через `v8std_get_summary` только без усечения.
Обзор модели загрузки и границы ревью: `<V8STD_ROOT>/docs/corporate/work/README.md`.
Изменения в этом репозитории не обновляют уже скопированные пользовательские
skills до отдельного запуска установщика; он здесь автоматически не запускается.

## Проверка

Статические regression-тесты:

```powershell
Get-ChildItem -LiteralPath .\tools\ai\tests -Filter 'test-*.ps1' |
  ForEach-Object { & $_.FullName }
```

Общий набор состоит из `test-project.ps1`, `test-installation.ps1` и
`test-code-index.ps1`. Repository-local компоненты могут иметь собственные компактные
проверки в репозитории-владельце.
`smoke-code-index-runtime.ps1` является отдельной live-проверкой.

Для SPEC-0012 из корня Kafka дополнительно запустите:

```powershell
$env:V8STD_REPO = '<путь к checkout v8std>'
node .\tools\ai\tests\test-policy.mjs
node .\tools\ai\tests\test-doctor.mjs
node .\tools\ai\tests\benchmark-context.mjs
```

`benchmark-context.mjs` измеряет только байты исходников/schema; фактические
Codex tool schemas и токены требуют live-проверки после установки.

Подробная архитектура, правила переноса и критерии готовности описаны в
[PORTING.md](PORTING.md); политика runtime — в [runtime/README.md](runtime/README.md).

## Доставка runtime declarations SPEC-0012

`install.cmd` устанавливает `kafka-policy` и `kafka-openviking` в существующий shared
managed MCP block, а reviewer — в `<CodexHome>/agents/kafka-reviewer.toml`.
Повторная установка не создаёт второй block; конфликтующие одноимённые MCP вне
managed block отклоняются по существующей политике installer. Repository-local
EDT и BSL LS остаются отдельными владельцами конфигурации.

`-OpenVikingStateDir <absolute-path>` задаёт developer-local disposable state.
По умолчанию используется `KAFKA_OPENVIKING_STATE_DIR`, а при отсутствии переменной
— `<CodexHome>/openviking`. Путь фиксируется в MCP args вместе с workspace root.
`update-openviking.cmd` берёт каталог из args установленного shared MCP
`kafka-openviking` через Codex CLI и проверяет совпадение workspace.
`KAFKA_OPENVIKING_STATE_DIR` позволяет явно переопределить каталог абсолютным путём;
при таком переопределении Codex CLI не требуется. Node command берётся из проверенного runtime normal
install либо из `-NodePath`/PATH при `-ConfigurationOnly`.

`-ConfigurationOnly` проверяет только доставку конфигурации и ресурсов: runtime,
provider, server, initial sync и hooks в этом режиме не устанавливаются. Обычный
повторный запуск всегда проверяет обновление и переиспользует runtime, если latest
уже установлен. Существующая provider-конфигурация не удаляется
и не перезаписывается; ошибка `doctor` требует её исправить и повторить установку.
Production cutover всё ещё требует отдельной live acceptance на целевой машине.

`test-installation.ps1` запускает `test-managed-mcp.mjs --config <installed-config>`:
реальные installed stdio servers проверяются из постороннего cwd через initialize
и tools/list. Проверяются точные allowlists и read-only reviewer. Backend queries,
Codex custom-agent discovery и runtime authority readiness проверяются отдельно.
