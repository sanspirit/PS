<#
----- Advanced Configuration Settings -----
Variable names can use either of the following two formats: 
    Octopus.Action.<Setting Name> - will apply to all steps in the deployment, e.g.
        Octopus.Action.DebugLogging
    Octopus.Action[Step Name].<Setting Name> - will apply to 'step name' alone, e.g.
        Octopus.Action[Provision Virtual Machine].DeploymentRetryCount

Available Settings:
    - DebugLogging - set to 'True' or 'False' to log all GET web requests
    - GuidedFailureMessage - will change the note used when submitting guided failure actions, the following variables will be replaced in the text:
        #{GuidedFailureActionIndex} - The current count of interrupts for that step e.g. 1
        #{GuidedFailureAction} - The action being submitted by the step e.g. Retry
    - DeploymentRetryCount - will override the number of times a deployment will be retried when unsuccessful and enable retrying when the failure option is set for a different option, default is 1
    - StepRetryCount - will override the number of times a deployment step will be retried before before submitting Ignore or Abort, default is 1
    - RetryWaitPeriod - an additional delay in seconds wait before retrying a failed step/deployment, default is 0
    - QueueTimeout - when scheduling a deployment for later a timeout must be provided, this allows a custom value, default is 30:00, format is hh:mm
    - OctopusServerUrl - will override the base url used for all webrequests, making it possible to chain deployments on a different Octopus instance/server, or as a workaround for misconfigured node settings
#>
#Requires -Version 5
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Test-String {
    param([Parameter(Position = 0)]$InputObject, [switch]$ForAbsence)

    $hasNoValue = [System.String]::IsNullOrWhiteSpace($InputObject)
    if ($ForAbsence) { $hasNoValue }
    else { -not $hasNoValue }
}

function Get-OctopusSetting {
    param([Parameter(Position = 0, Mandatory)][string]$Name, [Parameter(Position = 1, Mandatory)]$DefaultValue)
    $formattedName = 'Octopus.Action.{0}' -f $Name
    if ($OctopusParameters.ContainsKey($formattedName)) {
        $value = $OctopusParameters[$formattedName]
        if ($DefaultValue -is [int]) { return ([int]::Parse($value)) }
        if ($DefaultValue -is [bool]) { return ([System.Convert]::ToBoolean($value)) }
        if ($DefaultValue -is [array] -or $DefaultValue -is [hashtable] -or $DefaultValue -is [pscustomobject]) { return (ConvertFrom-Json -InputObject $value) }
        return $value
    }
    else { return $DefaultValue }
}

# Write functions are re-defined using octopus service messages to preserve formatting of log messages received from the chained deployment and avoid errors being twice wrapped in an ErrorRecord
function Write-Fatal($message, $exitCode = -1) {
    if (Test-Path Function:\Fail-Step) {
        Fail-Step $message
    }
    else {
        Write-Host ("##octopus[stdout-error]`n{0}" -f $message)
        Exit $exitCode
    }
}
function Write-Error($message) { Write-Host ("##octopus[stdout-error]`n{0}`n##octopus[stdout-default]" -f $message) }
function Write-Warning($message) { Write-Host ("##octopus[stdout-warning]`n{0}`n##octopus[stdout-default]" -f $message) }
function Write-Verbose($message) { Write-Host ("##octopus[stdout-verbose]`n{0}`n##octopus[stdout-default]" -f $message) }

$DefaultUrl = $OctopusParameters['#{if Octopus.Web.ServerUri}#{Octopus.Web.ServerUri}#{else}#{Octopus.Web.BaseUrl}#{/if}']
# Use "Octopus.Web.ServerUri" if it is available
if ($OctopusParameters['Octopus.Web.ServerUri']) {
    $DefaultUrl = $OctopusParameters['Octopus.Web.ServerUri']
}

$Chain_BaseUrl = (Get-OctopusSetting OctopusServerUrl $DefaultUrl).Trim('/')
if (Test-String $Chain_ApiKey -ForAbsence) {
    Write-Fatal "The step parameter 'API Key' was not found. This step requires an API Key to function, please provide one and try again."
}
$DebugLogging = Get-OctopusSetting DebugLogging $false

# Replace any "virtual directory" or route prefix e.g from the Links collection used
# with the api e.g. /api
function Format-LinksUri {
    param(
        [Parameter(Position = 0, Mandatory)]
        $Uri
    )
    $Uri = $Uri -replace '.*/api', '/api'
    Return $Uri
}
# Replace any "virtual directory" or route prefix e.g from the Links collection used
# with the web app e.g. /app
function Format-WebLinksUri {
    param(
        [Parameter(Position = 0, Mandatory)]
        $Uri
    )
    $Uri = $Uri -replace '.*/app', '/app'
    Return $Uri
}

function Invoke-OctopusApi {
    param(
        [Parameter(Position = 0, Mandatory)]$Uri,
        [ValidateSet('Get', 'Post', 'Put')]$Method = 'Get',
        $Body,
        [switch]$GetErrorResponse
    )
    # Replace query string example parameters e.g. {?skip,take,partialName} 
    # Replace any "virtual directory" or route prefix e.g from the Links collection.
    $Uri = $Uri -replace '{.*?}', '' -replace '.*/api', '/api'
    $requestParameters = @{
        Uri             = ('{0}/{1}' -f $Chain_BaseUrl, $Uri.TrimStart('/'))
        Method          = $Method
        Headers         = @{ 'X-Octopus-ApiKey' = $Chain_ApiKey }
        UseBasicParsing = $true
    }
    if ($Method -ne 'Get' -or $DebugLogging) {
        Write-Verbose ('{0} {1}' -f $Method.ToUpperInvariant(), $requestParameters.Uri)
    }
    if ($null -ne $Body) {
        $requestParameters.Add('Body', (ConvertTo-Json -InputObject $Body -Depth 10))
        Write-Verbose $requestParameters.Body
    }
    
    $wait = 0
    $webRequest = $null
    while ($null -eq $webRequest) {	
        try {
            $webRequest = Invoke-WebRequest @requestParameters
        }
        catch {
            if ($_.Exception -is [System.Net.WebException] -and $null -ne $_.Exception.Response) {
                $errorResponse = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd()
                Write-Verbose ("Error Response:`n{0}" -f $errorResponse)
                if ($GetErrorResponse) {
                    return ($errorResponse | ConvertFrom-Json)
                }
                if ($_.Exception.Response.StatusCode -in @([System.Net.HttpStatusCode]::NotFound, [System.Net.HttpStatusCode]::InternalServerError, [System.Net.HttpStatusCode]::BadRequest, [System.Net.HttpStatusCode]::Unauthorized)) {
                    Write-Fatal $_.Exception.Message
                }
            }
            if ($wait -eq 120) {
                Write-Fatal ("Octopus web request ({0}: {1}) failed & the maximum number of retries has been exceeded:`n{2}" -f $Method.ToUpperInvariant(), $requestParameters.Uri, $_.Exception.Message) -43
            }
            $wait = switch ($wait) {
                0 { 30 }
                30 { 60 }
                60 { 120 }
            }
            Write-Warning ("Octopus web request ({0}: {1}) failed & will be retried in $wait seconds:`n{2}" -f $Method.ToUpperInvariant(), $requestParameters.Uri, $_.Exception.Message)
            Start-Sleep -Seconds $wait
        }
    }
    $webRequest.Content | ConvertFrom-Json | Write-Output
}

function Test-SpacesApi {
    Write-Verbose "Checking API compatibility";
    $rootDocument = Invoke-OctopusApi "api/";
    if ($null -ne $rootDocument.Links -and $null -ne $rootDocument.Links.Spaces) {
        Write-Verbose "Spaces API found"
        return $true;
    }
    Write-Verbose "Pre-spaces API found"
    return $false;
}

$Chain_BaseApiUrl = "/api"
if (Test-SpacesApi) {
    $spaceId = $OctopusParameters['Octopus.Space.Id'];
    if ([string]::IsNullOrWhiteSpace($spaceId)) {
        throw "This step needs to be run in a context that provides a value for the 'Octopus.Space.Id' system variable. In this case, we received a blank value, which isn't expected - please reach out to our support team at https://help.octopus.com if you encounter this error.";
    }
    $Chain_BaseApiUrl = "/api/$spaceId" ;
}

enum GuidedFailure {
    Default
    Enabled
    Disabled
    RetryIgnore
    RetryAbort
    Ignore
    RetryDeployment
}

class DeploymentContext {
    hidden $BaseUrl
    hidden $BaseApiUrl
    DeploymentContext($baseUrl, $baseApiUrl) {
        $this.BaseUrl = $baseUrl
        $this.BaseApiUrl = $baseApiUrl
    }

    hidden $Project
    hidden $Lifecycle
    [void] SetProject($projectName) {
        $this.Project = Invoke-OctopusApi "$($this.BaseApiUrl)/projects/all" | Where-Object Name -eq $projectName
        if ($null -eq $this.Project) {
            Write-Fatal "Project $projectName not found"
        }
        Write-Host "Project: $($this.Project.Name)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $this.Project.Links.Self)"
        
        $this.Lifecycle = Invoke-OctopusApi ("$($this.BaseApiUrl)/lifecycles/{0}" -f $this.Project.LifecycleId)
        Write-Host "Project Lifecycle: $($this.Lifecycle.Name)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $this.Lifecycle.Links.Self)"
    }
    
    hidden $Channel
    [void] SetChannel($channelName) {
        $useDefaultChannel = Test-String $channelName -ForAbsence
        $this.Channel = Invoke-OctopusApi (Format-LinksUri -Uri $this.Project.Links.Channels) | ForEach-Object Items | Where-Object { $useDefaultChannel -and $_.IsDefault -or $_.Name -eq $channelName }
        if ($null -eq $this.Channel) {
            Write-Fatal "$(if ($useDefaultChannel) { 'Default channel' } else { "Channel $channelName" }) not found"
        }
        Write-Host "Channel: $($this.Channel.Name)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $this.Channel.Links.Self)"

        if ($null -ne $this.Channel.LifecycleId) {
            $this.Lifecycle = Invoke-OctopusApi ("$($this.BaseApiUrl)/lifecycles/{0}" -f $this.Channel.LifecycleId)
            Write-Host "Channel Lifecycle: $($this.Lifecycle.Name)"
            Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $this.Lifecycle.Links.Self)"        
        }
    }

    hidden $Release
    [void] SetRelease($releaseVersion) {
        if (Test-String $releaseVersion) {
            $this.Release = Invoke-OctopusApi ("$($this.BaseApiUrl)/projects/{0}/releases/{1}" -f $this.Project.Id, $releaseVersion) -GetErrorResponse
            if ($null -ne $this.Release.ErrorMessage) {
                Write-Fatal $this.Release.ErrorMessage
            }
        }
        else {
            $this.Release = Invoke-OctopusApi (Format-LinksUri -Uri $this.Channel.Links.Releases) | ForEach-Object Items | Select-Object -First 1
            if ($null -eq $this.Release) {
                Write-Fatal "There are no releases for channel $($this.Channel.Name)"
            }
        }
        Write-Host "Release: $($this.Release.Version)"
        Write-Verbose "`t$($this.BaseUrl)$($this.BaseApiUrl)/releases/$($this.Release.Id)"
    }
    [void] CreateRelease($releaseVersion) {
        $template = Invoke-OctopusApi ('{0}/template?channel={1}' -f (Format-LinksUri -Uri $this.Project.Links.DeploymentProcess), $this.Channel.Id)
        $selectedPackages = @()
        Write-Host 'Resolving package versions...'
        $template.Packages | ForEach-Object {
            $preReleaseTag = $this.Channel.Rules | Where-Object Actions -contains $_.StepName | Where-Object { $null -ne $_ } | ForEach-Object { '&preReleaseTag={0}' -f $([System.Net.WebUtility]::UrlEncode($_.Tag)) }
            $versionRange = $this.Channel.Rules | Where-Object Actions -contains $_.StepName | Where-Object { $null -ne $_ } | ForEach-Object { '&versionRange={0}' -f $([System.Net.WebUtility]::UrlEncode($_.VersionRange)) }

            $package = Invoke-OctopusApi ("$($this.BaseApiUrl)/feeds/{0}/packages?packageId={1}&partialMatch=false&includeMultipleVersions=false&includeNotes=false&includePreRelease=true&take=1{2}{3}" -f $_.FeedId, $_.PackageId, $preReleaseTag, $versionRange)
            $packageDesc = "$($package.Title) @ $($package.Version) for step $($_.StepName)"
            if ( $_.PackageReferenceName ) {
                $packageDesc += "/$($_.PackageReferenceName)"
            }
            Write-Host "Found $packageDesc"
            
            $selectedPackages += @{
                StepName             = $_.StepName
                ActionName           = $_.ActionName
                PackageReferenceName = $_.PackageReferenceName
                Version              = $package.Version
            }

            if ( (Test-String $releaseVersion -ForAbsence) -and ($_.StepName -eq $template.VersioningPackageStepName) ) {
                Write-Host "Release will be created using the version number from package step $($template.VersioningPackageStepName): $($package.Version)"
                $releaseVersion = $package.Version
            }
        }
        if (Test-String $releaseVersion) {
            $this.Release = Invoke-OctopusApi ("$($this.BaseApiUrl)/projects/{0}/releases/{1}" -f $this.Project.Id, $releaseVersion) -GetErrorResponse
            if ( ($null -eq $this.Release.ErrorMessage) -and ($this.Release.Version -ieq $releaseVersion) -and ($this.Release.ChannelId -eq $this.Channel.Id) ) {
                Write-Host "Release version $($this.Release.Version) has already been created, selecting it for deployment"
                Write-Verbose "`t$($this.BaseUrl)$($this.BaseApiUrl)/releases/$($this.Release.Id)"
                return
            }
        }
        else {
            Write-Host "Release will be created using the incremented release version: $($template.NextVersionIncrement)"
            $releaseVersion = $template.NextVersionIncrement
        }

        $this.Release = Invoke-OctopusApi "$($this.BaseApiUrl)/releases?ignoreChannelRules=false" -Method Post -Body @{
            ProjectId        = $this.Project.Id
            ChannelId        = $this.Channel.Id 
            Version          = $releaseVersion
            SelectedPackages = $selectedPackages
        } -GetErrorResponse
        if ($null -ne $this.Release.ErrorMessage) {
            Write-Fatal "$($this.Release.ErrorMessage)`n$($this.Release.Errors -join "`n")"
        }
        Write-Host "Release $($this.Release.Version) has been successfully created"
        Write-Verbose "`t$($this.BaseUrl)$($this.BaseApiUrl)/releases/$($this.Release.Id)"
    }

    [void] UpdateVariableSnapshot() {
        $this.Release = Invoke-OctopusApi (Format-LinksUri -Uri $this.Release.Links.SnapshotVariables) -Method Post
        Write-Host 'Variables snapshot update performed. The release now references the latest variables.'
    }

    hidden $DeploymentTemplate
    [void] GetDeploymentTemplate() {
        Write-Host 'Getting deployment template for release...'
        $this.DeploymentTemplate = Invoke-OctopusApi (Format-LinksUri -Uri $this.Release.Links.DeploymentTemplate)
    }

    hidden [bool]$UseGuidedFailure
    hidden [string[]]$GuidedFailureActions
    hidden [string]$GuidedFailureMessage
    hidden [int]$DeploymentRetryCount
    [void] SetGuidedFailure([GuidedFailure]$guidedFailure, $guidedFailureMessage) {
        $this.UseGuidedFailure = switch ($guidedFailure) {
            ([GuidedFailure]::Default) { [System.Convert]::ToBoolean($global:OctopusUseGuidedFailure) }
            ([GuidedFailure]::Enabled) { $true }
            ([GuidedFailure]::Disabled) { $false }
            ([GuidedFailure]::RetryIgnore) { $true }
            ([GuidedFailure]::RetryAbort) { $true }
            ([GuidedFailure]::Ignore) { $true } 
            ([GuidedFailure]::RetryDeployment) { $false }
        }
        Write-Host "Setting Guided Failure: $($this.UseGuidedFailure)"
        
        $retryActions = @(1..(Get-OctopusSetting StepRetryCount 1) | ForEach-Object { 'Retry' })
        $this.GuidedFailureActions = switch ($guidedFailure) {
            ([GuidedFailure]::Default) { $null }
            ([GuidedFailure]::Enabled) { $null }
            ([GuidedFailure]::Disabled) { $null }
            ([GuidedFailure]::RetryIgnore) { $retryActions + @('Ignore') }
            ([GuidedFailure]::RetryAbort) { $retryActions + @('Abort') }
            ([GuidedFailure]::Ignore) { @('Ignore') }
            ([GuidedFailure]::RetryDeployment) { $null }
        }
        if ($null -ne $this.GuidedFailureActions) {
            Write-Host "Automated Failure Guidance: $($this.GuidedFailureActions -join '; ') "
        }
        $this.GuidedFailureMessage = $guidedFailureMessage
        
        $defaultRetries = if ($guidedFailure -eq [GuidedFailure]::RetryDeployment) { 1 } else { 0 }
        $this.DeploymentRetryCount = Get-OctopusSetting DeploymentRetryCount $defaultRetries
        if ($this.DeploymentRetryCount -ne 0) {
            Write-Host "Failed Deployments will be retried #$($this.DeploymentRetryCount) times"
        }
    }
        
    [bool]$WaitForDeployment
    hidden [datetime]$QueueTime
    hidden [datetime]$QueueTimeExpiry
    [void] SetSchedule($deploySchedule) {
        if (Test-String $deploySchedule -ForAbsence) {
            Write-Fatal 'The deployment schedule step parameter was not found.'
        }
        if ($deploySchedule -eq 'WaitForDeployment') {
            $this.WaitForDeployment = $true
            Write-Host 'Deployment will be queued to start immediatley...'
            return
        }
        $this.WaitForDeployment = $false
        if ($deploySchedule -eq 'NoWait') {
            Write-Host 'Deployment will be queued to start immediatley...'
            return
        }
        
        $parsedSchedule = [regex]::Match($deploySchedule, '^(?i)(?:(?<Day>MON|TUE|WED|THU|FRI|SAT|SUN)?\s*@\s*(?<TimeOfDay>(?:[01]?[0-9]|2[0-3]):[0-5][0-9]))?\s*(?:\+\s*(?<TimeSpan>\d{1,3}(?::[0-5][0-9])?))?$')
        if (!$parsedSchedule.Success) {
            Write-Fatal "The deployment schedule step parameter contains an invalid value. Valid values are 'WaitForDeployment', 'NoWait' or a schedule in the format '[[DayOfWeek] @ HH:mm] [+ <MMM|HHH:MM>]'" 
        }
        $this.QueueTime = Get-Date
        if ($parsedSchedule.Groups['Day'].Success) {
            Write-Verbose "Parsed Day: $($parsedSchedule.Groups['Day'].Value)"
            while (!$this.QueueTime.DayOfWeek.ToString().StartsWith($parsedSchedule.Groups['Day'].Value)) {
                $this.QueueTime = $this.QueueTime.AddDays(1)
            }
        }
        if ($parsedSchedule.Groups['TimeOfDay'].Success) {
            Write-Verbose "Parsed Time Of Day: $($parsedSchedule.Groups['TimeOfDay'].Value)"
            $timeOfDay = [datetime]::ParseExact($parsedSchedule.Groups['TimeOfDay'].Value, 'HH:mm', $null)
            $this.QueueTime = $this.QueueTime.Date + $timeOfDay.TimeOfDay
        }
        if ($parsedSchedule.Groups['TimeSpan'].Success) {
            Write-Verbose "Parsed Time Span: $($parsedSchedule.Groups['TimeSpan'].Value)"
            $timeSpan = $parsedSchedule.Groups['TimeSpan'].Value.Split(':')
            $hoursToAdd = if ($timeSpan.Length -eq 2) { $timeSpan[0] } else { 0 }
            $minutesToAdd = if ($timeSpan.Length -eq 2) { $timeSpan[1] } else { $timeSpan[0] }
            $this.QueueTime = $this.QueueTime.Add((New-TimeSpan -Hours $hoursToAdd -Minutes $minutesToAdd))
        }
        Write-Host "Deployment will be queued to start at: $($this.QueueTime.ToLongDateString()) $($this.QueueTime.ToLongTimeString())"
        Write-Verbose "Local Time: $($this.QueueTime.ToLocalTime().ToString('r'))"
        Write-Verbose "Universal Time: $($this.QueueTime.ToUniversalTime().ToString('o'))"
        $this.QueueTimeExpiry = $this.QueueTime.Add([timespan]::ParseExact((Get-OctopusSetting QueueTimeout '00:30'), "hh\:mm", $null))
        Write-Verbose "Queued deployment will expire on: $($this.QueueTimeExpiry.ToUniversalTime().ToString('o'))"
    }

    hidden $Environments
    [void] SetEnvironment($environmentName) {
        $lifecyclePhaseEnvironments = $this.Lifecycle.Phases | Where-Object Name -eq $environmentName | ForEach-Object {
            $_.AutomaticDeploymentTargets
            $_.OptionalDeploymentTargets
        }
        $this.Environments = $this.DeploymentTemplate.PromoteTo | Where-Object { $_.Id -in $lifecyclePhaseEnvironments -or $_.Name -ieq $environmentName }
        if ($null -eq $this.Environments) {
            Write-Fatal "The specified environment ($environmentName) was not found or not eligible for deployment of the release ($($this.Release.Version)). Verify that the release has been deployed to all required environments before it can be promoted to this environment. Once you have corrected these problems you can try again." 
        }
        Write-Host "Environments: $(($this.Environments | ForEach-Object Name) -join ', ')"
    }
    
    [bool] $IsTenanted
    hidden $Tenants
    [void] SetTenants($tenantFilter) {
        $this.IsTenanted = Test-String $tenantFilter
        if (!$this.IsTenanted) {
            return
        }
        $tenantPromotions = $this.DeploymentTemplate.TenantPromotions | ForEach-Object Id
        $this.Tenants = $tenantFilter.Split("`n") | ForEach-Object { [uri]::EscapeUriString($_.Trim()) } | ForEach-Object {
            $criteria = if ($_ -like '*/*') { 'tags' } else { 'name' }
            
            $tenantResults = Invoke-OctopusApi ("$($this.BaseApiUrl)/tenants/all?projectId={0}&{1}={2}" -f $this.Project.Id, $criteria, $_) -GetErrorResponse
            if ($tenantResults -isnot [array] -and $tenantResults.ErrorMessage) {
                Write-Warning "Full Exception: $($tenantResults.FullException)"
                Write-Fatal $tenantResults.ErrorMessage
            }
            $tenantResults
        } | Where-Object Id -in $tenantPromotions

        if ($null -eq $this.Tenants) {
            Write-Fatal "No eligible tenants found for deployment of the release ($($this.Release.Version)). Verify that the tenants have been associated with the project."
        }
        Write-Host "Tenants: $(($this.Tenants | ForEach-Object Name) -join ', ')"
    }

    [DeploymentController[]] GetDeploymentControllers() {
        Write-Verbose 'Determining eligible environments & tenants. Retrieving deployment previews...'
        $deploymentControllers = @()
        foreach ($environment in $this.Environments) {
            $envPrefix = if ($this.Environments.Count -gt 1) { $environment.Name }
            if ($this.IsTenanted) {
                foreach ($tenant in $this.Tenants) {
                    $tenantPrefix = if ($this.Tenants.Count -gt 1) { $tenant.Name }
                    if ($this.DeploymentTemplate.TenantPromotions | Where-Object Id -eq $tenant.Id | ForEach-Object PromoteTo | Where-Object Id -eq $environment.Id) {
                        $logPrefix = ($envPrefix, $tenantPrefix | Where-Object { $null -ne $_ }) -join '::'
                        $deploymentControllers += [DeploymentController]::new($this, $logPrefix, $environment, $tenant)
                    }
                }
            }
            else {
                $deploymentControllers += [DeploymentController]::new($this, $envPrefix, $environment, $null)
            }
        }
        return $deploymentControllers
    }
}

class DeploymentController {
    hidden [string]$BaseUrl
    hidden [DeploymentContext]$DeploymentContext
    hidden [string]$LogPrefix
    hidden [object]$Environment
    hidden [object]$Tenant
    hidden [object]$DeploymentPreview
    hidden [int]$DeploymentRetryCount
    hidden [int]$DeploymentAttempt
    
    DeploymentController($deploymentContext, $logPrefix, $environment, $tenant) {
        $this.BaseUrl = $deploymentContext.BaseUrl
        $this.DeploymentContext = $deploymentContext
        if (Test-String $logPrefix) {
            $this.LogPrefix = "[${logPrefix}] "
        }
        $this.Environment = $environment
        $this.Tenant = $tenant
        if ($tenant) {
            $this.DeploymentPreview = Invoke-OctopusApi ("$($this.DeploymentContext.BaseApiUrl)/releases/{0}/deployments/preview/{1}/{2}" -f $this.DeploymentContext.Release.Id, $this.Environment.Id, $this.Tenant.Id)
        }
        else {
            $this.DeploymentPreview = Invoke-OctopusApi ("$($this.DeploymentContext.BaseApiUrl)/releases/{0}/deployments/preview/{1}" -f $this.DeploymentContext.Release.Id, $this.Environment.Id)
        }
        $this.DeploymentRetryCount = $deploymentContext.DeploymentRetryCount
        $this.DeploymentAttempt = 0
    }

    hidden [string[]]$SkipActions = @()
    [void] SetStepsToSkip($stepsToSkip) {
        $comparisonArray = $stepsToSkip.Split("`n") | ForEach-Object Trim
        $this.SkipActions = $this.DeploymentPreview.StepsToExecute | Where-Object {
            $_.CanBeSkipped -and ($_.ActionName -in $comparisonArray -or $_.ActionNumber -in $comparisonArray)
        } | ForEach-Object {
            $logMessage = "Skipping Step $($_.ActionNumber): $($_.ActionName)"
            if ($this.LogPrefix) { Write-Verbose "$($this.LogPrefix)$logMessage" }
            else { Write-Host $logMessage }
            $_.ActionId
        }
    }

    hidden [hashtable]$FormValues
    [void] SetFormValues($formValuesToSet) {
        $this.FormValues = @{}
        $this.DeploymentPreview.Form.Values | Get-Member -MemberType NoteProperty | ForEach-Object {
            $this.FormValues.Add($_.Name, $this.DeploymentPreview.Form.Values.$($_.Name))
        }

        $formValuesToSet.Split("`n") | ForEach-Object {
            $entry = $_.Split('=') | ForEach-Object Trim
            $entryName, $entryValues = $entry
            $entry = @($entryName, $($entryValues -join "="))
            $this.DeploymentPreview.Form.Elements | Where-Object { $_.Control.Name -ieq $entry[0] } | ForEach-Object {
                $logMessage = "Setting Form Value '$($_.Control.Label)' to: $($entry[1])"
                if ($this.LogPrefix) { Write-Verbose "$($this.LogPrefix)$logMessage" }
                else { Write-Host $logMessage }
                $this.FormValues[$_.Name] = $entry[1]
            }
        }
    }
	
    [ServerTask]$Task
    [void] Start() {
        $request = @{
            ReleaseId        = $this.DeploymentContext.Release.Id
            EnvironmentId    = $this.Environment.Id
            SkipActions      = $this.SkipActions
            FormValues       = $this.FormValues
            UseGuidedFailure = $this.DeploymentContext.UseGuidedFailure
        }
        if ($this.DeploymentContext.QueueTime -ne [datetime]::MinValue) { $request.Add('QueueTime', $this.DeploymentContext.QueueTime.ToUniversalTime().ToString('o')) }
        if ($this.DeploymentContext.QueueTimeExpiry -ne [datetime]::MinValue) { $request.Add('QueueTimeExpiry', $this.DeploymentContext.QueueTimeExpiry.ToUniversalTime().ToString('o')) }
        if ($this.Tenant) { $request.Add('TenantId', $this.Tenant.Id) }

        $deployment = Invoke-OctopusApi "$($this.DeploymentContext.BaseApiUrl)/deployments" -Method Post -Body $request -GetErrorResponse
        if ($deployment.ErrorMessage) { Write-Fatal "$($deployment.ErrorMessage)`n$($deployment.Errors -join "`n")" }
        Write-Host "Queued $($deployment.Name)..."
        Write-Host "`t$($this.BaseUrl)$(Format-WebLinksUri -Uri $deployment.Links.Web)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $deployment.Links.Self)"
        Write-Verbose "`t$($this.BaseUrl)$($this.DeploymentContext.BaseApiUrl)/deploymentprocesses/$($deployment.DeploymentProcessId)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $deployment.Links.Variables)"
        Write-Verbose "`t$($this.BaseUrl)$(Format-LinksUri -Uri $deployment.Links.Task)/details"

        $this.Task = [ServerTask]::new($this.DeploymentContext, $deployment, $this.LogPrefix)
    }

    [bool] PollCheck() {
        $this.Task.Poll()
        if ($this.Task.IsCompleted -and !$this.Task.FinishedSuccessfully -and $this.DeploymentAttempt -lt $this.DeploymentRetryCount) {
            $retryWaitPeriod = New-TimeSpan -Seconds (Get-OctopusSetting RetryWaitPeriod 0)
            $waitText = if ($retryWaitPeriod.TotalSeconds -gt 0) {
                $minutesText = if ($retryWaitPeriod.Minutes -gt 1) { " $($retryWaitPeriod.Minutes) minutes" } elseif ($retryWaitPeriod.Minutes -eq 1) { " $($retryWaitPeriod.Minutes) minute" }
                $secondsText = if ($retryWaitPeriod.Seconds -gt 1) { " $($retryWaitPeriod.Seconds) seconds" } elseif ($retryWaitPeriod.Seconds -eq 1) { " $($retryWaitPeriod.Seconds) second" }
                "Waiting${minutesText}${secondsText} before "
            }
            $this.DeploymentAttempt++
            Write-Error "$($this.LogPrefix)Deployment failed. ${waitText}Queuing retry #$($this.DeploymentAttempt) of $($this.DeploymentRetryCount)..."
            if ($retryWaitPeriod.TotalSeconds -gt 0) {
                Start-Sleep -Seconds $retryWaitPeriod.TotalSeconds
            }
            $this.Start()
            return $true
        }
        return !$this.Task.IsCompleted
    }
}

class ServerTask {
    hidden [DeploymentContext]$DeploymentContext
    hidden [object]$Deployment
    hidden [string]$LogPrefix

    hidden [bool] $IsCompleted = $false
    hidden [bool] $FinishedSuccessfully
    hidden [string] $ErrorMessage
    
    hidden [int]$PollCount = 0
    hidden [bool]$HasInterruptions = $false
    hidden [hashtable]$State = @{}
    hidden [System.Collections.Generic.HashSet[string]]$Logs
 
    ServerTask($deploymentContext, $deployment, $logPrefix) {
        $this.DeploymentContext = $deploymentContext
        $this.Deployment = $deployment
        $this.LogPrefix = $logPrefix
        $this.Logs = [System.Collections.Generic.HashSet[string]]::new()
    }
    
    [void] Poll() {	
        if ($this.IsCompleted) { return }

        $details = Invoke-OctopusApi ("$($this.DeploymentContext.BaseApiUrl)/tasks/{0}/details?verbose=false&tail=30" -f $this.Deployment.TaskId)
        $this.IsCompleted = $details.Task.IsCompleted
        $this.FinishedSuccessfully = $details.Task.FinishedSuccessfully
        $this.ErrorMessage = $details.Task.ErrorMessage

        $this.PollCount++
        if ($this.PollCount % 10 -eq 0) {
            $this.Verbose("$($details.Task.State). $($details.Task.Duration), $($details.Progress.EstimatedTimeRemaining)")
        }
        
        if ($details.Task.HasPendingInterruptions) { $this.HasInterruptions = $true }
        $this.LogQueuePosition($details.Task)
        $activityLogs = $this.FlattenActivityLogs($details.ActivityLogs)    
        $this.WriteLogMessages($activityLogs)
    }

    hidden [bool] IfNewState($firstKey, $secondKey, $value) {
        $key = '{0}/{1}' -f $firstKey, $secondKey
        $containsKey = $this.State.ContainsKey($key)
        if ($containsKey) { return $false }
        $this.State[$key] = $value
        return $true
    }

    hidden [bool] HasChangedState($firstKey, $secondKey, $value) {
        $key = '{0}/{1}' -f $firstKey, $secondKey
        $hasChanged = if (!$this.State.ContainsKey($key)) { $true } else { $this.State[$key] -ne $value }
        if ($hasChanged) {
            $this.State[$key] = $value
        }
        return $hasChanged
    }

    hidden [object] GetState($firstKey, $secondKey) { return $this.State[('{0}/{1}' -f $firstKey, $secondKey)] }

    hidden [void] ResetState($firstKey, $secondKey) { $this.State.Remove(('{0}/{1}' -f $firstKey, $secondKey)) }

    hidden [void] Error($message) { Write-Error "$($this.LogPrefix)${message}" }
    hidden [void] Warn($message) { Write-Warning "$($this.LogPrefix)${message}" }
    hidden [void] Host($message) { Write-Host "$($this.LogPrefix)${message}" }   
    hidden [void] Verbose($message) { Write-Verbose "$($this.LogPrefix)${message}" }

    hidden [psobject[]] FlattenActivityLogs($ActivityLogs) {
        $flattenedActivityLogs = { @() }.Invoke()
        $this.FlattenActivityLogs($ActivityLogs, $null, $flattenedActivityLogs)
        return $flattenedActivityLogs
    }

    hidden [void] FlattenActivityLogs($ActivityLogs, $Parent, $flattenedActivityLogs) {
        foreach ($log in $ActivityLogs) {
            $log | Add-Member -MemberType NoteProperty -Name Parent -Value $Parent
            $insertBefore = $null -eq $log.Parent -and $log.Status -eq 'Running'	
            if ($insertBefore) { $flattenedActivityLogs.Add($log) }
            foreach ($childLog in $log.Children) {
                $this.FlattenActivityLogs($childLog, $log, $flattenedActivityLogs)
            }
            if (!$insertBefore) { $flattenedActivityLogs.Add($log) }
        }
    }

    hidden [void] LogQueuePosition($Task) {
        if ($Task.HasBeenPickedUpByProcessor) {
            $this.ResetState($Task.Id, 'QueuePosition')
            return
        }
		
        $queuePosition = (Invoke-OctopusApi ("$($this.DeploymentContext.BaseApiUrl)/tasks/{0}/queued-behind" -f $this.Deployment.TaskId)).Items.Count
        if ($this.HasChangedState($Task.Id, 'QueuePosition', $queuePosition) -and $queuePosition -ne 0) {
            $this.Host("Queued behind $queuePosition tasks...")
        }
    }

    hidden [void] WriteLogMessages($ActivityLogs) {
        $interrupts = if ($this.HasInterruptions) {
            Invoke-OctopusApi ("$($this.DeploymentContext.BaseApiUrl)/interruptions?regarding={0}" -f $this.Deployment.TaskId) | ForEach-Object Items
        }
        foreach ($activity in $ActivityLogs) {
            $correlatedInterrupts = $interrupts | Where-Object CorrelationId -eq $activity.Id         
            $correlatedInterrupts | Where-Object IsPending -eq $false | ForEach-Object { $this.LogInterruptMessages($activity, $_) }

            $this.LogStepTransition($activity)         
            $this.LogErrorsAndWarnings($activity)
            $correlatedInterrupts | Where-Object IsPending -eq $true | ForEach-Object { 
                $this.LogInterruptMessages($activity, $_)
                $this.HandleInterrupt($_)
            }
        }
    }

    hidden [void] LogStepTransition($ActivityLog) {
        if ($ActivityLog.ShowAtSummaryLevel -and $ActivityLog.Status -ne 'Pending') {
            $existingState = $this.GetState($ActivityLog.Id, 'Status')
            if ($this.HasChangedState($ActivityLog.Id, 'Status', $ActivityLog.Status)) {
                $existingStateText = if ($existingState) { "$existingState -> " }
                $this.Host("$($ActivityLog.Name) ($existingStateText$($ActivityLog.Status))")
            }
        }
    }

    hidden [void] LogErrorsAndWarnings($ActivityLog) {
        foreach ($logEntry in $ActivityLog.LogElements) {
            if ($logEntry.Category -eq 'Info') { continue }
            if ($this.Logs.Add(($ActivityLog.Id, $logEntry.OccurredAt, $logEntry.MessageText -join '/'))) {
                switch ($logEntry.Category) {
                    'Fatal' {
                        if ($ActivityLog.Parent) {
                            $this.Error("FATAL: During $($ActivityLog.Parent.Name)")
                            $this.Error("FATAL: $($logEntry.MessageText)")
                        }
                    }
                    'Error' { $this.Error("[$($ActivityLog.Parent.Name)] $($logEntry.MessageText)") }
                    'Warning' { $this.Warn("[$($ActivityLog.Parent.Name)] $($logEntry.MessageText)") }
                }
            }
        }
    }

    hidden [void] LogInterruptMessages($ActivityLog, $Interrupt) {
        $message = $Interrupt.Form.Elements | Where-Object Name -eq Instructions | ForEach-Object Control | ForEach-Object Text
        if ($Interrupt.IsPending -and $this.HasChangedState($Interrupt.Id, $ActivityLog.Parent.Name, $message)) {
            $this.Warn("Deployment is paused at '$($ActivityLog.Parent.Name)' for manual intervention: $message")
        }
        if ($null -ne $Interrupt.ResponsibleUserId -and $this.HasChangedState($Interrupt.Id, 'ResponsibleUserId', $Interrupt.ResponsibleUserId)) {
            $user = Invoke-OctopusApi (Format-LinksUri -Uri $Interrupt.Links.User)
            $emailText = if (Test-String $user.EmailAddress) { " ($($user.EmailAddress))" }
            $this.Warn("$($user.DisplayName)$emailText has taken responsibility for the manual intervention")
        }
        $manualAction = $Interrupt.Form.Values.Result
        if ((Test-String $manualAction) -and $this.HasChangedState($Interrupt.Id, 'Action', $manualAction)) {
            $this.Warn("Manual intervention action '$manualAction' submitted with notes: $($Interrupt.Form.Values.Notes)")
        }
        $guidanceAction = $Interrupt.Form.Values.Guidance
        if ((Test-String $guidanceAction) -and $this.HasChangedState($Interrupt.Id, 'Action', $guidanceAction)) {
            $this.Warn("Failure guidance to '$guidanceAction' submitted with notes: $($Interrupt.Form.Values.Notes)")
        }
    }

    hidden [void] HandleInterrupt($Interrupt) {
        $isGuidedFailure = $null -ne ($Interrupt.Form.Elements | Where-Object Name -eq Guidance)
        if (!$isGuidedFailure -or !$this.DeploymentContext.GuidedFailureActions -or !$Interrupt.IsPending) {
            return
        }
        $this.IfNewState($Interrupt.CorrelationId, 'ActionIndex', 0)
        if ($Interrupt.CanTakeResponsibility -and $null -eq $Interrupt.ResponsibleUserId) {
            Invoke-OctopusApi (Format-LinksUri -Uri $Interrupt.Links.Responsible) -Method Put
        }
        if ($Interrupt.HasResponsibility) {
            $guidanceIndex = $this.GetState($Interrupt.CorrelationId, 'ActionIndex')
            $guidance = $this.DeploymentContext.GuidedFailureActions[$guidanceIndex]
            $guidanceIndex++
            
            $retryWaitPeriod = New-TimeSpan -Seconds (Get-OctopusSetting RetryWaitPeriod 0)
            if ($guidance -eq 'Retry' -and $retryWaitPeriod.TotalSeconds -gt 0) {
                $minutesText = if ($retryWaitPeriod.Minutes -gt 1) { " $($retryWaitPeriod.Minutes) minutes" } elseif ($retryWaitPeriod.Minutes -eq 1) { " $($retryWaitPeriod.Minutes) minute" }
                $secondsText = if ($retryWaitPeriod.Seconds -gt 1) { " $($retryWaitPeriod.Seconds) seconds" } elseif ($retryWaitPeriod.Seconds -eq 1) { " $($retryWaitPeriod.Seconds) second" }
                $this.Warn("Waiting${minutesText}${secondsText} before submitting retry failure guidance...")
                Start-Sleep -Seconds $retryWaitPeriod.TotalSeconds
            }
            Invoke-OctopusApi (Format-LinksUri -Uri $Interrupt.Links.Submit) -Body @{
                Notes    = $this.DeploymentContext.GuidedFailureMessage.Replace('#{GuidedFailureActionIndex}', $guidanceIndex).Replace('#{GuidedFailureAction}', $guidance)
                Guidance = $guidance
            } -Method Post

            $this.HasChangedState($Interrupt.CorrelationId, 'ActionIndex', $guidanceIndex)
        }
    }
}

function Show-Heading {
    param($Text)
    $padding = ' ' * ((80 - 2 - $Text.Length) / 2)
    Write-Host " `n"
    Write-Host (@("`t", ([string][char]0x2554), (([string][char]0x2550) * 80), ([string][char]0x2557)) -join '')
    Write-Host "`t$(([string][char]0x2551))$padding $Text $padding$([string][char]0x2551)"  
    Write-Host (@("`t", ([string][char]0x255A), (([string][char]0x2550) * 80), ([string][char]0x255D)) -join '')
    Write-Host " `n"
}

if ($OctopusParameters['Octopus.Action.RunOnServer'] -ieq 'False') {
    Write-Warning "For optimal performance use 'Run On Server' for this action"
}

$deploymentContext = [DeploymentContext]::new($Chain_BaseUrl, $Chain_BaseApiUrl)

if ($Chain_CreateOption -ieq 'True') {
    Show-Heading 'Creating Release'
}
else {
    Show-Heading 'Retrieving Release'
}
$deploymentContext.SetProject($Chain_ProjectName)
$deploymentContext.SetChannel($Chain_Channel)
Write-Host "`t$Chain_BaseUrl$(Format-WebLinksUri -Uri $deploymentContext.Project.Links.Web)"

if ($Chain_CreateOption -ieq 'True') {
    $deploymentContext.CreateRelease($Chain_ReleaseNum)
}
else {
    $deploymentContext.SetRelease($Chain_ReleaseNum)
}
Write-Host "`t$Chain_BaseUrl$(Format-WebLinksUri -Uri $deploymentContext.Release.Links.Web)"
if ($Chain_SnapshotVariables -ieq 'True') {
    $deploymentContext.UpdateVariableSnapshot()
}

Show-Heading 'Configuring Deployment'
$deploymentContext.GetDeploymentTemplate()
$email = if (Test-String $OctopusParameters['Octopus.Deployment.CreatedBy.EmailAddress']) { "($($OctopusParameters['Octopus.Deployment.CreatedBy.EmailAddress']))" }
$guidedFailureMessage = Get-OctopusSetting GuidedFailureMessage @"
Automatic Failure Guidance will #{GuidedFailureAction} (Failure ###{GuidedFailureActionIndex})
Initiated by $($OctopusParameters['Octopus.Deployment.Name']) of $($OctopusParameters['Octopus.Project.Name']) release $($OctopusParameters['Octopus.Release.Number'])
Created By: $($OctopusParameters['Octopus.Deployment.CreatedBy.DisplayName']) $email
${Chain_BaseUrl}$($OctopusParameters['Octopus.Web.DeploymentLink'])
"@
$deploymentContext.SetGuidedFailure($Chain_GuidedFailure, $guidedFailureMessage)
$deploymentContext.SetSchedule($Chain_DeploySchedule)

$deploymentContext.SetEnvironment($Chain_DeployTo)
$deploymentContext.SetTenants($Chain_Tenants)

$deploymentControllers = $deploymentContext.GetDeploymentControllers()
if (Test-String $Chain_StepsToSkip) {
    $deploymentControllers | ForEach-Object { $_.SetStepsToSkip($Chain_StepsToSkip) }
}
if (Test-String $Chain_FormValues) {
    $deploymentControllers | ForEach-Object { $_.SetFormValues($Chain_FormValues) }
}

Show-Heading 'Queue Deployment'
if ($deploymentContext.IsTenanted) {
    Write-Host 'Queueing tenant deployments...'
}
else {
    Write-Host 'Queueing untenanted deployment...'
}
$deploymentControllers | ForEach-Object Start

if (!$deploymentContext.WaitForDeployment) {
    Write-Host 'Deployments have been queued, proceeding to the next step...'
    return
}

Show-Heading 'Waiting For Deployment'
do {
    Start-Sleep -Seconds 1
    $tasksStillRunning = $false
    foreach ($deployment in $deploymentControllers) {
        if ($deployment.PollCheck()) {
            $tasksStillRunning = $true
        }
    }
} while ($tasksStillRunning)

if ($deploymentControllers | ForEach-Object Task | Where-Object FinishedSuccessfully -eq $false) {
    Show-Heading 'Deployment Failed!'
    Write-Fatal (($deploymentControllers | ForEach-Object Task | ForEach-Object ErrorMessage) -join "`n")
}
else {
    Show-Heading 'Deployment Successful!'
}

if (Test-String $Chain_PostDeploy -ForAbsence) {
    return 
}

Show-Heading 'Post-Deploy Script'
$rawPostDeployScript = Invoke-OctopusApi ("$Chain_BaseApiUrl/releases/{0}" -f $OctopusParameters['Octopus.Release.Id']) |
    ForEach-Object { Invoke-OctopusApi (Format-LinksUri -Uri $_.Links.ProjectDeploymentProcessSnapshot) } |
        ForEach-Object Steps | Where-Object Id -eq $OctopusParameters['Octopus.Step.Id'] |
            ForEach-Object Actions | Where-Object Id -eq $OctopusParameters['Octopus.Action.Id'] |
                ForEach-Object { $_.Properties.Chain_PostDeploy }
Write-Verbose "Raw Post-Deploy Script:`n$rawPostDeployScript"

Add-Type -Path (Get-WmiObject Win32_Process | Where-Object ProcessId -eq $PID | ForEach-Object { Get-Process -Id $_.ParentProcessId } | ForEach-Object { Join-Path (Split-Path -Path $_.Path -Parent) 'Octostache.dll' })

$deploymentControllers | ForEach-Object {
    $deployment = $_.Task.Deployment
    $tenant = $_.Tenant
    $variablesDictionary = [Octostache.VariableDictionary]::new()
    Invoke-OctopusApi ("$Chain_BaseApiUrl/variables/{0}" -f $deployment.ManifestVariableSetId) | ForEach-Object Variables | Where-Object {
        ($_.IsSensitive -eq $false) -and `
        ($_.Scope.Private -ne 'True') -and `
        ($null -eq $_.Scope.Action) -and `
        ($null -eq $_.Scope.Machine) -and `
        ($null -eq $_.Scope.TargetRole) -and `
        ($null -eq $_.Scope.Role) -and `
        ($null -eq $_.Scope.Tenant -or $_.Scope.Tenant -contains $tenant.Id) -and `
        ($null -eq $_.Scope.TenantTag -or (Compare-Object $_.Scope.TenantTag $tenant.TenantTags -ExcludeDifferent -IncludeEqual)) -and `
        ($null -eq $_.Scope.Environment -or $_.Scope.Environment -contains $deployment.EnvironmentId) -and `
        ($null -eq $_.Scope.Channel -or $_.Scope.Channel -contains $deployment.ChannelId) -and `
        ($null -eq $_.Scope.Project -or $_.Scope.Project -contains $deployment.ProjectId)
    } | ForEach-Object { $variablesDictionary.Set($_.Name, $_.Value) }
    $postDeployScript = $variablesDictionary.Evaluate($rawPostDeployScript)
    Write-Host "$($_.LogPrefix)Evaluated Post-Deploy Script:"
    Write-Host $postDeployScript
    Write-Host 'Script output:'
    [scriptblock]::Create($postDeployScript).Invoke()
}
