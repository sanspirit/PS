<#
.SYNOPSIS
    Creates a unique application directory for idempotent deployments
.DESCRIPTION
    Creates a unique application directory for idempotent deployments, optionally pass through an ApplicationName to create a nested directory,
    this has been designed with IIS Site/Application/Directory in mind
.EXAMPLE
    .\src\Create-UniqueAppDirectory.ps1 -SitePath "F:\FrontOffice" -ApplicationName "FrontOffice" -DirectoryPrefixName $OctopusParameters["Octopus.Release.Number"]
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $ApplicationName,

    [Parameter()]
    [string]
    $Sitepath,

    [Parameter()]
    [string]
    $DirectoryPrefixName
)

function New-NestedDirectory {
    param (
        $Apppath
    )
    # Create IIS Nested Application Path Directory
    $dirstring = $DirectoryPrefixName + (Get-Date).ToString(".ddMMyyyy")
    $dirsuffix = $null
    if (!(Get-ChildItem $Apppath)) {
        $dirsuffix = 1
    }
    else {
        $dirsuffix = [convert]::ToInt32((Get-ChildItem $Apppath | Sort-Object {"$PSItem"[-1]} -Descending | Select-Object -First 1).basename.split("_")[1],10) + 1
    }

    $AppDirectory = (New-Item -ItemType Directory ("$Apppath\$dirstring" + "_$dirsuffix")).FullName
    Write-Host "Application directory is: $AppDirectory"
    Set-Octopusvariable -name "AppDirectory" -value $AppDirectory
}

if ($ApplicationName) {
    # Create IIS Nested Application Path Parent Directory

    $ApplicationNameDir = "$Sitepath\$ApplicationName"
    if (!(Test-Path $ApplicationNameDir)) {
        $AppPath = (New-Item -ItemType Directory $ApplicationNameDir).FullName
    }
    else {
        $Apppath = (Get-Item $ApplicationNameDir).FullName
    }
    Write-Host "Application Site directory is: $AppPath"
    New-NestedDirectory -Apppath $AppPath
}
else {
    New-NestedDirectory -Apppath $Sitepath
}
