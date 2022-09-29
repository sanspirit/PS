<#
.SYNOPSIS
    Configures the app service custom domains
.DESCRIPTION
    Creates a custom domain within an app service

.EXAMPLE
    .\src\Configure-AppServiceDNSVerification.ps1 -resourcegroup "op00-function" -zonename 'prf' -url 'Operations' -asuid "mstest.ctazure.co.uk" -tmurl "MattTest"

#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]
    $resourcegroup,

    [Parameter(Mandatory = $True)]
    [string]
    $zonename,

    [Parameter(Mandatory = $True)]
    [string]
    $url,

    [Parameter(Mandatory = $True)]
    [string]
    $asuid,

    [Parameter(Mandatory = $True)]
    [string]
    $tmurl
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
Write-Verbose "Zonename: $zonename"
Write-Verbose "Url: $url"
Write-Verbose "Asuid: $asuid"
Write-Verbose "Tmurl: $tmurl"

Write-Verbose "Running on: $env:COMPUTERNAME"

Login-toAzure `
-clientpassword $OctopusParameters["AzAccount.Password"] `
-clientid $OctopusParameters["AzAccount.Client"] `
-azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
-tenantid $OctopusParameters["AzAccount.TenantId"] `
-subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]

Write-Verbose "Successfully authenticated with Service Principal"

$cname_zone = (Get-AzDnsrecordset -ZoneName "$zonename" -ResourceGroupName "$resourcegroup" | Where-Object Name -eq "$url" -ErrorAction SilentlyContinue)
if (!$cname_zone) {
    try {
        write-host "Adding DNS CNAME entry pointing to WAF:"
        $cname_records = @()
        $cname_records += New-AzDnsRecordConfig -Cname "$tmurl"
        New-AzDnsRecordSet -Name "$url" -RecordType CNAME -ResourceGroupName "$resourcegroup" -TTL 3600 -ZoneName "$zonename" -DnsRecords $cname_records
    }
    catch {
        Write-Error $error[0].Exception
    }
}
else {
    write-host "DNS CNAME entry already exists:-"
    Write-Verbose $cname_zone
}

$txt_zone = (Get-AzDnsrecordset -ZoneName "$zonename" -ResourceGroupName "$resourcegroup" | Where-Object Name -eq "asuid.$url" -ErrorAction SilentlyContinue)
if (!$txt_zone) {
    try {
        write-host "Adding TXT entry, to verify the domain"
        $txt_records = @()
        $txt_records += New-AzDnsRecordConfig -Value "$asuid"
        New-AzDnsRecordSet -Name "asuid.$url" -RecordType TXT -ResourceGroupName "$resourcegroup" -TTL 3600 -ZoneName "$zonename" -DnsRecords $txt_records
    }
    catch {
        Write-Error $error[0].Exception
    }
}
else {
    write-host "DNS TXT entry already exists:-"
    Write-Verbose $txt_zone
}
