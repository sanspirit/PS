<#
.SYNOPSIS
    Checks and Updates a named AKS cluster to a given version

.DESCRIPTION
    Using the AZ command suites and an authenticated account into Azure, the process checks
    for a given kubernetes version being available for upgrade. If available the upgrade will deploy
    to the entire cluster.

.EXAMPLE
    .\Upgrade-AKS.ps1 `
    -resourceGroupName "resourceGroup1" `
    -clusterName "aksCluster" `
    -aks_version "1.22.6"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True)] [string] $resourceGroupName,
    [Parameter(Mandatory = $True)] [string] $clusterName,
    [Parameter(Mandatory = $True)] [string] $aksVersion
)

$WarningPreference = "SilentlyContinue"
$versionConfirmFlag=$false
$thisCluster=$(az aks get-upgrades --resource-group $resourceGroupName --name $clusterName | ConvertFrom-JSON)

# For ease of information printing, create a PSObject with current values to display as a table
Write-Output "AKS Upgrade process"
$obj = New-Object psobject -Property @{
    Cluster = $clusterName
    CurrentClusterVersion = $thisCluster.controlPlaneProfile.kubernetesVersion
    DesiredUpgradeVersion = $aksVersion
}

Write-Output $obj | Format-Table Cluster,CurrentClusterVersion,DesiredUpgradeVersion
Write-Output "Checking for available upgrade versions..."

foreach ($version in $thisCluster.controlPlaneProfile.upgrades) { 
    if ($aksVersion -match $version.kubernetesVersion) {
        $versionConfirmFlag=$true
    }
}
if ( $versionConfirmFlag ) {
    Write-Output "CONFIRMED: $($aksVersion) is available for upgrade"
    Write-Output "Commencing release of Upgrade to cluster"
    az aks upgrade --resource-group $resourceGroupName --name $clusterName --kubernetes-version $aksVersion
    Write-Output "COMPLETE: AKS Cluster upgrade process completed."
    az aks show --resource-group $resourceGroupName --name $clusterName --output table
} else {
    Write-Output "ERROR: Version $($aksVersion) cannot be found or is not available."
    exit 1
}
