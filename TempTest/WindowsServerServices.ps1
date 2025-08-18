$vms = Get-VM -Server $vCenter
$poweredOnVMs = $vms | Where-Object { $_.Powerstate -eq "PoweredOn" }
$poweredOnWindowsServerVMs = $poweredOnVMs | Where-Object { $_.ExtensionData.Guest.GuestFullName -match "Windows Server" }

$serversByService = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.String]]]::new()
$servicesByName = [System.Collections.Generic.SortedDictionary[System.String, System.String]]::new()

$a = 0
while($a -lt $poweredOnWindowsServerVMs.Length)
{
    try
    {
        $hostServices = Get-Service -ComputerName $poweredOnWindowsServerVMs[$a].Name -ErrorAction Stop
        $runningHostServices = $hostServices | Where-Object { $_.Status -eq "running" }
        $b = 0
        while($b -lt $runningHostServices.Length)
        {
            if(-not $servicesByName.ContainsKey($runningHostServices[$b].Name))
            {
                $servicesByName.Add($runningHostServices[$b].Name, $runningHostServices[$b].DisplayName)
            }

            if(-not $serversByService.ContainsKey($runningHostServices[$b].Name))
            {
                $newList = [System.Collections.Generic.List[System.String]]::new()
                $serversByService.Add($runningHostServices[$b].Name, $newList)
            }

            $idx = $serversByService[$runningHostServices[$b].Name].BinarySearch($poweredOnWindowsServerVMs[$a].Name)
            if($idx -lt 0)
            {
                $serversByService[$runningHostServices[$b].Name].Insert(-bnot $idx, $poweredOnWindowsServerVMs[$a].Name)
            }

            $b++
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to get services for {0}." -f @($poweredOnWindowsServerVMs[$a].Name))
    }

    $a++
}