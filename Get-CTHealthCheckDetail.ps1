<#
.SYNOPSIS
    Gets the results from CtHealthCheckDetail
.DESCRIPTION
    Queries CtHealthCheckDetail for the specified site and outputs it 

.EXAMPLE
    .\src\Get-CTHealthCheckDetail.ps1 -environmentUrl "https://www.test1.com" -healthCheckDetailKey "xxx-123-xxx"

#>
[cmdletbinding()]
Param(
    
    [Parameter(Mandatory = $True)]
    [string]
    $environmentUrl,

    [Parameter(Mandatory = $True)]
    [string]
    $healthCheckDetailKey
)
$healthcheckUrl = "https://$environmentUrl/CtHealthCheckDetail"
Write-Host $healthcheckUrl
Write-host $healthCheckDetailKey 
$healthResponse = Invoke-RestMethod -Method Get -Uri $healthcheckUrl -Header @{ "X-HealthCheckDetail" = $healthCheckDetailKey }
Write-Host $healthResponse.OverallHealth
