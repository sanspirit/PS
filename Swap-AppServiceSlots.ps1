<#
.SYNOPSIS
    Swaps two App Service Deployment slots
.DESCRIPTION
    Typicaly used to swap the 'blue' and 'production' slots of an App service.
.EXAMPLE
    .\Swap-AppServiceSlots.ps1 -webApp "NA-mattdemo-slots" -resourceGroupName "sandbox-in00-mattdemo-slots" -slotName "blue" -targetSlotName "production" 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True)] [string] $webApp, # Name of the WebApp
    [Parameter(Mandatory = $True)] [string] $resourceGroupName, # Name of the containing Resource Group
    [Parameter(Mandatory = $True)] [string] $slotName, # Name of the current slot
    [Parameter(Mandatory = $True)] [string] $targetSlotName # Name of the slow to swap to
)

# Initiate the slot swap
Write-Host "Swapping deployment slots of $($webApp) from $($slotName) to $($targetSlotName)"
az webapp deployment slot swap -g $resourceGroupName -n $webApp --slot $slotname --target-slot $targetSlotName

# Check the exit code of the slot swap and exit on error if failed. 
if ($LASTEXITCODE) {
    Write-Host "Failed to swap slots of $($webApp) from $($slotName) to $($targetSlotName)"
    Exit $LASTEXITCODE
}
