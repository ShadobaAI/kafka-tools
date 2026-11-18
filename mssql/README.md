# MS SQL Server — локальный стенд

[← Все инструменты](../README.md)

> Каждый самостоятельный сценарий ниже начинается из корня репозитория `tools`; команды `cd` меняют каталог внутри сценария. Пути к файлам указаны относительно `tools`, если не оговорено иное.

MS SQL Server 2022 с кириллической сортировкой (`Cyrillic_General_CI_AS`) и русской локалью.

## Запуск

### Отдельный контейнер

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

### Compose и SQL MCP Server

[compose.yaml](compose.yaml) запускает отдельный SQL Server 2022 и [SQL MCP Server от Microsoft](https://learn.microsoft.com/en-us/sql/mcp/) на базе Data API builder. Сортировка, локаль и каталог резервных копий совпадают с настройками скрипта; SQL Server по умолчанию доступен на порту `1433`. Данные нового экземпляра сохраняются в отдельном Docker-томе `mssql-data` проекта Compose.

Compose запускает контейнер `mssql-mcp` со своим томом. Если старый экземпляр занимает порт `1433`, остановите его командой `docker stop mssql`. Данные останутся в старом контейнере; при необходимости их нужно перенести отдельно через резервную копию.

Пароль `sa` из `docker_run_mssql.ps1` уже указан в Compose-файле для SQL Server, инициализации и строки подключения MCP. Запуск из корня `tools` в PowerShell:

```powershell
docker compose -f mssql/compose.yaml up -d
```

Эта команда запускает только SQL Server. Политика `unless-stopped` автоматически запускает его вместе с Docker после перезагрузки, если контейнер не был остановлен вручную.

Чтобы запустить MCP по запросу:

```powershell
docker compose -f mssql/compose.yaml --profile mcp up -d
```

SQL Server сначала проходит проверку готовности; затем служба инициализации создаёт две процедуры в `master`, после чего запускается MCP. Контейнеры называются `mssql-mssql-mcp-init` и `mssql-mssql-mcp`. Чтобы остановить только MCP, выполните:

```powershell
docker compose -f mssql/compose.yaml --profile mcp stop mssql-mcp
```

Пароль задаётся при создании базы и хранится в её томе. При изменении пароля в Compose-файле его нужно согласовать во всех трёх настройках; изменение значения в файле не меняет пароль уже созданной базы.

Адрес MCP для клиента с транспортом Streamable HTTP: `http://127.0.0.1:5000/mcp`. Порт MCP можно изменить переменной `MCP_PORT`. Сервер работает без проверки пользователя и выполняет операции от имени `sa`; он слушает только `127.0.0.1`.

Стандартный SQL MCP Server предоставляет операции с заранее описанными сущностями. Для произвольных команд в этом стенде зарегистрированы процедуры `ExecuteSql` и `QuerySql`, доступные через `execute_entity` и как отдельные MCP-инструменты:

- `ExecuteSql`: параметр `sql` содержит пакет T-SQL без `GO` и без результирующего набора, включая DDL и DML. Параметр `database` выбирает базу; по умолчанию используется `master`.
- `QuerySql`: параметр `sql` содержит один `SELECT`, а `database` выбирает базу. Результат возвращается в поле `result` как JSON. Запрос не должен содержать `GO` или собственный `FOR JSON`; вычисляемым столбцам нужно давать имена. Команды с несколькими результирующими наборами этот интерфейс не возвращает.

Например, аргументы вызова `execute_entity` для списка баз:

```json
{
  "entity": "QuerySql",
  "parameters": {
    "database": "master",
    "sql": "SELECT name FROM sys.databases"
  }
}
```

Сущности SQL MCP Server описаны в [dab-config.json](config/dab-config.json). При повторной инициализации стенда процедуры `dbo.mcp_execute_sql` и `dbo.mcp_query_sql` в `master` обновляются из [mcp-init.sql](config/mcp-init.sql).

## Диагностика SQL

- [Очистка кеша и статистики](sql/clear-cache-and-statistics.sql) — сброс кешей экземпляра и удаление неиндексной статистики выбранной базы.
- [Статистика индексов](sql/index-statistics.sql) — анализ индексов и их фрагментации для выбранной таблицы.
- [Сбор Extended Events](sql/capture-extended-events.sql) — настройка сессии `kfk` с записью в `.xel`. Команда запуска сессии находится в конце файла.

## Импорт Extended Events в Elasticsearch

Для импорта нужны Windows, 64-разрядный Python 3.11 или новее и установленная SQL Server Management Studio (SSMS). Скрипт читает `.xel` напрямую с диска через библиотеку SSMS. Установите пакет Python.NET один раз. [Документация Python.NET](https://pythonnet.github.io/pythonnet/python.html)

```powershell
python -m pip install "pythonnet>=3.1,<4"
```

Скрипт [import-xel-to-elasticsearch.py](import-xel-to-elasticsearch.py) обрабатывает `.xel`, записанные сессией Extended Events. `--help` показывает справку на русском. `--dry-run` разбирает файлы и формирует пакеты локально, без запросов к Elasticsearch.

```powershell
python .\mssql\import-xel-to-elasticsearch.py --help
python .\mssql\import-xel-to-elasticsearch.py --dry-run
```

Для загрузки используйте команду без `--dry-run`. По умолчанию скрипт читает все `.xel` из `C:\docker-backups\mssql` и его подкаталогов и отправляет события на `http://localhost:9200`. [Инструкция по запуску Elasticsearch](../elk/README.md)

```powershell
python .\mssql\import-xel-to-elasticsearch.py
```

Каждое событие сохраняется отдельным документом в индексе `mssql-xel`. `@timestamp` содержит время в UTC, `event_name` — имя события, `file_name` — путь относительно каталога импорта. Поля события доступны в `data.*`, действия сессии — в `actions.*`, а числовые коды перечислений — в `map_keys.*`. Если поле индексируется как число, скрипт подставляет в него код перечисления и сохраняет подпись в `map_labels.*`. Например, состояние `Recompiled` представлено числом в `data.state` и строкой в `map_labels.data.state`. Поля `data.duration`, `data.cpu_time` и счётчики чтения индексируются как числа в исходных единицах. По `actions.sql_text`, `data.statement` и `data.batch_text` доступен полнотекстовый поиск.

Перед первым пакетом скрипт проверяет маппинг целевого индекса и при несовместимости останавливается до записи документов. Он создаёт индекс, если тот отсутствует, и проверяет получившийся маппинг. Если Elasticsearch отклонит документ, скрипт выведет имя файла, номер события и HTTP-статус. [API чтения маппинга](https://www.elastic.co/docs/api/doc/elasticsearch/v9/operation/operation-indices-get-mapping), [Bulk API Elasticsearch](https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-bulk)

В новом индексе `_id` учитывает источник. По умолчанию источник определяется по имени компьютера и полному пути каталога. Если файлы будут переноситься, задайте постоянное имя через `--source-id` при первой загрузке и используйте его при повторах. Одно имя соответствует одному источнику, а пути файлов внутри каталога сохраняются.

Для уже загруженных файлов из стандартного каталога `C:\docker-backups\mssql` в `mssql-xel` на `http://localhost:9200` скрипт автоматически сохраняет прежние `_id`. С другими настройками укажите `--legacy-ids` при повторной загрузке того же источника в старый индекс или `--source-id` при добавлении нового источника.

Другой источник, адрес REST API или индекс можно указать параметрами `--log-dir`, `--url` и `--index`. Для нестандартной установки SSMS передайте полный путь к `Microsoft.SqlServer.XEvent.Linq.dll` через `--ssms-dll`. В Kibana Discover используйте индекс `mssql-xel` и поле времени `@timestamp`.
