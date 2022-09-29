<#
.SYNOPSIS
    Finds the latest successful deployment in the source environment and tenant and deploys to a target environment and tenant, based on deployment type in the Octopus description
.DESCRIPTION
    Finds the latest successful deployment in the source environment and tenant and deploys to a target environment and tenant, specify -updatevariables $true to update the variable snapshot,
    this will only action on Feature channel releases.
.EXAMPLE
    Refresh-OctopusEnvironment.ps1 -octopusURI "https://octopus.ctazure.co.uk" -defaultSpaceName "Apps" -sourceenv "Production" -sourcetenant "PDW" -targetenv "FT2" -targettenant "per" `
    -targetchannel "Feature" -targetdescriptions 'API Host,API IIS Site' -apikey 'API-XXXXXXXX' -updatevariables $true
#>

[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $octopusURI,

    [Parameter()]
    [string]
    $defaultSpaceName,

    [Parameter()]
    [string]
    $sourceenv,

    [Parameter()]
    [string]
    $sourcetenant,

    [Parameter()]
    [string]
    $targetenv,

    [Parameter()]
    [string]
    $targettenant,

    [Parameter()]
    [string]
    $targetchannel,

    [Parameter()]
    [string[]]
    $targetdescriptions,

    [Parameter()]
    [string]
    $apikey,

    [Parameter()]
    [string]
    $updatevariables

)

function Deploy-Release {
    param (
        [Parameter()]
        [string]
        $ReleaseId,
        [Parameter()]
        [string]
        $EnvironmentId,
        [Parameter()]
        [string]
        $TenantId
    )
    #Creating deployment
    $DeploymentBody = @{ 
        ReleaseID = $ReleaseId
        EnvironmentID = $EnvironmentId
        TenantID = $TenantId
    }
    try {
        $NewDeployment = Invoke-WebRequest -Uri $octopusAPIURI/deployments -Method Post -Headers $Header -Body ($DeploymentBody | ConvertTo-Json -depth 10)
    }
    catch {
        Write-Verbose "An exception was caught: $($_.Exception.Message)"
        Write-Warning "Deployment failed, ErrorMessage: $($($_.ErrorDetails.Message | ConvertFrom-Json).Errors)"
    }
    return
}

$header =  @{ "X-Octopus-ApiKey" = $apiKey }

$ErrorActionPreference = 'silentlycontinue'
#$defaultSpaceId = (Invoke-WebRequest -Uri "$octopusURI/api/spaces/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12 | Where-Object {$_.Name -eq $defaultSpaceName}).id
$octopusAPIURI = "$octopusURI/api/Spaces-63"

$dashboardInformation = Invoke-RestMethod -Uri "$octopusAPIURI/dashboard?highestLatestVersionPerProjectAndEnvironment=true" -Headers $header
$environmentToUse = $dashboardInformation.Environments | Where-Object {$_.Name -eq $sourceenv}
$deploymentsToEnvironment = @($dashboardInformation.Items | Where-Object {$_.EnvironmentId -eq $environmentToUse.Id})

$tenant = (Invoke-RestMethod -Uri "$octopusAPIURI/tenants/all" -Method GET -Headers $header) | Where-Object {$_.Name -eq $sourcetenant}

$projects = Invoke-WebRequest -Uri "$octopusAPIURI/projects/all" -Method GET -Headers $header | ConvertFrom-Json -Depth 12
$projlist = $projects | Where-Object {$_.Description -in $targetdescriptions.Split(",")}

foreach ($project in $projlist) {
    Write-Host "---------------------------------------------------------"
    $NewRelease = $null
    Write-Verbose "Checking $($project.Name) for $sourceenv releases with $sourcetenant tenant"
    $deployment = $deploymentsToEnvironment | Where-Object {$_.ProjectId -eq $project.id -and $_.TenantId -eq $tenant.id}

    if ($deployment) {
        if ($deployment.State -eq "Success") {
            Write-Host "Found successful deployment of $($project.Name) $($deployment.ReleaseVersion) in $sourceenv with $sourcetenant"
            # Finds the release in order to build up the releasebody for new releases
            $release = Invoke-WebRequest -Uri "$octopusAPIURI/releases/$($deployment.ReleaseId)" -Method GET -Headers $header | ConvertFrom-Json -Depth 12
            # Finds the Channel id of the target channel
            $channel = (Invoke-RestMethod -Method Get -Uri "$octopusAPIURI/projects/$($project.Id)/channels" -Headers $header).Items | Where-Object {$_.Name -eq $targetchannel}
            # Gets a list of the current releases for the project
            $releaselist = Invoke-WebRequest -Uri "$octopusAPIURI/projects/$($project.id)/releases" -Method GET -Headers $header | ConvertFrom-Json -Depth 12
            # Gets the target environment id for deployment
            $targetenvirid = ((Invoke-RestMethod -Uri "$octopusAPIURI/environments?take=100" -Method GET -Headers $header).Items | Where-Object {$_.Name -eq $targetenv}).Id
            # Gets the target tenant id for deployment
            $targettenantid = ((Invoke-RestMethod -Uri "$octopusAPIURI/tenants/all" -Method GET -Headers $header) | Where-Object {$_.Name -eq $targettenant}).Id

            if ($targetchannel -eq "Feature") {
                # Checking for existing release to determine whether to create a new one or use an existing one
                $NewReleaseVersion = "$($release.Version)-$targettenant"

                if ($NewReleaseVersion -notin $releaselist.Items.Version) {
                    # Creating a new Feature channel release
                    Write-Host "Creating new Feature channel release $NewReleaseVersion and deploying in $targetenv with $targettenant tenant"
                    $releaseBody = @{
                        ChannelId        = $channel.Id
                        ProjectId        = $project.Id
                        ReleaseNotes     = $release.ReleaseNotes
                        Version          = "$($release.Version)-$targettenant"
                        SelectedPackages = $release.SelectedPackages
                    }
                    $NewRelease = try { 
                        Invoke-RestMethod -Uri "$octopusAPIURI/releases" -Method POST -Headers $header -Body ($releaseBody | ConvertTo-Json -depth 10)
                    }
                    catch {
                        Write-Verbose "An exception was caught: $($_.Exception.Message)"
                        Write-Warning "Release creation failed, ErrorMessage: $($($_.ErrorDetails.Message | ConvertFrom-Json).ErrorMessage)"
                    }
                    if ($NewRelease) {
                        Deploy-Release -ReleaseId $NewRelease.Id -EnvironmentId $targetenvirid -TenantId $targettenantid
                    }
                }
                else {
                    # Deploy the existing release that has been found
                    Write-Host "Using existing Feature channel release $NewReleaseVersion and deploying in $targetenv with $targettenant tenant"
                    $existingreleaseid = $releaselist.Items | Where-Object {$_.Version -eq $NewReleaseVersion} | Select-Object -ExpandProperty Id

                    if ($updatevariables -eq "True") {
                        Write-Verbose "Updating variable set on release $NewReleaseVersion"
                        $snapshotupdate = Invoke-WebRequest "$octopusAPIURI/releases/$existingreleaseid/snapshot-variables" -Method POST -Headers $header
                        if (!($snapshotupdate)) {Write-Warning "Snapshot failed to update"}
                    }
                    Deploy-Release -ReleaseId $existingreleaseid -EnvironmentId $targetenvirid -TenantId $targettenantid
                }                
            }
            else {
                # Deploying the existing release using the Release or Business channel, will not update variable snapshot even if specified
                Write-Host "Deploying existing release $($deployment.ReleaseVersion) to $targetenv with $targettenant tenant"
                Deploy-Release -ReleaseId $release.id -EnvironmentId $targetenvirid -TenantId $targettenantid
            }
        }
        else {
            Write-Warning "Last deployment to $sourceenv was not successful, state was $($deployment.State), skipping deployment"
        }
    }
    else {
        Write-Warning "No deployment found in $sourceenv with $sourcetenant tenant for $($project.Name)"
    }
}
