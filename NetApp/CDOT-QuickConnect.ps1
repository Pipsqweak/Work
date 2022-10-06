Import-Module DataONTAP

$cDotNames = @(
    "DEN-CDOTCLST01", "CDC-CDOTCLST01", "APL-CDOTCLST01", "BDC-CDOTCLST01", "ADC-CDOTCLST01",
    "AST-CDOTCLST01", "AUS-CDOTCLST01", "BDCD-CDOTCLST01", "BIL-CDOTCLST01", "BOI-CDOTCLST01",
    "CLK-CDOTCLST01", "FMC-CDOTCLST01", "FRE-CDOTCLST01", "HOU-CDOTCLST01", "MIN-CDOTCLST01",
    "OPK-CDOTCLST01", "PHX-CDOTCLST01", "PLV-CDOTCLST01", "PTL-CDOTCLST01", "SAN-CDOTCLST01",
    "SLC-CDOTCLST01", "ITO-CDOTCLST01", "LAB-NTAP01")


function CDOT-QuickConnect([string[]] $clusterNames)
{
    $tDict = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()
    foreach($n in @($clusterNames | Sort-Object))
    {
        try
        {
            $k = $null
            $k = Connect-NcController -Name $n -Credential $cred -Transient -HTTPS -ErrorAction Stop
            if($null -ne $k)
            {
                Write-Host ("Connected to {0}" -f @($n))
                $tDict.Add($n, $k)
            }
            else
            {
                Write-Error ("Failed to connect to {0}" -f @($n))
            }
        }
        catch
        {
            Write-Error ("Failed to connect to {0}" -f @($n))
        }
    }

    return $tDict
}

$cDot = CDOT-QuickConnect $cDotNames
