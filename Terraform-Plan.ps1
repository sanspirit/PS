<#
.SYNOPSIS
    Runs Terraform Plan

.DESCRIPTION
    Terraform plan for a given directory

.EXAMPLE
    .\Terraform-Plan.ps1 -terraformDirectoryPath "D:\"
#>

[CmdletBinding()]
param(
    # The path to the Terraform code
    [Parameter(Mandatory = $True)]
    [string]
    $terraformDirectoryPath,

    [Parameter(Mandatory = $false)]
    [bool]
    $UseServicePrincipal,

    [Parameter(Mandatory = $True)]
    [string]
    $UseAzureStorageForPlan
)

# Construction of variables
$terraformDirectoryPathMain = Join-Path -Path $terraformDirectoryPath -ChildPath "\main.tf"
$terraformDirectoryPath

# Plan files with dates to allow for multiple runs of the same release within the same day.
$plantime = get-date -format "dd.MM.yy-HH.mm"
$planfileRAW = $OctopusParameters["Octopus.Project.Name"] +  "-" + $OctopusParameters["Octopus.Release.Number"] + "-" + $plantime + ".tfplan"
$transcriptfileRAW = $OctopusParameters["Octopus.Project.Name"] +  "-" + $OctopusParameters["Octopus.Release.Number"] + "-" + $plantime + ".txt"

# Substituting spaces with _
$planfile = $planfileRAW -replace ('\s', '_')
$transcriptfile = $transcriptfileRAW -replace ('\s', '_')

# A generalisation of the plafile name without dates that will be uploaded to Azure for later use.
$uploadPath = $OctopusParameters["hub_name"] + "/" + $OctopusParameters["azure.env_name"] + "/"
# Removing the date/time from teh file name as these plans will be stored on a per release basis.
$uploadFileNameRAW = $uploadPath + $OctopusParameters["Octopus.Project.Name"] + "-" + $OctopusParameters["Octopus.Release.Number"] + ".tfplan"
# Substituting spaces with _
$uploadFileName = $uploadFileNameRAW -replace ('\s', '_')

If(Test-Path $terraformDirectoryPathMain) {

    if ($UseServicePrincipal -eq $true) {
        Write-Output "Setting environment variables for service principal"
        $env:ARM_CLIENT_ID = $OctopusParameters["AzAccount.Client"]
        $env:ARM_CLIENT_SECRET = $OctopusParameters["AzAccount.Password"]
        $env:ARM_SUBSCRIPTION_ID = $OctopusParameters["AzAccount.SubscriptionNumber"]
        $env:ARM_TENANT_ID = $OctopusParameters["AzAccount.TenantId"]
    }

    Set-Location -Path $terraformDirectoryPath
    Write-Output "Set location to: $terraformDirectoryPath, running terraform plan"

    # Start the Terraform init and plan processes
    terraform --version
    terraform init -no-color

    # Using Go Util to upload planfile to Azure Storage
    if ($UseAzureStorageForPlan -eq "true") {
        New-Item -Path $transcriptfile
        terraform plan -no-color -out $planfile | Set-Content -Path $transcriptfile
        # Uploading the plan file
        Write-Output "Uploading TF Plan file: $uploadFileName to Azure Storage"
        store-terraform-plan --account-name $OctopusParameters["tfplan.azure_storage_account_name"] --account-key $OctopusParameters["tfplan.azure_storage_account_key"] --plan-file $planfile --container-name $OctopusParameters["tfplan.azure_storage_container_name"] --blob-name $uploadFileName
        # Presenting the plan as an artifact for Octopus
        Write-Output "Forming Octopus Artifacts"       
        New-OctopusArtifact -Path $transcriptfile -Name $transcriptfile
        New-OctopusArtifact -Path $planfile -Name "Plan.tfplan"   
    } else {
        New-Item $planfile
        terraform plan -no-color | Set-Content -Path $planfile
        # Presenting the plan as an artifact for Octopus
        Write-Output "Forming Octopus Artifacts"
        New-OctopusArtifact -Path $planfile -Name $planfile
    }
} Else { 
    Write-Error "This directory does not contain terraform files"
    exit -2
}
