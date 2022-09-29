<#
.SYNOPSIS
    Runs Terraform Plan

.DESCRIPTION
    Terraform apply for a given directory

.EXAMPLE
    .\Terraform-Apply.ps1 -terraformDirectoryPath "D:\"
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

# The constructed name and location of the plan file for this release to be obtained from Azure Storage.
$uploadPath = $OctopusParameters["hub_name"] + "/" + $OctopusParameters["azure.env_name"] + "/"
$uploadFileNameRAW = $uploadPath + $OctopusParameters["Octopus.Project.Name"] + "-" + $OctopusParameters["Octopus.Release.Number"] + ".tfplan"
$uploadFileName = $uploadFileNameRAW -replace ('\s', '_')

If(Test-Path $terraformDirectoryPathMain) {

    if ($UseServicePrincipal -eq $true) {
        Write-Output "Setting environment variables for service principal"
        $env:ARM_CLIENT_ID = $OctopusParameters["AzAccount.Client"]
        $env:ARM_CLIENT_SECRET = $OctopusParameters["AzAccount.Password"]
        $env:ARM_SUBSCRIPTION_ID = $OctopusParameters["AzAccount.SubscriptionNumber"]
        $env:ARM_TENANT_ID = $OctopusParameters["AzAccount.TenantId"]
    }

    # Terraform init and version print are common actions regardless of tfplan file source.
    Set-Location -Path $terraformDirectoryPath
    terraform --version
    terraform init -no-color

    if ($UseAzureStorageForPlan -eq "true") {
        Write-Output "Pulling TF plan from azure blob cttfstate [tfplan] $uploadFileName"
        retrieve-terraform-plan --account-name $OctopusParameters["tfplan.azure_storage_account_name"] --account-key $OctopusParameters["tfplan.azure_storage_account_key"] --plan-file "terraform.tfplan" --container-name $OctopusParameters["tfplan.azure_storage_container_name"] --blob-name $uploadFileName

        # For confidence we are going to print the terraform plan output into the logs for the moment until we know the process works. 
        Write-Output "Set location to: $terraformDirectoryPath, running terraform apply"
        terraform apply -auto-approve -no-color "terraform.tfplan"
    } else {
        Write-Output "Set location to: $terraformDirectoryPath, running terraform apply"
        terraform apply -auto-approve -no-color
    }
}
Else { 
    Write-Error "This directory does not contain terraform files"
    exit -2
}
