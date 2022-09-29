<#
.SYNOPSIS
    This adds a exclusion of a environment to all process steps.
.DESCRIPTION
    Using the envtoexclude var, it goes through the defined projects and pulls the deployment process for each, using this it gets the steps and looks in each step for any excluded envs. 
    If it the env we're matching against, it'll skip that step. If it doesn't, it'll add it onto any existing excluded step, or it'll just add it to an empty excluded steps. 
.EXAMPLE
    .\src\Octopus-ExcludeAllProcessStepsFromEnv.ps1 -apikey API-XXX -deploymentproject "" -envstoexclude "Pre-Production"
#>

Param (

    [Parameter()]
    [string]
    $octopusURI = "https://octopus.ctazure.co.uk",

    [Parameter()]
    [string]
    $defaultSpaceName = "Apps",

    [Parameter()]
    [string]
    $apikey,

    [Parameter()]
    [string]
    $deploymentproject,

    [Parameter()]
    [string]
    $envtoexclude,

    $header =  @{ "X-Octopus-ApiKey" = $apiKey }

)

$ErrorActionPreference = 'stop'

write-host "The current working directory is "$pwd.path

$defaultSpaceId = ((Invoke-WebRequest -Uri "$octopusURI/api/spaces/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $defaultSpaceName}).id

if ([string]::IsNullOrEmpty($deploymentproject)) {
    $projects = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | where-Object {$_.Name -notlike "*application runbooks*" -and $_.Name -notlike "*test*"})
}
else {
    $projects = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $deploymentproject})
}

Write-Verbose "The Project ID(s) = $($projects.id)"

if ([string]::IsNullOrEmpty($envstoexclude)) {
    Write-Error "You need atleast one environment to exclude."
    exit
}
else {
    $envid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Environments/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.name -eq $envtoexclude}).id
    if ($null -ne $envid) {
        foreach ($project in $projects) {   
            #Get Deployment Process for Projects
            $deploymentprocessid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $($project.name)}).deploymentprocessid
            $deploymentprocess = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/deploymentprocesses/$deploymentprocessid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12)
            $steps = $deploymentProcess.Steps
            
            Write-Verbose "The Destination Deployment Process ID is $deploymentprocessid"
            foreach ($step in $steps) {
                if ($step.Actions.Id.Count -gt 1) {
                    foreach ($substep in $step.Actions) {
                        if ($substep.Environments.Count -eq 0) {
                            write-verbose "Checking $($substep.name)"
                            $excludedenvs = $substep.ExcludedEnvironments
                            if ($excludedenvs -contains $envid) {
                                write-verbose "$($substep.name) already contains the excluded step! Skipping..."
                            }
                            else {
                                Write-verbose "$($substep.name) doesn't exclude $envtoexclude, adding..."
                                #adds envid to exluded envs
                                $excludedenvs += $envid
                                $substep.ExcludedEnvironments = $excludedenvs
                            }   
                        }
                        else {
                            Write-Verbose "$($substep.name) is scoped to run on specific environments"
                        }
                    }
                }
                else {
                    if ($step.Actions[0].Environments.Count -eq 0) {
                        write-verbose "Checking $($step.name)"
                        $excludedenvs = $step.actions[0].ExcludedEnvironments
                        if ($excludedenvs -contains $envid) {
                            write-verbose "$($step.name) already contains the excluded step! Skipping..."
                        }
                        else {
                            Write-verbose "$($step.name) doesn't exclude $envtoexclude, adding..."
                            #adds envid to exluded envs
                            $excludedenvs += $envid
                            $step.actions[0].ExcludedEnvironments = $excludedenvs
                        }   
                    }
                    else {
                        Write-Verbose "$($step.name) is scoped to run on specific environments"
                    }
                }
            }
            $deploymentProcess.Steps = $steps
            $jsonbody = $deploymentProcess | ConvertTo-Json -Depth 12
            Invoke-RestMethod -Uri "$octopusURI/api/$defaultSpaceId/deploymentprocesses/$deploymentprocessid" -Method PUT -Headers $header -Body $jsonbody | Out-Null
            Write-host "Changes have been deployed for $($project.name)"-ForegroundColor Green
        }  
    }
}

