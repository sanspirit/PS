<#
.SYNOPSIS
    This deploys a step from another process to a project or multiple projects before all other steps.
.DESCRIPTION
    Using the source project and source step name, the script searches to find the step. If the step has been found, it will set this step as the step to copy and clear the ID field. 
    Using this, it will get the project or projects and for each project, it will search the current deployment process of that project to see if the stepname already exists. if it doesn't, it will 
    add add the steps onto the end of the step we copied before in the script, convert this to JSON, and then update the deployment process. 
.EXAMPLE
    .\src\Deploy-OctopusProcessStep.ps1 -apikey API-XXX -deploymentproject "" -sourceproject "assethunter" -sourcestepname "Determine Rolling Window Size"
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
    $sourceprojectname,

    [Parameter()]
    [string]
    $sourcestepname,

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


if ([string]::IsNullOrEmpty($sourceprojectname) -or ([string]::IsNullOrEmpty($sourcestepname))) {
    Write-Error "You need a source project and/or a source step name"
    exit
}
else {
    #Get step to replicate
    $sourceproject = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $sourceprojectname})
    $sourcedeploymentprocessid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $($sourceproject.name)}).deploymentprocessid
    $sourcedeploymentprocess = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/deploymentprocesses/$sourcedeploymentprocessid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).steps

    Write-Verbose "The Source Deployment Process ID is $sourcedeploymentprocessid"

    foreach ($step in $sourcedeploymentprocess) {
        Write-Verbose "Checking step $($step.name) for $sourcestepname"
        if ($step.name -eq $sourcestepname) {
            Write-Verbose "Found $sourcestepname in step $($step.name)"
            #step to copy
            $step.PSObject.Properties.Remove('id')
            $stepstocopy = $step
        }
    }
    if ($null -ne $stepstocopy) {
        foreach ($project in $projects) {   
            #Get Deployment Process for Projects
            $deploymentprocessid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $($project.name)}).deploymentprocessid
            $deploymentprocess = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/deploymentprocesses/$deploymentprocessid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12)
            $steps = $deploymentProcess.Steps
    
            Write-Verbose "The Destination Deployment Process ID is $deploymentprocessid"
    
            if ($steps.name -contains $sourcestepname) {
                Write-Warning "The destination project $($project.name) already contains a step called $sourcestepname. Skipping..."
            }
            else {
                #Add step previosuly copied to start of the deployment process
                $newstep = $null
                $newstep = $stepstocopy
                $stepsafter = $steps
                [array]$newstep += $stepsafter
                $steps = $newstep
                $deploymentProcess.Steps = $steps
    
                #Convert to JSON and submit request.
                $jsonbody = $deploymentProcess | ConvertTo-Json -Depth 12
                Invoke-RestMethod -Uri "$octopusURI/api/$defaultSpaceId/deploymentprocesses/$deploymentprocessid" -Method PUT -Headers $header -Body $jsonbody
            }
        }  
    }
    else {
        Write-Error "Can't find process step, $sourcestepname. Exiting."
        exit
    }
}

