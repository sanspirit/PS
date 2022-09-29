<#
.SYNOPSIS
    Deploys an Azure Web App
.DESCRIPTION
    Deploys an Azure Web App using the Kudo Zip Deploy approach.
    WebApp and associated components (Resource Group etc) must already exist
.EXAMPLE
    .\Deploy-WebApp.ps1 `
    -resourceGroupName "resourceGroup1" `
    -webAppName "WebApp1" `
    -webAppZipContentPath "./src/webapp1/bin/Release/netcoreapp3.1/*" `
    -slotName "Blue"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True)] [string] $resourceGroupName, # Azure RG housing the WebApp (Must exist prior to this)
    [Parameter(Mandatory = $True)] [string] $webAppName, # Name of the WebApp being deployed
    [Parameter(Mandatory = $True)] [string] $webAppZipContentPath, # Path to the unzipped content
    [Parameter(Mandatory = $True)] [string] $slotName # Name of the deployment slot e.g. Blue or Production
)

mkdir "./zip-output"
$zipFile = "./zip-output/$($webAppName).zip"

# Create Zip
try {
    Write-Host "Zipping WebApp contents to $($webAppZipContentPath)"
    7z a $zipFile $webAppZipContentPath
}
catch {
    Write-Host "Failed to create WebApp Zip - $($_)"
    Exit $LASTEXITCODE
}

# Deploy Zip
Write-Host "Deploying WebApp Zip to WebApp $($webAppName) in Resource Group $($resourceGroupName)"
az webapp deployment source config-zip --src $zipFile --name $webAppName --resource-group $resourceGroupName --slot $slotName
if ($LASTEXITCODE) {
    Write-Host "Failed to deploy WebApp Zip $($zipFile) to WebApp $($webAppName)"
    Remove-Item -Path $zipFile -Force
    Remove-Item -Path "./zip-output" -Force
    Exit $LASTEXITCODE
}

# Delete Zip remnants
Remove-Item -Path $zipFile -Force
Remove-Item -Path "./zip-output" -Force
