<#
.SYNOPSIS
    This script grants Enable elevated permissions
.DESCRIPTION
    Runs in the User Access Provisioning runbook in Octopus, to allow devs and QAs to request elevated permissions for Enable testing.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $ConnectionString,

    [Parameter(Mandatory)]
    [bool]
    $SARequired,

    [Parameter(Mandatory)]
    [string]
    $dbuser,

    [Parameter(Mandatory)]
    [string]
    $dbpassword,

    [Parameter(Mandatory)]
    [int]
    $querytimeout,

    [Parameter(Mandatory)]
    [string]
    $forename,

    [Parameter(Mandatory)]
    [string]
    $surname,

    [Parameter(Mandatory)]
    [string]
    $CommissionInput,

    [Parameter(Mandatory)]
    [string]
    $Compliance,

    [Parameter(Mandatory)]
    [string]
    $ComplianceManager,

    [Parameter(Mandatory)]
    [string]
    $FinanceOfficer,

    [Parameter(Mandatory)]
    [string]
    $GlobalAdministrator,

    [Parameter(Mandatory)]
    [string]
    $NetworkAdministrator,

    [Parameter(Mandatory)]
    [string]
    $WebServiceUser,

    [Parameter(Mandatory)]
    [string]
    $CommitTransaction
)

$CommandText = @"

BEGIN TRANSACTION

DECLARE @commitTransaction BIT = $CommitTransaction;

DECLARE
@WORKERID INT =
(
        SELECT
            W.WorkerID
        FROM
            tblWorkers W
        WHERE
            W.Forename = '$forename'		/* Worker Forename as it appears on Enable */
            AND W.Surname = '$surname'		/* Worker Surname as it appears on Enable */
            AND W.MemberID = 369
);

IF @WORKERID IS NULL
BEGIN
    SELECT 'No user was found with this name, please check variable input' [Error];
    RETURN;
END;

SELECT 
    'Current Permissions'
	,w.forename
	,w.surname
	,w.memberID
    ,m.member
	,w.CommissionInput
	,w.FinanceOfficer
	,w.Compliance
	,w.ComplianceManager
	,w.NetworkAdministrator
	,w.Administrator 
	,w.IsWebServiceUser
FROM 
    tblworkers w
    INNER JOIN tblMember M ON w.MemberID = M.MemberID
WHERE
    w.WorkerID = @WORKERID
    AND W.Archive = 0 
    AND M.Archive = 0;

UPDATE 
    w
SET 
	 w.CommissionInput      = $CommissionInput				/* For fee's, commission etc. */
	,w.FinanceOfficer       = $FinanceOfficer				/* DONT USE UNLESS INSTRUCTED */
	,w.Compliance           = $Compliance			        /* Some tasks under compliance tab */
	,w.ComplianceManager    = $ComplianceManager			/* Compliance Manager on Enable */
	,w.NetworkAdministrator = $NetworkAdministrator			/* Network Admin on ENABLE */
	,w.Administrator        = $GlobalAdministrator  		/* Global Admin on Enable Only Granted when InfoSec/Senior Manager Has Confirm It's Needed */
    ,w.IsWebServiceUser     = $WebServiceUser				/* Enable API Access */
FROM 
    tblworkers w
    INNER JOIN tblMember M ON w.MemberID = M.MemberID
WHERE
    w.WorkerID = @WORKERID
    AND W.Archive = 0 
    AND M.Archive = 0;

    SELECT 
    'Requested Permissions'
    ,w.forename
	,w.surname
	,w.memberID
    ,m.member
	,w.CommissionInput
	,w.FinanceOfficer
	,w.Compliance
	,w.ComplianceManager
	,w.NetworkAdministrator
	,w.Administrator 
	,w.IsWebServiceUser
FROM 
    tblworkers w
    INNER JOIN tblMember M ON w.MemberID = M.MemberID
WHERE
    w.WorkerID = @WORKERID
    AND W.Archive = 0 
    AND M.Archive = 0;

    SELECT 
    'Final Permissions'
    ,w.forename
	,w.surname
	,w.memberID
    ,m.member
	,w.CommissionInput
	,w.FinanceOfficer
	,w.Compliance
	,w.ComplianceManager
	,w.NetworkAdministrator
	,w.Administrator 
	,w.IsWebServiceUser
FROM 
    tblworkers w
    INNER JOIN tblMember M ON w.MemberID = M.MemberID
WHERE
    w.WorkerID = @WORKERID
    AND W.Archive = 0 
    AND M.Archive = 0;

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

        $DataSet.Tables[0] | Export-Csv -NoTypeInformation -Path 'C:\Temp\EnableCurrentPermissionsOutput.csv';
        $DataSet.Tables[1] | Export-Csv -NoTypeInformation -Path 'C:\Temp\EnableRequestedPermissionOutput.csv';
        $DataSet.Tables[1] | Export-Csv -NoTypeInformation -Path 'C:\Temp\EnableFinalPermissionOutput.csv';

        if ($CommitTransaction -eq 0){
        New-OctopusArtifact -Path "C:\Temp\EnableCurrentPermissionsOutput.csv" -Name "EnableCurrentPermissionsOutput.csv"
        New-OctopusArtifact -Path "C:\Temp\EnableRequestedPermissionOutput.csv" -Name "EnableRequestedPermissionOutput.csv"
        }
        elseif ($CommitTransaction -eq 1) 
        {
        New-OctopusArtifact -Path "C:\Temp\EnableFinalPermissionOutput.csv" -Name "EnableFinalPermissionOutput.csv"
        }
    }
    catch { Write-Error $error[0].Exception }
        
}
