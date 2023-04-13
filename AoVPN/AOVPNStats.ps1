$aoVPNServerNames = @("ADCZ-AOVPN01", "ADCZ-AOVPN02", "ASTZ-AOVPN01", "ASTZ-AOVPN02", "BOIZ-AOVPN01", "BOIZ-AOVPN02", "CDCZ-AOVPN01", "CDCZ-AOVPN02", "CDCZ-AOVPN03", "CH3Z-AOVPN01", "CH3Z-AOVPN02", "CH3Z-AOVPN03", "DDCZ-AOVPN01", "DDCZ-AOVPN02", "DDCZ-AOVPN03", "FMCZ-AOVPN01", "FMCZ-AOVPN02", "FREZ-AOVPN01", "FREZ-AOVPN02", "FTWZ-AOVPN01", "FTWZ-AOVPN02", "OPKZ-AOVPN01", "OPKZ-AOVPN02", "ORAZ-AOVPN01", "ORAZ-AOVPN02", "PTLZ-AOVPN01", "PTLZ-AOVPN02", "STLZ-AOVPN01", "STLZ-AOVPN02")

$aoVPNUserData = [System.Collections.Generic.List[Object]]::new()
# $d = "" | Select-Object AoVPNServer, ClientName, ClientIP, ClientExternalIP, Location

$aoVPNUserAddress = [System.Collections.Generic.List[String]]::new()
$aoUsers = [System.Collections.Generic.SortedDictionary[[String],[String]]]::new()

foreach($aoVPNServer in $aoVPNServerNames)
{
    try
    {
        $clients = Get-RemoteAccessConnectionStatistics -ComputerName $aoVPNServer -ErrorAction Stop
        foreach($c in $clients)
        {
            $d = "" | Select-Object AoVPNServer, ClientName, ClientIP, ClientExternalIP, City, State
            $d.AoVPNServer = $aoVPNServer
            $d.ClientName = $c.UserName -join "|"
            $d.ClientIP = $c.ClientIPAddress.IPAddressToString
            $d.ClientExternalIP = $c.ClientExternalAddress.IPAddressToString

            $uri = "http://ip-api.com/json/{0}" -f @($d.ClientExternalIP)
            try
            {
                $result = Invoke-RestMethod -Method Get -Uri $uri -ErrorAction Stop
                Start-Sleep -Milliseconds 1500  # Pause to not exceed limit
                if(($null -ne $result) -and ($result.status -eq "success"))
                {
                    $d.City = $result.city
                    $d.State = $result.regionName

                    Write-Host ("{0}, {1}, {2}, {3}, {4}, {5}" -f @($d.AoVPNServer, $d.ClientName, $d.ClientIP, $d.ClientExternalIP, $d.City, $d.State))
                    $aoVPNUserData.Add($d)
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed: {0}" -f @($uri))
            }
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to query: {0}" -f @($aoVPNServer))
    }
}

$aoUserLocations = [System.Collections.Generic.SortedDictionary[[String],[String]]]::new()
foreach($a in @($aoUsers.Values))
{
    $uri = "http://ip-api.com/json/{0}" -f @($a)
    try
    {
        $result = Invoke-RestMethod -Method Get -Uri $uri -ErrorAction Stop
        if(($null -ne $result) -and ($result.status -eq "success"))
        {
            $userLoc = "{0}, {1}" -f ($result.City, $result.regionName)
            if(-not $aoUserLocations.ContainsKey($a))
            {
                $aoUserLocations.Add($a, $userLoc)
            }
        }
    }
    catch
    {

    }
}
