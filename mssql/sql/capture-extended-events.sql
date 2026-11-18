/*
Создание серверной сессии Extended Events [kfk]

Сессия собирает события для диагностики медленных и ресурсоёмких запросов,
ошибок и прерываний. Все события фильтруются по sqlserver.database_id.
ID базы определяется по @DatabaseName при создании сессии. По умолчанию база kafka.
Поля событий приведены для SQL Server 2022.

sqlserver.rpc_completed и sqlserver.sql_batch_completed
    Фиксируют завершение вызова RPC или пакета T-SQL при любом из условий.
    - duration >= 500000 мкс (500 мс)
    - cpu_time >= 200000 мкс (200 мс)
    - logical_reads >= 50000 логических чтений страниц
    - result = 1 (Error) или result = 2 (Abort)

    Общие поля событий — duration, cpu_time, logical_reads, physical_reads,
    page_server_reads, writes, row_count, result.
    rpc_completed содержит object_name и текст statement (collect_statement = 1).
    connection_reset_option заполняется для RPC сброса соединения.
    sql_batch_completed содержит spills и текст batch_text (collect_batch_text = 1).

sqlserver.error_reported
    Ошибки с severity >= 16 или error_number = 1205 (жертва взаимоблокировки).
    Поля события — error_number, severity, state, message, user_defined,
    category, destination, is_intercepted.

sqlserver.attention
    Отмена запроса, включая отмену по тайм-ауту клиента, или разрыв соединения.
    Поля события — duration (мкс) и request_id. Применяется общий фильтр по базе.

Действия (ACTION)
    Для всех событий — client_app_name, client_hostname, database_id,
    session_id и sql_text. Для RPC и пакетов T-SQL добавляется query_hash.

Запись и запуск
    package0.event_file пишет серию .xel с базовым именем @EventFileBasePath.
    Ротация по размеру 128 МБ на файл. Лимит серии — 512 файлов (около 64 ГиБ).
    При ротации старые файлы удаляются по мере достижения лимита.
    Память буферов — 4 МБ, задержка отправки — 30 с. При заполнении буферов
    допускается потеря отдельных событий (ALLOW_SINGLE_EVENT_LOSS).
    TRACK_CAUSALITY и автозапуск отключены. Команда ручного запуска в конце файла.
*/
USE [master];

DECLARE @DatabaseName sysname = N'kafka';
-- Базовое имя серии .xel в каталоге, доступном для записи службе SQL Server.
DECLARE @EventFileBasePath nvarchar(max) = N'/var/opt/mssql/backup/kfk.xel';

DECLARE @DatabaseId int = DB_ID(@DatabaseName);

IF @DatabaseId IS NULL
BEGIN
    THROW 50000, N'База из @DatabaseName отсутствует или недоступна.', 1;
END;

IF @EventFileBasePath IS NULL OR LOWER(RIGHT(@EventFileBasePath, 4)) <> N'.xel'
BEGIN
    THROW 50001, N'Укажите путь с расширением .xel в @EventFileBasePath.', 1;
END;

DECLARE @CreateSession nvarchar(max) = N'
CREATE EVENT SESSION [kfk] ON SERVER
ADD EVENT [sqlserver].[rpc_completed]
(
    SET collect_statement = (1)
    ACTION (
        [sqlserver].[client_app_name],
        [sqlserver].[client_hostname],
        [sqlserver].[database_id],
        [sqlserver].[query_hash],
        [sqlserver].[session_id],
        [sqlserver].[sql_text]
    )
    WHERE (
        [sqlserver].[database_id] = ({database_id})
        AND ([duration] >= (500000) OR [cpu_time] >= (200000)
            OR [logical_reads] >= (50000) OR [result] = (1) OR [result] = (2))
    )
),
ADD EVENT [sqlserver].[sql_batch_completed]
(
    SET collect_batch_text = (1)
    ACTION (
        [sqlserver].[client_app_name],
        [sqlserver].[client_hostname],
        [sqlserver].[database_id],
        [sqlserver].[query_hash],
        [sqlserver].[session_id],
        [sqlserver].[sql_text]
    )
    WHERE (
        [sqlserver].[database_id] = ({database_id})
        AND ([duration] >= (500000) OR [cpu_time] >= (200000)
            OR [logical_reads] >= (50000) OR [result] = (1) OR [result] = (2))
    )
),
ADD EVENT [sqlserver].[error_reported]
(
    ACTION (
        [sqlserver].[client_app_name],
        [sqlserver].[client_hostname],
        [sqlserver].[database_id],
        [sqlserver].[session_id],
        [sqlserver].[sql_text]
    )
    WHERE ([sqlserver].[database_id] = ({database_id})
        AND ([severity] >= (16) OR [error_number] = (1205)))
),
ADD EVENT [sqlserver].[attention]
(
    ACTION (
        [sqlserver].[client_app_name],
        [sqlserver].[client_hostname],
        [sqlserver].[database_id],
        [sqlserver].[session_id],
        [sqlserver].[sql_text]
    )
    WHERE ([sqlserver].[database_id] = ({database_id}))
)
ADD TARGET [package0].[event_file]
(
    SET filename = N''{event_file_base_path}'',
        max_file_size = (128),
        max_rollover_files = (512)
)
WITH (
    MAX_MEMORY = 4096 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    MAX_EVENT_SIZE = 0 KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = OFF,
    STARTUP_STATE = OFF
);';

SET @CreateSession = REPLACE(@CreateSession, N'{database_id}', CONVERT(nvarchar(11), @DatabaseId));
SET @CreateSession = REPLACE(
    @CreateSession,
    N'{event_file_base_path}',
    REPLACE(@EventFileBasePath, N'''', N''''''));

EXEC sys.sp_executesql @CreateSession;

-- Для запуска сбора выполните команду отдельно.
-- ALTER EVENT SESSION [kfk] ON SERVER STATE = START;
