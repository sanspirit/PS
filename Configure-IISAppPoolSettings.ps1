<#
.SYNOPSIS
    Configures IIS app pool values
.DESCRIPTION
    Configures all of the neccessary IIS app pool values, these values will be set on each deployment

    Requires IISAdministration module and IIS installed
.EXAMPLE
    .\src\Configure-IISAppPoolSettings.ps1 -IISSitename "Enable"

#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True, Position = 0)]
    [string]
    $IISSitename
)

function Get-AppPoolFromSite {
    param (
        $sitename
    )

    $manager = Get-IISServerManager
    $website = $manager.Sites[$sitename]
    $apppool = $website.Applications["/"].ApplicationPoolName
    Write-Output $apppool
}

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

function Get-IISAppPoolValue {
    param (
        $apppoolname,
        $attributename
    )
    
    $ConfigSection = Get-IISConfigSection -SectionPath "system.applicationHost/applicationPools"
    $SitesCollection = Get-IISConfigCollection -ConfigElement $ConfigSection
    $apppool = Get-IISConfigCollectionElement -ConfigCollection $SitesCollection -ConfigAttribute @{"name" = $apppoolname}
    Get-IISConfigAttributeValue -ConfigElement $apppool -AttributeName $attributename
}

function Set-IISAppPoolValue {
    param (
        $apppoolname,
        $attributename,
        $attributevalue
    )
    
    $ConfigSection = Get-IISConfigSection -SectionPath "system.applicationHost/applicationPools"
    $SitesCollection = Get-IISConfigCollection -ConfigElement $ConfigSection
    $apppool = Get-IISConfigCollectionElement -ConfigCollection $SitesCollection -ConfigAttribute @{"name" = $apppoolname}
    Set-IISConfigAttributeValue -ConfigElement $apppool -AttributeName $attributename -AttributeValue $attributevalue
}

Import-Module IISAdministration

$attributenamelist = @{
    'StartMode' = 'AlwaysRunning'
    'Recycling.periodicRestart.schedule' = '00:00:00'
}

$apppoolname = Get-AppPoolFromSite -sitename $IISSitename

foreach ($a in $attributenamelist.GetEnumerator()) {

    $attributename = $a.name
    $attributevalue = $a.value

    if ('Recycling.periodicRestart.schedule' -eq $attributename) {
        
        $manager = Get-IISServerManager
        $pool = $manager.ApplicationPools[$apppoolname]
        
        $mins = Get-Random -Minimum 5 -Maximum 110
        $value = (New-TimeSpan -Hours 1 -Minutes $mins).ToString()
        
        if (0 -ne $pool.Recycling.PeriodicRestart.Time.TotalHours) {
           $pool.Recycling.PeriodicRestart.Time = "00:00:00"
        }
        
        $pool.Recycling.PeriodicRestart.Schedule.Clear()
        $pool.Recycling.PeriodicRestart.Schedule.Add($value) | Out-Null

        try {
            Write-Host "Setting App Pool recycle schedule time to $value"
            $manager.CommitChanges()
        }
        catch {
            Write-Host "exception caught setting App Pool recycle schedule time"
        }
        
    }
    elseif ($null -ne $attributename) {
        $currentvalue = Get-IISAppPoolValue -apppoolname $apppoolname -attributename $attributename
    
        if ($attributevalue -ne $currentvalue) {
            Write-Host "Setting: $attributename, current value:$currentvalue, new value:$attributevalue"
            Execute-WithRetry {
                Set-IISAppPoolValue -apppoolname $apppoolname -attributename $attributename -attributevalue $attributevalue
            }
        }
        else {
            Write-Host "No Change: $attributename, current value is $currentvalue"
       }
    }
}
