<#
.SYNOPSIS
    Add or update access keys for azure function apps.
.DESCRIPTION
    For the specified Azure Resource Group, find the azure function app. If the key name already exists, update the key with the new value. if it doesn't exist, add a new key.
.EXAMPLE
    .\src\Create-FunctionAppAccesskey.ps1 -resourcegroupname "Development-DV10-PYXFT2-Function-EnableApi" -FunctionAppName "pyxft2-EnableApi" -keyname "TEST" -keyvalue "w2ga2kVeaKSXEkfJHajdk508q2Rzazwrrdke45kPRXmmBYa2zUDo7Q=="
#>
[CmdletBinding()]
Param (

    [Parameter()]
    [string]
    $resourceGroupName,

    [Parameter()]
    [string]
    $FunctionAppName,

    [Parameter()]
    [string]
    $KeyName,

    [Parameter()]
    [string]
    $KeyValue
)

$group = (az group exists --name $resourceGroupName)

if ($null -eq $group)
{
    Write-Warning "The group for $resourceGroupName can't be found! Please ensure you have the correct group name."
    Exit
}
else {
    Write-Host "$resourceGroupName group found" -ForegroundColor Cyan
    if ($FunctionAppName -in (az functionapp list -g $resourceGroupName | convertfrom-json).name) {
        write-host "Found Functionapp: $functionappname" -ForegroundColor Cyan
        if (!(az functionapp keys list -g $resourceGroupName -n $FunctionAppName | convertFrom-Json).functionkeys.$KeyName) {
            Write-host "No key found with the name: $KeyName. Adding..." -ForegroundColor DarkBlue
            az functionapp keys set -g $resourceGroupName -n $FunctionAppName --key-type functionKeys --key-name $KeyName --key-value $KeyValue | Out-Null
            write-host "The new key, $KeyName has been added to $FunctionAppName" -ForegroundColor Cyan
        }
        else {
            Write-host "found a key already matching $keyname, checking value" -ForegroundColor DarkBlue
            $value = (az functionapp keys list -g $resourceGroupName -n $FunctionAppName | convertFrom-Json).functionkeys.$KeyName
            if ($value -eq $KeyValue) {
                write-host "The values are the same." -ForegroundColor Cyan
            }
            else {
                Write-Host "The values are different, updating the current key with the new value. Old value: $value , New value: $KeyValue" -ForegroundColor DarkBlue
                az functionapp keys set -g $resourceGroupName -n $FunctionAppName --key-type functionKeys --key-name $KeyName --key-value $KeyValue | Out-Null
                write-host "The key $keyname has been updated so the value is now $keyvalue." -ForegroundColor Cyan
            }
        }
    }
    else {
        Write-Error "Can't find the functionapp: $functionappname"
    }
}
