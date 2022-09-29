<#
.SYNOPSIS
    Count number of Octopus variables, including Project variables and LibraryVariableSets variables
.DESCRIPTION
    specify the Space Name to operate in or will use Default

    Requires Octopus.Client. Use dll from your Octopus Server/Tentacle installation directory or get from https://www.nuget.org/packages/Octopus.Client/
    Install-Package Octopus.Client -source https://www.nuget.org/api/v2 -SkipDependencies
.EXAMPLE
    # run locally
    .\src\Get-VariableCount.ps1 -spaceName Networking

    # or from package in Octopus Step
    Script file: Get-VariableCount.ps1
    Script params: -apiKey #{Octopus.Agent.ProgramDirectoryPath} -spaceName Networking
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $octopusURI = "https://octopus.ctazure.co.uk",

    [Parameter()]
    [string]
    $apiKey = "-",

    [Parameter()]
    [string]
    $spaceName = "Default",

    [Parameter()]
    [string]
    $octopusClientPath = "-"

)

$clientdll = "Octopus.Client.dll"

if (Test-Path -Path .\OctopusApi.key) {
    $secureApiKey = Get-Content -Path .\OctopusApi.key | ConvertTo-SecureString
    $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList "Domain\User", $secureApiKey
    $apiKey = $credentials.GetNetworkCredential().Password
    Write-Verbose "Using saved API Key"
}
if ($apiKey -eq "-") {
    throw "no ApiKey was provided"
}

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
else {
    Write-Output "Using Octopus client path: $octopusClientPath "
}


$path = Join-Path $octopusClientPath $clientdll

Add-Type -Path $path

$endpoint = New-Object Octopus.Client.OctopusServerEndpoint($octopusURI, $apikey)
$client = New-Object Octopus.Client.OctopusClient($endpoint)

# Get default repository and get space by name
$defaultRepository = $client.ForSystem()
$space = $defaultRepository.Spaces.FindByName($spaceName)


# Get space specific repository
$repositoryForSpace = $client.ForSpace($space)

$projectPattern = ""  #"EnvironmentTarget : Deployment"
$projects = $repositoryForSpace.Projects.GetAll().Where( { $_.Description -match $projectPattern})
#$projects = $repositoryForSpace.Projects.GetAll().Where( {$_.Name -eq "AssetHunter"})

Write-Output "Total Projects: $($projects.Count)"

$variablesTotal = 0
$libraryVariablesTotal = 0
$libraryVariableValuesTotal = 0

foreach ($project in $projects)
{
    #Write-Output $project.Name
    #$project = $repositoryForSpace.Projects.FindByName($projectName)
    $projectVariables = $repositoryForSpace.VariableSets.Get($project.VariableSetId)

    $variablesTotal += $projectVariables.Variables.Count
}
Write-Output "Total Project Variables: $variablesTotal"

$variableSets = $repositoryForSpace.LibraryVariableSets.FindAll()

Write-Output "Total LibraryVariableSets: $($variableSets.Count)"

foreach ($set in $variableSets)
{
    #Write-Output $set.Name $set.VariableSetId
    
    $setVariables = $repositoryForSpace.VariableSets.Get($set.VariableSetId)

    # unique variables by Name
    $libraryVariablesTotal += ($setVariables.Variables | Select-Object Name -Unique).Count

    # all variable scoped values
    $libraryVariableValuesTotal += $setVariables.Variables.Count
}

Write-Output "Total LibraryVariableSets Unique Variables: $libraryVariablesTotal"

Write-Output "Total LibraryVariableSets Variable Scoped Values: $libraryVariableValuesTotal"

Write-Output "Grand Total Variables: $($variablesTotal + $libraryVariablesTotal)"
