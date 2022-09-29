<#
.SYNOPSIS
    Send a Slack Notification message to the specified Slack Channel with result of an Octopus Deployment.
.DESCRIPTION
    Send a Slack Notification message to the specified Slack Channel with result of an Octopus Deployment.
.EXAMPLE
    # run locally
    .\src\Send-SlackNotification.ps1 -SlackChannel octobot_test -ProjectName Testing -ReleaseNumber 0.0.0 -EnvironmentName Dev -WebDeploymentLink "https://octopus.ctazure.co.uk/app#/Spaces-1/"  -WebReleaseLink "https://octopus.ctazure.co.uk/app#/Spaces-1/"


    # from package in an Octopus Step
    Script file: Send-SlackNotification.ps1
    Script params:  -SlackChannel #{_SlackChannel}
                    -ProjectName #{Octopus.Project.Name}
                    -ReleaseNumber #{Octopus.Release.Number}
                    -EnvironmentName #{Octopus.Environment.Name}
                    -WebDeploymentLink #{Octopus.Web.DeploymentLink}
                    -WebReleaseLink #{Octopus.Web.ReleaseLink}
                    -DeploymentTenantName #{Octopus.Deployment.Tenant.Name}
                    -TargetRoles #{Octopus.Action.TargetRoles}
                    -DeploymentError #{Octopus.Deployment.Error}
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $octopusURI = "https://octopus.ctazure.co.uk",

    [Parameter()]
    [string]
    $SlackChannel = "#octopus",

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
    $WebDeploymentLink,

    [Parameter()]
    [string]
    $WebReleaseLink,

    [Parameter()]
    [string]
    $DeploymentTenantName
)

$ErrorActionPreference = "continue"

# param not set if success
$DeploymentError = $OctopusParameters['Octopus.Deployment.Error']

function Send-SlackRichNotification ($hook_config, $notification)
{
    $payload = @{
        channel = $hook_config["channel"];
        username = $hook_config["username"];
        icon_url = $hook_config["icon_url"];
        text = $notification["fallback"];
        blocks = @(
            @{
            type = "section";
            text = @{
                type = "mrkdwn";
                text = $notification["text"];
                };
            },
            @{type = "divider"};
        );
    }

    try {
        #Write-Output ($payload | ConvertTo-Json )
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Method POST -Body ($payload | ConvertTo-Json -Depth 4) -Uri $hook -ContentType 'application/json'
    }
    catch [Exception] {
        $_.Exception | format-list
        Write-Warning "Failed to invoke $hook"
    }
}

$hook = "https://hooks.slack.com/services/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"

$hook_config = @{
    channel = $SlackChannel;
    username = "droctobot";
    icon_url = "https://octopus.com/images/company/Logo-Blue_140px_rgb.png";
};


$msgOutcome = "Success" # or "Failed"
$emoji = ":heavy_check_mark:"

if ($DeploymentError)
{
    Write-Output "Deployment Error: $DeploymentError"

    $msgOutcome = "Failed"
    $emoji = ":x:"
}

Send-SlackRichNotification $hook_config @{
    text = "$emoji *$msgOutcome* Deploying <$octopusURI$WebDeploymentLink|$ProjectName> release <$octopusURI$WebReleaseLink|$ReleaseNumber> to $EnvironmentName $TargetRoles $DeploymentTenantName";
    fallback = "$msgOutcome Deploying $ProjectName release $ReleaseNumber to $EnvironmentName";
};

exit 0  # don't fail deployment for logging.
