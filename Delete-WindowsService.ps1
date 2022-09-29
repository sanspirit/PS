<#
.SYNOPSIS
    Find, Stop and then Delete a Windows Service.
.DESCRIPTION
    Stop and Delete a Windows service
    will close Services mmc window if open , as it can prevent the service deletion.

    if service Stop does not succeed, it will terminate the service process with taskkill

.EXAMPLE
    # run locally
    .\src\Delete-WindowsService.ps1 -windowsServiceName MyService

    # or from package in Octopus Step
    Script file: Delete-WindowsService.ps1
    Script params: -windowsServiceName MyService
    #>
    [CmdletBinding()]
    Param (
    
        [Parameter(Mandatory)]
        [string]
        $windowsServiceName
    )

Write-Output "Attempting to stop $windowsServiceName..."

$serviceInstance = Get-Service -DisplayName $windowsServiceName -ErrorAction SilentlyContinue

if ($null -ne $serviceInstance) 
{
    $localserviceName = $serviceInstance.Name
    Write-Output "Short Service Name: $localserviceName"

    if ($serviceInstance.StartType -eq "Disabled")
    {
    	Write-Output "Service is Disabled!"
        
    	if ($serviceInstance.Status -eq "Running")
        {
          # this is bad! - Running whilst Disabled
          # try Kill with Process Id
          $ServicePID = (Get-WmiObject Win32_Service | Where-Object {$_.Name -eq $serviceInstance.Name}).ProcessID

          Write-Output "ServicePID: $ServicePID"

          if ($ServicePID -gt 0)
          {
              taskkill /F /PID $ServicePID
              Start-Sleep -Second 4
          }
        }
    }
    else
    {
      # Remove Recovery Restart options
      sc.exe failure $localserviceName reset= 0 actions= ///
	}
    
	# check if Services mmc is open - preventing service deletion
    $procs = Get-Process -Name mmc -ErrorAction SilentlyContinue
    foreach ($proc in $procs)
    {
        Write-Output "Found $($proc.Name) process running; ID: $($proc.Id)"
        if ($proc.Id -gt 0) {
            Write-Output "Stopping $($proc.Name) process; ID: $($proc.Id)"
            Stop-Process $proc -Force
        }
    }

    $serviceInstance = Get-Service $localserviceName -ErrorAction SilentlyContinue
    if ($null -ne $serviceInstance) 
    {
      if ($serviceInstance.Status -eq "Running" -and $serviceInstance.StartType -ne "Disabled")
      {
          try {
              Stop-Service -InputObject $serviceInstance -Force
              # exception might be thrown
              Start-Sleep -Second 1
              Write-Output "Wait for Service to stop..."
              $serviceInstance.WaitForStatus('Stopped', '00:02:00')
          }
          catch {
              Write-Output "Exception trying to stop service: $localserviceName... attempting to force"
          }        
          if ($serviceInstance.Status -eq "Stopped")
          {
              Write-Output "Service $localserviceName stopped."
          }
          else
          {
              # try again with Process Id
              $ServicePID = (Get-WmiObject Win32_Service | Where-Object {$_.Name -eq $localserviceName}).ProcessID

              Write-Output "ServicePID: $ServicePID"

              if ($ServicePID -gt 0)
              {
                  taskkill /F /PID $ServicePID
                  Start-Sleep -Second 4
              }
          }
      }
	}

    $serviceInstance = Get-Service $localserviceName -ErrorAction SilentlyContinue
    if ($null -ne $serviceInstance) 
    {
      # delete the service
      try {
          Write-Output "sc.exe delete $localserviceName"
          sc.exe delete $localserviceName
          $retries = 9
          $counter = 1
          if (1072 -eq $LastExitCode) {$LastExitCode = 0}	# 1072 means service has been marked for deletion
          do
          {
              Write-Output "Service: $($serviceInstance.Name) - Status: $($serviceInstance.Status)"
              Start-Sleep -Second 10

              # check if service has gone
              $serviceInstance = Get-Service $localserviceName -ErrorAction SilentlyContinue
              $counter++
          } while ($null -ne $serviceInstance -and $counter -le $retries)

          if ($null -ne $serviceInstance) 
          {
              Write-Error "$($serviceInstance.Name) is not removed; Status: $($serviceInstance.Status)"
          }
          else
          {
              Write-Output "deleted service: $localserviceName"
              $LastExitCode = 0
          }
      }
      catch 
      {
          $serviceInstance = Get-Service $localserviceName -ErrorAction SilentlyContinue
          if ($null -ne $serviceInstance) 
          {
              Write-Error "Exception trying to delete service: $localserviceName"
          }
          else
          {
              Write-Output "deleted service: $localserviceName"
              $LastExitCode = 0
          }
      }
	}
    else
    {
      Write-Output "service: $localserviceName has been removed."
    }
} 
else 
{
    Write-Output "The $windowsServiceName service could not be located"
}

exit $LastExitCode
