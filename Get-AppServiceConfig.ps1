<#
.SYNOPSIS
    Obtains details of a given app service. Output is then saved to Octopus artifact.

.DESCRIPTION
    Connects to an app service and obtains details to present to Octopus for processing

.EXAMPLE
    .\Get-AppServiceConfig -siteName "wibble" -resourceGroupName "testResGroup" -slotName "blue" -subscriptionID "XXXX-XXXXX-XXXXXX-XXXXX-XXXX" 
#>

[CmdletBinding()]
param(
    # The path to the Terraform code
    [Parameter(Mandatory = $True)]
    [string]
    $subscriptionID,

    [Parameter(Mandatory = $True)]
    [string]
    $resourceGroupName,

    [Parameter(Mandatory = $True)]
    [string]
    $siteName,

    [Parameter(Mandatory = $True)]
    [string]
    $slotName
)

# Disabling the ANSI control characters on output
$PSStyle.OutputRendering = 'Plain'

$configTime = get-date -format "dd.MM.yy-HH.mm"
$configFile = $OctopusParameters["Octopus.Project.Name"] + "-" + $OctopusParameters["Octopus.Release.Number"] + "-" + $configTime + ".txt"

Write-Host "Setting environment variables for service principal"
$aToken = az account get-access-token | ConvertFrom-Json

$token = ConvertTo-SecureString($aToken.accessToken) -AsPlainText -Force 
$body = @{
	'preserveVnet' = ''
	'targetSlot' = ''
}

# Invoke the REST API
$restUri = "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$siteName/slots/$slotName/slotsdiffs?api-version=2019-08-01"
$response = Invoke-RestMethod -Uri $restUri -Authentication Bearer -Token $token -Method post -Body $body
$response.value.properties  | select-object -Property settingType, settingName, valueInCurrentSlot, valueInTargetSlot, description| out-file $configFile

# Save responses into Octopus artifact for verification
New-OctopusArtifact -Path $configFile -Name $configFile
