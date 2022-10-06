Import-Module DataONTAP

$smNodeNames = @(
    "ARBPRDNAS1","ATLPRDNAS2","ATLPRDNAS3","BOSPRDNAS1",
    "EDPPRDNAS1","FTWPRDNAS1","HAMPRDNAS1","HLYPRDNAS2","HLYPRDNAS3",
    "MSNNAS1","MTLPRDNAS1","ORASAN1","ORASAN2","ORLPRDNAS1","ORLPRDNAS2",
    "STLPRDNAS2","STLPRDNAS3","SYRNAS1","TDCPRDNAS1","VANPRDNAS1")

$smNodes = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]]::new()

$smNodeNames | % {
    $c = $null
    $t = 0
    Write-Host -NoNewline ("Connecting to: {0}" -f @($_))
    while(($c -eq $null) -and ($t -lt 5))
    {
        try
        {
            Write-Host -NoNewline "."
            $c = Connect-NaController -Name $_ -Transient -RPC -ErrorAction Stop
        }
        catch
        {
            try
            {
                Write-Host -NoNewline "."
                $c = Connect-NaController -Name $_ -Transient -ErrorAction Stop
            }
            catch
            {
            }
        }
        $t++
    }
    if($null -ne $c)
    {
        Write-Host ("`r`n`tConnected")
        $smNodes.Add($_, $c)
    }
    else
    {
        Write-Host ("`r`n`tFailed to connect")
    }
}


$cDotNames = @(
    "DEN-CDOTCLST01", "CDC-CDOTCLST01", "APL-CDOTCLST01", "BDC-CDOTCLST01", "ADC-CDOTCLST01",
    "AST-CDOTCLST01", "AUS-CDOTCLST01", "BDCD-CDOTCLST01", "BIL-CDOTCLST01", "BOI-CDOTCLST01",
    "CLK-CDOTCLST01", "FMC-CDOTCLST01", "FRE-CDOTCLST01", "HOU-CDOTCLST01", "LAX-CDOTCLST01",
    "MIN-CDOTCLST01", "OPK-CDOTCLST01", "PHX-CDOTCLST01", "PLV-CDOTCLST01", "PTL-CDOTCLST01",
    "SAN-CDOTCLST01", "SLC-CDOTCLST01", "ITO-CDOTCLST01", "LAB-NTAP01")

$cDot = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()
foreach($n in @($cDotNames | Sort-Object))
{
<#
    try
    {
        $ncCred = Get-NcCredential -Controller $n -ErrorAction Stop
        if($null -ne $ncCred)
        {
            Remove-NcCredential -Controller $n -Confirm:$false
        }
    }
    catch {}
    Add-NcCredential -Controller $n -Credential $cred | Out-Null
#>
    try
    {
        $k = $null
        $k = Connect-NcController -Name $n <# -Credential $cred #> -Transient -HTTPS -ErrorAction Stop
        if($null -ne $k)
        {
            Write-Host ("Connected to {0}" -f @($n))
            $cDot.Add($n, $k)
        }
        else
        {
            Write-Host ("Failed to connect to {0}" -f @($n))
        }
    }
    catch { }
}
