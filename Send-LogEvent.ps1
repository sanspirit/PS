<#
.SYNOPSIS
    Send a Log Event message (JSON) to the specified Log API with result of an Octopus Deployment.
.DESCRIPTION
    Send a Log Event message (JSON) to the specified Log API with result of an Octopus Deployment.
.EXAMPLE
    # run locally
    .\src\Send-LogEvent.ps1 -Event Start -ProjectName Testing -ReleaseNumber 0.0.0 -EnvironmentName Dev -Uri "https://octopus.ctazure.co.uk/app#/Spaces-1/" -Channel Release

    # from package in an Octopus Step
    Script file: Send-LogEvent.ps1
    Script params:  -ProjectName #{Octopus.Project.Name}
                    -ReleaseNumber #{Octopus.Release.Number}
                    -EnvironmentName #{Octopus.Environment.Name}
                    -Uri #{Octopus.Web.DeploymentLink}
                    -Channel #{Octopus.Release.Channel.Name}
                    -Space #{Octopus.Space.Name}
                    -TenantName #{Octopus.Deployment.Tenant.Name}
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $logAPI = "https://logstash.ctazure.co.uk/",

    [Parameter()]
    [string]
    $Source = "Octopus",

    [Parameter()]
    [string]
    $Type = "Deployment",

    [Parameter()]
    [ValidateSet("Start", "Complete")]
    [string]
    $Event = "Complete",

    [Parameter(Mandatory)]
    [string]
    $ProjectName,

    [Parameter(Mandatory)]
    [string]
    $ReleaseNumber,

    [Parameter()]
    [string]
    $EnvironmentName,

    [Parameter()]
    [string]
    $Uri,

    [Parameter()]
    [string]
    $Channel,

    [Parameter()]
    [string]
    $Space,

    [Parameter()]
    [string]
    $TenantName
)

    $ErrorActionPreference = "continue"

    # param not set if success
    $DeploymentError = $OctopusParameters['Octopus.Deployment.Error']

    $Agent = $env:COMPUTERNAME

    $logAPI = "https://logstash.ctazure.co.uk/"

    # build the authorization header        
    $headers = @{'authorization'='ApiKey ' + $apiKey}

    # build the body of the post
    $bodyObj = @{ source=$Source; Type=$Type; Event=$Event; Version=$ReleaseNumber; Name=$ProjectName; Environment=$EnvironmentName; }
    
    if ($Event -eq "Start" -or $Event -eq "Complete")
    {
        if ($Uri) { $bodyObj.Uri = $Uri }        
        if ($Agent) { $bodyObj.Agent = $Agent }
        if ($Space) { $bodyObj.Space = $Space }
        if ($Channel) { $bodyObj.Channel = $Channel }
        if ($TenantName) { $bodyObj.TenantName = $TenantName }
    }
    if ($Event -eq "Complete")
    {
        $msgOutcome = "Success"
        if ($DeploymentError) { $msgOutcome = "Failed" }
        $bodyObj.Outcome = $msgOutcome

        if ($DeploymentError)
        {
            Write-Output "Deployment Error: $DeploymentError"
            $bodyObj.Error = $DeploymentError
        }
    }
    
    $body = ConvertTo-Json $bodyObj
    
    Write-Output $body

    # Post the JSON event details
    Invoke-RestMethod -Uri $logAPI -Method POST -ContentType "application/json" -Headers $headers -Body $body

    exit 0  # don't fail deployment for logging.
