<#
.SYNOPSIS
    Configures diagnostics logs at a subscription level.
.DESCRIPTION
    Configures diagnostics logs at a subscription level in Azure
    If debug is set to true will run it with -whatif enabled and verbose logging
    To run this from your local machine set the -local $True

.EXAMPLE
    .\src\Configure-AzureSubcriptionDiagnostics.ps1 -TemplateFile "D:\Devops\CustomCode\src\Templates\Sub-Diagnostic-Logging-V2.json" -debugmode $true -local $true
#>
[CmdletBinding()]
Param (

    [Parameter(Mandatory = $True)]
    [string]
    $TemplateFile,

    [Parameter(Mandatory = $True)]
    [Boolean]
    $debugmode,

    [Parameter(Mandatory = $False)]
    [Boolean]
    $local = $False
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
Write-Verbose "TemplateFile: $TemplateFile"
Write-Verbose "DebugMode: $debugMode"
Write-Verbose "local: $local"

Write-Verbose "Running on: $env:COMPUTERNAME"

if($local -eq $False) {
    Login-toAzure `
    -clientpassword $OctopusParameters["AzAccount.Password"] `
    -clientid $OctopusParameters["AzAccount.Client"] `
    -azureenvironment $OctopusParameters["AzAccount.AzureEnvironment"] `
    -tenantid $OctopusParameters["AzAccount.TenantId"] `
    -subscriptionid $OctopusParameters["AzAccount.SubscriptionNumber"]
}

if($debugMode -eq $True) {
    $WhatIfPreference = $True
    $VerbosePreference = "Continue"
}

$TemplateName = (Get-Item $TemplateFile).BaseName
Write-Verbose $TemplateName

$deployment_exists = Get-AzDeployment -Name $TemplateName -ErrorAction SilentlyContinue

if ($deployment_exists) {
    write-host "Deployment already exists:" $deployment_exists.DeploymentName
    write-verbose $deployment_exists.ProvisioningState
    write-verbose $deployment_exists.Timestamp
}
else {
    try {
        if ($local -eq $True) {
            Write-Verbose "Adding new Deployment using $TemplateFile"
            if ($debugMode -eq $True) {
                New-AzDeployment -Location "northeurope"  -TemplateFile $TemplateFile -whatif
            }
            else {
                New-AzDeployment -Location "northeurope"  -TemplateFile $TemplateFile    
            }
        }
        else {
            $Subscription = Get-AzSubscription -SubscriptionId $OctopusParameters["AzAccount.SubscriptionNumber"]
            Write-Verbose "Adding new Deployment using $TemplateFile for subcription:" 
            Write-Verbose $Subscription.Name
            New-AzDeployment -Location "northeurope"  -TemplateFile $TemplateFile
        }
    }
    catch {
        Write-Error $error[0].Exception
    }
}
