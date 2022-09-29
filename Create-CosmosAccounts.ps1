<#
.SYNOPSIS
    Configures the application cosmos accounts
.DESCRIPTION
    Creates all of the neccessary cosmos accounts for the specified environment

.EXAMPLE
    .\src\Create-CosmosAccounts.ps1 -resourcegroup "op00-cosmos" -infraenv "op00" -location 'ukwest' -tenantname 'prf' -hubname 'Operations'

#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $resourcegroup,

    [Parameter(Mandatory = $True)]
    [string]
    $infraenv,

    [Parameter(Mandatory = $True)]
    [string]
    $hubname,

    [Parameter(Mandatory = $True)]
    [string]
    $location
)

$consistencyPolicy = "Session"
$isZoneRedundant = $false

if (!($resourcegroup)) {
    $resourcegroup = $hubname + "-" + $infraenv + "-Cosmos"
}

$caenv = $infraenv.ToLower()

$cosmosaccountlist = `
    "$($caenv)-client-profile",`
    "$($caenv)-enable-intellisync",`
    "$($caenv)-factfind-template",`
    "$($caenv)-fund-service",`
    "$($caenv)-suitability-template",
    "$($caenv)-fusion-migration",
    "$($caenv)-materialized-view"

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
function Get-CosmosAccount {
    param (
        $resourceGroupName,
        $Name
    )
    # Get the properties of an Azure Cosmos Account
    Get-AzResource -ResourceType "Microsoft.DocumentDb/databaseAccounts" `
        -ApiVersion "2015-04-08" -ResourceGroupName $resourceGroupName `
        -Name $Name `
        -ErrorAction SilentlyContinue
}
function New-CosmosAccount {
    param (
        $location,
        $resourceGroupName,
        $accountName,
        $consistencyPolicy,
        $isZoneRedundant
    )
    # Create an Azure Cosmos Account for Core (SQL) API

    if ($isZoneRedundant -eq $True) {
        $locations = @(
            @{ "locationName"="$location"; "failoverPriority"=0; "isZoneRedundant"= "true" }
            $enableMultipleWriteLocations = "true"
        )
    }
    else {
        $locations = @(
            @{ "locationName"="$location"; "failoverPriority"=0 }
            $enableMultipleWriteLocations = "false"
        )
    }
    
    $consistencyPolicy = @{
        "defaultConsistencyLevel"="$consistencyPolicy";
        "maxIntervalInSeconds"=5;
        "maxStalenessPrefix"=100
    }

    $CosmosDBProperties = @{
        "databaseAccountOfferType"="Standard";
        "locations"=$locations;
        "consistencyPolicy"=$consistencyPolicy;
        "enableMultipleWriteLocations"="$enableMultipleWriteLocations"
    }

    New-AzResource -ResourceType "Microsoft.DocumentDb/databaseAccounts" `
        -ApiVersion "2015-04-08" -ResourceGroupName $resourceGroupName -Location $location `
        -Name $accountName -PropertyObject $CosmosDBProperties -Force
}

Write-Host "Running on: $env:COMPUTERNAME"

Login-toAzure `
-clientpassword $OctopusParameters["AzAccount.Password"] `
-clientid $OctopusParameters["AzAccount.Client"] `
-azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
-tenantid $OctopusParameters["AzAccount.TenantId"] `
-subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]

if (!(Get-AzResourceGroup -Name $resourcegroup -ErrorAction SilentlyContinue)) {
    try {
        Write-Host "Creating ResourceGroup: $resourcegroup"
        New-AzResourceGroup -Name $resourcegroup -Location $location
    }
    catch {
        Write-Error $error[0].Exception
    }
}
else {Write-Host "Using ResourceGroup: $resourcegroup"}

foreach ($cosmosaccountname in $cosmosaccountlist) {
    $exists = Get-CosmosAccount -Name $cosmosaccountname -ResourceGroupName $resourcegroup -ErrorAction SilentlyContinue

    if (!($exists)) {
        try {
            Write-Host "Creating cosmos account: $cosmosaccountname"
            New-CosmosAccount -resourceGroupName $resourcegroup -location $location -accountName $cosmosaccountname -consistencyPolicy $consistencyPolicy -isZoneRedundant $isZoneRedundant
        }
        catch {
            Write-Error $error[0].Exception
        }
    }
    else {Write-Host "$cosmosaccountname already exists"}
}
