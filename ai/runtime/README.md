# Runtime-артефакты

`setup.ps1` сначала использует runtime из `runtime/windows`, если там находятся
`bsl-indexer.exe` и один `bsl-language-server-*-exec.jar`. Недостающие компоненты
он получает с GitHub:

- последний опубликованный GitHub release `Regsorm/code-index-mcp` (включая
  prerelease), asset `bsl-indexer-windows-x64.zip`;
- последний стабильный (не draft и не prerelease) release
  `1c-syntax/bsl-language-server`, asset
  `bsl-language-server-*-exec.jar`.

Запуск из корня workspace `Kafka`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1
```

Для bundled runtime обращения к GitHub не выполняются. После сетевой загрузки
скрипт проверяет размер, SHA-256, upstream digest при наличии, ZIP и версию
executable JAR, сохраняет проверенные файлы в `runtime/windows`, затем изменяет
persistent configuration. Следующая установка использует локальные файлы.

Для закрытого контура можно отключить сеть, передав оба проверенных файла явно:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1 `
  -BslIndexerPath D:\distribution\bsl-indexer.exe `
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

Явно переданные пути имеют приоритет над файлами в `runtime/windows`; GitHub
используется только как fallback для отсутствующих компонентов.
