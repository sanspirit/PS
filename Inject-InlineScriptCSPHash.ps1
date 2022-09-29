<#
.SYNOPSIS
    Create CSP hashes for inline HTML scripts
.DESCRIPTION
    Looks inside the [htmlfile] file for any inline <script> tags then generates a SHA256 hash for the content of each script tag.
    In [webconfigfile] the placeholder #{INLINE_SCRIPT_HASH} is then replaced with the hashes. This means you can create a Content-Security-Policy
    header that blocks script excecution of any scripts except for our own (Specifically malicious browser extensions). 
    We do this at the deployment stage as it allows us to inject Octopus variables into our script tag at deploy time. If we generated the 
    hash at build time they would be incorrect when the content of <script> is changed with the updated Octopus variables.
.EXAMPLE
    .\src\Inject-InlineScriptCSPHash.ps1 -htmlfile .\index.html -webconfigfile .\web.config
#>

[CmdletBinding()]
Param (
  [Parameter(Mandatory)]
  [string]
  $htmlfile,

  [Parameter(Mandatory)]
  [string]
  $webconfigfile
)

$HTML = Get-Content -path $htmlfile -raw
$HTMLBytes = [System.Text.Encoding]::Unicode.GetBytes($HTML)
$document = New-Object -Com "HTMLFile"
$document.write($HTMLBytes)
$hashes = ""

foreach ($scriptBlock in $document.all.tags("script")) {
  if ($scriptBlock.text) {

    $encoder = [system.Text.Encoding]::UTF8
    $hasher = [System.Security.Cryptography.SHA256]::Create()

    $bytes = $encoder.GetBytes($scriptBlock.text)
    $hash = [System.Convert]::ToBase64String($hasher.ComputeHash($bytes))
    
    Write-Host "Found hash: $hash"
    $hashes += " 'sha256-" + $hash + "'"
  }
}

(Get-Content $webconfigfile) -replace "#{INLINE_SCRIPT_HASH}", $hashes.trim() | Set-Content $webconfigfile
