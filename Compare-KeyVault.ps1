<#
.SYNOPSIS
    Runs Comparison against Azure KeyVault

.DESCRIPTION
    Given a name of an Azure KeyVault this script will compare the values set against each key against an corresponding key in Octopus.

.EXAMPLE
    .\CompareKeyVault.ps1 -KeyVaultName "pegft3-AssetHunter"
#>

[CmdletBinding()]
param(
    # The name of the keyvault
    [Parameter(Mandatory = $True)] [string] $KeyVaultName,
    [Parameter(Mandatory = $True)] [string] $SubscriptionID
)

$ErrorActionPreference = "Continue"
# Create Dictionaries to store the key valye pairs.
$all_existing_secrets = New-Object System.Collections.Generic.Dictionary"[String,String]"
$all_incoming_secerts = New-Object System.Collections.Generic.Dictionary"[String,String]"
# Octopus Artifact Name
$releaseTime = get-date -format "dd.MM.yy-HH.mm"
$artifact_name = $OctopusParameters["Octopus.Release.Number"] + "-" + $releaseTime + "-" + $KeyVaultName + ".txt"
# Loop over the keys and obtain the plain text values

try {     
    Set-AzContext -Subscription $SubscriptionID
    foreach ($secret in (Get-AzKeyVaultSecret -VaultName $KeyVaultName)) {
        # Get all existing values for the keys we have found.
        $all_existing_secrets.Add($secret.Name, ((Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secret.Name).SecretValue | ConvertFrom-SecureString -AsPlainText))
        # Get the values for the same keys as above from Octopus
        $all_incoming_secerts.Add($incomingSecrets, $OctopusParameters[$incomingSecrets])
        # Compare the two and append any differences to a file for later.
        if ( $all_incoming_secerts[$secret] -ne $all_existing_secrets[$secret] ) {
            Write-Output "The key $secret differs in current value to incoming value" | Out-File -Path $artifact_name -Append
        }
   }

   # Attach the written file to OD as an artifact.
   New-OctopusArtifact -Path $artifact_name -Name $artifact_name
} 
catch {
    Write-Output "Error, Cannot locate keyvault Named $KeyVaultName"
}
