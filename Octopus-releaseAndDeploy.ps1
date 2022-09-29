<#
.SYNOPSIS
    Effects deployments of releases of a given project in Octopus. 
.DESCRIPTION
    Checks for the existance of a given release version and creates a release if one cannot be found that matches.
    The release is then deployed permitting the environment doesn't match Production
.EXAMPLE
    .\Octopus-releaseAndDeploy.ps1 
        -octopusAPIKey 'XXXXXXXXXX' -spaceName 'Platform' -projectName 'AzureWebApp'
        -environmentName 'Development' -tenantName 'MDemo' -channelName 'Demo'
        -releaseName '0.0.95'
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $True)] [string] $octopusAPIKey,
    [Parameter(Mandatory = $True)] [string] $spaceName,
    [Parameter(Mandatory = $True)] [string] $projectName,
    [Parameter(Mandatory = $True)] [string] $environmentName,
    [Parameter(Mandatory = $True)] [string] $tenantName,
    [Parameter(Mandatory = $True)] [string] $channelName,
    [Parameter(Mandatory = $True)] [string] $releaseName
)

$ErrorActionPreference = "Stop";
# Define working variables
$headers = @{ "X-Octopus-ApiKey" = $octopusAPIKey }
$octopusBaseURL = 'https://octopus.ctazure.co.uk/api'

$spaces = Invoke-WebRequest -Uri "$octopusBaseURL/spaces/all" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
$space = $spaces | Where-Object { $_.Name -eq $spaceName }
Write-Output "Using Space named $($space.Name) with id $($space.Id)"

# Create space specific url
$octopusSpaceUrl = "$octopusBaseURL/$($space.Id)"

# Get project by name
$projects = Invoke-WebRequest -Uri "$octopusSpaceUrl/projects/all" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
$project = $projects | Where-Object { $_.Name -eq $projectName }
Write-Output "Using Project named $($project.Name) with id $($project.Id)"

# Get channel by name
$channels = Invoke-WebRequest -Uri "$octopusSpaceUrl/projects/$($project.Id)/channels" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
$channel = $channels.items | Where-Object { $_.Name -eq $channelName }
Write-Output "Using Channel named $($channel.Name) with id $($channel.Id)"

# Get environment by name
$environments = Invoke-WebRequest -Uri "$octopusSpaceUrl/environments/all" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
$environment = $environments | Where-Object { $_.Name -eq $environmentName }
Write-Output "Using Environment named $($environment.Name) with id $($environment.Id)"

# Get tenant by name
$tenants = Invoke-WebRequest -Uri "$octopusSpaceUrl/tenants/all" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
$tenant = $tenants | where-object {$_.Name -eq $tenantName}

# Get the deployment process template
Write-Output "Fetching deployment process template..."
$template = Invoke-WebRequest -Uri "$octopusSpaceUrl/deploymentprocesses/deploymentprocess-$($project.id)/template?channel=$($channel.Id)" -UseBasicParsing -Headers $headers | ConvertFrom-Json

# Check if the release already exists before creating one
$releases = Invoke-WebRequest -Uri "$octopusSpaceUrl/projects/$($project.Id)/releases" -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json

if ( -Not ($releases.items | where-object {$_.Version -eq $releaseName}) ) {
    Write-Output "A release matching $($releaseName) for $($releaseName) cannot be located and will be created"
    # Create the release body
    $releaseBody = @{
        ChannelId        = $channel.Id
        ProjectId        = $project.Id
        Version          = $releaseName
        SelectedPackages = @()
    }

    # Set the package version to the latest for each package
    # If you have channel rules that dictate what versions can be used, you'll need to account for that
    Write-Output "Getting step package versions"
    $template.Packages | ForEach-Object {
        $uri = "$octopusSpaceUrl/feeds/$($_.FeedId)/packages/versions?packageId=$($_.PackageId)&take=1"
        $version = Invoke-WebRequest -Uri $uri -Method GET -UseBasicParsing -Headers $headers -Body $releaseBody -ErrorVariable octoError | ConvertFrom-Json
        $version = $version.Items[0].Version

        $releaseBody.SelectedPackages += @{
            ActionName           = $_.ActionName
            PackageReferenceName = $_.PackageReferenceName
            Version              = $version
        }
    }

    # Create release
    $releaseBody = $releaseBody | ConvertTo-Json
    Write-Output "Creating release with these values: $releaseBody"
    $release = Invoke-WebRequest -Uri $octopusSpaceUrl/releases -Method POST -UseBasicParsing -Headers $headers -Body $releaseBody -ErrorVariable octoError | ConvertFrom-Json
} else {
    Write-Output "A release matching $($releaseName) for $($projectName) has been found"
    $release =  $releases.items | where-object {$_.Version -eq $releaseName}
}   

if ( -Not ($environmentName -eq 'Production') ) {
    # Creating a deployment
    $deploymentBody = @{
       ReleaseId     = $release.Id
        EnvironmentId = $environment.Id
        TenantId = $tenant.Id
    } | ConvertTo-Json

    Write-Output "Creating deployment with these values: $deploymentBody"
    $deployment = Invoke-WebRequest -Uri $octopusSpaceUrl/deployments -Method POST -UseBasicParsing -Headers $headers -Body $deploymentBody -ErrorVariable octoError
} 
