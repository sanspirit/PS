<#
.SYNOPSIS
    This script grants Fusion elevated permissions
.DESCRIPTION
    Runs in the User Access Provisioning runbook in Octopus, to allow devs and QAs to request elevated permissions for Fusion testing.
#>

[CmdletBinding()]
param (

    [Parameter(Mandatory)] [string] $ConnectionString,
    [Parameter(Mandatory)] [bool] $SARequired,
    [Parameter(Mandatory)] [string] $dbuser,
    [Parameter(Mandatory)] [string] $dbpassword,
    [Parameter(Mandatory)] [int] $querytimeout,
    [Parameter(Mandatory)] [string] $forename,
    [Parameter(Mandatory)] [string] $surname,
    [Parameter(Mandatory)] [string] $FirmAdmin,
    [Parameter(Mandatory)] [string] $OperationManager,
    [Parameter(Mandatory)] [string] $ARFirmManager,
    [Parameter(Mandatory)] [string] $DocumentManager,
    [Parameter(Mandatory)] [string] $AccountOpenAdmin,
    [Parameter(Mandatory)] [string] $AccountOpenSeniorAdmin,
    [Parameter(Mandatory)] [string] $OpsManager,
    [Parameter(Mandatory)] [string] $AccountClosureAdmin,
    [Parameter(Mandatory)] [string] $FundingAdmin,
    [Parameter(Mandatory)] [string] $StaticDataAdmin,
    [Parameter(Mandatory)] [string] $TradingAdmin,
    [Parameter(Mandatory)] [string] $TransfersAdmin,
    [Parameter(Mandatory)] [string] $ProjectsAdmin,
    [Parameter(Mandatory)] [string] $ProjectsManager,
    [Parameter(Mandatory)] [string] $PlatformControlsAdmin,
    [Parameter(Mandatory)] [string] $ProcessOversightAdmin,
    [Parameter(Mandatory)] [string] $QAAdmin,
    [Parameter(Mandatory)] [string] $ThirdPartyAdmin,
    [Parameter(Mandatory)] [string] $WrapperAdmin,
    [Parameter(Mandatory)] [string] $StrategyAdmin,
    [Parameter(Mandatory)] [string] $ServiceDeliveryManager,
    [Parameter(Mandatory)] [string] $UserImpersonationAdmin,
    [Parameter(Mandatory)] [string] $VendorManager,
    [Parameter(Mandatory)] [string] $TechnicalManager,
    [Parameter(Mandatory)] [string] $Finance,
    [Parameter(Mandatory)] [string] $PensionsSupport,
    [Parameter(Mandatory)] [string] $CommitTransaction

)

$CommandText = @"

Begin Transaction

/* Commit transaction switch */
DECLARE @CommitTransaction BIT = $CommitTransaction;

/* Get User forename and surname */
DECLARE @Forename AS NVARCHAR(255) = '$forename'
DECLARE @Surname AS NVARCHAR(255) = '$surname';

/* Select roles */
DECLARE @FirmAdmin BIT = $FirmAdmin
DECLARE @OperationManager BIT = $OperationManager
DECLARE @ARFirmManager BIT = $ARFirmManager
DECLARE @DocumentManager BIT = $DocumentManager
DECLARE @AccountOpenAdmin BIT = $AccountOpenAdmin
DECLARE @AccountOpenSeniorAdmin BIT = $AccountOpenSeniorAdmin
DECLARE @OpsManager BIT = $OpsManager
DECLARE @AccountClosureAdmin BIT = $AccountClosureAdmin
DECLARE @FundingAdmin BIT = $FundingAdmin
DECLARE @StaticDataAdmin BIT = $StaticDataAdmin
DECLARE @TradingAdmin BIT = $TradingAdmin
DECLARE @TransfersAdmin BIT = $TransfersAdmin
DECLARE @ProjectsAdmin BIT = $ProjectsAdmin
DECLARE @ProjectsManager BIT = $ProjectsManager
DECLARE @PlatformControlsAdmin BIT = $PlatformControlsAdmin
DECLARE @ProcessOversightAdmin BIT = $ProcessOversightAdmin
DECLARE @QAAdmin BIT = $QAAdmin
DECLARE @ThirdPartyAdmin BIT = $ThirdPartyAdmin
DECLARE @WrapperAdmin BIT = $WrapperAdmin
DECLARE @StrategyAdmin BIT = $StrategyAdmin
DECLARE @ServiceDeliveryManager BIT = $ServiceDeliveryManager
DECLARE @UserImpersonationAdmin BIT = $UserImpersonationAdmin
DECLARE @VendorManager BIT = $VendorManager
DECLARE @TechnicalManager BIT = $TechnicalManager
DECLARE @Finance BIT = $Finance
DECLARE @PensionsSupport BIT = $PensionsSupport;

/* Insert selected roles into temp table */

DECLARE @Roles TABLE (RoleID INT NOT NULL)
IF @FirmAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (3) --  FirmAdmin 
END;

IF @OperationManager = 1
BEGIN
INSERT INTO @Roles VALUES (14) -- OperationManager
END;

IF @ARFirmManager = 1
BEGIN
INSERT INTO @Roles VALUES (15) -- ARFirmManager
END;

IF @DocumentManager = 1
BEGIN
INSERT INTO @Roles VALUES (19) -- DocumentManager
END;

IF @AccountOpenAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (20) -- AccountOpenAdmin 
END;

IF @AccountOpenSeniorAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (21) -- AccountOpenSeniorAdmin
END;

IF @OpsManager = 1
BEGIN
INSERT INTO @Roles VALUES (22) -- OpsManager
END;

IF @AccountClosureAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (23) -- AccountClosureAdmin
END;

IF @FundingAdmin = 1 
BEGIN
INSERT INTO @Roles VALUES (24) -- FundingAdmin
END;

IF @StaticDataAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (25) -- StaticDataAdmin
END;

IF @TradingAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (26) -- TradingAdmin
END;

IF @TransfersAdmin = 1 
BEGIN
INSERT INTO @Roles VALUES (27) -- TransfersAdmin
END;

IF @ProjectsAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (28) -- ProjectsAdmin
END;

IF @ProjectsManager = 1
BEGIN
INSERT INTO @Roles VALUES (29) -- ProjectsManager
END;

IF @PlatformControlsAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (30) -- PlatformControlsAdmin
END;

IF @ProcessOversightAdmin = 1 
BEGIN
INSERT INTO @Roles VALUES (31) -- ProcessOversightAdmin
END; 

IF @QAAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (32) -- QAAdmin
END;

IF @ThirdPartyAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (34) -- ThirdPartyAdmin
END;

IF @WrapperAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (35) -- WrapperAdmin
END;

IF @StrategyAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (36) -- StrategyAdmin
END;

IF @ServiceDeliveryManager = 1
BEGIN
INSERT INTO @Roles VALUES (40) -- ServiceDeliveryManager
END;

IF @UserImpersonationAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (41) -- UserImpersonationAdmin
END;

IF @VendorManager = 1
BEGIN
INSERT INTO @Roles VALUES (42) -- VendorManager
END;

IF @TechnicalManager = 1
BEGIN
INSERT INTO @Roles VALUES (43) -- TechnicalManager
END;

IF @Finance = 1
BEGIN
INSERT INTO @Roles VALUES (44) -- Finance
END;

IF @PensionsSupport = 1
BEGIN
INSERT INTO @Roles VALUES (45) -- PensionsSupport
END;

/* Find UserID */
DECLARE @UserID AS INT = (SELECT UserID FROM dbo.tblUser WHERE Forename = @Forename AND Surname = @Surname);

/* Throw error if UserID is null */
IF @UserID IS NULL
BEGIN
    SELECT 'No user was found with this name, please check variable input' [Error]
    RETURN;
END;

/* Select current user's permissions */
Select 
	u.forename + '  ' + u.surname [User],
	ur.RoleID,
	r.RoleName [Current Permissions],
    CASE WHEN 
	r.roleID IN (1,2,37,38,39) THEN 'Admin Role' 
    WHEN r.roleID IN (3,14,15,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,40,41,42,43,44,45) THEN 'Non Admin - Requires DLP'
    ELSE 'Non Admin Role' END [Is Admin Role?]
from 
	tblUserRole ur 
	inner join tbluser u on ur.userId = u.userID 
	inner join tblrole r on ur.roleID = r.roleID
Where 
	u.userID = @UserID;

/* Delete any admin user permissions for user */
DELETE
FROM
	dbo.tblUserRole
WHERE
	UserID = @UserID AND
    (
        RoleID NOT IN (SELECT RoleID FROM @Roles) 
		AND RoleID NOT IN  
        (4,5,6,7,8,9,10,11,12,13,16,17,18)
        );

/* Select requested permissions */
Select 
	u.forename + '  ' + u.surname [User],
	r.roleID [Role ID],
	r.RoleName [Requested Permissions],
    CASE WHEN 
	r.roleID IN (1,2,37,38,39) THEN 'Admin Role' 
    WHEN r.roleID IN (3,14,15,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,40,41,42,43,44,45) THEN 'Non Admin - Requires DLP'
    ELSE 'Non Admin Role' END [Is Admin Role?]
from 
	tbluser u, 
	@roles ro
	inner join tblrole r on ro.roleID = r.roleID
Where 
	u.userID = @UserID
	and r.roleID in (select ro.roleID from @roles ro);
	    
/* Insert requested permissions into tbluserrole for user */			    
INSERT INTO dbo.tblUserRole
	(UserID, RoleID, PlatformID, CreatedByDate, CreatedByUserID, ModifiedByDate, ModifiedByUserID, MemberID, UserGUID)
SELECT
	u.UserID, r.RoleID, 1, GETDATE(), u.UserID, GETDATE(), u.UserID, u.MemberID, u.UserGUID
FROM
	dbo.tblUser AS u
	INNER JOIN dbo.tblRole AS r ON
		r.RoleID IN (SELECT RoleID FROM @Roles)
WHERE
	u.UserID = @UserID AND
	NOT EXISTS (SELECT NULL FROM dbo.tblUserRole WHERE UserID = u.UserID AND RoleID = r.RoleID);

/* Select all permissions for user */
Select 
	u.forename + '  ' + u.surname [User],
	ur.roleID [Role ID],
	r.RoleName [Final Permissions],
    CASE WHEN 
	r.roleID IN (1,2,37,38,39) THEN 'Admin Role' 
    WHEN r.roleID IN (3,14,15,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,40,41,42,43,44,45) THEN 'Non Admin - Requires DLP'
    ELSE 'Non Admin Role' END [Is Admin Role?]
from 
	tblUserRole ur 
	inner join tbluser u on ur.userId = u.userID 
	inner join tblrole r on ur.roleID = r.roleID
Where 
	u.userID = @UserID;

/* Commit transaction if switch is true */
IF @commitTransaction = 1
    COMMIT
ELSE
    ROLLBACK
"@;

Write-Host "Running on: $env:COMPUTERNAME"

Install-Module -Name sqlserver -AllowClobber -Scope AllUsers -Force
Import-Module sqlserver

$builderoutput = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$builderoutput.Password = '********'
Write-Host "ConnectionString: $($builderoutput.ConnectionString)"

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$ServerInstance = $($builder['Data Source'])
if ($ServerInstance -like 'tcp:*') { $ServerInstance = $ServerInstance.split(':')[1] }
if ($ServerInstance -like '*1433') { $ServerInstance = $ServerInstance.TrimEnd(", 1433") }
Write-Host "ServerInstance: $ServerInstance"

$nettest = Test-NetConnection $ServerInstance -Port 1433
if ($nettest.TcpTestSucceeded -ne $True) {
    Write-Host "Connection to SQL Instance failed"; Exit 1
}
Else {
    if ($true -eq $SARequired) {
        Write-Host "Using SA Credentials"
        $builder.'User ID' = $dbuser
        $builder.Password = $dbpassword
        $ConnectionString = $builder.ConnectionString
    }

    Write-Host "Invoking SqlCmd..."
    Write-Host "Executing sql query"
    try {
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection;
        $SqlConnection.ConnectionString = $ConnectionString;

        $SqlCommand = New-Object System.Data.SqlClient.SqlCommand;
        $SqlCommand.CommandText = $CommandText;
        $SqlCommand.Connection = $SqlConnection;

        $SqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
        $SqlDataAdapter.SelectCommand = $SqlCommand;

        $DataSet = New-Object System.Data.DataSet;

        $SqlConnection.Open();
        $SqlDataAdapter.Fill($DataSet) | Out-Null;
        $SqlConnection.Close();
        $SqlConnection.Dispose();

        $DataSet.Tables[0] | Export-Csv -NoTypeInformation -Path 'C:\Temp\CurrentPermissionsOutput.csv';
        $DataSet.Tables[1] | Export-Csv -NoTypeInformation -Path 'C:\Temp\RequestedPermissionsOutput.csv';
        $DataSet.Tables[2] | Export-Csv -NoTypeInformation -Path 'C:\Temp\FinalPermissionOutput.csv';

        if ($CommitTransaction -eq 0){
        New-OctopusArtifact -Path "C:\Temp\CurrentPermissionsOutput.csv" -Name "FusionCurrentPermissionOutput.csv"
        New-OctopusArtifact -Path "C:\Temp\RequestedPermissionsOutput.csv" -Name "FusionRequestedPermissionOutput.csv"
        }
        elseif ($CommitTransaction -eq 1) 
        {
        New-OctopusArtifact -Path "C:\Temp\FinalPermissionOutput.csv" -Name "FusionFinalPermissionOutput.csv"
        }
    }
    catch { Write-Error $error[0].Exception }
        
}
