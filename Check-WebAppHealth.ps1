<#
.SYNOPSIS
    Checks the health of a Webapp by curling the known URL and healthcheck file. 
.DESCRIPTION
    Used as part of the webapp release process to guage confidence in output. 
.EXAMPLE
    .\Check-WebAppHealth.ps1 -webApp "NA-mattdemo-slots
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True)] [string] $webApp, # Name of the webApp being checked
    [Parameter(Mandatory = $False)] [string] $healthCheckQuery # Name of the webApp being checked
)

$ErrorActionPreference = "Continue"
# Building up of application Urls 
$domain = "azurewebsites.net" # default Microsoft App Service hosted domain name
if (!$healthCheckQuery) {
    $greenUrl = "https://$($webApp.ToLower()).$($domain)" # Url of proudction slot
    $blueUrl = "https://$($webApp.ToLower())-blue.$($domain)" # url of blue slot
} else {
    $greenUrl = "https://$($webApp.ToLower()).$($domain)/$($healthCheckQuery)" # Url of proudction slot
    $blueUrl = "https://$($webApp.ToLower())-blue.$($domain)/$($healthCheckQuery)" # url of blue slot
}

# Create an array of Urls to check and add the above to it.
$Urls = [System.Collections.ArrayList]::new()
$Urls.Add($greenUrl)
$Urls.Add($blueUrl)

# Loop over each Url and check the return code status. 
foreach($Url in $Urls) {
    try {
        Write-Output "Checking health of $($webApp) at $($Url)..."
        $status = Invoke-WebRequest -Uri $Url -UseBasicParsing
    } catch {
        Write-Error "Unable to check health of $($webApp) at $($Url)"
    }

    if ($status.StatusDescription -eq "OK") {
        Write-Output "$($webApp) at $($url) is HEALTHY. Retruned status code: $($status.StatusCode)"
    } else {
        Write-Output "$($webApp) at $($url) is NOT healthy"
        exit $LASTEXITCODE
    }
}
