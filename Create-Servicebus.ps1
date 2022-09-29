<#
.SYNOPSIS
    Creates a azure servicebus.
.DESCRIPTION
    Creates an azure servicebus using azure powershell. This will circle round and create a servicebus for each specified feature envs. 
.EXAMPLE
    .\src\Create-Servicebus -resouceGroupName "Development-DV10" -sku "standard" -tenantname "pyx" -ftenvs @("ft1","ft2")
#>

Param (

    [Parameter()]
    [string]
    $location = "northeurope",

    [Parameter()]
    [string]
    $namspacePrefix = "ct-servicebus",

    [Parameter()]
    [string]
    $resourceGroupName,

    [Parameter()]
    [string]
    $sku,

    [Parameter()]
    [array]
    $tenantnames,

    [Parameter()]
    [array]
    $ftenvs

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
$ErrorActionPreference = 'stop'

Login-toAzure `
-clientpassword $OctopusParameters["AzAccount.Password"] `
-clientid $OctopusParameters["AzAccount.Client"] `
-azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
-tenantid $OctopusParameters["AzAccount.TenantId"] `
-subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]

if (!(Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Resource group doesn't exist!"
}
else {
    foreach ($tenantname in $tenantnames) {
        $namespaceName = "${namspacePrefix}-${tenantname}"
        Write-Host "Using ResourceGroup: $resourceGroupName"
        if ($ftenvs.count -eq 0) {
            write-verbose "Can't find any feature envs..."
            $servicebusname = $null
            $connectionstring = $null
            $servicebusname = $namespaceName
            Write-Verbose "The service bus name we're trying to add is :$servicebusname"
            if (!(Get-AzServiceBusNamespace -ResourceGroup $resourceGroupName -NamespaceName $servicebusname -ErrorAction SilentlyContinue)) {
                New-AzServiceBusNamespace -ResourceGroupName $resourceGroupName -Name $servicebusname -Location $location -SkuName $sku
                $connectionstring = (Get-AzServiceBusKey -ResourceGroupName $resourceGroupName -Namespace $servicebusname -Name RootManageSharedAccessKey).PrimaryConnectionString
                Write-host "Primary connection string for $servicebusname is: $connectionstring"
            }
            else {
                Write-Warning "Skipping $servicebusname as this already exists!"
            }
        }
        else {
            write-verbose "found feature envs..."
            foreach ($ftenv in $ftenvs) {
                $servicebusname = $null
                $connectionstring = $null
                $servicebusname = $namespaceName+$ftenv
                Write-Verbose "The service bus name we're trying to add is :$servicebusname"
                if (!(Get-AzServiceBusNamespace -ResourceGroup $resourceGroupName -NamespaceName $servicebusname -ErrorAction SilentlyContinue)) {
                    New-AzServiceBusNamespace -ResourceGroupName $resourceGroupName -Name $servicebusname -Location $location -SkuName $sku
                    $connectionstring = (Get-AzServiceBusKey -ResourceGroupName $resourceGroupName -Namespace $servicebusname -Name RootManageSharedAccessKey).PrimaryConnectionString
                    Write-host "Primary connection string for $servicebusname is: $connectionstring"
                }
                else {
                    Write-Warning "Skipping $servicebusname as this already exists!"
                }
            }
        }
    }
}

