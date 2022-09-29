<#
.SYNOPSIS
    Configures IIS site values
.DESCRIPTION
    Configures all of the neccessary IIS site values, these values will be set on each deployment

    Requires IISAdministration module and IIS installed
.EXAMPLE
    .\src\Configure-IISSiteSettings.ps1 -IISSitename "Enable" -PreloadEnabled "True"

#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True, Position = 0)]
    [string]
    $IISSitename,

    [Parameter()]
    [bool]
    $PreloadEnabled
)

function Execute-WithRetry([ScriptBlock] $command) {
    $attemptCount = 0
    $operationIncomplete = $true
    $maxFailures = 5
    $sleepBetweenFailures = 5

    while ($operationIncomplete -and $attemptCount -lt $maxFailures) {
        $attemptCount = ($attemptCount + 1)

        if ($attemptCount -ge 2) {
            Write-Host "Waiting for $sleepBetweenFailures seconds before retrying..."
            Start-Sleep -s $sleepBetweenFailures
            Write-Host "Retrying..."
        }

        try {
            # Call the script block
            & $command

            $operationIncomplete = $false
        } catch [System.Exception] {
            if ($attemptCount -lt ($maxFailures)) {
                Write-Host ("Attempt $attemptCount of $maxFailures failed: " + $_.Exception.Message)
            } else {
                throw
            }
        }
    }
}

function Get-IISSitePreloadValue {
    param (
        $sitename
    )
    
    $ConfigSection = Get-IISConfigSection -SectionPath "system.applicationHost/sites"
    $SitesCollection = Get-IISConfigCollection -ConfigElement $ConfigSection
    $Site = Get-IISConfigCollectionElement -ConfigCollection $SitesCollection -ConfigAttribute @{"name" = $sitename}
    $Elem = Get-IISConfigElement -ConfigElement $Site -ChildElementName "applicationDefaults"
    Get-IISConfigAttributeValue -ConfigElement $Elem -AttributeName "preloadEnabled"
}

function Set-IISSitePreloadValue {
    param (
        $sitename,
        $PreloadValue
    )
    
    $ConfigSection = Get-IISConfigSection -SectionPath "system.applicationHost/sites"
    $SitesCollection = Get-IISConfigCollection -ConfigElement $ConfigSection
    $Site = Get-IISConfigCollectionElement -ConfigCollection $SitesCollection -ConfigAttribute @{"name" = $sitename}
    $Elem = Get-IISConfigElement -ConfigElement $Site -ChildElementName "applicationDefaults"
    Set-IISConfigAttributeValue -ConfigElement $Elem -AttributeName "preloadEnabled" -AttributeValue $PreloadValue
}

Import-Module IISAdministration

if ($PreloadEnabled -ne $null) {
    $currentvalue = Get-IISSitePreloadValue -sitename $IISSitename
    if ($PreloadEnabled -ne $currentvalue) {
        Write-Host "Setting attribute:preloadEnabled current value:$currentvalue, new value:$PreloadEnabled"
        Execute-WithRetry {
            Set-IISSitePreloadValue $IISSitename -PreloadValue $PreloadEnabled
        }
    }
    else {
        Write-Host "No Change required, preloadEnabled current value is $currentvalue"
   }
}
