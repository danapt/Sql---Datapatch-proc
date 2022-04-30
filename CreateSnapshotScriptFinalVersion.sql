-- Note: Change this list of database as required. The rest of the script can be left unchanged.

DECLARE @dbNames as Varchar(500) =  'dbTest1, dbTes2, Dbtest3 ... etc. '

-- =======================================================================
-- STEP 0: Pre-defined constants & time-based snapshot names
-- =======================================================================
DECLARE @Extension_pre AS VARCHAR(100) = 'Snapshot' +convert(varchar,format(getdate(),'yyyyMMdd_HHmm')) +'_';
DECLARE @Extension_post AS VARCHAR(100) = '_after_DBRefresh';

print @dbNames
-- =======================================================================
-- STEP 1: Split DB Names into #DbNamesRows
-- =======================================================================
DROP TABLE IF EXISTS #dbNames
CREATE TABLE #dbNames (
    id INT,
    csv VARCHAR(MAX)
)
INSERT #dbNames SELECT 1, @dbNames ;

select * from #dbNames

-- Technique Copied from https://www.saurabhmisra.dev/sql-server-convert-delimited-string-into-rows
-- create the CTE
--WITH cte_split(id, split_values, csv) AS
DROP TABLE IF EXISTS #DbNamesRows
;WITH cte_split(split_values, csv) AS
(
    -- anchor member
    SELECT
        --id,
        LEFT(csv, CHARINDEX(',', csv + ',') - 1),
        STUFF(csv, 1, CHARINDEX(',', csv + ','), '')
    FROM #dbNames
    UNION ALL
    -- recursive member
    SELECT
        --id,
        LEFT(csv, CHARINDEX(',', csv + ',') - 1),
        STUFF(csv, 1, CHARINDEX(',', csv + ','), '')
    FROM cte_split
    -- termination condition
    WHERE csv > ''
)
-- use the CTE and generate the final result set
--SELECT id, split_values, ROW_NUMBER() OVER (order by id)
SELECT ID=ROW_NUMBER() OVER (order by split_values) , name=split_values 
INTO #DbNamesRows
FROM cte_split
--ORDER BY id;

select * from #DbNamesRows


-- =======================================================================
-- STEP 2: Create Snapshot on Each Database
-- =======================================================================

DECLARE @count INT = 1 
DECLARE @count_total INT 
select  @count_total =  count(1) from #DbNamesRows
DECLARE @SQL AS VARCHAR(MAX)
DECLARE @DB AS sysname ;

WHILE @count < @count_total + 1
BEGIN
       
		set @DB = (select name from #DbNamesRows where id = @count)
		--print @DB

		Declare @snapshotName as varchar(100) = @Extension_pre +@DB + @Extension_post;

		SET @SQL = 'CREATE DATABASE ' + @snapshotName + '
		ON'

		SELECT
				@SQL = @SQL + ',
		(NAME = ' + name + ',FILENAME  = ''' + REPLACE(physical_name, '.' + PARSENAME(physical_name, 1), @snapshotName + '.SS') + ''' )'
		FROM sys.master_files
		WHERE
				database_id = DB_ID(@DB)
				AND type_desc = 'ROWS';

		--End statement
		SET @SQL = @SQL + '
		AS SNAPSHOT OF ' + @DB + ';';

		--Strip out the leading comma
		SET @SQL = REPLACE (@SQL, 'ON,
		', 'ON
		');
       
		exec (@SQL);       -- <---------------------------- EXECUTING DYNAMIC SQL HERE !
		--PRINT @SQL

		set @snapshotName = null
		set @SQL = null

        SET @count = @count + 1
End;
