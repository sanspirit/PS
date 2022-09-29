<#
.SYNOPSIS
    Queries Octopus for the first numbered machine in the given role
.DESCRIPTION
    Queries Octopus for the first numbered machine in the given role given a substring location of (8,1) for the number

.EXAMPLE
    .\src\Get-FirstMachineinRole.ps1 -apikey 'API-xxx' -role "BS-Web"
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $apikey,

    [Parameter()]
    [string]
    $role
)

$apiKey = ($OctopusParameters['System.api.key'])
$Header =  @{ "X-Octopus-ApiKey" = $apiKey }

$response = Invoke-RestMethod -Method GET -Uri "https://octopus.ctazure.co.uk/api/Spaces-63/machines?take=300" -Headers $Header
$firstmachine = ($response.Items | Where-Object {$PSItem.Roles -in $role -and $PSItem.EnvironmentIds -in $OctopusParameters["Octopus.Environment.Id"]}).Name | Sort-Object {"$PSItem".Substring(8,1)} | Select-Object -First 1
Write-Host "PDF Virtual directory master is $firstmachine"
Set-Octopusvariable -name "FirstMachineinRole" -value $firstmachine
