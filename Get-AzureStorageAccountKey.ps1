<#
.SYNOPSIS
    Retrieve Azure Storage Account Key and set as Octopus Variable
.DESCRIPTION
    For the specified Azure Resource Group and Storage Account Name
    Retrieve the Azure Storage Account Key and set as an Octopus Variable.
.EXAMPLE
    # from package in an Octopus Step
    Script file: Get-AzureStorageAccountKey.ps1
    Script params: -resourceGroupName #{StorageResourceGroupName} -storageAccountName #{StorageAccountName} -octopusVariableNameToSet #{StorageAccountAccessKey_VarName}
#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory)]
    [string]
    $resourceGroupName,

    [Parameter(Mandatory)]
    [string]
    $storageAccountName,

    [Parameter(Mandatory)]
    [string]
    $octopusVariableNameToSet

)

function Login-toAzure {
    param (
        $clientpassword,
        $clientid,
        $azureenvironment,
        $tenantid,
        $subscriptionid
    )
    
    $securePassword = ConvertTo-SecureString $clientpassword -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ($clientid, $securePassword)
    $azEnv = if ($azureenvironment) { $azureenvironment } else { "AzureCloud" }

    $azEnv = Get-AzEnvironment -Name $azEnv
    if (!$azEnv) {
        Write-Error "No Azure environment could be matched given the name $($azureenvironment)"
        exit -2
    }

    Write-Verbose "Authenticating with Service Principal"

    Login-AzAccount -Credential $creds -TenantId $tenantid -SubscriptionId $subscriptionid -Environment $azEnv -ServicePrincipal
}

Write-Host "Running on: $env:COMPUTERNAME"

Login-toAzure `
-clientpassword $OctopusParameters["AzAccount.Password"] `
-clientid $OctopusParameters["AzAccount.Client"] `
-azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
-tenantid $OctopusParameters["AzAccount.TenantId"] `
-subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]


if (-not (Get-AzResourceGroup | Where-Object ResourceGroupName -eq $resourceGroupName)) {
    Write-Warning "${resourceGroupName} does not exist!"
}

if (-not (Get-AzStorageAccount -ResourceGroupName $resourceGroupName | Where-Object StorageAccountName -eq $storageAccountName)) {
    Write-Warning "$storageAccountName does not exist!"
}

$SAAccessKey = (Get-AzStorageAccountKey -ResourceGroupName "$resourceGroupName" -Name "$storageAccountName").Value[0]

Write-Output "Setting StorageAccount AccessKey to Variable Name: $octopusVariableNameToSet, for: $storageAccountName"

Set-OctopusVariable -name $octopusVariableNameToSet -value "$SAAccessKey" -Sensitive
