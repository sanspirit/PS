<#
.SYNOPSIS
    Creates a puppet external fact
.DESCRIPTION
    Creates a Powershell script that will be deployed to the puppet facts.d folder to be used as a puppet external fact
.EXAMPLE
    .\src\Set-PuppetExternalFact.ps1 -FactName "AppLocation" -FactValue "C:\Temp" -FactFilename "TestFact.ps1"
#>
[CmdletBinding(SupportsShouldProcess=$True)]
Param (

    [Parameter()]
    [string]
    $FactName,

    [Parameter()]
    [string]
    $FactValue,

    [Parameter()]
    [string]
    $FactFilename,

    [Parameter()]
    [bool]$overwrite
)

$factfile = "C:\ProgramData\PuppetLabs\facter\facts.d\$FactFilename"
$factcontent = "Write-Host ""$FactName=$FactValue"""

if (Test-Path $factfile) {
    if ($true -eq $overwrite) {
        Write-Verbose "$FactFilename exists and overwite is true, removing file"
        Remove-Item $factfile -Force
        Write-Verbose "Creating new file at $factfile"
        New-Item $factfile -Value $factcontent
    }
    else {
        Write-Error "Fact File already exists but overwrite not specified"
    }
}
else {
    Write-Verbose "$FactFilename does not exist, creating now.."
    New-Item $factfile -Value $factcontent
}
