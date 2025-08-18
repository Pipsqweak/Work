$smbVServers = @(Get-NcCifsShare -Controller @($cdot.values) | Select-Object -Unique -ExpandProperty CifsServer) # | Where-Object { $_ -notmatch "DR-" })
$cnames = Get-DnsServerResourceRecord -ComputerName CDC-DC01 -ZoneName powereng.com -RRType CName

$aliases = @()
$a = 0
while($a -lt $smbVServers.Length)
{
    $d = "" | Select-Object CIFSName, Aliases
    $d.CIFSName = $smbVServers[$a].ToLower()
    $smbCNames = @($cnames | Where-Object { $_.RecordData.HostNameAlias -match ("^{0}" -f @($smbVServers[$a])) })

    if($smbCNames.Length -gt 0)
    {
        $d.Aliases = @($smbCNames | ForEach-Object { $_.HostName.ToLower() }) -join ", "

        $aliases += $d
    }
    $a++
}
$aliases | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
