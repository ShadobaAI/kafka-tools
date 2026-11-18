----------------------------------------------------------
-- НАСТРОЙКА: укажи имя базы, где чистим статистику
----------------------------------------------------------
DECLARE @DbName sysname = N'kafka';
----------------------------------------------------------

----------------------------------------------------------
-- 1. Полная очистка кэшей (весь инстанс!)
----------------------------------------------------------
DBCC FREEPROCCACHE;                                           -- планы запросов
DBCC DROPCLEANBUFFERS;                                       -- буферный кэш (страницы данных)
DBCC FREESYSTEMCACHE('ALL') WITH MARK_IN_USE_FOR_REMOVAL;    -- системный кэш
DBCC FREESESSIONCACHE;                                       -- кэш сессий
PRINT 'Кэши очищены.';

----------------------------------------------------------
-- 2. Удаление всей НЕИНДЕКСНОЙ статистики в базе @DbName
--    (включая все _WA_Sys_ и пользовательские CREATE STATISTICS)
----------------------------------------------------------
DECLARE @sql nvarchar(MAX) = N'';

SET @sql = N'USE ' + QUOTENAME(@DbName) + N';
DECLARE @drop nvarchar(MAX) = N''''; 

SELECT @drop = @drop +
    N''DROP STATISTICS '' 
    + QUOTENAME(sch.[name]) + N''.'' 
    + QUOTENAME(tbl.[name]) + N''.'' 
    + QUOTENAME(st.[name]) + N'';'' + CHAR(10)
FROM sys.stats st
JOIN sys.tables tbl      ON st.object_id = tbl.object_id
JOIN sys.schemas sch     ON tbl.schema_id = sch.schema_id
LEFT JOIN sys.indexes ix ON ix.object_id = st.object_id 
                        AND ix.index_id = st.stats_id    -- индексная статистика
WHERE ix.index_id IS NULL;                                -- оставляем только неиндексную

IF LEN(@drop) > 0
BEGIN
    PRINT ''Будет удалена следующая статистика:'';
    PRINT @drop;
    EXEC sp_executesql @drop;
END
ELSE
BEGIN
    PRINT ''Не найдена неиндексная статистика для удаления.'';
END
';

PRINT 'Генерируем и выполняем скрипт удаления статистики для базы ' + QUOTENAME(@DbName);
EXEC (@sql);

PRINT 'Готово: кэш очищен, неиндексная статистика в базе ' + QUOTENAME(@DbName) + ' удалена.';
