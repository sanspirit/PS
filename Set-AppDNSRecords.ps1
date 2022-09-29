#Ensure you are on the CTInfrastructure Subscription // Set-AzContext CTInfrastructure

$dnsenv = "elt"
$tenantlist = "ft1","ft2"
$endpoint = "dev-ctazure.trafficmanager.net."
$dnsiamenv = $dnsenv
if ($tenantlist -notlike "*ft*") {$dnsenv = $null}

foreach ($tenantname in $tenantlist){
    $dnslist = `
    "$($dnsiamenv)",`
    "iam-identity$($dnsenv)$($tenantname)",`
    "token-identity$($dnsenv)$($tenantname)",`
    "assethunter$($dnsenv)$($tenantname)",`
    "enable$($dnsenv)$($tenantname)",`
    "enable$($dnsenv)$($tenantname)2",`
    "enable$($dnsenv)$($tenantname)admin",`
    "fusion$($dnsenv)$($tenantname)",`
    "fusion$($dnsenv)$($tenantname)admin",`
    "fusionfunds$($dnsenv)$($tenantname)",`
    "fusionops$($dnsenv)$($tenantname)",`
    "fusionopsapi$($dnsenv)$($tenantname)",`
    "ariaip$($dnsenv)$($tenantname)",`
    "ariaip$($dnsenv)$($tenantname)admin",`
    "suitabilityapi$($dnsenv)$($tenantname)",`
    "suitabilitywriter$($dnsenv)$($tenantname)",`
    "enableaccessapi$($dnsenv)$($tenantname)",`
    "iq$($dnsenv)$($tenantname)",`
    "benchmarkidadmin$($dnsenv)$($tenantname)",`
    "advisor$($dnsenv)$($tenantname)",`
    "storybook$($dnsenv)$($tenantname)",`
    "playground$($dnsenv)$($tenantname)",`
    "callback$($dnsenv)$($tenantname)"

    foreach ($record in $dnslist) {
        Write-Host "Checking for record name: $record" -ForegroundColor Cyan
        $Records = @()
        $Records += New-AzDnsRecordConfig -Cname $endpoint
        if (!(Get-AzDnsRecordSet -Name $record -RecordType CNAME -ResourceGroupName "ctazuredns" -ZoneName "ctazure.co.uk" -ErrorAction SilentlyContinue)) {
            Write-Host "Record was not found! Adding: $record" -ForegroundColor Magenta
            $recordSet = New-AzDnsRecordSet -Name $record -RecordType CNAME -ResourceGroupName "ctazuredns" -TTL 3600 -ZoneName "ctazure.co.uk" -DnsRecords $Records
        }
        else {
            write-host "Record was found!" -ForegroundColor DarkCyan
        }
    }
}
