/**************************************************************************
 * By                 : Daniel Apetri
 * this is an exmple of SQL work -- data patch -- 

 ***************************************************************************/

 SET NOCOUNT ON

 DECLARE
 	@WI AS VARCHAR(200),
 	@RowCount AS INT,
 	@ErrorMessage NVARCHAR(4000),
 	@ErrorState INT, 
	@LaUserID   AS INT,
	@LaDateTime AS DATETIME
	 
PRINT 	'Expecting 1 Payemnt and 1 Payemnt Item udpated for each of two cases - see output below '
 
 SELECT @WI = 'WI_test',
		@LaUserID   = 10571,
		@LaDateTime = GETDATE(); --Migration
 	
 --Only execute if patch was not already run
IF NOT EXISTS
( 		SELECT 1
 	FROM dbo.DB_Release
 	WHERE dccm_data_ver = @WI

)
BEGIN
 
		BEGIN TRAN

			

			DECLARE @rowCountUpdated as int 
			DECLARE @CheckErrorMessage as varchar(100) = 'Patch not run , since the data seems to have been changed from what we expected'
			--Declare variables for WSS claim
			DECLARE @PaymentIdWSS AS int= 688838059 --Set variable with the payment_id for Employer: 0000000 Amount 826.80 Payment due date: 09-SEP-2021 WSS
			DECLARE @UpdateStatusRecordIdWSS as int = 321013 --Set variable for the row id that will update the effective_to for  Employer: 4761510G
			DECLARE @DeleteStatusRecordIdWSS as int = 332021 --Set variable for the row id that will delete the row where approvat status was set to 'NOT' for Employer: 4761510G
			DECLARE @ExternalClaimIdWSS as int = 73066

			--Declare variables for ESS claim
			DECLARE @PaymentIdESS as int = 688839140 --Set variable for with the payment_id for Employer: 00000000 Amount 753.07 Payment Due date: 09-SEP-2021 ESS
			DECLARE @UpdateStatusRecordIdESS as int = 322590 --Set variable for the row id that will update the effective_to for Employer: 0001736H
			DECLARE @DeleteStatusRecordIdESS as int = 332020 --Set variable for the row id that will delete the row where approvat status was set to 'NOT' for Employer: 0001736H
			DECLARE @ExternalClaimIdESS as int = 69297

			--test 
					select top 11* from  [Generic_Claim].[External_Organisation_Claim] 
					WHERE external_organisation_claim_id = @ExternalClaimIdWSS

			-- ========================================================================================================
			-- Pre-Validate that the data we are about to patch has not chnaged since we wrote the data patch
			-- ========================================================================================================

			-- WSS ID's we are about to Update...
			Declare @PaymentIdWSSLaDateTime As datetime = (Select la_date_time from payment.payment where payment_id = @PaymentIdWSS)
			Declare @PaymentItemIdWSSLaDateTime As datetime = (Select la_date_time from payment.payment_item where payment_id = @PaymentIdWSS)
			Declare @UpdateStatusRecordIdWSSLadateTime As datetime = (Select la_date_time from  [Wage_Subsidy].[Status_Record] where status_record_id = @UpdateStatusRecordIdWSS)
			Declare @DeleteStatusRecordIdWSSLadateTime As datetime = (Select la_date_time from  [Wage_Subsidy].[Status_Record] where status_record_id = @UpdateStatusRecordIdWSS)
			if (@PaymentIdWSSLaDateTime <> '2021-10-06 17:24:02.460' or
			 @PaymentItemIdWSSLaDateTime <> '2021-10-06 17:24:02.460' or
			 @UpdateStatusRecordIdWSSLadateTime <>'2021-10-06 17:24:02.460' or
			 @DeleteStatusRecordIdWSSLadateTime <> '2021-10-06 17:24:02.460')
			 RaisError (@CheckErrorMessage,17,1)



			-- ESS ID's we are about to Update...
			Declare @PaymentIdESSLaDateTime As datetime = (Select la_date_time from payment.payment where payment_id = @PaymentIdESS)
			Declare @PaymentItemIdESSLaDateTime As datetime = (Select la_date_time from payment.payment_item where payment_id = @PaymentIdESS)
			Declare @UpdateStatusRecordIdESSLadateTime As datetime = (Select la_date_time from  [Wage_Subsidy].[Status_Record] where status_record_id = @UpdateStatusRecordIdESS)
			Declare @DeleteStatusRecordIdESSLadateTime As datetime = (Select la_date_time from  [Wage_Subsidy].[Status_Record] where status_record_id = @UpdateStatusRecordIdESS)
			if (@PaymentIdESSLaDateTime <> '2022-10-06 17:20:32.200' or
			 @PaymentItemIdESSLaDateTime <> '2021-10-06 17:20:32.200' or
			 @UpdateStatusRecordIdESSLadateTime <>'2021-10-06 17:20:32.200' or
			 @DeleteStatusRecordIdESSLadateTime <> '2021-10-06 17:20:32.200')
			 RaisError (@CheckErrorMessage,17,1)
		
		BEGIN TRY
					-- ========================================================================
					--Employer: 0111111 Amount 826.80 Payment due date: 09-SEP-2021 WSS
					-- ========================================================================

					-- Update Payment status back to ISSUED
					UPDATE [Payment].[Payment]
					SET [status] = 2,	--2:Issued 
					[la_date_time] = @LaDateTime, 
					[la_user_id] = @LaUserID, 
					[status_reason_code] = NULL      
					WHERE 1=1
					AND [payment_id] = @PaymentIdWSS 
					AND [total_amount] = 826.80		-- double check on the amount
					AND [status]  = 3		--3:Cancelled
					
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'First case Payment Rows Updated: ' + cast(@rowCountUpdated  as varchar(12)) 

					--Update Payment_item back to NonDeleted
					UPDATE [Payment].[Payment_Item] 
					SET [is_deleted_ind] = 0,	--0:Not Deleted
					[la_date_time] = @LaDateTime, 
					[la_user_id] = @LaUserID
					WHERE 1=1
					AND [payment_id] = @PaymentIdWSS   
					AND [amount] = 826.80     -- double check on the amount  
					AND [is_deleted_ind] = 1    --1:Deleted
					
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'First case Payment Item Rows Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 

					--Update Status_Record Effectice_to date back to null
					UPDATE [Wage_Subsidy].[Status_Record]
					SET effective_to = NULL,
					la_user_id = @LaUserID,
					la_date_time = @LaDateTime
					WHERE status_record_id = @UpdateStatusRecordIdWSS
					
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'First case Status_Recored effective_to Row Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 				

					--Update Claim for Employer: 4761510G Amount 826.80 Payment due date: 09-SEP-2021 WSS
					UPDATE [Generic_Claim].[External_Organisation_Claim] 
					SET 
					la_date_time = @LaDateTime,
					la_user_id = @LaUserID,
					payment_mode_code = 'PAY',
					reason_code = NUll
					WHERE external_organisation_claim_id = @ExternalClaimIdWSS

					--test 
					select top 11* from  [Generic_Claim].[External_Organisation_Claim] 
					WHERE external_organisation_claim_id = @ExternalClaimIdWSS
			
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'First case External_Organisation_Claim Status and Reason Row Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 

					--delete Status_Record_Link where approval status was set to 'NOT'
					DELETE SRL
					FROM [Wage_Subsidy].[Status_Record_Link] SRL 
					JOIN [Wage_Subsidy].[Status_Record] SR ON sr.status_record_id = srl.status_record_id
					WHERE sr.status_record_id = @DeleteStatusRecordIdWSS

					--delete Status_Record approval status to 'NOT'
					DELETE FROM [Wage_Subsidy].[Status_Record]
					WHERE status_record_id = @DeleteStatusRecordIdWSS


					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'First case Status_Recored deleted when approval status set to "NOT":  ' + cast(@rowCountUpdated  as varchar(12)) 

					-- ========================================================================
					--Employer: 0222222Amount 753.07 Payment Due date: 09-SEP-2021 ESS
					-- ========================================================================

					-- Update Payment status back to ISSUED
					UPDATE [Payment].[Payment]
					SET [status] = 2,	 -- 2:ISSUED
					[la_date_time] = @LaDateTime, 
					[la_user_id] = @LaUserID, 
					[status_reason_code] = NULL        
					WHERE 1=1
					AND  [payment_id] = @PaymentIdESS 
					AND status = 3	--3:CANCELLED
					AND [total_amount] = 753.07     -- double check on the amount

					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'Second case Payment Rows Updated:  ' + cast(@rowCountUpdated  as varchar(12))

					--Update Payment_item back to NonDeleted
					UPDATE [Payment].[Payment_Item] 
					SET [is_deleted_ind] = 0,	--0: NOT DELETED
					[la_date_time] = @LaDateTime, 
					[la_user_id] = @LaUserID
					WHERE 1=1
					AND [payment_id] = @PaymentIdESS 
					AND is_deleted_ind = 1		--1:Deleted
					AND [amount] = 753.07     -- double check on the amount
					
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'Second case Payment Item Rows Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 

					--Update Status_Record Effectice_to date back to null
					Update [Wage_Subsidy].[Status_Record]
					set effective_to = NULL,
					la_user_id = @LaUserID,
					la_date_time = @LaDateTime
					Where status_record_id = @UpdateStatusRecordIdESS
					
					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'Second case Status_Recored effective_to Row Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 

					--Update Claim for Employer: 4761510G Amount 826.80 Payment due date: 09-SEP-2021 WSS
					Update [Generic_Claim].[External_Organisation_Claim] 
					set 
					la_date_time = @LaDateTime,
					la_user_id = @LaUserID,
					payment_mode_code = 'PAY',
					reason_code = NUll
					where external_organisation_claim_id = @ExternalClaimIdESS

					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'Second case External_Organisation_Claim Status and Reason Row Updated:  ' + cast(@rowCountUpdated  as varchar(12)) 

					--delete Status_Record_Link where approval status was set to 'NOT'
					Delete SRL
					FROM [Wage_Subsidy].[Status_Record_Link] SRL 
					JOIN [Wage_Subsidy].[Status_Record] SR ON sr.status_record_id = srl.status_record_id
					Where sr.status_record_id = @DeleteStatusRecordIdESS

					--delete Status_Record approval status to 'NOT'
					DELETE FROM [Wage_Subsidy].[Status_Record]
					WHERE status_record_id = @DeleteStatusRecordIdESS 

					SET @rowCountUpdated = @@ROWCOUNT
					PRINT 'Second case Status_Recored deleted when approval status set to "NOT":  ' + cast(@rowCountUpdated  as varchar(12)) 
 			
					EXEC usp_rw_DataPatchDbRelease_insert @WI;
 
 			END TRY 
 		
 			BEGIN CATCH 
				SET NOCOUNT OFF

 				If @@TRANCOUNT > 0
 					ROLLBACK;
 
 				-- Throwing error 
 				SELECT @ErrorMessage = ERROR_MESSAGE(), @ErrorState = ERROR_STATE();  
 				RAISERROR (@ErrorMessage, 16, @ErrorState);  
 
 			END CATCH 

			If @@TRANCOUNT > 0
			     rollback
 				--COMMIT
		
END
ELSE
BEGIN
 	PRINT 'Data patch "' + @WI + '" was already run';
END;

SET NOCOUNT OFF
