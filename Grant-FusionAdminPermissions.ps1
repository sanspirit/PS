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
    [Parameter(Mandatory)] [string] $GlobalAdmin,
    [Parameter(Mandatory)] [string] $PlatformAdmin,
    [Parameter(Mandatory)] [string] $CustomerServicesAdmin,
    [Parameter(Mandatory)] [string] $CustomerServicesManager,
    [Parameter(Mandatory)] [string] $CustomerSupportAdmin,
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
DECLARE @GlobalAdmin BIT = $GlobalAdmin
DECLARE @PlatformAdmin BIT = $PlatformAdmin
DECLARE @CustomerServicesAdmin BIT = $CustomerServicesAdmin
DECLARE @CustomerServicesManager BIT = $CustomerServicesManager
DECLARE @CustomerSupportAdmin BIT = $CustomerSupportAdmin;

/* Insert selected roles into temp table */

DECLARE @Roles TABLE (RoleID INT NOT NULL)
IF @GlobalAdmin = 1 
BEGIN 
INSERT INTO @Roles VALUES (1) --  GlobalAdmin
END;

IF @PlatformAdmin = 1 
BEGIN
INSERT INTO @Roles VALUES (2) --  PlatformAdmin 
END;

IF @CustomerServicesAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (37) -- CustomerServicesAdmin
END;

IF @CustomerServicesManager = 1
BEGIN
INSERT INTO @Roles VALUES (38) -- CustomerServicesManager
END;

IF @CustomerSupportAdmin = 1
BEGIN
INSERT INTO @Roles VALUES (39) -- CustomerSupportAdmin
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
        (3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,40,41,42,43,44,45)
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
