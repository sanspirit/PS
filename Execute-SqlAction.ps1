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
        [string]
        $DbUser,

        [Parameter()]
        [string]
        $DbPw
    )

Write-Host "Running on: $env:COMPUTERNAME"

Install-Module -Name sqlserver -AllowClobber -Scope AllUsers -Force
Import-Module sqlserver

$builderoutput = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$builderoutput.Password = '********'
Write-Host "ConnectionString: $($builderoutput.ConnectionString)"

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $ConnectionString
$ServerInstance = $($builder['Data Source'])
if ($ServerInstance -like 'tcp:*') {$ServerInstance = $ServerInstance.split(':')[1]}
if ($ServerInstance -like '*1433') {$ServerInstance = $ServerInstance.TrimEnd(", 1433")}
Write-Host "ServerInstance: $ServerInstance"

$nettest = Test-NetConnection $ServerInstance -Port 1433
if ($nettest.TcpTestSucceeded -ne $True) {
    Write-Host "Connection to SQL Instance failed"; Exit 1
}
Else {
    if ($true -eq $SARequired) {
        Write-Host "Using SA Credentials"
        $builder.'User ID' = $DbUser
        $builder.Password = $DbPw
        $ConnectionString = $builder.ConnectionString
    }

	Write-Host "Invoking SqlCmd..."
    if ($executetype -eq 'query') {
        Write-Host "Executing sql query"
        try {
            Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query -QueryTimeout 1200
        }
        catch {Write-Error $error[0].Exception}
        
    }
    elseif ($executetype -eq 'file') {
        Write-Host "Executing sql file"
        try {
            Invoke-Sqlcmd -ConnectionString $ConnectionString -InputFile $file -QueryTimeout 1200
        }
        catch {Write-Error $error[0].Exception}
    }
}
