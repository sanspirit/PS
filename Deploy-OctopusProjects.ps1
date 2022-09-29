<#
.SYNOPSIS
    Finds the latest successful deployment of a project to an environment and deploys it to a project group specified
.DESCRIPTION

.EXAMPLE
    # run locally
    .\src\Deploy-OctopusProjects.ps1 -DestinationSpace Apps -DestinationEnvironment performance -DeployToTenantName prf -ProjectGroups @("Enable")
    .\src\Deploy-OctopusProjects.ps1 -DestinationSpace Apps -DestinationEnvironment FT -DeployToTenantName elt -ProjectGroups @("CTSuite") -TargetChannel Feature

    # or from package in Octopus Step
    Script file: Deploy-OctopusProjects.ps1
    Script params: -apiKey #{OctopusAPIKey} -octopusClientPath #{Octopus.Agent.ProgramDirectoryPath} -DestinationSpace Apps -DestinationEnvironment performance -DeployToTenantName prf -ProjectGroups @("Enable")
#>

[CmdletBinding(SupportsShouldProcess=$True)]
Param (

    [Parameter()]
    [string]
    $octopusURI = "https://octopus.ctazure.co.uk",

    [Parameter()]
    [string]
    $apiKey = "-",

    [Parameter()]
    [string]
    $SourceSpace = "Default",

    [Parameter(Mandatory)]
    [string]
    $DestinationSpace,

#    [Parameter(Mandatory)]
    [Parameter()]
    [string]
    $SourceEnvironment = "Production",

    [Parameter(Mandatory)]
    [string]
    $DestinationEnvironment,

    [Parameter(Mandatory)]
    [string]
    $DeployToTenantName,

    [Parameter()]
    [string]
    $TargetChannel = "Release",

    [Parameter(Mandatory)]
    [string[]]
    $ProjectGroups,
#    $ProjectGroups = @("Enable"),

    [Parameter()]
    [string]
    $OctopusCustomCodeVersion = "1.0.71",

    [Parameter()]
    [string]
    $WAFConfigVersion = "1.0.100",

    [Parameter()]
    [string]
    $octopusClientPath = "-"
)

Begin
{
    $clientdll = "Octopus.Client.dll"

    if (Test-Path -Path .\OctopusApi.key)
    {
        $secureApiKey = Get-Content -Path .\OctopusApi.key | ConvertTo-SecureString
        $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList "Domain\User", $secureApiKey
        $apiKey = $credentials.GetNetworkCredential().Password
        Write-Verbose "Using saved API Key"
    }
    if ($apiKey -eq "-") { throw "no ApiKey was provided" }
    
    if ($octopusClientPath -eq "-")
    {
        if (Test-Path -Path "C:/Program Files/Octopus Deploy/Octopus/$clientdll")
        {
            $octopusClientPath = "C:/Program Files/Octopus Deploy/Octopus"
        }
        else {
            $octopusClientPath = (Get-Item ((Get-Package Octopus.Client).source)).Directory.FullName
            $clientdll = "lib/netstandard2.0/Octopus.Client.dll"    # PS Core 6 - netstandard2
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($octopusClientPath))
    {
        throw "no path for Octopus.Client"
    }
    else
    {
        Write-Output "Using Octopus client path: $octopusClientPath "
    }
    
    $path = Join-Path $octopusClientPath $clientdll
    
    Add-Type -Path $path
    
    $endpoint = New-Object Octopus.Client.OctopusServerEndpoint($octopusURI, $apikey)
    $client = New-Object Octopus.Client.OctopusClient($endpoint)

    # Get default repository and get space by name
    $defaultRepository = $client.ForSystem()

    $srcSpace = $defaultRepository.Spaces.FindByName($SourceSpace)
    $destSpace = $defaultRepository.Spaces.FindByName($DestinationSpace)
 
    # Get space specific repositories
    $repositoryForSrc = $client.ForSpace($srcSpace)
    $repositoryForDest = $client.ForSpace($destSpace)
    
    # Create an array to add the Project Deployment Package Info objects to
    [System.Collections.ArrayList]$deploymentsArray = @()

}
Process
{
    # Get Source Environment
    $srcEnvironment = $repositoryForSrc.Environments.FindByName($SourceEnvironment)
    if ($srcEnvironment)
    {
        Write-Verbose "Environment [$($srcEnvironment.Name)] : has ID $($srcEnvironment.Id)"
    }
    else
    {
        Throw "No Environment by the name $($SourceEnvironment)"
    }

    # Get Destination Environment
    $destEnvironment = $repositoryForDest.Environments.FindByName($DestinationEnvironment)
    if ($destEnvironment)
    {
        Write-Verbose "Dest Environment [$($destEnvironment.Name)] : has ID $($destEnvironment.Id)"
    }
    else
    {
        Throw "No Environment by the name $($DestinationEnvironment)"
    }

    # Get Destination Deployment Tenant
    $deployToTenant = $repositoryForDest.Tenants.FindByName($DeployToTenantName)

    # source project groups
    foreach ($Projectgroupname in $ProjectGroups)
    {
        # Get Project with ProjectGroupName
        $ProjectGroup = $repositoryForSrc.ProjectGroups.FindByName($Projectgroupname)
        if ($ProjectGroup)
        {
            Write-Verbose "ProjectGroup [$($ProjectGroup.Name)] : has ID $($ProjectGroup.Id)"
            $projects = ($repositoryForSrc.Projects.FindAll()) | Where-Object {$PSItem.ProjectGroupId -eq ($ProjectGroup.Id)}
            foreach ($project in $projects)
            {
                if (!$project.IsDisabled)   # don't bother with disabled projects
                {
                    $sourceProjectName = $project.Name
                    Write-Output "Project $($project.Name) $($project.Id)"
                    $dashboard = $repositoryForSrc.Dashboards.GetDynamicDashboard($project.Id, $srcEnvironment.Id)
                    $currentDeployment = $dashboard.Items | Where-Object {$_.IsCurrent} | Select-Object -First 1
                    $releaseChannel = $repositoryForSrc.Channels.Get($currentDeployment.ChannelId)
                    if ($currentDeployment)
                    {
                        $DeploymentProcessId = $repositoryForSrc.Deployments.Get($currentDeployment.DeploymentId).DeploymentProcessId

                        $packages = $repositoryForSrc.Releases.Get($currentDeployment.ReleaseId).SelectedPackages
                        $packageVersion = $packages[0].Version

                        $DeploymentProcesses = $repositoryForSrc.DeploymentProcesses.Get($DeploymentProcessId)
                        if ($DeploymentProcesses)
                        {
                            $steps = $DeploymentProcesses.Steps
                            # look for package deployment steps - not script steps with a custom code package
                            $pkgSteps = $steps.Where({$_.Actions.Packages.Count -gt 0 -and $_.Actions.ActionType -ne 'Octopus.Script'})
                            #$pkgSteps = $steps.Where({$_.Actions.ActionType -eq 'Octopus.TentaclePackage' -or $_.Actions.ActionType -eq 'Octopus.IIS'})

                            if ($pkgSteps)
                            {
                                foreach ($step in $pkgSteps)
                                {
                                    Write-Output "Step Name $($step.Name) "
                                    $pkgActions = $step.Actions.Where({$_.ActionType -eq 'Octopus.TentaclePackage' -or $_.ActionType -eq 'Octopus.IIS'})

                                    foreach ($action in $pkgActions)
                                    {
                                        Write-Output "Step Name $($step.Name)  ActionType $($action.ActionType) packageId $($action.Packages.PrimaryPackage.PackageId)"
                                        if ( ($action.Packages.Count -gt 0) ) #-and ( ($action.ActionType -eq 'Octopus.TentaclePackage') -or ($action.ActionType -eq 'Octopus.IIS')) )
                                        {
                                            $packageId = $action.Packages.PrimaryPackage.PackageId
                                            Write-Output "found package action: $packageId"
                                            #Write-Output "action.Name $($action.Name)"

                                            $deploymentPackageObject = [PSCustomObject]@{
                                                SourceProject = $sourceProjectName
                                                PackageId = $packageId
                                                PackageVersion = $packageVersion
                                                ReleaseVersion = $currentDeployment.ReleaseVersion
                                                ChannelName = $releaseChannel.Name
                                                ProjectId = ""
                                                SelectedPackage = $null
                                            }

                                            # only add once - unique package Id's
                                            if ($deploymentsArray.PackageId -notcontains $deploymentPackageObject.PackageId)
                                            {
                                                $deploymentsArray.Add($deploymentPackageObject) | Out-Null
                                            }
                                            break   # this project will be deployed so break out
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        else
        {
            Throw "No project group by the name $($Projectgroupname)"
        }
    }

    # object array of Deployments to try and match by Package Id
    $deploymentsArray


    # look at all dest Space projects for those using same Package ID in process deployment steps 
    $projects = $repositoryForDest.Projects.GetAll() # .Where({$_.Name -match "AssetHunter" -and $_.Name -notmatch "Chain"})

    if ($projects)
    {
        foreach ($project in $projects)
        {
            if (!$project.IsDisabled)
            {
                $projectDeploymentProcesses = $repositoryForDest.DeploymentProcesses.Get($project.DeploymentProcessId)
                if ($projectDeploymentProcesses)
                {
                    $steps = $projectDeploymentProcesses.Steps
                    #if ( ($action.Packages.Count -gt 0) -and ( ($action.ActionType -eq 'Octopus.TentaclePackage') -or ($action.ActionType -eq 'Octopus.IIS')) )
                    $pkgSteps = $steps.Where({$_.Actions.ActionType -eq 'Octopus.TentaclePackage' -or $_.Actions.ActionType -eq 'Octopus.IIS'})

                    if ($pkgSteps)
                    {
                        foreach ($step in $pkgSteps)
                        {
                            #Write-Output "Step Name $($step.Name)"
                            $pkgActions = $step.Actions.Where({$_.ActionType -eq 'Octopus.TentaclePackage' -or $_.ActionType -eq 'Octopus.IIS'})
                            foreach ($action in $pkgActions)
                            {
                                if ( $action.Packages.Count -gt 0 ) # ($action.ActionType -eq 'Octopus.TentaclePackage') -and
                                {
                                    $matchPackageId = $action.Packages.PrimaryPackage.PackageId
                                    Write-Output "looking for Package Id  $matchPackageId"
                                    $newDeployment = $deploymentsArray | Where-Object{$_.PackageId -eq $matchPackageId}

                                    if ($newDeployment)
                                    {
                                        Write-Output "Match found in Project: $($project.Name)"
                                        $newDeployment.ProjectId = $project.Id
                                        $pkg = new-object Octopus.Client.Model.SelectedPackage($action.Name, $newDeployment.PackageVersion)
                                        $newDeployment.SelectedPackage = $pkg
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        foreach ($newDep in $deploymentsArray.Where({$_.ProjectId -ne ""}))
        {
            # Create new Release for Project found matching package Id
            $project = $repositoryForDest.Projects.Get($newDep.ProjectId)

            $process = $repositoryForDest.DeploymentProcesses.Get($project.DeploymentProcessId)
            Write-Output "was originaly deployed on $($newDep.ChannelName) channel"
            # deploy to TargetChannel (default "Release")
            $channel = $repositoryForDest.Channels.FindByName($project, $TargetChannel)
            $template = $repositoryForDest.DeploymentProcesses.GetTemplate($process, $channel)
            
            $release = new-object Octopus.Client.Model.ReleaseResource
            $release.SpaceId = $destSpace.Id
            $release.ProjectId = $project.Id
            $release.ChannelId = $channel.Id
            $newRelVer = $($newDep.ReleaseVersion) -Replace("-Release", "") -Replace("-Hotfix", "")
            $release.Version = "$newRelVer-$DeployToTenantName"
            
            foreach ($package in $template.Packages)
            {
                if ($package.ActionName -eq $newDep.SelectedPackage.ActionName)
                {
                    $selectedPackage = $newDep.SelectedPackage
                }
                else
                {
                    $selectedPackage = new-object Octopus.Client.Model.SelectedPackage
                    $selectedPackage.ActionName = $package.ActionName
                    $selectedPackage.PackageReferenceName = $package.PackageReferenceName
                    if ($null -eq $package.VersionSelectedLastRelease)
                    {
                        if ($package.ActionName.StartsWith("WAF_"))
                        {
                            $selectedPackage.Version = $WAFConfigVersion
                        }
                        else
                        {
                            $selectedPackage.Version = $OctopusCustomCodeVersion
                        }
                    }
                    else
                    {
                        $selectedPackage.Version = $package.VersionSelectedLastRelease # Select last used version
                    }
                }
                $release.SelectedPackages.Add($selectedPackage)
            }
            
            try {
                if ($PSCmdlet.ShouldProcess($release.ProjectId))
                {
                    $rel = $null
                    # check if a Release already exists for this Project/Channel
                    $progressions = $repositoryForDest.Projects.GetProgression($project).Releases.Where({$_.Channel.Id -eq $release.ChannelId})

                    foreach ($existingRel in $progressions.Release)
                    {
                        if ($existingRel.Version -eq $release.Version)
                        {
                            $rel = $existingRel
                        }
                    }
                    if ($rel)
                    {
                        Write-Output "Release version $($release.Version) already exists"
                    }
                    else
                    {
                        $rel = $repositoryForDest.Releases.Create($release, $false)
                    }

                    # deploy the new Release
                    $deployment = New-Object Octopus.Client.Model.DeploymentResource
                    $deployment.ReleaseId = $rel.Id
                    $deployment.EnvironmentId = $destEnvironment.Id
                    $deployment.TenantId = $deployToTenant.Id
        
                    $repositoryForDest.Deployments.Create($deployment)
                }
            }
            catch [Exception] {
                #$_.Exception | format-list
                Write-Warning "Failed to invoke $($_.Exception.Message)"
            }

        }
    }

}
