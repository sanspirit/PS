<#
.SYNOPSIS
    Install and then Start a Windows Service.
.DESCRIPTION
    Install and Start a Windows service
    try to determine the type of Service e.g. NSB or TopShelf.
.EXAMPLE
    # run locally
    .\src\Install-WindowsService.ps1 -windowsServiceName MyService -servicePath c:/temp -serviceExecutable -serviceUsername me -servicePassword pwd123

    # if you want to install but not start the service use the switch param --dontStartIt

    # or from package in Octopus Step
    Script file: Install-WindowsService.ps1
    Script params: -windowsServiceName #{LocalPackageName} -servicePath #{LocalApplicationPath} -serviceExecutable #{LocalPackageName} -serviceUsername #{nsbUser} -servicePassword #{nsbPassword}
    #>
    [CmdletBinding()]
    Param (
    
        [Parameter(Mandatory)]
        [string]
        $windowsServiceName,

        [Parameter(Mandatory)]
        [string]
        $servicePath,

        [Parameter(Mandatory)]
        [string]
        $serviceExecutable,

        [Parameter()]
        [string]
        $timespanWaitToStart = "00:03:30",

        [Parameter()]
        [string]
        $serviceUsername = "Creative\NServiceBus",

        [Parameter()]
        [string]
        $servicePassword = "",

        [Parameter()]
        [switch]
        $dontStartIt
    )


Write-Verbose "Service Executable is: $serviceExecutable"
#Write-Verbose "HostType is: $hostType"

$displayName = $windowsServiceName
Write-Output "ServiceName is: $windowsServiceName"
Write-Verbose "DisplayName is: $displayName"

Write-Verbose "Username is: $serviceUsername"
Write-Verbose "Password is: ####"

$description = "endpoint for $windowsServiceName"

# Find out the Service type
#$hostType = "Topshelf"

# remove env prefix
$nameArray = $serviceExecutable.Split(".")
$serviceExecutable = ($nameArray | Select-Object -skip 1) -join "."

$hostExecutable = "$servicePath/$serviceExecutable"

if (Test-Path "$servicePath/NServiceBus.Host.exe")
{
	#$hostType = "NServiceBus"
    Write-Host "Installing as NServiceBus"
    $hostExecutable = Join-Path $servicePath "NServiceBus.Host.exe"
	$dependson = "MSMQ"
    $ArgsList = @("/install", "/serviceName:$windowsServiceName", "/displayName:$displayName", "/description:`"$description`"", "/username:$serviceUsername", "/password:$servicePassword", "/dependsOn:$dependson")
    #Write-Host $ArgsList
	Start-Process -FilePath $hostExecutable -ArgumentList $ArgsList 
}
elseif (Test-Path "$servicePath/Topshelf.dll")
{
    if ($hostExecutable -notmatch "\.exe$")
    {
        $hostExecutable = Join-Path $servicePath "$serviceExecutable.exe"
    }
	#$hostType = "Topshelf"
	Write-Host "Installing as Topshelf"
	& "$hostExecutable" install -username:"$serviceUsername" -password:"$servicePassword" -servicename:"$windowsServiceName" -displayname:"$displayName"
}
elseif (Test-Path "$hostExecutable.exe")
{
    $hostExecutable = Join-Path $servicePath "$serviceExecutable.exe"
	Write-Host "Installing as something else (not topshelf or nservicebus service :/ )"
    $secpasswd = ConvertTo-SecureString "$servicePassword" -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("$serviceUsername", $secpasswd)
    New-Service -Name $windowsServiceName -BinaryPathName $hostExecutable -DisplayName $windowsServiceName -StartupType Automatic -Credential $cred
}
else
{
	Write-Error "Service Type unknown"
}


$varnum = 0
do
{
    Start-Sleep -Seconds 4
    $varnum += 1
	Write-Host "Attempt number $varnum"
    $svc = Get-Service $windowsServiceName -ErrorAction SilentlyContinue
} while ($null -eq $svc -and $varnum -le 30)


if ($null -eq $svc)
{
    Write-Error "Failed to get installed service within specified time"
}
else {
    # now Start the Service

    if (-not $dontStartIt)
    {
        if ($svc.Status -eq "Running") {
            Write-Output "The $windowsServiceName service is already running."
        } else {
            Write-Output "Starting $windowsServiceName..."
            #$outputLog = Join-Path $env:TEMP "StartingSvc.txt"
            #(get-wmiobject win32_service -filter "name='$windowsServiceName'").startService()
            try
            {
                #$svc = Start-Service $windowsServiceName -ErrorAction SilentlyContinue -ErrorVariable ProcessError -PassThru -NoWait
                $svc.Start()
                $svc.WaitForStatus("Running", $timespanWaitToStart)
                Write-Output "Started $windowsServiceName"
            }
            catch 
            {
                Write-Verbose -message "Exception: Service $windowsServiceName failed to start."
                $ProcessError = $PSItem
            }            
        }

        if ($ProcessError)
        {
            Write-Warning -message "Service $windowsServiceName failed to start"
            if ($ProcessError.Exception)
            {
                Write-Warning -message $ProcessError.Exception.Message
                $baseException = $ProcessError.Exception.GetBaseException()
                if ($baseException)
                {
                    Write-Error -message $baseException.Message
                }
                else {Write-Error -message "$($ProcessError.Exception.Message), no base exception provided"}
            }
            else {Write-Error -message "Service $windowsServiceName failed to start, no exception message provided"}
        }
    }
    else {
        Set-Service $svc -StartupType Disabled
        If ($svc.Status -eq "Running") {
            Stop-Service $svc
        }
        Write-Warning "Service is installed but set to Disabled and not Started, as StartService variable is set to False"
    }
}
