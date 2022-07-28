@(
    $a = 0
    while($a -lt $gisVMS.Length)
    {
        $b = 0
        while($b -lt $gisVMS[$a].Guest.Nics.Length)
        {
            $d = "" | Select-Object VM, IP, MAC

            $d.VM = $gisVMS[$a].Name
            $d.IP = $gisVMS[$a].Guest.Nics[$b].IPAddress | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" }
            $d.MAC = $gisVMS[$a].Guest.Nics[$b].MacAddress

            $d

            $b++
        }
        $a++
    }
) | Sort-Object VM, IP
