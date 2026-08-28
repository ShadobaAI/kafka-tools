# Runtime-артефакты

`setup.ps1` сам получает runtime с GitHub:

- последний опубликованный GitHub release `Regsorm/code-index-mcp` (включая
  prerelease), asset `bsl-indexer-windows-x64.zip`;
- последний стабильный (не draft и не prerelease) release
  `1c-syntax/bsl-language-server`, asset
  `bsl-language-server-*-exec.jar`.

Запуск из корня workspace `Kafka`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1
```

При каждом запуске версия определяется через GitHub Releases API. Runtime сначала
скачивается и проверяется во временном staging: размер, SHA-256, upstream digest
при наличии, ZIP и версия executable JAR. Только после этого setup изменяет
persistent configuration.

Для закрытого контура можно отключить сеть, передав оба проверенных файла явно:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\ai\setup.ps1 `
  -BslIndexerPath D:\distribution\bsl-indexer.exe `
  -BslLanguageServerJar D:\distribution\bsl-language-server-exec.jar
```

Каталог `runtime/windows` намеренно не хранит third-party бинарники.
