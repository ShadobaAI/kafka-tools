USE master;
GO

-- The MCP server is intentionally unrestricted for this local development instance.
CREATE OR ALTER PROCEDURE dbo.mcp_execute_sql
    @sql nvarchar(max),
    @database nvarchar(128) = N'master'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @executor nvarchar(300) = QUOTENAME(@database) + N'.sys.sp_executesql';
    EXEC @executor @sql WITH RESULT SETS NONE;

    SELECT N'OK' AS result;
END;
GO

CREATE OR ALTER PROCEDURE dbo.mcp_query_sql
    @sql nvarchar(max),
    @database nvarchar(128) = N'master'
AS
BEGIN
    SET NOCOUNT ON;

    -- FOR JSON gives DAB a stable, single-column result regardless of the query.
    WHILE DATALENGTH(@sql) > 0 AND UNICODE(RIGHT(@sql, 1)) IN (9, 10, 13, 32)
        SET @sql = LEFT(@sql, DATALENGTH(@sql) / 2 - 1);
    IF RIGHT(@sql, 1) = N';'
        SET @sql = LEFT(@sql, LEN(@sql) - 1);

    DECLARE @executor nvarchar(300) = QUOTENAME(@database) + N'.sys.sp_executesql';
    DECLARE @statement nvarchar(max) = N'SELECT @result = (' + @sql + NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
    DECLARE @result nvarchar(max);

    EXEC @executor @statement, N'@result nvarchar(max) OUTPUT', @result OUTPUT WITH RESULT SETS NONE;

    SELECT @result AS result;
END;
GO
