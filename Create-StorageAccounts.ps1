<#
.SYNOPSIS
    Configures the application storage accounts
.DESCRIPTION
    Creates all of the neccessary storage accounts for the specified environment

.EXAMPLE
    .\src\Create-StorageAccounts.ps1 -resourcegroup "op00-storage" -environmentname "storage" -subscription 'CTOperations' -location 'ukwest' -skuname 'Standard_LRS'

#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $resourcegroup,

    [Parameter(Mandatory = $True)]
    [string]
    $infraenv,

    [Parameter()]
    [string]
    $featureenv,

    [Parameter(Mandatory = $True)]
    [array]
    $tenantnames,

    [Parameter(Mandatory = $True)]
    [string]
    $hubname,

    [Parameter(Mandatory = $True)]
    [string]
    $location,

    [Parameter(Mandatory = $True)]
    [string]
    $skuname
)

Install-Module -Name az.storage -AllowClobber -Scope AllUsers -Force -Confirm:$false
Install-Module -Name az.resources -AllowClobber -Scope AllUsers -Force -Confirm:$false
Install-Module -Name az.accounts -AllowClobber -Scope AllUsers -Force -Confirm:$false
Import-Module -Name az.storage
Import-Module -Name az.resources
Import-Module -Name az.accounts

$BlobCorsRules = (@{
    AllowedHeaders=@("*");
    AllowedOrigins=@("*");
    MaxAgeInSeconds=36000;
    AllowedMethods=@("Get","Options","Put")})

$TableCorsRules = (@{
    AllowedHeaders=@("*");
    AllowedOrigins=@("*");
    MaxAgeInSeconds=36000;
    AllowedMethods=@("Get","Options")})

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

foreach ($tenantname in $tenantnames) {
    $tenantname = $tenantname.ToLower()

    if ($featureenv -like "FT*") {
        $featureenv = $featureenv.ToLower()
        $saenv = $tenantname + $featureenv
        $saiamenv = "$($tenantname)ft"
    }
    else {
        $featureenv = ''
        $saenv = $tenantname + $featureenv
        $saiamenv = $saenv
    }

    if (!($resourcegroup)) {
        $resourcegroup = $hubname + "-" + $infraenv + "-Storage"
    }

    $storageaccountlist = `
        "$($saenv)cashflowmod",`
        "$($saenv)ctcoresupport",`
        "$($saenv)cliprof",`
        "$($saenv)documentrenderer",`
        "$($saenv)dynamicquestion",`
        "$($saenv)eacv2",`
        "$($saenv)ehmpg",`
        "$($saenv)efilemigration",`
        "$($saenv)efilestorage",`
        "$($saenv)eintellisync",`
        "$($saenv)enablecompliance",`
        "$($saenv)enable",`
        "$($saenv)enableapifunction",`
        "$($saenv)enablemvc",`
        "$($saenv)enableaccess",`
        "$($saenv)enableaccesskeys",`
        "$($saenv)ereports",`
        "$($saenv)factfind",`
        "$($saenv)feeimporter",`
        "$($saenv)feeprocessor",`
        "$($saenv)fundservice",`
        "$($saenv)groupschemes",`
        "$($saenv)ehmpg",`
        "$($saenv)informuser",`
        "$($saenv)illussvc",`
        "$($saenv)identityiam",`
        "$($saenv)identityiamkeys",`
        "$($saenv)idhost",`
        "$($saenv)recproc",`
        "$($saenv)statements",`
        "$($saenv)fusionanticorr",`
        "$($saenv)fusioncomm",`
        "$($saenv)fusionillus",`
        "$($saenv)fusioncompliance",`
        "$($saenv)fusionconsole",`
        "$($saenv)fusioninterfaces",`
        "$($saenv)fusionidentity",`
        "$($saenv)fusionopsdata",`
        "$($saenv)fusiontopup",`
        "$($saenv)fusionprovint",`
        "$($saenv)commservice",`
        "$($saenv)fusiondms",`
        "$($saenv)fusionmigration",`
        "$($saiamenv)ctsuitekeys",`
        "$($saenv)sdocvault",`
        "$($saenv)sdocvaultkeys",`
        "$($saenv)suitability",`
        "$($saenv)tokenserver",`
        "$($saenv)tokenserverkeys",`
        "$($tenantname)databus",`
        "$($tenantname)filestore",
        "$($saenv)wpapikeys",
        "$($saenv)wpaccessapikeys",
        "$($saenv)wpiam",
        "$($saenv)wpiamkeys",
        "$($saenv)ctidentitykeys",
        "$($saenv)idverification",
        "$($saenv)enablereviewskeys",
        "$($saenv)reviewsinternal"

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

    foreach ($storageaccountname in $storageaccountlist) {
        $exists = Get-AzStorageAccount -Name $storageaccountname -ResourceGroupName $resourcegroup -ErrorAction SilentlyContinue
        $Available = Get-AzStorageAccountNameAvailability -name $storageaccountname

        if (!($exists) -and ($Available.NameAvailable)) {
            try {
                if (!($storageaccountname -in "pdsfilestore","pdsdatabus","pdwfilestore","pdwdatabus")) {
                    Write-Host "Creating storage account: $storageaccountname"
                    New-AzStorageAccount -ResourceGroupName $resourcegroup -AccountName $storageaccountname -Location $location -SkuName $skuname | Out-Null
                    Set-AzStorageAccount -ResourceGroupName $resourcegroup -AccountName $storageaccountname -EnableHttpsTrafficOnly $true | Out-Null
                    if ($storageaccountname -match "filestore") {
                        Write-Verbose "Adding CORSRules to $storageaccountname"
                        $accountkey = (Get-AzStorageAccountKey -ResourceGroupName $resourcegroup -Name $storageaccountname).Value[0]
                        $context = New-AzStorageContext -StorageAccountName $storageaccountname -StorageAccountKey $accountkey
                        if (!(Get-AzStorageCORSRule -ServiceType Blob -Context $context)) {
                            Set-AzStorageCORSRule -ServiceType Blob -Context $context -CorsRules $BlobCorsRules
                        }
                        if (!(Get-AzStorageCORSRule -ServiceType Table -Context $context)) {
                            Set-AzStorageCORSRule -ServiceType Table -Context $context -CorsRules $TableCorsRules
                        }
                    }
                    if ($storageaccountname -match "suitability") {
                        Write-Verbose "Trying to update $storageaccountname to enable versioning"
                        Update-AzStorageBlobServiceProperty -ResourceGroupName $resourcegroup -AccountName $storageaccountname -IsVersioningEnabled $true                    
                    }
                }
            }
            catch {
                Write-Error $error[0].Exception
            }
        }
        else {
            Write-Host "Account name $($storageaccountname) availability status is $($Available.NameAvailable)"
            Write-Host "Storage account $($storageaccountname) already exists."
        }
    }
}
