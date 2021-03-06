<#
_author_ = Raajeev Kalyanaraman <raajeev.kalyanaraman@Dell.com>
_version_ = 0.1

Copyright (c) 2018 Dell EMC Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>

<#
 .SYNOPSIS
   Script to retrieve the inventory for a device

 .DESCRIPTION

   This script exercises the OME REST API to get the inventory
   for a device. The device can be filtered using the Device Name
   or Asset Tag or Service Tag or Device Id
   This example uses ODATA queries with filter constructs.

   Note that the credentials entered are not stored to disk.

 .PARAMETER IpAddress
   This is the IP address of the OME Appliance
 .PARAMETER Credentials
   Credentials used to talk to the OME Appliance
 .PARAMETER FilterBy
   Express filter criteria - Name/SvcTag/Id/AssetTag
 .PARAMETER DeviceInfo
   The actual field value to search by

   Note that this is a case sensitive search.

 .EXAMPLE
   $cred = Get-Credential
   .\Get-DeviceInventory.ps1 -IpAddress "10.xx.xx.xx" -Credentials
    $cred -FilterBy Name -DeviceInfo idrac-BZ0M630

 .EXAMPLE
   .\Get-DeviceInventory.ps1 -IpAddress "10.xx.xx.xx" -FilterBy SvcTag -DeviceInfo BZ0M630
   In this instance you will be prompted for credentials to use to
   connect to the appliance
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [System.Net.IPAddress] $IpAddress,

    [Parameter(Mandatory)]
    [pscredential] $Credentials,

    [Parameter(Mandatory)]
    [ValidateSet("Name","AssetTag", "Id", "SvcTag")]
    [String] $FilterBy,

    [Parameter(Mandatory)]
    [String] $DeviceInfo
)

function Set-CertPolicy() {
## Trust all certs - for sample usage only
Try {
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    Catch {
        Write-Error "Unable to add type for cert policy"
    }
}

Try {
    Set-CertPolicy
    $FilterMap = @{'Name'='DeviceName'; 'AssetTag'='AssetTag';
                   'Id'='Id'; 'SvcTag'='DeviceServiceTag'}
    $SessionUrl  = "https://$($IpAddress)/api/SessionService/Sessions"
    $FilterExpr  = $FilterMap[$FilterBy]
    $BaseUrl     = "https://$($IpAddress)/api/DeviceService/Devices?`$filter=$($FilterExpr) eq"
    $DevUrl      = ""
    $Type        = "application/json"
    $UserName    = $Credentials.username
    $Password    = $Credentials.GetNetworkCredential().password
    $UserDetails = @{"UserName"=$UserName;"Password"=$Password;"SessionType"="API"} | ConvertTo-Json
    $Headers     = @{}
    $DeviceId    = ""
    if ($FilterBy -eq 'Id') {
        $DevUrl = "$($BaseUrl) $($DeviceInfo)"
    }
    else {
        $DevUrl = "$($BaseUrl) '$($DeviceInfo)'"
    }
    $SessResponse = Invoke-WebRequest -Uri $SessionUrl -Method Post -Body $UserDetails -ContentType $Type
    if ($SessResponse.StatusCode -eq 200 -or $SessResponse.StatusCode -eq 201) {
        ## Successfully created a session - extract the auth token from the response
        ## header and update our headers for subsequent requests
        $Headers."X-Auth-Token" = $SessResponse.Headers["X-Auth-Token"]
        $DevResp = Invoke-WebRequest -Uri $DevUrl -UseBasicParsing -Headers $Headers -Method Get -ContentType $Type
        if ($DevResp.StatusCode -eq 200) {
            $DevInfo = $DevResp.Content | ConvertFrom-Json
            if ($DevInfo.'@odata.count' -gt 0) {
                $DeviceId = $DevInfo.value[0].Id
                $InventoryUrl = "https://$($IpAddress)/api/DeviceService/Devices($($DeviceId))/InventoryDetails"
                $InventoryResp = Invoke-WebRequest -Uri $InventoryUrl -UseBasicParsing -Headers $Headers -Method Get -ContentType $Type
                if ($InventoryResp.StatusCode -eq 200) {
                    $InventoryInfo = $InventoryResp.Content | ConvertFrom-Json
                    $InventoryInfo.value | ConvertTo-Json -Depth 4
                }
                else {
                    Write-Warning "Unable to retrieve inventory for device ($($DeviceInfo))"
                }
            }
            else {
                    Write-Warning "Unable to retrieve details for device ($($DeviceInfo)) from $($IpAddress)"
            }
        }
        else {
            Write-Warning "No device data retrieved from from $($IpAddress)"
        }
    }
    else {
        Write-Error "Unable to create a session with appliance $($IpAddress)"
    }
}
Catch {
    Write-Error "Exception occured - $($_.Exception.Message)"
}