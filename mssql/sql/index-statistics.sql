----------------------------------------------------------
-- НАСТРОЙКА: укажи имя таблицы и имя таблицы в 1С
----------------------------------------------------------
DECLARE @tableName   sysname = N'dbo._InfoRg685X1';
DECLARE @tableName1C sysname = N'ИмяТаблицы1С';
----------------------------------------------------------

----------------------------------------------------------
-- 1. Информация по индексам для указанной таблицы
----------------------------------------------------------
SELECT 
    ------------------------------------------------------
    -- Общая информация
    ------------------------------------------------------
    OBJECT_SCHEMA_NAME(i.object_id)          AS [Схема],
    OBJECT_NAME(i.object_id)                 AS [Таблица],
    @tableName1C                             AS [Таблица 1С],
    i.name                                   AS [Имя индекса],
    i.type_desc                              AS [Тип индекса],
    i.is_primary_key                         AS [Первичный ключ],
    i.is_unique                              AS [Уникальность],
    i.is_unique_constraint                   AS [Уник. ограничение],
    i.is_disabled                            AS [Отключён],
    i.filter_definition                      AS [Фильтр],

    ------------------------------------------------------
    -- Статистика использования
    ------------------------------------------------------
    ISNULL(ius.user_seeks, 0)                AS [Чтение (seek)],
    ISNULL(ius.user_scans, 0)                AS [Скан (scan)],
    ISNULL(ius.user_lookups, 0)              AS [Lookup],
    ISNULL(ius.user_updates, 0)              AS [Обновления],

    ------------------------------------------------------
    -- Размер индекса
    ------------------------------------------------------
    ps.row_count                             AS [Строк],
    ps.used_page_count                       AS [Исп. страниц],
    ps.reserved_page_count                   AS [Резерв страниц],
    (ps.reserved_page_count * 8) / 1024.0    AS [Размер MB],

    ------------------------------------------------------
    -- Полный список колонок индекса
    ------------------------------------------------------
    STUFF((
        SELECT ', ' 
             + COL_NAME(ic.object_id, ic.column_id)
             + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
             + CASE WHEN ic.is_included_column = 1 THEN ' (INCLUDED)' ELSE '' END
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id 
          AND ic.index_id = i.index_id
        ORDER BY ic.key_ordinal, ic.index_column_id
        FOR XML PATH('')
    ), 1, 2, '') AS [Колонки индекса],

    ------------------------------------------------------
    -- Ключевые колонки
    ------------------------------------------------------
    STUFF((
        SELECT ', ' 
             + COL_NAME(ic.object_id, ic.column_id)
             + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE ' ASC' END
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id 
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH('')
    ), 1, 2, '') AS [Ключевые],

    ------------------------------------------------------
    -- Included-колонки
    ------------------------------------------------------
    STUFF((
        SELECT ', ' + COL_NAME(ic.object_id, ic.column_id)
        FROM sys.index_columns ic
        WHERE ic.object_id = i.object_id 
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH('')
    ), 1, 2, '') AS [Included],

    ------------------------------------------------------
    -- Метрики по количеству колонок
    ------------------------------------------------------
    (SELECT COUNT(*) FROM sys.index_columns ic
     WHERE ic.object_id = i.object_id 
       AND ic.index_id = i.index_id
       AND ic.is_included_column = 0
    ) AS [Кол-во ключевых],

    (SELECT COUNT(*) FROM sys.index_columns ic
     WHERE ic.object_id = i.object_id 
       AND ic.index_id = i.index_id
       AND ic.is_included_column = 1
    ) AS [Кол-во included],

    ------------------------------------------------------
    -- Статус использования
    ------------------------------------------------------
    CASE 
        WHEN ius.database_id IS NULL THEN 'Нет данных'
        WHEN ISNULL(ius.user_seeks,0) + ISNULL(ius.user_scans,0) + ISNULL(ius.user_lookups,0) = 0
            THEN 'Не используется'
        ELSE 'Используется'
    END AS [Статус],

    ------------------------------------------------------
    -- Процент seek от всех обращений
    ------------------------------------------------------
    CASE 
        WHEN ISNULL(ius.user_seeks,0) 
           + ISNULL(ius.user_scans,0) 
           + ISNULL(ius.user_lookups,0) > 0 
        THEN CAST(
                ISNULL(ius.user_seeks,0) * 100.0 
                / (ISNULL(ius.user_seeks,0) 
                 + ISNULL(ius.user_scans,0) 
                 + ISNULL(ius.user_lookups,0))
             AS DECIMAL(5,2))
        ELSE 0
    END AS [Seek %],

    ------------------------------------------------------
    -- Соотношение чтений к обновлениям
    ------------------------------------------------------
    CASE 
        WHEN ISNULL(ius.user_updates, 0) > 0 
        THEN CAST(
                (ISNULL(ius.user_seeks,0) 
               + ISNULL(ius.user_scans,0) 
               + ISNULL(ius.user_lookups,0)) * 1.0 
                / ius.user_updates
             AS DECIMAL(10,2))
        ELSE NULL 
    END AS [Read/Write]

FROM sys.indexes i
INNER JOIN sys.dm_db_partition_stats ps 
        ON i.object_id = ps.object_id 
       AND i.index_id = ps.index_id
LEFT JOIN sys.dm_db_index_usage_stats ius 
        ON i.object_id = ius.object_id 
       AND i.index_id = ius.index_id 
       AND ius.database_id = DB_ID()
WHERE i.object_id = OBJECT_ID(@tableName)
  AND i.index_id > 0
ORDER BY 
    [Таблица 1С],
    CASE WHEN i.is_primary_key = 1 THEN 1 ELSE 2 END,
    ISNULL(ius.user_seeks,0) + ISNULL(ius.user_scans,0) DESC;
