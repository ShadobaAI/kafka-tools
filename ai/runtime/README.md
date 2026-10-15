# Runtime-артефакты

## Vanessa Automation Single

Встроенная обработка запускается по `runtime.navigationUrl` из профиля и не
требует внешней EPF. Для внешнего runtime подготовьте закреплённый официальный
Single-релиз с проверкой SHA-256 архива и EPF:

```powershell
powershell -NoProfile -File tools/ai/runtime/prepare-vanessa.ps1
```

Команда принимает `-ArchivePath <zip>` для установки из локального архива без сети
и `-Destination <directory>` для явного каталога. Версия и контрольные суммы
находятся в `vanessa-release.json`; лицензия поставляется в `vanessa-LICENSE`.
Каталог `windows/vanessa/<version>` — локальный runtime cache, исключённый из Git.
Укажите полученные `epf` и `manifest` в `runtime` профиля. Существующая EPF
проверяется и повторно не скачивается; несовпадение хеша останавливает подготовку.
Команда не запускает 1С и не устанавливает расширения. Ежедневная работа использует
готовый runtime или обработку базы и не обращается к upstream checkout.

Проверка повторной подготовки без загрузки после первой установки:

```powershell
powershell -NoProfile -File tools/ai/runtime/prepare-vanessa.ps1
```

## Общие анализаторы

Если runtime не передан явно, `install.cmd` определяет локальные версии в
`runtime/windows`, получает сведения о canonical GitHub releases и сравнивает их.
Отсутствующие или отличающиеся по версии компоненты он получает с GitHub:

- последний опубликованный GitHub release `Regsorm/code-index-mcp` (включая
  prerelease), asset `bsl-indexer-windows-x64.zip`;
- последний стабильный (не draft и не prerelease) release
  `1c-syntax/bsl-language-server`, asset
  `bsl-language-server-*-exec.jar`.

Запуск из корня workspace `Kafka`:

```bat
.\tools\ai\install.cmd
```

Актуальный bundled runtime повторно не загружается. После сетевой загрузки скрипт
проверяет размер, SHA-256, upstream digest при наличии, ZIP и версию executable/JAR,
сохраняет проверенные файлы в `runtime/windows`, затем изменяет persistent
configuration.

Для закрытого контура можно отключить сеть, передав оба проверенных файла явно:

```bat
.\tools\ai\install.cmd ^
  -BslIndexerPath D:\distribution\bsl-indexer.exe ^
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

Явно переданные пути имеют приоритет над файлами в `runtime/windows`; для них
GitHub-запрос и автоматическая замена не выполняются.
