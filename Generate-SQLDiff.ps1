<#
.SYNOPSIS
    Generates a SQL script with changes to deploy
.DESCRIPTION
    Uses a dacpac to generate a delta between two database schemas, this script will output the generated file as a .sql file ready to be deployed to the target database
.EXAMPLE
    .\Generate-SQLDiff.ps1
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory=$true)]
    [string]
    $deploymentPath,

    [Parameter(Mandatory=$true)]
    [string]
    $connectionString,

    [Parameter(Mandatory=$true)]
    [string]
    $DacPacName,

    [Parameter(Mandatory=$true)]
    [string]
    $DbUser,

    [Parameter(Mandatory=$true)]
    [string]
    $DbPw
)
$ErrorActionPreference = "Stop"

# Set Variables and output to host

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -argumentlist $connectionString
$DbName = $($builder['Initial Catalog'])
$ServerInstance = $($builder['Data Source'])

Write-Host "Generating Deploy Script"
Write-Host "Server Instance: $ServerInstance"
Write-Host "DB Name: $DbName"
Write-Host "DB User: $DbUser"
Write-Host "DeploymentPath: $deploymentPath"

# Validate Publish Profile path

$dbPublishProfile = 
    if (Test-Path "$deploymentPath\$DacPacName.publish.xml") {$DacPacName}
    elseif (Test-Path "$deploymentPath\DatabaseTESTAutoDeploy.publish.xml") {"DatabaseTESTAutoDeploy"}
    else {Write-Error "No Publish Profile found in package"}
Write-Host "PublishProfile File name: $dbPublishProfile"

# Add the DLL

$dllpath = (Get-ChildItem -Path 'C:\Program Files\Microsoft SQL Server' | Where-Object {$PSItem.name -Match '^(\d*)$'} | Sort-Object {[int]($PSItem.Name)} -Descending | Select-Object -First 1).FullName + "\DAC\bin\Microsoft.SqlServer.Dac.dll"
if (!(Test-Path $dllpath)) { Write-Error "DAC Dll path not found: $dllpath" }
Add-Type -path $dllpath

# Set DacPac paths
$dacpac = "$deploymentPath\$DacPacName.dacpac"
$dacpacOptions = "$deploymentPath\$dbPublishProfile.publish.xml"
    
Write-Host "DacPac path: $dacpac"
Write-Host "DacPac Options path: $dacpacOptions"

#Open Connection
$d = New-Object Microsoft.SqlServer.Dac.DacServices ("server=$ServerInstance;User ID=$DbUser;Password=$DbPw")

#Load Dacpac
$dp = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpac)
    
#Read a publish profile XML to get the deployment options
$dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($dacpacOptions)
$file = "$deploymentPath\GeneratedSQL.sql"

# Override DacPac Deploy Options, do not Script DB Options (Alter Database statements) will break when using managed SQL. 
$dacProfile.DeployOptions.ScriptDatabaseOptions = $false

# Deploy the dacpac
try {
    Write-Host "Script generation beginning and outputting to $deploymentPath\GeneratedSQL.sql"
    $sqlcontent = $d.GenerateDeployScript($dp, $DbName, $dacProfile.DeployOptions) 
    $sqlcontent | Out-File $file
    Set-Octopusvariable -name "SqlGeneratedScript" -value $sqlcontent
    New-OctopusArtifact -Path $file -Name "GeneratedSQL.sql"
    Write-Host "Script generated successfully"
}
catch {
    Write-Host 'Error is' $PSItem
    Write-Host 'Error FullName is' $PSItem.GetType().FullName
    Write-Host 'Error Exception is' $PSItem.Exception
    Write-Host 'Error Exception FullName is' $PSItem.Exception.GetType().FullName
    Write-Host 'Error Exception Message is' $PSItem.Exception.Message
    exit 1
}
