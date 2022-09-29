<#
.SYNOPSIS
    Configures the app service custom domains
.DESCRIPTION
    Creates a custom domain within an app service

.EXAMPLE
    .\src\Configure-AppServiceDomain.ps1 -resourcegroup "op00-function" -url "mstest.ctazure.co.uk" -appname "MattTest"
#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]
    $resourcegroup,

    [Parameter(Mandatory = $True)]
    [string]
    $appname,

    [Parameter(Mandatory = $True)]
    [string]
    $url
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
    Write-Verbose "Printing out login variables"
    Write-Verbose "Clientid: $clientid"
    Write-Verbose "Azureenvironment: $azureenvironment"
    Write-Verbose "Tenantid: $tenantid"
    Write-Verbose "Subscriptionid: $subscriptionid"
    Write-Verbose "Authenticating with Service Principal"

    Login-AzAccount -Credential $creds -TenantId $tenantid -SubscriptionId $subscriptionid -Environment $azEnv -ServicePrincipal
}


Write-Verbose "Printing out variables"
Write-Verbose "Resourcegroup: $resourcegroup"
Write-Verbose "Appname: $appname"
Write-Verbose "Url: $url"

Write-Verbose "Running on: $env:COMPUTERNAME"

Login-toAzure `
-clientpassword $OctopusParameters["AzAccount.Password"] `
-clientid $OctopusParameters["AzAccount.Client"] `
-azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
-tenantid $OctopusParameters["AzAccount.TenantId"] `
-subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]

$app_exists = Get-AzWebApp -Name "$appname" -ResourceGroupName "$resourcegroup" -ErrorAction SilentlyContinue

if ($app_exists) {
    $url_exists = Resolve-DnsName -Name "asuid.$url"
    if ($url_exists) {
        if ($app_exists.HostNames -like "*$url*") {
            write-host "HostName already exists: $url" 
        }
        else {
            try {
                $existing_host = $app_exists.HostNames
                Write-Verbose "Adding new hostname: $appname and keeping existing hostnames $existing_host"
                set-AzWebApp -Name "$appname" -ResourceGroupName "$resourcegroup" -HostNames @("$url","$existing_host") -WarningAction Stop
            }
            catch {
                Write-Error $error[0].Exception
            }
        }
    }
    else {
        Write-Error "Unable to resolve DNS record: $url"
    }
}
else {
    Write-Error "$appname doesn't exist in resource group: $resourcegroup"
}
