# Перенос подхода EDT-MCP + code-index + BSL LS + v8std на другой проект

## 1. Назначение

Этот документ описывает не копирование Kafka-конфигурации как есть, а воспроизводимый
подход к оснащению другого workspace с проектами 1С. Итоговая система должна давать
агенту четыре независимых источника возможностей с явными границами ответственности:

1. **EDT-MCP** — актуальная модель EDT, исходный код и метаданные, platform-aware
   навигация, диагностика и все изменения проекта 1С.
2. **code-index** — быстрый read-only поиск по нескольким репозиториям, структура
   метаданных, графы, связи и предварительный impact analysis.
3. **BSL Language Server** — точная семантическая навигация и сфокусированная
   диагностика BSL внутри конкретного репозитория.
4. **v8std** — стандарты разработки, политики, диагностические правила и подбор
   требований для фрагментов кода.

EDT остаётся источником истины. Остальные компоненты ускоряют исследование или дают
специализированные сведения, но не заменяют EDT при окончательной проверке состояния
проекта и не получают право изменять модель 1С.

## 2. Основная идея архитектуры

Подход строится на разделении общей инфраструктуры workspace и конфигурации конкретного
репозитория.

### Общий слой workspace

Общий versioned toolkit хранит:

- managed-фрагмент пользовательской конфигурации Codex;
- общие skills маршрутизации;
- read-only proxy и launcher для code-index;
- управление единым Windows daemon `bsl-indexer`;
- hook, запрещающий обход правил доступа к проектам 1С;
- декларативный список репозиториев и aliases индекса;
- единый идемпотентный `setup.ps1`;
- regression-тесты установки и lifecycle.

Этот слой устанавливает общие MCP и skills в `%CODEX_HOME%`, потому что Codex не обязан
загружать `.codex` из соседнего инфраструктурного репозитория. При этом versioned toolkit
остаётся источником конфигурации, а пользовательский `config.toml` — установленным
экземпляром. Такое разделение соответствует штатным механизмам config, `AGENTS.md`, MCP,
skills и hooks, описанным в [официальной документации Codex](https://learn.chatgpt.com/docs/config-file/config-basic).

### Repository-local слой

Каждый рабочий репозиторий владеет только своей конфигурацией:

- назначенным EDT-MCP;
- optional BSL LS, если в репозитории есть его analyzer configuration;
- optional SonarQube или другими project-specific MCP;
- локальным `AGENTS.md` с границами проекта и командами проверки;
- risk policy для опасных инструментов EDT.

Repository-local конфигурация не должна ссылаться на соседний проект и не должна
содержать абсолютный путь машины разработчика. Для stdio MCP используются относительный
`cwd = "."`, repository-owned proxy и root текущего репозитория.

## 3. Почему компоненты не объединяются в один MCP

Компоненты отвечают на разные вопросы и имеют разные гарантии:

| Компонент | Основная роль | Что нельзя считать гарантией |
|---|---|---|
| EDT-MCP | Live-модель, mutation, diagnostics, platform docs | Не предназначен для дешёвого широкого federated-поиска |
| code-index | Discovery, metadata graph, call/data graph, impact | Индекс eventually consistent; статический граф не покрывает dynamic dispatch |
| BSL LS | Definition, references, hover, focused diagnostics | Не является federated project search и не знает всю metadata-модель EDT |
| v8std | Стандарты и policy corpus | Релевантное правило не доказывает наличие дефекта в конкретном контексте |

Правильный маршрут исследования:

```text
code-index: быстро сузить область
    → BSL LS: уточнить семантические ссылки при необходимости
        → EDT: подтвердить актуальный код, метаданные, API и диагностику
            → v8std: проверить применимые требования стандартов
```

Это не обязательная последовательность для каждого запроса. Маршрутизирующий skill
выбирает минимальный достаточный набор инструментов по типу задачи.

## 4. Рекомендуемая структура поставки

```text
<WORKSPACE_ROOT>/
├── AGENTS.md                         # устанавливается из общего toolkit
├── <repo-a>/
│   ├── AGENTS.md
│   └── .codex/
│       ├── config.toml               # EDT и optional BSL LS этого репозитория
│       ├── README.md
│       ├── mcp/
│       │   └── bsl-ls-proxy.mjs      # только если BSL LS нужен здесь
│       └── tests/
├── <repo-b>/
│   ├── AGENTS.md
│   └── .codex/config.toml
└── <tools-repo>/ai/
    ├── AGENTS.md
    ├── PORTING.md
    ├── setup.ps1                     # единая команда установки
    ├── workspace-policy.json
    ├── .codex/
    │   ├── config.toml               # managed user-level block
    │   └── skills/
    ├── code-index/
    │   └── daemon.toml.template
    ├── hooks/
    │   └── guard-1c-routing.ps1
    ├── mcp/
    │   ├── code-index-mcp.ps1
    │   ├── code-index-daemon.ps1
    │   └── code-index-proxy.mjs
    ├── runtime/windows/.gitignore
    └── tests/
```

Runtime-файлы являются неизменёнными сторонними артефактами. `setup.ps1` получает
последний опубликованный Windows x64 release `bsl-indexer`, включая prerelease,
и последний стабильный BSL LS release из canonical GitHub repositories. Файлы
проверяются во временном staging до persistent writes. Для закрытого контура
остаются явные offline-параметры.

## 5. Что требуется определить для нового workspace

До копирования toolkit нужно составить явный inventory:

| Данные | Пример placeholder |
|---|---|
| Корень workspace | `<WORKSPACE_ROOT>` |
| Список самостоятельных Git-репозиториев | `<REPOSITORY_ROOTS>` |
| Уникальный code-index alias каждого репозитория | `<REPOSITORY_ALIASES>` |
| Язык индексирования | обычно `bsl` |
| EDT-MCP, обслуживающий каждый проект | `<EDT_SERVER_BY_REPOSITORY>` |
| EDT projectName внутри workspace | `<EDT_PROJECT_NAMES>` |
| Репозитории с BSL LS configuration | `<BSL_LS_REPOSITORIES>` |
| Локальные или remote MCP endpoints | `<MCP_ENDPOINTS>` |
| Опасные EDT tools и approval policy | `<EDT_RISK_POLICY>` |
| Пути 1С source trees, запрещённые для filesystem tools | `<PROTECTED_1C_PATHS>` |
| Документированные команды тестов | `<TEST_COMMANDS_BY_REPOSITORY>` |

Aliases должны быть стабильными и уникальными. Нельзя строить routing по basename,
случайному текущему каталогу или неявному соседству репозиториев.

## 6. Порядок адаптации

### Шаг 1. Зафиксировать границы репозиториев

Для каждого репозитория определить:

- canonical относительный путь от workspace root;
- наличие собственного `.git`;
- локальный `AGENTS.md` или README с инженерными командами;
- EDT-проект и назначенный EDT-MCP;
- наличие `.bsl-language-server.json`;
- допустимые read-only и write operations.

Workspace root не следует считать Git-репозиторием, если он является только каталогом,
объединяющим несколько независимых checkout.

### Шаг 2. Настроить federated code-index

В `code-index/daemon.toml.template` заменить список `[[paths]]`:

```toml
[daemon]
http_port = 0
max_concurrent_initial = 1

[[paths]]
alias = "<repo-alias>"
path = "__WORKSPACE_ROOT_FORWARD__/<relative/repository/path>"
language = "bsl"
```

Тот же список aliases должен использоваться в skills, `AGENTS.md`, policy и тестах.
Installer подставляет фактический workspace root и обновляет общий
`%CODEX_HOME%\code-index\daemon.toml`: заменяет только aliases текущего workspace,
сохраняет остальные `[[paths]]` и существующие настройки `[daemon]`. Один
`CODE_INDEX_HOME` и daemon обслуживают все зарегистрированные workspace.

Не следует экспортировать через MCP команды мутации индекса или daemon. MCP surface
ограничивается чтением; daemon пишет только coordination/runtime в `CODE_INDEX_HOME` и
собственные `.code-index/` каталоги настроенных репозиториев.

### Шаг 3. Настроить repository-local EDT

В `.codex/config.toml` каждого репозитория задаётся только назначенный ему EDT endpoint.
Необходимо:

- отключить raw `git` и `ask_workmate`, если они обходят управляемый workflow;
- оставить destructive metadata/project/database operations под explicit approval;
- не хранить credentials в TOML;
- не использовать EDT другого workspace как fallback;
- для version-sensitive semantics обращаться к tool guide, а не угадывать параметры.

Если один EDT-MCP обслуживает несколько связанных проектов, это фиксируется явно в
workspace policy. Само соседство каталогов не является достаточным основанием.

### Шаг 4. Добавить BSL LS только там, где он нужен

BSL LS подключается repository-local и только при наличии валидной analyzer
configuration. Переносимая секция выглядит концептуально так:

```toml
[mcp_servers.bsl-ls]
command = "node"
args = [".codex\\mcp\\bsl-ls-proxy.mjs", "--root", "."]
cwd = "."
enabled = true
required = false
```

Proxy должен:

- жёстко фиксировать repository root;
- отклонять file paths вне root;
- находить JAR через явный параметр, environment или managed `%CODEX_HOME%\bsl-ls`;
- корректно завершать Java child при закрытии MCP client;
- не скрывать несовместимость Unicode paths на Windows.

Если BSL LS не поддерживает не-ASCII Windows path, временный proxy может использовать
реальный 8.3 short path и восстанавливать исходные пути в ответах. Если short names на
томе отключены, запрос должен завершаться явной compatibility error, а не молча работать
с копией файла или другим checkout.

### Шаг 5. Настроить v8std

Общий MCP сохраняет имя `v8std`. Default endpoint может быть публичным или локальным,
но endpoint выбирает пользователь/организация, а installer сохраняет уже настроенный
`mcp_servers.v8std.url` при повторном запуске.

Перед внедрением организация должна отдельно принять решение о допустимости передачи
фрагментов кода remote endpoint. Agent-side скрытое переключение endpoint или
эвристическая классификация кода не добавляются.

### Шаг 6. Адаптировать routing skills

Минимальный набор skills:

- `1c-routing` — выбирает источник по типу задачи;
- `1c-code-change` — проводит все изменения через EDT с последующей диагностикой;
- `1c-code-index` — задаёт binding alias, freshness и ограничения read-only индекса;
- `bsl-ls-mcp` — ограничивает BSL LS focused diagnostics/navigation;
- `1c-platform-docs` — направляет platform API questions в live EDT documentation;
- `1c-standards` — направляет standards/policy questions в v8std;
- `yaxunit-tests` — создаёт, изменяет, ищет, проверяет и запускает модульные тесты
  YAxUnit через назначенный EDT и индекс ядра.

Skill `1c-routing` должен загружаться только для работы с конкретным проектом 1С или
общего вопроса про 1С. Наличие 1С-исходников в workspace само по себе не должно включать
этот routing для задач Git, документации, CI или обычного tooling.

### Шаг 7. Адаптировать guard policy

`workspace-policy.json` содержит только относительные canonical roots. Hook должен
запрещать:

- прямой filesystem/shell-доступ к сериализованным 1С source trees;
- write-инструменты code-index и BSL LS;
- опасные EDT tools, отключённые policy;
- обращение к alias вне разрешённого workspace.

Guard — дополнительный enforcement, а не источник бизнес-логики. Он не должен изменять
файлы, выполнять диагностику или автоматически выбирать другой проект при ошибке.

### Шаг 8. Настроить установку

`setup.ps1` должен выполнять один воспроизводимый workflow:

1. вычислить workspace root относительно собственного расположения либо принять
   `-WorkspaceRoot`;
2. проверить наличие всех обязательных repository roots;
3. проверить Node.js и Java;
4. принять явно переданный runtime, иначе использовать bundled runtime из
   `runtime/windows`, а для отсутствующих там компонентов определить latest releases
   через GitHub API;
5. скачать assets во временный staging, проверить size, SHA-256, upstream digest,
   ZIP и версию executable JAR, не изменяя persistent configuration;
6. проверить минимальную версию `bsl-indexer`;
7. сделать backup и идемпотентно установить managed config, skills, Kafka guard,
   aliases и MCP launchers;
8. проверить общий daemon в `CODE_INDEX_HOME`; если он запущен, остановить его
   и дождаться завершения PID до замены executable;
9. сделать backup и установить runtime под стабильными managed-именами;
10. запустить daemon и подтвердить реальный `GET /health` с совпадающим PID;
11. при ошибке замены runtime или запуска восстановить прежние runtime/daemon
   config и перезапустить прежний daemon;
12. сообщить о необходимости перезапуска Codex.

Daemon health не равен readiness индексов. На чистой установке configured paths появляются
в daemon health после подключения `bsl-indexer serve`, то есть после запуска MCP в Codex.
Итоговая operational-проверка выполняется через `code-index.health`: daemon должен быть
`online/healthy`, endpoint — подтверждён, каждый ожидаемый alias — `ready`.

### Шаг 9. Обеспечить идемпотентность

Повторный запуск не должен:

- дублировать TOML tables;
- сбрасывать пользовательский v8std URL;
- удалять посторонние skills;
- перезаписывать credentials;
- удалять или изменять code-index aliases других workspace;
- сбрасывать существующие настройки `[daemon]`;
- менять runtime, если SHA-256 совпадает;
- оставлять daemon на старом config;
- создавать конкурирующий daemon поверх live/unhealthy процесса.

Общий MCP block и workspace-specific guard block в пользовательском `config.toml`
имеют разные BEGIN/END markers.
Посторонняя конфигурация сохраняется; конфликтующие `v8std` и `code-index` tables
заменяются только с явным параметром и backup.

## 7. Команда установки для команды

После подготовки полной структуры workspace:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\<tools-repo>\ai\setup.ps1
```

Если `runtime/windows` содержит `bsl-indexer.exe` и один файл
`bsl-language-server-*-exec.jar`, setup автоматически использует их без обращения к
GitHub. Явные пути имеют приоритет над bundled runtime:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\<tools-repo>\ai\setup.ps1 `
  -BslIndexerPath D:\distribution\bsl-indexer.exe `
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

После успешной установки пользователь перезапускает Codex и открывает нужный репозиторий
как project root, чтобы загрузилась его repository-local конфигурация.

## 8. Обязательная проверка переноса

### Статические regression-тесты

Новый workspace должен иметь автоматические тесты как минимум на:

- PowerShell parse всех installer/launcher scripts;
- отсутствие machine-specific absolute paths в repository config;
- portable install в произвольном временном каталоге;
- повторную идемпотентную установку;
- backup перед заменой конфликтующей managed-конфигурации;
- сохранение пользовательского v8std URL;
- routing guard на разрешённых и запрещённых путях/tools;
- проверку Node.js и минимальной версии `bsl-indexer`;
- read-only MCP allowlist;
- daemon stale runtime, unhealthy live process и serialized startup;
- ожидание фактического завершения PID после `daemon stop`;
- завершение BSL LS proxy после закрытия client stdin;
- отклонение BSL LS file path вне repository root.

### Live smoke

На реальных, но неизменённых runtime-артефактах в изолированном временном workspace:

1. выполнить полный `setup.ps1`;
2. проверить установленные managed-файлы;
3. подтвердить daemon `GET /health` и PID;
4. остановить daemon штатным launcher;
5. убедиться, что процесс завершён и SQLite/runtime-файлы больше не удерживаются;
6. после запуска Codex проверить `code-index.health` и readiness всех aliases;
7. выполнить по одному реальному запросу discovery, source retrieval, impact analysis и
   BSL LS navigation;
8. подтвердить существенные результаты через назначенный EDT-MCP.

Live smoke не должен изменять проект 1С.

## 9. Критерии готовности

Перенос завершён, если одновременно выполняются условия:

- установка новой машины требует одной команды после раскладки workspace;
- конфигурация не содержит путей конкретного разработчика;
- каждый репозиторий использует только свой EDT-MCP;
- code-index видит aliases текущего workspace и сохраняет утверждённые aliases других workspace;
- `code-index.health` подтверждает daemon endpoint и readiness каждого path;
- BSL LS не может читать файл вне repository root;
- все изменения 1С технически возможны только через EDT-MCP;
- diagnostics EDT не скрываются и не подменяются BSL LS;
- пользовательские secrets и unrelated Codex config сохраняются;
- повторная установка идемпотентна;
- обновление runtime не оставляет старый daemon или заблокированные файлы;
- все static regressions и live smoke проходят.

## 10. Что нельзя копировать из Kafka механически

Перед использованием в другом проекте обязательно заменить или удалить:

- пути `adapter/adapter`, `adapter/base`, `adapter/examples`, `conversion/KFK`, `conversion/КД`,
  `tests/unit/base`, `tests/unit/examples`, `tests/unit/unit`, `tests/unit/yaxunit`;
- управляемые aliases `kfk*`;
- имена EDT-MCP `kfk-edt`, `conv-edt`, `unit-edt`;
- EDT project names и описания project scope;
- SonarQube URL и наличие самого SonarQube MCP;
- список protected source roots;
- repository-specific команды тестов;
- правила нескольких Git-репозиториев;
- локальные ports и service ownership, включая раздельные порты трёх EDT-MCP;
- business-specific standards или corporate policy.

Нужно сохранить сам принцип: общий управляемый read-only/search слой, локальный authoritative
EDT слой, optional semantic BSL LS, отдельный standards corpus, явная маршрутизация,
enforcement hook и одна проверяемая команда установки.

## 11. Существенные ограничения

- `code-index` eventually consistent и не доказывает отсутствие вызова или ссылки.
- Статические call graphs не покрывают строковый вызов, reflection и произвольный dynamic
  dispatch; object method resolution также может быть неполным.
- `get_register_writers` может отражать только декларативные metadata relations, если
  программная запись не моделируется индексом.
- BSL LS не заменяет metadata model, platform documentation и диагностику EDT.
- Windows Unicode workaround зависит от доступности 8.3 short paths до появления
  upstream-поддержки Unicode.
- Remote v8std может получать переданные ему фрагменты; это отдельное организационное
  решение владельца endpoint.
- Runtime берётся только из canonical GitHub repositories или из явно переданных
  владельцем offline-артефактов.
- `daemon online` подтверждает процесс и HTTP API, но readiness aliases подтверждается
  только после запуска MCP через `code-index.health`.

Эти ограничения должны быть отражены в `AGENTS.md` и skills нового workspace, чтобы агент
не превращал вспомогательный источник в источник истины.
