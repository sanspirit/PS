<#
.SYNOPSIS
    Replaces a connection string in an xml file.
.DESCRIPTION
    Replaces a connection string in an xml file
.EXAMPLE
    #
    .\src\Replace-ConnectionString.ps1 -ConfigFile "F:\AppPath\Web.config" -ConnectionstringName "AppName" -NewConnectionstring "Initial Catalog=DBName;Data Source=SQLServer;User ID=DBLogin;Password=DBPassword;MultipleActiveResultSets=True;persist security"
    #>

[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $ConfigFile,

    [Parameter()]
    [string]
    $ConnectionstringName,

    [Parameter()]
    [string]
    $NewConnectionstring
)

Write-Verbose "Config file is: $ConfigFile"
[xml]$content = Get-Content $ConfigFile
$con = $content.configuration.connectionStrings.add | Where-Object {$PSItem.name -eq "$ConnectionstringName"}
Write-Verbose "Current connectionstring: $($con.connectionString)"
Write-Verbose "New connectionstring: $NewConnectionstring"
Write-Host "Replacing Connection String with Name:$ConnectionstringName"
$con.connectionString = $NewConnectionstring
$content.Save($ConfigFile)
