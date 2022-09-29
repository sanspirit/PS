<#
.SYNOPSIS
    The script diffs vars between two deployments.
.DESCRIPTION
    Using two deployments, it gets the releases for the deployments and diffs the vars. If it finds new vars, it'll add them to an array. 
    If it finds differences in variables (matching on the ID), it will add to the same array and output these with the changes.
    It will filter out all the variables that don't match against Unscoped, or doesn't match against selected evnviroments.
.EXAMPLE
    .\src\Get-VariableDiffs.ps1 -apikey API-XXX -olddeployment "Deployments-65171" -newdeployment "Deployments-67194" -envstocheck @('Environments-803','Environments-1001')
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
    $olddeployment,

    [Parameter()]
    [string]
    $newdeployment,

    [Parameter()]
    [array]
    $envstocheckname,

    [Parameter()]
    [array]
    $deploymentenv,

    $header =  @{ "X-Octopus-ApiKey" = $apiKey }

)

$ErrorActionPreference = 'stop'

write-host "The current working directory is "$pwd.path

$defaultSpaceId = ((Invoke-WebRequest -Uri "$octopusURI/api/spaces/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $defaultSpaceName}).id

if ($deploymentenv -eq "Pre-Production") {
    $deploymentenv = "Production"
}

Write-Host "The deployment environment is $deploymentenv. Trying to grab the most recent deployment for $deploymentenv in this project."

$projectid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/deployments/$newdeployment" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).projectid
$deploymentenvid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Environments/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.Name -eq $deploymentenv}).id
$deployments = (Invoke-WebRequest "$OctopusURI/api/$defaultSpaceId/deployments?take=5000" -Headers $header | ConvertFrom-Json -Depth 12).items

Write-Verbose "The env ID for $deploymentenv is $deploymentenvid"
Write-Verbose "The deployments for this deployment ID are $deployments"

foreach ($deployment in $deployments) {
    Write-Verbose " "
    Write-Verbose "Checking $($deployment.id)"
    Write-verbose "$($deployment.id) has a env of $($deployment.EnvironmentId) and a Project ID of $($deployment.projectid)"
    if ($deployment.ProjectId -eq $projectid -and $deployment.EnvironmentId -eq $deploymentenvid) {
        Write-Verbose "$($deployment.id) matches the criteria of a matching deployment."
        $result = (Invoke-WebRequest "$OctopusURI/api/$defaultSpaceId/tasks/$($deployment.TaskId)" -Headers $header | ConvertFrom-Json).state
        Write-Verbose $result
        if ($result -eq "Success") {
            $olddeployment = $deployment.id
            Write-Host "The old deployment we will compare against is $olddeployment"
            break
        }
    }
}

if ([string]::IsNullOrEmpty($olddeployment)) {
    Write-Warning "Can't diff the variables as we don't have an old deployment to compare against."
}
else {
    $oldreleaseid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Deployments/$olddeployment" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).releaseId
    $newreleaseid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Deployments/$newdeployment" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).releaseId
    $oldrelease = Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/releases/$oldreleaseid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12
    $newrelease = Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/releases/$newreleaseid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12
    $newlibvars = $newrelease.LibraryVariableSetSnapshotIds
    $oldlibvars = $oldrelease.LibraryVariableSetSnapshotIds

    if ([string]::IsNullOrEmpty($envstocheckname)) {
        $envstocheck = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Environments/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).id
    }
    else {
        $envstocheck = @()
        foreach ($envname in $envstocheckname) {
            $envid = ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/Environments/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12) | Where-Object {$_.name -eq $envname}).id
            $envstocheck += $envid
        }
    }

    Write-Verbose "Default space ID is $defaultspaceId"

    Write-Verbose " "
    Write-Verbose "Old release details"
    Write-Verbose "Old release ID is $oldreleaseid"
    Write-Verbose "Old release is $oldrelease"
    Write-Verbose "Old release library snapshots are $oldlibvars"

    Write-Verbose " "
    Write-Verbose "New release details"
    Write-Verbose "New release ID is $newreleaseid"
    Write-Verbose "Old release is $newrelease"
    Write-Verbose "Old release library snapshots are $newlibvars"

    if ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/releases/$oldreleaseid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).projectid -eq (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/releases/$newreleaseid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).projectid) {
        $projectid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/releases/$newreleaseid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).projectid
        $projectname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/projects/$projectid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
        
        $prevVariablesUri = $oldrelease.ProjectVariableSetSnapshotId
        $latestVariablesUri = $newrelease.ProjectVariableSetSnapshotId

        $libarr = @()

        Write-Host "Checking the project variables" -ForegroundColor Cyan
        if ($latestVariablesUri -eq $prevVariablesUri) {
            Write-Host "The two releases uses the same project variable snapshots" -ForegroundColor Green
        }
        else {
            $latestVariables = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$latestVariablesUri" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables
            $prevVariables = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$prevVariablesUri" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables

            foreach ($newvar in $latestVariables) {
                $newvarname = $newvar.name
                $newprovarscopeenv = $newvar.Scope.environment
                $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                if ($newvar.id -in $prevVariables.id) {
                    foreach ($oldvar in $prevVariables) {
                        $oldprovarscopeenv = $oldvar.Scope.environment
                        $newenvinvar = @($newprovarscopeenv | Where-Object {$envstocheck  -contains $_})
                        $oldenvinvar = @($oldprovarscopeenv | Where-Object {$envstocheck  -contains $_})
                        if (($newenvinvar.Count -gt 0) -or ($null -eq $newprovarscopeenv) -or ($oldenvinvar.Count -gt 0) -or ($null -eq $oldprovarscopeenv)) {
                            if ($oldvar.id -eq $newvar.Id) {
                                Write-Verbose ("Checking matching variable - $newvarname")
                                if ($oldvar.value -ne $newvar.value) {
                                    Write-Verbose ("$newvarname values don't match, checking scopes")
                                    if (Compare-Object "$oldprovarscopeenv" "$newprovarscopeenv") {
                                        Write-Verbose ("for $newvarname, scopes don't match")
                                        $result.VariableName = $oldvar.name
                                        $result.VariableState = "Updated"
                                        if ($newvar.Type -eq "Sensitive") {
                                            $result.newvalue = "*********************"
                                            $result.oldvalue = "*********************"
                                        }
                                        else {
                                            $result.newvalue = $newvar.Value
                                            $result.oldvalue = $oldvar.Value
                                        }
                                        $result.type = $newvar.Type
                                        $result.SetName = $ProjectName
                                        $result.ProjectOrLibrarySet = "Project"
                                        $oldenvs = @()
                                        if ($null -eq $oldprovarscopeenv) {
                                            $oldenvs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $oldprovarscopeenv) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $oldenvs += $envname
                                            }
                                        }
                                        $newenvs = @()
                                        if ($null -eq $newprovarscopeenv) {
                                            $newenvs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $newprovarscopeenv) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $newenvs += $envname
                                            }
                                        }
                                        [string]$oldenvstring = $null
                                        $oldenvstring = $oldenvs -join ","
                                        [string]$newenvstring = $null
                                        $newenvstring = $newenvs -join ","
                                        $result.newenvironment = $newenvstring
                                        $result.oldenvironment = $oldenvstring
                                        $libarr += $Result
                                    }
                                    else {
                                        Write-Verbose ("for $newvarname, scopes match")
                                        $result.VariableName = $oldvar.name
                                        $result.VariableState = "Updated"
                                        if ($newvar.Type -eq "Sensitive") {
                                            $result.newvalue = "*********************"
                                            $result.oldvalue = "*********************"
                                        }
                                        else {
                                            $result.newvalue = $newvar.Value
                                            $result.oldvalue = $oldvar.Value
                                        }
                                        $result.type = $newvar.Type
                                        $result.SetName = $ProjectName
                                        $result.ProjectOrLibrarySet = "Project"
                                        $envs = @()
                                        if ($null -eq $newprovarscopeenv) {
                                            $envs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $newprovarscopeenv) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $envs += $envname
                                            }
                                        }
                                        [string]$envstring = $null
                                        $envstring = $envs -join ","
                                        $result.oldenvironment = $envstring
                                        $result.newenvironment = $envstring
                                        $libarr += $Result
                                    }
                                }
                                else {
                                    Write-Verbose ("$newvarname values match, checking the scope")
                                    if (Compare-Object "$oldprovarscopeenv" "$newprovarscopeenv") {
                                        Write-Verbose ("$newvarname scopes don't match")
                                        $result.VariableName = $oldvar.name
                                        $result.VariableState = "Updated"
                                        if ($newvar.Type -eq "Sensitive") {
                                            $result.newvalue = "*********************"
                                            $result.oldvalue = "*********************"
                                        }
                                        else {
                                            $result.newvalue = $oldvar.Value
                                            $result.oldvalue = $oldvar.Value
                                        }
                                        $result.type = $newvar.Type
                                        $result.SetName = $ProjectName
                                        $result.ProjectOrLibrarySet = "Project"
                                        $oldenvs = @()
                                        if ($null -eq $oldprovarscopeenv) {
                                            $oldenvs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $oldprovarscopeenv) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $oldenvs += $envname
                                            }
                                        }
                                        $newenvs = @()
                                        if ($null -eq $newprovarscopeenv) {
                                            $newenvs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $newprovarscopeenv) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $newenvs += $envname
                                            }
                                        }
                                        [string]$oldenvstring = $null
                                        $oldenvstring = $oldenvs -join ","
                                        [string]$newenvstring = $null
                                        $newenvstring = $newenvs -join ","
                                        $result.newenvironment = $newenvstring
                                        $result.oldenvironment = $oldenvstring
                                        $libarr += $Result
                                    }
                                Write-Verbose ("For $newvarname, scopes match")
                                }
                            }
                        }
                    }
                }
                else {
                    $envinvar = @($newprovarscopeenv | Where-Object {$envstocheck  -contains $_})
                    if (($envinvar.Count -gt 0) -or ($null -eq $newprovarscopeenv)) {
                        Write-Verbose ("$newvarname has been found in the current deployment but not the old.")
                        $result.VariableName = $newvar.name
                        $result.VariableState = "New"
                        $result.oldvalue = $null
                        if ($newvar.Type -eq "Sensitive") {
                            $result.newvalue = "*********************"
                        }
                        else {
                            $result.newvalue = $newvar.Value
                        }
                        $result.type = $newvar.Type
                        $envs = @()
                        if ($null -eq $newprovarscopeenv) {
                            $envs = "Unscoped"
                        }
                        else {
                            foreach ($env in $newprovarscopeenv) {
                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                $envs += $envname
                            }
                        }
                        [string]$envstring = $null
                        $envstring = $envs -join ","
                        $result.oldenvironment = $null
                        $result.newenvironment = $envstring
                        $result.SetName = $projectname
                        $result.ProjectOrLibrarySet = "Project"
                        $libarr += $Result
                    }
                }
            }
            foreach ($oldprovar in $prevVariables) {
                $oldprovarname = $oldprovar.Name
                $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                if ($oldprovar.id -notin $latestVariables.id) {
                    $envinvar = @($oldprovar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                    if (($envinvar.Count -gt 0) -or ($null -eq $oldprovar.Scope.environment)) {
                        Write-Verbose ("$oldprovarname has not been found in the current deployment.")
                        $result.VariableName = $oldprovar.name
                        $result.VariableState = "Deleted"
                        if ($oldprovar.Type -eq "Sensitive") {
                            $result.newvalue = "Deleted"
                            $result.oldvalue = "*********************"
                        }
                        else {
                            $result.newvalue = "Deleted"
                            $result.oldvalue = $oldprovar.Value
                        }
                        $result.type = $oldprovar.Type
                        $result.SetName = $ProjectName
                        $result.ProjectOrLibrarySet = "Project"
                        $envs = @()
                        if ($null -eq $oldprovar.Scope.environment) {
                            $envs = "Unscoped"
                        }
                        else {
                            foreach ($env in $oldprovar.Scope.environment) {
                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                $envs += $envname
                            }
                        }
                        [string]$envstring = $null
                        $envstring = $envs -join ","
                        $result.oldenvironment = $envstring
                        $result.newenvironment = "Deleted"
                        $libarr += $Result
                    }
                }
            }
        }
        if ([string]::IsNullOrEmpty($newlibvars) -and [string]::IsNullOrEmpty($oldlibvars)) {
            Write-host " "
            Write-host "Skipping library variables there are no library variables in the old or current deployment." -ForegroundColor Yellow
        }
        else {
            Write-host " "
            Write-Host "Checking libary sets" -ForegroundColor Cyan
            $oldlibvarownerids = @()
            foreach ($oldlibvar1 in $oldlibvars) {
                $oldlibownerid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar1" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).OwnerId
                $oldlibvarownerids += $oldlibownerid
            }
            $newlibvarownerids = @()
            foreach ($newlibvar1 in $newlibvars) {
                $newlibownerid = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$newlibvar1" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).OwnerId
                $newlibvarownerids += $newlibownerid
            }
            if ($newlibvars) {
                foreach ($libvar in $newlibvars) {
                    if ($oldlibvars) {
                        foreach ($oldlibvar in $oldlibvars) {
                            if ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).OwnerId -notin $newlibvarownerids) {
                                $oldlibvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                                $oldlibid = ($oldlibvar | Select-String -Pattern 'LibraryVariableSets-(\d*)').Matches.Value
                                $libname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$oldlibid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                Write-host "This Library variableset - $libname, has been deleted since after the deployment you're comparing against" -ForegroundColor Yellow
                                foreach ($oldvar in $oldlibvarvars) {
                                    $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                                    $envinvar = @($oldvar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                                    if (($envinvar.Count -gt 0) -or ($null -eq $oldvar.Scope.environment)) {
                                        $result.VariableName = $oldvar.name
                                        $result.VariableState = "Deleted"
                                        if ($newvar.Type -eq "Sensitive") {
                                            $result.newvalue = "Deleted"
                                            $result.oldvalue = "*********************"
                                        }
                                        else {
                                            $result.newvalue = "Deleted"
                                            $result.oldvalue = $oldvar.Value
                                        }
                                        $result.type = $newvar.Type
                                        $result.SetName = $libname
                                        $result.ProjectOrLibrarySet = "Library"
                                        $envs = @()
                                        if ($null -eq $oldvar.Scope.environment) {
                                            $envs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $oldvar.Scope.environment) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $envs += $envname
                                            }
                                        }
                                        [string]$envstring = $null
                                        $envstring = $envs -join ","
                                        $result.oldenvironment = $envstring
                                        $result.newenvironment = "Deleted"
                                        $libarr += $Result
                                    }
                                }
                            }
                            if ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$libvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).OwnerId -in $oldlibvarownerids) {
                                if ($oldlibvar.split("-")[2] -eq $libvar.split("-")[2]) {
                                    Write-Host " "
                                    Write-Host "matching $libvar to $oldlibvar" -ForegroundColor Cyan
                                    $oldversion = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).Version
                                    $newversion = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$libvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).Version
                                    if ($oldversion -ne $newversion) {
                                        Write-Host "The version are not the same! Checking if any changes have happened in the environments you've scoped." -ForegroundColor Yellow
                                        $libname = ($libvar | Select-String -Pattern 'LibraryVariableSets-(\d*)').Matches.Value
                                        $oldlibvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                                        $libvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$libvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                                        foreach ($newvar in $libvarvars) {
                                            $newvarname = $newvar.name
                                            $newvarscopeenv = $newvar.Scope.Environment
                                            $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                                            if ($newvar.Id -in $oldlibvarvars.id) {
                                                foreach ($oldvar in $oldlibvarvars) {
                                                    $oldvarscopeenv = $oldvar.Scope.Environment
                                                    $newenvinvar = @($newvarscopeenv | Where-Object {$envstocheck  -contains $_})
                                                    $oldenvinvar = @($oldvarscopeenv | Where-Object {$envstocheck  -contains $_})
                                                    if (($newenvinvar.Count -gt 0) -or ($null -eq $newvarscopeenv) -or ($oldenvinvar.Count -gt 0) -or ($null -eq $oldvarscopeenv)) {
                                                        if ($oldvar.id -eq $newvar.Id) {
                                                            Write-Verbose ("Checking matching variable - $newvarname")
                                                            if ($oldvar.value -ne $newvar.value) {
                                                                Write-Verbose ("$newvarname values don't match, checking scopes")
                                                                if (Compare-Object "$oldvarscopeenv" "$newvarscopeenv") {
                                                                    Write-Verbose ("for $newvarname, scopes don't match")
                                                                    $result.VariableName = $oldvar.name
                                                                    $result.VariableState = "Updated"
                                                                    if ($newvar.Type -eq "Sensitive") {
                                                                        $result.newvalue = "*********************"
                                                                        $result.oldvalue = "*********************"
                                                                    }
                                                                    else {
                                                                        $result.newvalue = $newvar.Value
                                                                        $result.oldvalue = $oldvar.Value
                                                                    }
                                                                    $result.type = $newvar.Type
                                                                    $result.SetName = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libname" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                    $result.ProjectOrLibrarySet = "Library"
                                                                    $oldenvs = @()
                                                                    if ($null -eq $oldvarscopeenv) {
                                                                        $oldenvs = "Unscoped"
                                                                    }
                                                                    else {
                                                                        foreach ($env in $oldvarscopeenv) {
                                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                            $oldenvs += $envname
                                                                        }
                                                                    }
                                                                    $newenvs = @()
                                                                    if ($null -eq $newvarscopeenv) {
                                                                        $newenvs = "Unscoped"
                                                                    }
                                                                    else {
                                                                        foreach ($env in $newvarscopeenv) {
                                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                            $newenvs += $envname
                                                                        }
                                                                    }
                                                                    [string]$oldenvstring = $null
                                                                    $oldenvstring = $oldenvs -join ","
                                                                    [string]$newenvstring = $null
                                                                    $newenvstring = $newenvs -join ","
                                                                    $result.newenvironment = $newenvstring
                                                                    $result.oldenvironment = $oldenvstring
                                                                    $libarr += $Result
                                                                }
                                                                else {
                                                                    Write-Verbose ("for $newvarname, scopes match")
                                                                    $result.VariableName = $oldvar.name
                                                                    $result.VariableState = "Updated"
                                                                    if ($newvar.Type -eq "Sensitive") {
                                                                        $result.newvalue = "*********************"
                                                                        $result.oldvalue = "*********************"
                                                                    }
                                                                    else {
                                                                        $result.newvalue = $newvar.Value
                                                                        $result.oldvalue = $oldvar.Value
                                                                    }
                                                                    $result.type = $newvar.Type
                                                                    $result.SetName = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libname" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                    $result.ProjectOrLibrarySet = "Library"
                                                                    $envs = @()
                                                                    if ($null -eq $newvarscopeenv) {
                                                                        $envs = "Unscoped"
                                                                    }
                                                                    else {
                                                                        foreach ($env in $newvarscopeenv) {
                                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                            $envs += $envname
                                                                        }
                                                                    }
                                                                    [string]$envstring = $null
                                                                    $envstring = $envs -join ","
                                                                    $result.oldenvironment = $envstring
                                                                    $result.newenvironment = $envstring
                                                                    $libarr += $Result
                                                                }
                                                            }
                                                            else {
                                                                Write-Verbose ("$newvarname values match, checking the scope")
                                                                if (Compare-Object "$oldvarscopeenv" "$newvarscopeenv") {
                                                                    $result.VariableName = $oldvar.name
                                                                    $result.VariableState = "Updated"
                                                                    if ($newvar.Type -eq "Sensitive") {
                                                                        $result.newvalue = "*********************"
                                                                        $result.oldvalue = "*********************"
                                                                    }
                                                                    else {
                                                                        $result.newvalue = $oldvar.Value
                                                                        $result.oldvalue = $oldvar.Value
                                                                    }
                                                                    $result.type = $newvar.Type
                                                                    $result.SetName = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libname" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                    $result.ProjectOrLibrarySet = "Library"
                                                                    $oldenvs = @()
                                                                    if ($null -eq $oldvarscopeenv) {
                                                                        $oldenvs = "Unscoped"
                                                                    }
                                                                    else {
                                                                        foreach ($env in $oldvarscopeenv) {
                                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                            $oldenvs += $envname
                                                                        }
                                                                    }
                                                                    $newenvs = @()
                                                                    if ($null -eq $newvarscopeenv) {
                                                                        $newenvs = "Unscoped"
                                                                    }
                                                                    else {
                                                                        foreach ($env in $newvarscopeenv) {
                                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                                            $newenvs += $envname
                                                                        }
                                                                    }
                                                                    [string]$oldenvstring = $null
                                                                    $oldenvstring = $oldenvs -join ","
                                                                    [string]$newenvstring = $null
                                                                    $newenvstring = $newenvs -join ","
                                                                    $result.newenvironment = $newenvstring
                                                                    $result.oldenvironment = $oldenvstring
                                                                    $libarr += $Result
                                                                }
                                                            Write-Verbose ("For $newvarname, scopes match")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            if ($newvar.Id -notin $oldlibvarvars.id) {
                                                $envinvar = @($newvarscopeenv | Where-Object {$envstocheck  -contains $_})
                                                if (($envinvar.Count -gt 0) -or ($null -eq $newvarscopeenv)) {
                                                    Write-Verbose ("$newvarname has been found in the current deployment but not the old.")
                                                    $result.VariableName = $newvar.name
                                                    $result.VariableState = "New"
                                                    $result.oldvalue = $null
                                                    if ($newvar.Type -eq "Sensitive") {
                                                        $result.newvalue = "*********************"
                                                    }
                                                    else {
                                                        $result.newvalue = $newvar.Value
                                                    }
                                                    $result.type = $newvar.Type
                                                    $envs = @()
                                                    if ($null -eq $newvarscopeenv) {
                                                        $envs = "Unscoped"
                                                    }
                                                    else {
                                                        foreach ($env in $newvarscopeenv) {
                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                            $envs += $envname
                                                        }
                                                    }
                                                    [string]$envstring = $null
                                                    $envstring = $envs -join ","
                                                    $result.oldenvironment = $null
                                                    $result.newenvironment = $envstring
                                                    $result.SetName = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libname" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                    $result.ProjectOrLibrarySet = "Library"
                                                    $libarr += $Result
                                                }
                                            }
                                        }
                                        foreach ($oldvar in $oldlibvarvars) {
                                            $oldvarname = $oldvar.Name
                                            $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                                            if ($oldvar.id -notin $libvarvars.id) {
                                                $envinvar = @($oldvar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                                                if (($envinvar.Count -gt 0) -or ($null -eq $oldvar.Scope.environment)) {
                                                    Write-Verbose ("$oldvarname has not been found in the current deployment.")
                                                    $result.VariableName = $oldvar.name
                                                    $result.VariableState = "Deleted"
                                                    if ($newvar.Type -eq "Sensitive") {
                                                        $result.newvalue = "Deleted"
                                                        $result.oldvalue = "*********************"
                                                    }
                                                    else {
                                                        $result.newvalue = "Deleted"
                                                        $result.oldvalue = $oldvar.Value
                                                    }
                                                    $result.type = $newvar.Type
                                                    $result.SetName = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libname" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                    $result.ProjectOrLibrarySet = "Library"
                                                    $envs = @()
                                                    if ($null -eq $oldvar.Scope.environment) {
                                                        $envs = "Unscoped"
                                                    }
                                                    else {
                                                        foreach ($env in $oldvar.Scope.environment) {
                                                            $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                            $envs += $envname
                                                        }
                                                    }
                                                    [string]$envstring = $null
                                                    $envstring = $envs -join ","
                                                    $result.oldenvironment = $envstring
                                                    $result.newenvironment = "Deleted"
                                                    $libarr += $Result
                                                }
                                            }
                                        }
                                    }
                                    else {
                                        Write-Host "The version are the same, no need to check!" -ForegroundColor Green
                                    }
                                }
                            }
                            else {
                                $libvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$libvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                                $libid = ($libvar | Select-String -Pattern 'LibraryVariableSets-(\d*)').Matches.Value
                                $libname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                Write-host "This Library variableset - $libname, has been added since after the deployment you're comparing against" -ForegroundColor Yellow
                                foreach ($newvar in $libvarvars) {
                                    $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                                    $envinvar = @($newvar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                                    if (($envinvar.Count -gt 0) -or ($null -eq $newvar.Scope.environment)) {
                                        $result.VariableName = $newvar.name
                                        $result.VariableState = "New"
                                        if ($newvar.Type -eq "Sensitive") {
                                            $result.newvalue = "*********************"
                                        }
                                        else {
                                            $result.newvalue = $newvar.Value
                                        }
                                        $result.type = $newvar.Type
                                        $result.SetName = $libname
                                        $result.ProjectOrLibrarySet = "Library"
                                        $envs = @()
                                        if ($null -eq $newvar.Scope.environment) {
                                            $envs = "Unscoped"
                                        }
                                        else {
                                            foreach ($env in $newvar.Scope.environment) {
                                                $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                                $envs += $envname
                                            }
                                        }
                                        [string]$envstring = $null
                                        $envstring = $envs -join ","
                                        $result.newenvironment = $envstring
                                        $libarr += $Result
                                    }
                                }
                            break
                            }
                        }
                    }
                    else {
                        $libvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$libvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                        $libid = ($libvar | Select-String -Pattern 'LibraryVariableSets-(\d*)').Matches.Value
                        $libname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$libid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                        Write-host "This Library variableset - $libname, has been added since after the deployment you're comparing against" -ForegroundColor Yellow
                        foreach ($newvar in $libvarvars) {
                            $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                            $envinvar = @($newvar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                            if (($envinvar.Count -gt 0) -or ($null -eq $newvar.Scope.environment)) {
                                $result.VariableName = $newvar.name
                                $result.VariableState = "New"
                                if ($newvar.Type -eq "Sensitive") {
                                    $result.newvalue = "*********************"
                                }
                                else {
                                    $result.newvalue = $newvar.Value
                                }
                                $result.type = $newvar.Type
                                $result.SetName = $libname
                                $result.ProjectOrLibrarySet = "Library"
                                $envs = @()
                                if ($null -eq $newvar.Scope.environment) {
                                    $envs = "Unscoped"
                                }
                                else {
                                    foreach ($env in $newvar.Scope.environment) {
                                        $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                        $envs += $envname
                                    }
                                }
                                [string]$envstring = $null
                                $envstring = $envs -join ","
                                $result.newenvironment = $envstring
                                $libarr += $Result
                            }
                        }
                    }
                }
            }
            else {
                foreach ($oldlibvar in $oldlibvars) {
                    if ((Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).OwnerId -notin $newlibvarownerids) {
                        $oldlibvarvars = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/variables/$oldlibvar" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).variables 
                        $oldlibid = ($oldlibvar | Select-String -Pattern 'LibraryVariableSets-(\d*)').Matches.Value
                        $libname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/libraryVariableSets/$oldlibid" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                        Write-host "This Library variableset - $libname, has been deleted since after the deployment you're comparing against" -ForegroundColor Yellow
                        foreach ($oldvar in $oldlibvarvars) {
                            $result = "" | Select ProjectOrLibrarySet,SetName,VariableName,VariableState,OldValue,NewValue,Type,OldEnvironment,NewEnvironment
                            $envinvar = @($oldvar.Scope.environment | Where-Object {$envstocheck  -contains $_})
                            if (($envinvar.Count -gt 0) -or ($null -eq $oldvar.Scope.environment)) {
                                $result.VariableName = $oldvar.name
                                $result.VariableState = "Deleted"
                                if ($oldvar.Type -eq "Sensitive") {
                                    $result.newvalue = "Deleted"
                                    $result.oldvalue = "*********************"
                                }
                                else {
                                    $result.newvalue = "Deleted"
                                    $result.oldvalue = $oldvar.Value
                                }
                                $result.type = $oldvar.Type
                                $result.SetName = $libname
                                $result.ProjectOrLibrarySet = "Library"
                                $envs = @()
                                if ($null -eq $oldvar.Scope.environment) {
                                    $envs = "Unscoped"
                                }
                                else {
                                    foreach ($env in $oldvar.Scope.environment) {
                                        $envname = (Invoke-WebRequest -Uri "$octopusURI/api/$defaultSpaceId/environments/$env" -Method GET -Headers $header | ConvertFrom-Json -Depth 12).name
                                        $envs += $envname
                                    }
                                }
                                [string]$envstring = $null
                                $envstring = $envs -join ","
                                $result.oldenvironment = $envstring
                                $result.newenvironment = "Deleted"
                                $libarr += $Result
                            }
                        }
                    }
                }
            }
            if ($null -ne $libarr) {
                $filedate = get-date -format "ddMMyyyyHHmm"
                Write-host "Please see variable changes below."
                $libarr | Format-Table -AutoSize | Out-String -Width 10000
                $libarr | Export-Csv "$($projectname)_VariableChanges_$filedate.csv" -NoTypeInformation
                New-OctopusArtifact -Path "$($projectname)_VariableChanges_$filedate.csv" -Name "$($projectname)_VariableChanges_$filedate.csv"
            }
            else {
                Write-host "There are no changes to display."
            }
        }
    }
    else {
        Write-Warning "You are trying to diff variables across two projects! Please ensure you are selecting a deployment from the current project."
    }
}
