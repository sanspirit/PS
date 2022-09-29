<#
.SYNOPSIS
    Installs or Uninstalls an MSI provided by Dunstan Thomas for Imago Illustrations
.DESCRIPTION
    Will install one of the following packages for Imago Illustraions:
    - FrontOffice.Install.Admin.msi
    - FrontOffice.Install.DBTools.msi
    - FrontOffice.Install.Integration.msi
    - FrontOffice.Install.Legacy.msi
    - FrontOffice.Install.UI.msi
.EXAMPLE
    .\src\Configure-ImagoIllustrationsInstallation.ps1 `
     -InstallOption Install `
     -MSIfile "F:\Install\FrontOffice.Install.UI.msi" `
     -InstallLocation "F:\Install" `
     -DBServer "BSDevDB1" `
     -DBName "FrontOffice" `
     -SiteName "FrontOffice" `
     -ApplicationName "FrontOffice" `
     -AppPoolName "FrontOffice"

    .\src\Configure-ImagoIllustrationsInstallation.ps1 `
     -InstallOption Uninstall `
     -MSIfile "F:\Install\FrontOffice.Install.UI.msi"
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [ValidateSet('Install','Uninstall')]
    [string]
    $InstallOption,

    [Parameter()]
    [string]
    $MSIfile,

    [Parameter()]
    [string]
    $InstallLocation,

    [Parameter()]
    [string]
    $DBServer,

    [Parameter()]
    [string]
    $DBName,

    [Parameter()]
    [string]
    $SiteName,

    [Parameter()]
    [string]
    $ApplicationName,

    [Parameter()]
    [string]
    $AppPoolName,

    [Parameter()]
    [string]
    $DBLogin,

    [Parameter()]
    [string]
    $DBPassword,

    [Parameter()]
    [string]
    $ProductName

)

Write-Verbose "Install Option is: $InstallOption"
Write-Verbose "File path is: $MSIfile"
Write-Verbose "Install location is $InstallLocation"
Write-Verbose "Database Server is: $DBServer"
Write-Verbose "Database Name is: $DBName"
Write-Verbose "IIS Site is $SiteName"
Write-Verbose "IIS Application is $ApplicationName"
Write-Verbose "IIS App Pool is $AppPoolName"

if ($installoption -eq 'Install') {
    $logname = "$($ApplicationName)_InstallLog_" + (Get-Date).ToString("ddMMyyyy") + ".log"
    $Loggingpath = "$InstallLocation\$logname"

    try {
        Write-Host "Installing $MSIfile"
        if ($ProductName -eq "DT Collate - Imago Illustrations (Benchmark)") {
            Write-Verbose "Reporting installation detected, running reporting specific install command"
            $PackageDropped = "$InstallLocation\PackageDropped\"
            Start-Process -FilePath msiexec -ArgumentList "/qn /i ""$msifile"" SITEPATH=""$ApplicationName"" APPPOOL=""$AppPoolName"" WEBSITENAME=""$SiteName"" INSTALLLOCATION=""$InstallLocation"" PACKAGEDROPPED=""$PackageDropped"" /l*v $Loggingpath" -Wait
        }
        elseif ($ProductName -eq "Imago Database Upgrade") {
            Write-Verbose "DB Upgrade installation detected, running DB Upgrade specific install command"
            Install-Module -Name sqlserver -AllowClobber -Scope AllUsers -Force
            Import-Module sqlserver
            $Loggingpath = "$env:TEMP\$logname"
            $CurrentDBVersion = (Invoke-Sqlcmd -ServerInstance $DBServer -Database $DBName -QueryTimeout 100 -Username $DBLogin -Password $DBPassword -Query "SELECT TOP (1) [Version]
            FROM [$DBName].[dbo].[UpdatesApplied]
            ORDER BY Id DESC").Version
            Write-Host "Upgrading $DBName on $DBServer, current version=$CurrentDBVersion"
            Start-Process -FilePath msiexec -ArgumentList "/qn /i ""$msifile"" DBSERVER=""$DBServer"" DBNAME=""$DBName"" CONNECTIONTYPE=1 LOGIN=""$DBLogin"" PASSWORD=""$DBPassword"" PROCEED=1 EXECUTEACTION=""INSTALL"" CURRENTDBVERSION=""$CurrentDBVersion"" SECONDSEQUENCE=1 ADDLOCAL=""ProductFeature"" /l*v ""$Loggingpath""" -Wait
        }
        else {
            Start-Process -FilePath msiexec -ArgumentList "/qn /i ""$msifile"" SITEPATH=""$ApplicationName"" APPPOOL=""$AppPoolName"" WEBSITENAME=""$SiteName"" INSTALLLOCATION=""$InstallLocation"" DBSERVER=""$DBServer"" DBNAME=""$DBName"" APPPOOLLIST=""$AppPoolName"" WEBSITELIST=""$SiteName"" /l*v $Loggingpath" -Wait
        }
    }
    catch {
        Write-Host "An error occured"
        Write-Error $error[0].Exception
    }
    Finally {
        New-OctopusArtifact -Path $Loggingpath -Name $logname
    }
    
}
elseif ($installoption -eq 'Uninstall') {
    $logname = "UninstallLog_" + (Get-Date).ToString("ddMMyyyy") + ".log"
    $Loggingpath = "$env:TEMP\$logname"
    
    if ($ProductName -eq "DT Collate - Imago Illustrations (Benchmark)") {
        $Product =  Get-CimInstance Win32_Product | Where-Object {$PSItem.Name -like "*DT Collate*"}
    }
    else {
        $Product =  Get-CimInstance Win32_Product | Where-Object {$PSItem.Name -eq $ProductName}
    }
    if ($Product) {
        Write-Verbose "Product Name is: $($Product.Name)"
        Write-Verbose "Product ID is: $($Product.IdentifyingNumber)"
        
        try {
            Write-Host "Uninstalling $($Product.Name)"
            Start-Process -FilePath msiexec -ArgumentList "/qn /x ""$($Product.IdentifyingNumber)"" /l*v $Loggingpath" -Wait -NoNewWindow
        }
        catch {
            Write-Host "An error occured"
            Write-Error $error[0].Exception
        }
        Finally {
            New-OctopusArtifact -Path $Loggingpath -Name $logname
        }
    }
    else {
        Write-Host "No previous version detected, continuing with install"
    }
}
