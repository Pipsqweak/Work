$dnsServers = [System.Collections.Generic.SortedDictionary[String, [System.Collections.Generic.List[Object]]]]::new()
$dnsServers.Add("east", [System.Collections.Generic.List[Object]]::new())
$dnsServers["east"].Add("10.1.201.198")
$dnsServers["east"].Add("10.71.128.75")

$dnsServers.Add("west", [System.Collections.Generic.List[Object]]::new())
$dnsServers["west"].Add("10.71.128.75")
$dnsServers["west"].Add("10.1.201.198")

$dnsServers.Add("calgary", [System.Collections.Generic.List[Object]]::new())
$dnsServers["calgary"].Add("10.254.38.68")
$dnsServers["calgary"].Add("10.254.9.115")

function SetSVMDNS
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [DataONTAP.C.Types.Net.NetDnsInfo] $dnsInfo,

        [Parameter(Mandatory=$true, Position=1)]
        [String] $region,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $TestOnly
    )

    if($Script:dnsServers.ContainsKey($region))
    {
        $setDNS = $TestOnly.IsPresent
        if(-not $setDNS)
        {
            $setDNS = $dnsInfo.NameServers.Length -ne 2
            if(-not $setDNS)
            {
                $a = 0
                while((-not $setDNS) -and ($a -lt $Script:dnsServers[$region].Count))
                {
                    $setDNS = $Script:dnsServers[$region][$a] -ne $dnsInfo.NameServers[$a]
                    $a++
                }
            }
        }

        if($setDNS)
        {
            Write-Host -ForegroundColor Green ("Updating DNS servers on {0}:{1}" -f @($dnsInfo.NcController.Name, $dnsInfo.VserverName))
            try
            {
                $Error.Clear()
                if(-not $TestOnly.IsPresent)
                {
                    $setDNSParams = @{
                        Controller = $dnsInfo.NcController
                        NameServers = $Script:dnsServers[$region]
                        SkipConfigValidation = $true
                        ErrorAction = "Stop"
                    }
                    if(-not [String]::IsNullOrEmpty($dnsInfo.VserverName))
                    {
                        $setDNSParams.Add("VserverContext", $dnsInfo.Vserver)
                    } `
                    else
                    {
                        $setDNSParams.Add("VserverContext", $dnsInfo.NcController.Name)
                    }

                    $newDNSInfo = Set-NcNetDns @setDNSParams
                } `
                else
                {
                    Write-Host -ForegroundColor Yellow ("`tsimulated")
                }

                try
                {
                    $dnsTestParams = @{
                        Controller = $dnsInfo.NcController
                        ErrorAction = "Stop"
                    }
                    if(-not [String]::IsNullOrEmpty($dnsInfo.VserverName))
                    {
                        $dnsTestParams.Add("VserverContext", $dnsInfo.Vserver)
                    } `
                    else
                    {
                        $dnsTestParams.Add("VserverContext", $dnsInfo.NcController.Name)
                    }
                    $dnsTestResults = Test-NcNetDns @dnsTestParams

                    $dnsTestResults.ForEach({ Write-Host -ForegroundColor Green ("`tNS: {0}`tController: {1}`tStatus: {2}`tStatusDetails: {3}`tVServer: {4}`tCode: {5}" -f @($_.NameServer, $_.NCController.Name, $_.Status, $_.StatusDetails, $_.VServer, $_.Code)) })
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("Failed to test DNS settings on {0}:{1}" -f @($dnsInfo.NcController.Name, $dnsInfo.VserverName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to update DNS servers on {0}:{1}" -f @($dnsInfo.NcController.Name, $dnsInfo.VserverName, $Error[0].Exception.Message))
            }
        }
    } `
    else
    {
        Write-Host -ForegroundColor Red ("Bad region specified: {0}" -f @($region))
    }
}


$ncDNS = Get-NCNetDNS -Controller @($cdot.Values)
$sb.Clear()
for($a = 0; $a -lt $ncDNS.Length; $a++) { $null = $sb.AppendLine(("{0}) {1}:{2} [{3}]" -f @($a, $ncDNS[$a].NcController.Name, $ncDNS[$a].VserverName, ($ncDNS[$a].NameServers -join ",")))) }
$sb.ToString() | scb


$ncDNS.ForEach({
    $region = "east"

    if($_.NCController.Name -in @("BDC-CDOTCLST01", "DA11-NTAP01", "LAB-NTAP01", "LAS04-NTAP01", "SE4-NTAP01"))
    {
        $region = "west"
    } `
    elseif($_.NCController.Name -in @("YYC01-NTAP01"))
    {
        $region = "calgary"
    }

    if(($_.VServerName -match "DR\-") -or ($true -eq $true))
    {
        Write-Host ("`r`nSetSVMDNS -dnsInfo {0}:{1} -region {2}" -f @($_.NcController.Name, $_.VserverName, $region))
        SetSVMDNS -dnsInfo $_ -region $region # -TestOnly
    }
})
