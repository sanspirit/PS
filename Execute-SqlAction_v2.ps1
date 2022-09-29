<#
.SYNOPSIS
    Execute a SQL file or query.
.DESCRIPTION
    Executes a sql file or query depending on $executetype variable
.EXAMPLE
    #
    .\src\Execute-SqlAction.ps1 -executetype 'query' -query 'SELECT * FROM [example]'
    .\src\Execute-SqlAction.ps1 -executetype 'file' -file C:\Path\file.sql
    #>
    [CmdletBinding()]
    Param (
    
        [Parameter(Mandatory)]
        [string]
        $ConnectionString,

        [Parameter(Mandatory)]
        [ValidateSet("query","file")]
        [string]
        $executetype,

        [Parameter()]
        [string]
        $query,

        [Parameter()]
        [string]
        $file,

        [Parameter(Mandatory)]
        [bool]
        $SARequired,

        [Parameter()]
        [Int32]
        $querytimeout,

        [Parameter()]
        [string]
        $DbUser,

        [Parameter()]
        [string]
        $DbPw
    )

Write-Host "Running on: $env:COMPUTERNAME"

Import-Module sqlserver

$builderoutput = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$builderoutput.Password = '********'
Write-Host "ConnectionString: $($builderoutput.ConnectionString)"

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$ServerInstance = $($builder['Data Source'])
if ($ServerInstance -like 'tcp:*') {$ServerInstance = $ServerInstance.split(':')[1]}
if ($ServerInstance -like '*1433') {$ServerInstance = $ServerInstance.TrimEnd(", 1433")}
Write-Host "ServerInstance: $ServerInstance"

if ($executetype -eq 'query') {
    Write-Host "Executing sql query"
    if ($true -eq $SARequired) {
        Write-Host "Using SA Credentials"
        try {
            Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $query -QueryTimeout $querytimeout -Username $DbUser -Password $DbPw
        }
        catch {Write-Error $error[0].Exception}
    }
    else {
        try {
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query -QueryTimeout $querytimeout
        }
        catch {Write-Error $error[0].Exception}
    }
}
elseif ($executetype -eq 'file') {
    Write-Host "Executing sql file"
    if ($true -eq $SARequired) {
        Write-Host "Using SA Credentials"
        try {
            Invoke-Sqlcmd -ServerInstance $ServerInstance -InputFile $file -QueryTimeout $querytimeout -Username $DbUser -Password $DbPw
        }
        catch {Write-Error $error[0].Exception}
    }
    else {
        try {
            Invoke-Sqlcmd -ConnectionString $ConnectionString -InputFile $file -QueryTimeout $querytimeout
        }
        catch {Write-Error $error[0].Exception}
    }
}
