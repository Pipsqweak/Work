[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $apiKey,

    [Parameter(Mandatory=$true,Position=1)]
    [String]
    $exportFile
)

if(-not [String]::IsNullOrEmpty($apiKey))
{
    $headers = @{
      "X-Cisco-Meraki-API-Key" = $apiKey
    }  

    $clientsPerPage = 1000
    $organizations = @()

    try
    {
        $organizations = Invoke-RestMethod 'https://api.meraki.com/api/v0/organizations' -Method 'GET' -Headers $headers
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
                $networksURI = "https://api.meraki.com/api/v0/organizations/{0}/networks" -f @($organizations[$o].id)
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

                                $timeSpan = 2678400   # 31 days = max
                                $timeSpan = 3600      # 1 hour
                                $networkClientsURI = "https://api.meraki.com/api/v0/networks/{0}/clients?timespan={1}&perPage={2}&startingAfter={3}" -f @($networks[$n].id, $timeSpan, $clientsPerPage,$startingAfter)
                          
                                try
                                {
                                    $networkClients = Invoke-RestMethod $networkClientsURI -Method 'GET' -Headers $headers
                                }
                                catch
                                {
                                    $apiFailed = $true
                                    Write-Error ("    API call failed. [{0}]" -f @($networkClientsURI))
                                }

                                if($networkClients.Length -gt 0)
                                {
                                    $c = 0
                                    while($c -lt $networkClients.Length)
                                    {
                                        $clients += $networkClients[$c]
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
                            Write-Error ("  Missing network id for network {0}." -f @($networks[$n].name))
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