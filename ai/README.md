# Codex toolkit для Kafka Adapter

Каталог `tools/ai` содержит общую AI-инфраструктуру фиксированного Kafka workspace:
установщик, `code-index`, общие 1С-skills, routing guard и regression-тесты.
EDT и BSL LS остаются repository-local и настраиваются в репозиториях-владельцах.

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

После успешной установки перезапустите Codex и откройте нужный repository root.

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
