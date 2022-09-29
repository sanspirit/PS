<#
.SYNOPSIS
    Sets an Octopus variable 

.DESCRIPTION
    Deploys Functions to a FunctionApp using the Kudo Zip Deploy approach.
    FunctionApp and associated components (Resource Group etc) must already exist

.EXAMPLE
    .\JsonLookUp.ps1 `
    -JsonFileLocation "resourceGroup1" `
    -KeyName "FunctionApp1" `
    -octopusVariableNameToSet "./src/functionapp1/bin/Release/netcoreapp3.1/*"
#>

[CmdletBinding()]
param(
    
    # Path to json file
    [Parameter(Mandatory = $True)]
    [string]
    $JsonFileLocation,
    
    # Name of the key to lookup
    [Parameter(Mandatory = $True)]
    [string]
    $KeyName,

    # Parameter help description
    [Parameter(Mandatory = $True)]
    [string]
    $octopusVariableNameToSet
)

$jsoncontent = Get-Content -Raw -Path $JsonFileLocation
$json = $jsoncontent | Out-String | ConvertFrom-Json
$value = $json.psobject.properties.Where({$_.name -eq $KeyName}).value

Write-Output "Setting variable to be value of Json Key, KeyName: $KeyName, for Variable: $octopusVariableNameToSet, value is: $value "

Set-OctopusVariable -name $octopusVariableNameToSet -value "$value"

## Saves a copy of the json content in the TEMP location with encoding UTF-8 with no BOM to be used in Terraform Plan/Apply
$jsonpath = "$env:Temp\jsonoutput" + (Get-Date -Format ddMM_hhmmss) + ".json"

$content = Get-Content -Raw $JsonFileLocation
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines($jsonpath, $content, $Utf8NoBomEncoding)

Set-OctopusVariable -name $octopusFilecontentVarNameToSet -value $jsonpath
