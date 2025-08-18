[CmdLetBinding()]
Param(
    [Parameter(Mandatory,Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $apiKey,

    [Parameter(Mandatory,Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $exportFile,

    [Parameter(Position=2)]
    [ValidateRange(1, 2678400)]
    [Int32]
    $secondsBack = 86400
)

$clientProperties = @("network","adaptivePolicyGroup", "description", "deviceTypePrediction", "firstSeen", "groupPolicy8021x", "id", "ip", "ip6", "ip6Local", "lastSeen", "mac", "manufacturer", "notes", "os", "pskGroup", "recentDeviceConnection", "recentDeviceMac", "recentDeviceName", "recentDeviceSerial", "smInstalled", "ssid", "status", "switchport", "usage", "user", "vlan", "wirelessCapabilities")

if(-not [String]::IsNullOrEmpty($apiKey))
{
    $headers = @{
        "X-Cisco-Meraki-API-Key" = $apiKey
    }

    $clientsPerPage = 1000
    $organizations = @()

    try
    {
        $organizations = Invoke-RestMethod 'https://api.meraki.com/api/v1/organizations' -Method 'GET' -Headers $headers
    }
    catch { }

    $clients = @()
    if($organizations.Length -gt 0)
    {
        $o = 0
        while($o -lt $organizations.Length)
        {
            Write-Host ("`r`nProcessing {0}..." -f @($organizations[$o].name))

            if(-not [String]::IsNullOrEmpty($organizations[$o].id))
            {
                $networks = @()
                $networksURI = "https://api.meraki.com/api/v1/organizations/{0}/networks" -f @($organizations[$o].id)
                try
                {
                    $networks = Invoke-RestMethod $networksURI -Method Get -Headers $headers
                }
                catch { }

                if($networks.Length -gt 0)
                {
                    $n = 0
                    while($n -lt $networks.Length)
                    {
                        if($networks[$n].productTypes -notcontains "systemsManager")
                        {
                            if(-not [String]::IsNullOrEmpty($networks[$n].id))
                            {
                                Write-Host ("`r`n  Retrieving clients for network {0}..." -f @($networks[$n].name))

                                $networkClients = @()
                                $totalNetworkClients = 0
                                $apiFailed = $false
                                do
                                {
                                    $startingAfter = ""
                                    if($networkClients.Length -eq $clientsPerPage)
                                    {
                                        $startingAfter = $networkClients[$clientsPerPage - 1].id
                                    }

                                    $timeSpan = $secondsBack
                                    $networkClientsURI = "https://api.meraki.com/api/v1/networks/{0}/clients?timespan={1}&perPage={2}&startingAfter={3}" -f @($networks[$n].id, $timeSpan, $clientsPerPage,$startingAfter)

                                    $tries = 0
                                    $successful = $false
                                    do
                                    {
                                        $tries++
                                        try
                                        {
                                            $networkClients = Invoke-RestMethod $networkClientsURI -Method 'GET' -Headers $headers
                                            $successful = $true
                                        }
                                        catch
                                        {
                                            if($tries -eq 5)
                                            {
                                                $apiFailed = $true
                                                Write-Error ("    API call failed. [{0}]" -f @($networkClientsURI))
                                            }
                                            else
                                            {
                                                Start-Sleep -Milliseconds 500
                                            }
                                        }
                                    } while((-not $successful) -and ($tries -lt 5))

                                    if($networkClients.Length -gt 0)
                                    {
                                        $c = 0
                                        while($c -lt $networkClients.Length)
                                        {
                                            $d = Invoke-Expression ("`"`" | Select-Object " + ($clientProperties -join ","))
                                            $d.network = $networks[$n].name
                                            $p = 1   # skip "network"
                                            while($p -lt $clientProperties.Length)
                                            {
                                                $d.$($clientProperties[$p]) = $networkClients[$c].$($clientProperties[$p])
                                                $p++
                                            }

                                            $clients += $d
                                            $totalNetworkClients++

                                            $c++
                                        }
                                    }
                                    else
                                    {
                                        Write-Host ("`tNo clients returned for network: {0}" -f @($networks[$n].name))
                                    }
                                } while((-not $apiFailed) -and ($networkClients.Length -eq $clientsPerPage))

                                if(-not $apiFailed)
                                {
                                    Write-Host ("    Retrieved {0} clients." -f $totalNetworkClients)
                                }
                                else
                                {
                                }
                            }
                            else
                            {
                                # Write-Error ("  Missing network id for network {0}." -f @($networks[$n].name))
                            }
                        } `
                        else
                        {
                            # Nothing
                        }
                        $n++
                    }
                }
                else
                {
                    Write-Error ("Unable to retrieve a list of networks for organization {0}." -f @($organization[0].name))
                }
            }

            $o++
        }

        $clients | Sort-Object manufacturer,os | Export-CSV -Path $exportFile -NoTypeInformation -Force
        Write-Host ("{0} client records exported to {1}" -f @($clients.Count, $exportFile))
    }
    else
    {
        Write-Error ("Unable to determine organization ID.")
    }
}
else
{
    Write-Error ("Missing API key.")
}
