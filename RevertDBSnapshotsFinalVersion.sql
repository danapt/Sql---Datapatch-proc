-- =======================================================================
-- STEP 0 : change the variables in this section - the rest of the script can be left unchanged.
-- =======================================================================
-- Note: It is really important to get the snapshot name right - it will DELETE all other snapshots that don't match it !!!
DECLARE @SnapshotDBNames as Varchar(500) =  'dbtest1,dbtest2'         -- The list of databases to revert
DECLARE @revertSnapshotPrefixe as Varchar(100) = 'Snapshot20220329_1000_'  -- the **EXACT** database snapshot to Revert to 
DECLARE @revertSnapshotSuffix as Varchar(100) = '_after_DBRefresh'		   -- no need to change this constant



/*
DECLARE @SnapshotDBNames as Varchar(500) =  'dbBomAudit,dbBombatch,dbBomCRS,dbBomMain,dbBomReporting,dbBomsemp,dbBomWebService,dbClientSearch,dbCloudIntegration,dbDisc,dbISTS,'+
                                                       'dbMygovIdMain,dbNotifications,dbPaymentsAnalysis,dbPubsub,dbScandocs,dbWssActivity,dbWssMain,dbWssMain_Audit,Electronic_Forms,'+
                                                              'Electronic_Forms_Audit,Performance'
*/

-- =======================================================================
-- STEP 1: Split DB Names into #DbNamesRows
-- =======================================================================
DROP TABLE IF EXISTS #revertSnapshotDBNames
CREATE TABLE #revertSnapshotDBNames (
    id INT,
    csv VARCHAR(MAX)
)
INSERT #revertSnapshotDBNames SELECT 1, @SnapshotDBNames ;

select * from #revertSnapshotDBNames

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
    FROM #revertSnapshotDBNames
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
SELECT ID=ROW_NUMBER() OVER (order by split_values) 
       , name=split_values 
       , revert_snapshot_name = @revertSnapshotPrefixe +split_values + @revertSnapshotSuffix
       , revert_db_id = (select database_id from sys.databases where name = split_values)
INTO #DbNamesRows
FROM cte_split
--ORDER BY id;


-- =======================================================================
-- STEP 2: Loop Through the Databases
-- =======================================================================

DECLARE @count INT = 1 
DECLARE @count_total INT = (SELECT count(1) from #DbNamesRows)

WHILE @count < @count_total + 1
BEGIN
              -- --------------------------------------------
              -- Work out the snapshot we want to Revert to .
              -- --------------------------------------------
              DECLARE @revertDBName AS varchar(max)                  = (select name from #DbNamesRows where id = @count)
              DECLARE @revertSnapshotName AS varchar(max)            = (select revert_snapshot_name from #DbNamesRows where id = @count)
              DECLARE @revertDbId int                                              = (select revert_db_id from #DbNamesRows where id = @count) 

              if exists (select * from sys.databases where name = @revertSnapshotName)
              BEGIN

                           -- -------------------------------------------------------------------------
                           -- Delete all other snapshots for this database only  
                           -- -------------------------------------------------------------------------
                           DECLARE @Sql varchar(max) = ''
                           select @sql = @sql + 'DROP Database ' + QUOTENAME(name) + ';'
                           from sys.databases 
                           where 1=1
                           and name like '%snapshot%'                  -- ie. DELETE where the databse is a snapshot
                           and name like ('%' + @revertDBName + '%')   -- ie. DELETE where it is a snapshots for this datbase we are goign to revert to (eg. "dbBomMain" etc.)
                           and name <> @revertSnapshotName             -- ie. DELETE where it is **NOT** the  one we are going to revert to - we need to keep that !!!
                     
                           print(@sql) 
                           execute(@sql)
        
              
          
                           -- --------------------------------------------
                           -- Kill users on the DB
                           -- --------------------------------------------
                           DECLARE @kill varchar(8000) = '';  
                           SELECT @kill = @kill + 'kill ' + CONVERT(varchar(5), session_id) + ';'  
                           FROM sys.dm_exec_sessions
                           WHERE database_id  = @revertDbId
                           Select 'IKillSQL=', @kill
                           EXECUTE(@kill);
       

                            -- --------------------------------------------
                           -- Restore the Database
                           -- --------------------------------------------

                           /* TEMPLATE: This is what we are constructing below..
                           --use master
                           --alter database dbbommain set single_user with rollback immediate 
                           --RESTORE DATABASE dbbommain from DATABASE_SNAPSHOT = 'Snapshot20220323_0922_dbBomMain_after_DBRefresh';
                           --alter database dbbommain set multi_user with rollback immediate 
                           --use dbbommain
                           */

                           -- Use Master
                           declare @usem varchar(30) = 'use master'
                           print(@usem)
                           Execute(@usem)

                           -- set DB to single user mode 
                           declare @SqlAlter varchar(max) = 'alter Database ' + @revertDBName + ' set single_user with rollback immediate'
                           print(@SqlAlter) 
                           Execute(@SqlAlter)

                           -- Restore Database
                           declare @SqlRestore varchar(max) = ''
                           set @SqlRestore = @SqlRestore + 'RESTORE DATABASE ' + @revertDBName + ' FROM DATABASE_SNAPSHOT = ' + '''' + @revertSnapshotName + '''' + ';'
                           print(@SqlRestore)   
                           Execute(@SqlRestore)

                           -- set DB back to multi user mode                   
                           declare @SqlAlter1 varchar(max) = ''
                           set @SqlAlter1 = @SqlAlter1 + 'alter database ' + @revertDBName + ' set multi_user with rollback immediate'
                           print(@SqlAlter1) 
                           Execute(@SqlAlter1)

                           -- Return context to the original database 
                           declare @use varchar(30) = ''
                           set @use = @use + 'use ' + @revertDBName 
                           print (@use)
                           Execute(@use)


              END

              -- --------------------------------------------
              -- Next iteration ... +1
              -- --------------------------------------------

              SET @count = @count + 1
       

END -- end loop

