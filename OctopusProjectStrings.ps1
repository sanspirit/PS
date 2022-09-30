$apiKey = 'Add your API key here'
$header =  @{ "X-Octopus-ApiKey" = $apiKey }

try
{
    $Response=Invoke-WebRequest -Uri "https://octopus.ctazure.co.uk/api/spaces-63/runbookProcesses/?take=15000" -Method GET -Headers $header 
    # execute if the Invoke-WebRequest is successful
    $StatusCode = $Response.StatusCode
} catch {
    $StatusCode = $_.Exception.Response.StatusCode.value__
}


Write-Host  $StatusCode

$Response | ConvertFrom-Json |
ForEach-Object Items |
Where-Object { $_.Steps.Actions.Properties.'Octopus.Action.Script.ScriptSource' -Contains 'Inline' } |
  ForEach-Object {
    [pscustomobject]@{
      ProjectId = $_.ProjectId 
      RunbookId = $_.RunbookId 
      Name = $_.Steps.Name 
    }
  } | Out-File -FilePath ./output.txt
