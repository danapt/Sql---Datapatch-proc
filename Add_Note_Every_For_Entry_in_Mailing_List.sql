/*
*	Add Note for every entry in MailingList 
Procudere Example in SQL Server
*/
USE dbBatch
GO

CREATE OR ALTER PROCEDURE [db].[Add_Note_Every_For_Entry_in_Mailing_List]
@creationDate AS DATETIME2
,@communicationType AS Varchar(1000)
AS 
BEGIN
DECLARE
        @LaDateTime AS DATETIME
       ,@LaUserID   AS INT;

SELECT
        @LaDateTime = GETDATE()
       ,@LaUserID   = 10571; --Migration
 

Create table #addNote
(
	creation_date        DATETIME2 null, 
	communication_type  VARCHAR(100) null,
	claim_id bigint null,
	note_description   VARCHAR(128)  not null
	
)

 Begin
		insert into #addNote
		(
			creation_date  , 
			communication_type ,
			claim_id,
			note_description
		)
		select distinct cmm.creation_date, cmm.communication_type, cc.claim_id, cmm.note_description from dbBatch.db.Transition_Mail_Merge as cmm
		join dbCustomers.dbo.customer_link cl on cl.pps_no = cmm.ppsn
		join dbCustomers.cust_claim.claim as cc on cl.customer_id = cc.claimant_id
        join dbCustomers.Claim.Claim_Version cv (NOLOCK) ON cv.claim_id = cc.claim_id 
        join dbCustomers.Claim.Claim_Status cs (NOLOCK) ON cs.claim_status_id = cv.status 
		--join customer_case cca on cl.customer_id = cca.customer_id 
		--join Customer_Case_Content ccc on ccc.case_id = cca.case_id
		--join content as c on c.content_id = ccc.content_id
		--join Case_Note as cn on cn.cas_note_id = c.content_id
              WHERE 1 = 1     
              and cc.scheme_code = 'db'
              and is_deleted_ind = 0 
		      and cmm.creation_date =@creationDate
		      and cmm.communication_type = @communicationType

 end

  IF OBJECT_ID('#case_note') IS NULL
 BEGIN 
	PRINT 'Create table #case_note'
	CREATE TABLE #case_note (
	   [logical_cas_note_id] [bigint] null
	  ,[physical_id] [bigint] NULL
      ,[notes] [varchar](2500) null
      ,[cas_note_type_id][int] null
      ,[noted_by] [int] null
      ,[la_date_time] [datetime] null
      ,[la_user_id] [int] null
      ,[created_date] [datetime] null) ON [PRIMARY];
END

  IF OBJECT_ID('#content') IS NULL
 BEGIN 
	PRINT 'Create table #content'
	CREATE TABLE #content (
	   [logical_cas_note_id] [bigint] null
	  ,[physical_id] [bigint] NULL
      ,[cas_note_type_id][int] null
      ,[la_date_time] [datetime] null
      ,[la_user_id] [int] null
	  ,[parent_content_id] int) ON [PRIMARY];
END

 IF OBJECT_ID('#claim_correspondence') IS NULL
 BEGIN 
	PRINT 'Create table #claim_correspondence'
	CREATE TABLE #claim_correspondence (
	   [claim_id] [int] null
      ,[document_id] [int] null
	  ,[physical_id] [bigint] NULL
      ,[la_date_time] [datetime] null
      ,[la_user_id] [int] null) ON [PRIMARY];
END

INSERT INTO #case_note
select 
	   [logical_cas_note_id] =  ROW_NUMBER() OVER(order by claim_id)
	  ,[physical_id]  = null
      ,[notes] = note_description
      ,[cas_note_type_id] = 1
      ,[noted_by] = @LaUserID
      ,[la_date_time] = @LaDateTime
      ,[la_user_id] = @LaUserID
      ,[created_date] = @LaDateTime
	From #addNote

INSERT INTO #content
select 
	   [logical_cas_note_id] =  ROW_NUMBER() OVER(order by claim_id)
	  ,[physical_id]  = null
      ,[cas_note_type_id] = 1
      ,[la_date_time] = @LaDateTime
      ,[la_user_id] = @LaUserID
	  ,[parent_content_id] = null
	From #addNote


INSERT INTO #claim_correspondence
select 
	   [claim_id] = claim_id
      ,[document_id] = ROW_NUMBER() OVER(order by claim_id)
	  ,[physical_id] = null
      ,[la_date_time] = @LaDateTime
      ,[la_user_id] = @LaUserID
	  From #addNote
	  
-- Lock Recorded Action table					
SELECT * INTO #WI_480243_TEMP456_Certification_Expire  --into #TEMP table purely so it doesnt get returned as a result set from the batch job. There will be no rows expected.
FROM [dbCustomers].[dbo].[Content] WITH (TABLOCKX, HOLDLOCK)	--**TABLE** LOCK
WHERE 1=2; --ie. no rows

--Get latest rec_action id.
DECLARE @cas_note_id_LastVal INT = 0;
Set @cas_note_id_LastVal =  (select top 1 cas_note_id from dbCustomers.dbo.Case_Note order by cas_note_id desc)
print @cas_note_id_LastVal


UPDATE #case_note
set [physical_id] = [logical_cas_note_id] + @cas_note_id_LastVal
UPDATE #claim_correspondence
set [physical_id] = [document_id] + @cas_note_id_LastVal
UPDATE #content
set [physical_id] = [logical_cas_note_id] + @cas_note_id_LastVal

--Insert dbo.rec_action
SET IDENTITY_INSERT dbCustomers.dbo.Content  ON

 insert into dbCustomers.dbo.Content (
	    [content_id],[cas_content_type_id],[la_date_time],[la_user_id],[parent_content_id])
	select [physical_id], 1,@LaDateTime ,@LaUserID,null
	from #content

SET IDENTITY_INSERT dbCustomers.dbo.Content  OFF

insert into dbCustomers.dbo.Case_Note (
	    [cas_note_id],[notes],[cas_note_type_id],[noted_by],[la_date_time],[la_user_id],[created_date])
		select [physical_id], notes,1,@LaUserID,@LaDateTime,@LaUserID,@LaDateTime
		from #case_note

insert into [dbCustomers].[Claim].[Claim_Correspondence](
	  [claim_id], [document_id], [la_date_time],[la_user_id])
	  select claim_id, physical_id,@LaDateTime,@LaUserID
	  from #claim_correspondence
	
--create a recorded action  -- 
DECLARE @recActionTypeId INT
SELECT TOP 1 @recActionTypeId = [rec_action_type_id] FROM [dbCustomers].[dbo].[rec_action_Type] WHERE full_name = 'Sdm.Cluster.Claims.Impl.GenericClaims.GenericClaim#CreateNewNote'
 
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

 IF OBJECT_ID('#rec_action_cust_claim') IS NULL
 BEGIN 
	PRINT 'Create table #rec_action_cust_claim'
	CREATE TABLE #rec_action_cust_claim(
	[rec_action_id] [bigint] NULL, 
	[logical_rec_action_id] [bigint] NULL,
	[physical_rec_action_id] [bigint] NULL,
	[Claim_id] [bigint] NULL
	) ON [PRIMARY];
END

-- Insert into base recorded action table	
INSERT INTO #rec_action
select 
	 [date_of_action] = @LaDateTime
    ,[logical_rec_action_id]= ROW_NUMBER() OVER(order by claim_id)
	,[physcial_rec_action_id] = null
	,[details] = 'Document Created on Claim'
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
	From #addNote

-- Insert into subclass recorded action table
INSERT INTO #rec_action_cust_claim
select
	  [rec_action_id] = claim_id
	 ,[logical_rec_action_id]= ROW_NUMBER() OVER(order by claim_id)
	 ,[physcial_rec_action_id]=null
	 ,[Claim_id] = claim_id  
From #addNote
					
-- Lock Recorded Action table					
SELECT * INTO #WI_480243_TEMP456_Certification_Expiree  --into #TEMP table purely so it doesnt get returned as a result set from the batch job. There will be no rows expected.
FROM [dbCustomers].[dbo].[rec_action] WITH (TABLOCKX, HOLDLOCK)	--**TABLE** LOCK
WHERE 1=2; --ie. no rows

--Get latest rec_action id.
DECLARE @rec_action_id_LastVal INT = 0;
Set @rec_action_id_LastVal =  (select top 1 rec_action_id from dbCustomers.dbo.rec_action order by date_of_action desc)
print @rec_action_id_LastVal

UPDATE #rec_action
set [physical_rec_action_id] = [logical_rec_action_id] + @rec_action_id_LastVal
UPDATE #rec_action_cust_claim	
set [physical_rec_action_id] = [logical_rec_action_id] + @rec_action_id_LastVal

--Insert dbo.rec_action
SET IDENTITY_INSERT dbCustomers.dbo.rec_action  ON

INSERT INTO [dbCustomers].[dbo].[rec_action]
		(rec_action_id,[date_of_action],[details],[actor_id],[assigned_to]
		,[cas_status_id],[rec_action_type_id],[object_type_code],[commentary],[context_case_id]
		,[encrypted_xml_digest_base64],[x509_certificate_base64],[xml]
		,[locked],[la_date_time],[la_user_id],[task_id])
	SELECT 
		[physical_rec_action_id], @LaDateTime,'Document Created on Claim',@LaUserID,NULL,NULL,@recActionTypeId
		,'db',NULL,NULL,NULL,NULL,NULL,NULL,@LaDateTime,@LaUserID,NULL
	FROM #rec_action
			 						
SET IDENTITY_INSERT dbCustomers.dbo.rec_action  OFF

INSERT INTO [dbCustomers].[Claim].[rec_action_cust_claim]
		([rec_action_id],[Claim_id])
	SELECT [physical_rec_action_id],[Claim_id]
	FROM #rec_action_cust_claim

drop table #addNote
drop table #case_note
drop table #content
drop table #rec_action
drop table #rec_action_cust_claim

END;
go
