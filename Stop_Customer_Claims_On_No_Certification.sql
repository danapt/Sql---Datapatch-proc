/*
*	Stop Claim where claimant has not certified
*/

CREATE OR ALTER PROCEDURE [dbo].[Stop_Claimant_With_No_Certification]
@issuedDate AS Date
,@groupSize  int 
,@stopDate Datetime
,@stopDays int
AS 
BEGIN
DECLARE
        @LaDateTime AS DATETIME
       ,@LaUserID   AS INT;

SELECT
        @LaDateTime = GETDATE()
       ,@LaUserID   = 10571; --Migration

DECLARE @LinkedServernameDigital nvarchar(256) = ''
DECLARE @ParmDefinition nvarchar(500);
DECLARE @spread_sheet_id int;

--Determine linked server name	
declare @linkedServer sysname=( 
	select AGlName=case when AGL.dns_name is not null then '[' + AGL.dns_name + '].' else '' end   
    from sys.availability_group_listeners AGL 
    join sys.availability_groups AG on AG.group_id=AGL.group_id 
    Join sys.dm_hadr_database_replica_states AS st on st.group_id=AGL.group_id 
    Join sys.databases d on d.database_id=st.database_id 
    where d.name='dbTest2' 
    and st.is_local=1 
    and st.is_primary_replica=0 
  ) 
  print @linkedServer 
        Set @LinkedServernameDigital=isnull(@linkedServer,'')

Create table #customers_to_stop
(
	customer_id bigint null, 
	cust_certification_id bigint null,
	pps_no varchar(100)
)

--If Group Size not specified all claims that meet the criteria will be selected.
 if(@groupSize is null)
  Begin
		insert into #customers_to_stop
		(
		    customer_id , 
			cust_certification_id,
			pps_no
		)
		select distinct cl.customer_id, cust_certification_id,pps_no from customer_claim.claim clm
		join customer_link cl on clm.claimant_id = cl.customer_id
		left join dbCustomers.dbo.Life_Event le on cl.customer_id = le.customer_id and le.life_event_type_id = 2 and le.life_event_date is not null
		join [db].[cust_Certification] crt on clm.claim_id = crt.claim_id 
		join dbCustomers.Claim.Claim_Version cv on clm.claim_id = cv.claim_id
		WHERE cv.effective_from < = getdate() 
		AND ( 
				cv.effective_to is null 
				or cv.effective_to > getdate() 
			) 
		AND CV.status in (1)
		AND cv.payment_mode in ('PAY') 
		AND cv.is_deleted_ind = 0
		AND cast(crt.issued_date as date) = @issuedDate
		AND le.life_event_id is null
		AND crt.status not in (3,4) --Looking for cases where they have not been certified and expired
		order by cl.pps_no
 end
else
  Begin
		insert into #customers_to_stop
		(
			customer_id , 
			cust_certification_id,
			pps_no
		)
		select  distinct top (@groupSize) cl.customer_id, cust_certification_id,pps_no from customer_claim.claim clm
		join customer_link cl on clm.claimant_id = cl.customer_id
		left join dbCustomers.dbo.Life_Event le on cl.customer_id = le.customer_id and le.life_event_type_id = 2 and le.life_event_date is not null
		join [db].[cust_Certification] crt on clm.claim_id = crt.claim_id 
		join dbCustomers.Claim.Claim_Version cv on clm.claim_id = cv.claim_id
		WHERE cv.effective_from < = getdate() 
		AND ( 
				cv.effective_to is null 
				or cv.effective_to > getdate() 
			) 
		AND CV.status in (1)
		AND cv.payment_mode in ('PAY') 
		AND cv.is_deleted_ind = 0
		AND cast(crt.issued_date as date) = @issuedDate
		AND le.life_event_id is null
		AND crt.status not in (3,4) --Looking for cases where they have not been certified and expired
		order by cl.pps_no
 end


--update the cert table mark the status as 4 (expired)
update [db].[cust_Certification]
set status = 4, la_date_time = @LaDateTime
from [db].[cust_Certification] puc 
inner join
#customers_to_stop  cts on puc.cust_certification_id = cts.cust_certification_id

--create a recorded action  -- "Certification Expire" 
DECLARE @recActionTypeId INT
SELECT TOP 1 @recActionTypeId = [rec_action_type_id] FROM [dbCustomers].[dbo].[rec_action_Type] WHERE full_name = 'CustUnemployment.Impl.Certification#Expire'
 
 IF OBJECT_ID('#rec_action') IS NULL
 BEGIN 
	PRINT 'Create table #rec_action'
	CREATE TABLE #rec_action (
	[date_of_action] [datetime] NULL,
	[logical_rec_action_id] [bigint] NULL,
	[physical_rec_action_id] [bigint] NULL,
	[details] [varchar](255) NULL,
	[actor_id] [int] NULL,
	[assigned_to] [int] NULL,
	[cas_status_id] [int] NULL,
	[rec_action_type_id] [int] NULL,
	[object_type_code] [char](3) NULL,
	[commentary] [varchar](1024) NULL,
    [context_case_id] [int] NULL,
	[encrypted_xml_digest_base64] [int] NULL,
	[x509_certificate_base64] [int] NULL,
	[xml] [int] NULL,
	[locked] [bit] NULL,
	[la_date_time] [datetime] NULL,
	[la_user_id] [int] NULL,
	[task_id] [int] NULL
	) ON [PRIMARY];
END

 IF OBJECT_ID('#rec_action_certification') IS NULL
 BEGIN 
	PRINT 'Create table #rec_action_certification'
	CREATE TABLE #rec_action_certification(
	[rec_action_id] [bigint] NULL, 
	[logical_rec_action_id] [bigint] NULL,
	[physical_rec_action_id] [bigint] NULL,
	[cust_certification_id] [bigint] NULL
	) ON [PRIMARY];
END

-- Insert into base recorded action table	
INSERT INTO #rec_action
select 
	 [date_of_action] = @LaDateTime
    ,[logical_rec_action_id]= ROW_NUMBER() OVER(order by customer_id)
	,[physcial_rec_action_id] = null
	,[details] = 'Customer failed to confirm eligibility’'
	,[actor_id] =@LaUserID
	,[assigned_to] = Null
	,[cas_status_id] = null
	,[rec_action_type_id] = @recActionTypeId
	,[object_type_code] = 'db'
	,[commentary] = Null
	,[context_case_id] = Null
	,[encrypted_xml_digest_base64] = Null
	,[x509_certificate_base64] = Null
	,[xml] = Null
	,[locked] = Null
	,[la_date_time] = @LaDateTime
	,[la_user_id] = @LaUserID
	,[task_id] = Null 
	From #customers_to_stop

-- Insert into subclass recorded action table
INSERT INTO #rec_action_certification
select
	  [rec_action_id] = customer_id
	 ,[logical_rec_action_id]= ROW_NUMBER() OVER(order by customer_id)
	 ,[physcial_rec_action_id]=null
	 ,[cust_certification_id] = cust_certification_id  
From #customers_to_stop

-- Lock Recorded Action table					
SELECT * INTO #WI_480243_TEMP456_Certification_Expire  --into #TEMP table purely so it doesnt get returned as a result set from the batch job. There will be no rows expected.
FROM [rec_action] WITH (TABLOCKX, HOLDLOCK)	--**TABLE** LOCK
WHERE 1=2; --ie. no rows

--Get latest rec_action id.
DECLARE @rec_action_id_LastVal INT = 0;
SELECT @rec_action_id_LastVal = CAST(last_value AS INT) FROM sys.identity_columns WHERE [object_id] = OBJECT_ID('rec_action') AND [name] = 'rec_action_id'

UPDATE #rec_action
set [physical_rec_action_id] = [logical_rec_action_id] + @rec_action_id_LastVal
UPDATE #rec_action_certification	
set [physical_rec_action_id] = [logical_rec_action_id] + @rec_action_id_LastVal

--Insert dbo.rec_action
SET IDENTITY_INSERT dbCustomers.dbo.rec_action  ON

INSERT INTO rec_action 
		(rec_action_id,[date_of_action],[details],[actor_id],[assigned_to]
		,[cas_status_id],[rec_action_type_id],[object_type_code],[commentary],[context_case_id]
		,[encrypted_xml_digest_base64],[x509_certificate_base64],[xml]
		,[locked],[la_date_time],[la_user_id],[task_id])
	SELECT 
		[physical_rec_action_id], @LaDateTime,'Customer failed to confirm eligibility',@LaUserID,NULL,NULL,@recActionTypeId
		,'db',NULL,NULL,NULL,NULL,NULL,NULL,@LaDateTime,@LaUserID,NULL
	FROM #rec_action
			 						
SET IDENTITY_INSERT dbCustomers.dbo.rec_action  OFF

INSERT INTO db.rec_action_Certification
		([rec_action_id],[cust_certification_id])
	SELECT [physical_rec_action_id],[cust_certification_id]
	FROM #rec_action_certification

--Timeline stops will be created in the database for each PPSN selected with

IF(EXISTS(select 1 from #customers_to_stop))
BEGIN
		DECLARE @dbTest2_SPREADSHEET_SQL nvarchar(max), @maxSpreadSheetId nvarchar(max);
		SET @dbTest2_SPREADSHEET_SQL = 'INSERT INTO '
		+ @LinkedServernameDigital 
		+ '[dbTest2].[db].[External_Spreadsheet] ([file_name], [uploaded_date], [processed_date], [rowcount], [command], [eligibility_time_line_extension_type_id], [comment], [spreadsheet_type]) values(''STOP_dbS_ON_NO_CERTIFICATION'', GETDATE(),GETDATE(),NULL,''EXC'',1,''Stopping db claims on no certification'',''RCT'')' 

		EXECUTE sp_executesql @dbTest2_SPREADSHEET_SQL

		SELECT @maxSpreadSheetId = N'SELECT @spread_sheet_id = max(id) from '+ @LinkedServernameDigital +'[dbTest2].[db].[External_Spreadsheet]' 
		SET @ParmDefinition = N'@spread_sheet_id int OUTPUT';
		EXEC sp_executesql @maxSpreadSheetId, @ParmDefinition, @spread_sheet_id=@spread_sheet_id OUTPUT;

		DECLARE @dbTest2_TIMELINE_SQL nvarchar(max);
		SET @dbTest2_TIMELINE_SQL = 'INSERT INTO'
		+ @LinkedServernameDigital 
		+ ' [dbTest2].[db].[Eligibility_Time_Line_Extension] (pps_no,created_date_time,db_external_spreadsheet_id,failure_reason,start_date,end_date,claim_type)'
		+ ' select cl.pps_no,GETDATE(),' + cast(@spread_sheet_id as varchar(4)) + ',''Failed to Confirm Eligibility'',''' + convert(varchar, @stopDate, 23) + ''',''' + convert(varchar, DATEADD(day,@stopDays -1 , @stopDate), 23) + ''',''ENP4''' 
		+ ' from #customers_to_stop ctc join customer_link cl on ctc.customer_id = cl.customer_id'
		+ ' order by ctc.pps_no'
		EXECUTE sp_executesql @dbTest2_TIMELINE_SQL

END;

drop table #customers_to_stop
drop table #rec_action
drop table #rec_action_certification

END;
go