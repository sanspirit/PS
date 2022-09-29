<#
.SYNOPSIS
    Deploys Functions to a FunctionApp

.DESCRIPTION
    Deploys Functions to a FunctionApp using the Kudo Zip Deploy approach.
    FunctionApp and associated components (Resource Group etc) must already exist

.EXAMPLE
    .\Deploy-FunctionApp.ps1 `
    -resourceGroupName "resourceGroup1" `
    -functionAppName "FunctionApp1" `
    -functionZipContentPath "./src/functionapp1/bin/Release/netcoreapp3.1/*"
#>

[CmdletBinding()]
param(
    
    # The Azure Resource Group Name
    [Parameter(Mandatory = $True)]
    [string]
    $resourceGroupName,
    
    # The Azure FunctionApp Name
    [Parameter(Mandatory = $True)]
    [string]
    $functionAppName,
    
    # The path to the contents that should be Zipped for deployment
    [Parameter(Mandatory = $True)]
    [string]
    $functionZipContentPath
)

#### Helper Functions ####
function CheckLastExitCode {
    if ($LASTEXITCODE) {
        Exit
    } 
}

#### PROCESS ####
mkdir "./zip-output"
$zipFile = "./zip-output/$($functionAppName).zip"

#### Create ZIP File ####
try {
    Write-Host "Zipping Function contents to $($functionZipContentPath)"
    Compress-Archive -Path $functionZipContentPath -CompressionLevel Fastest -DestinationPath $zipFile -Force
}
catch {
    Write-Host "Failed to create Function Zip - $($_)"
    Exit
}
#########################

$ErrorActionPreference = 'SilentlyContinue'
#### DEPLOY ZIP ####
Write-Host "Deploying Function Zip to Function App $($functionAppName) in Resource Group $($resourceGroupName)"
az functionapp deployment source config-zip --src $zipFile --name $functionAppName --resource-group $resourceGroupName
if ($LASTEXITCODE) {
    Write-Host "Failed to deploy Function Zip $($zipFile) to FunctionApp $($functionAppName)"
    Exit
}
####################

#### Delete ZIP ####
Remove-Item -Path $zipFile -Force
Remove-Item -Path "./zip-output" -Force
####
