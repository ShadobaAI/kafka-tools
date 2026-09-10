# Codex toolkit для Kafka Adapter

Каталог `tools/ai` содержит общую AI-инфраструктуру фиксированного Kafka workspace:
установщик, `code-index`, общие 1С-skills, routing guard и regression-тесты.
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

Установщик проверяет полную структуру Kafka, Node.js 18+ и Java. Явный `-NodePath`
имеет высший приоритет; иначе сначала используется `%ProgramFiles%\nodejs\node.exe`,
и только затем первый `node` из `PATH`. Node.js здесь нужен
для локальных JavaScript proxy `code-index` и BSL LS; к Kafka broker он отношения не
имеет. Явно переданные runtime-пути используются без сетевого поиска. Иначе
установщик сравнивает версии `bsl-indexer` и BSL Language Server из
`runtime\windows` с canonical GitHub releases и загружает проверенный artifact,
только если локальный компонент отсутствует или отличается от опубликованного.

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

Контекст загружается по этапам: routing → нужный skill → общий селектор
`1c-code-change/references/requirements.md` → применимые подразделы v8std.
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

Подробная архитектура, правила переноса и критерии готовности описаны в
`PORTING.md`; политика runtime — в `runtime/README.md`.
