ConnectTo ucs

# $ucsManagers = @($labUCS, $cdcUCS, $ddcUCS)
$basePath = "E:\UCS Backups\"
$ucsManagerKeys = @($ucsManagers.Keys)
$a = 0
while($a -lt $ucsManagerKeys.Length)
{
    $ucs = $ucsManagers[$ucsManagerKeys[$a]]
    Write-Host ("Backing up UCS: {0}..." -f @($ucs.Ucs))
    foreach($b in @("config-all", "full-state"))
    {
        if ($b -eq "config-all")
        {
            $ext = "xml"
            $isXML = $true
        } `
        else # NOT ($b -eq "config-all")
        {
            $ext = "bak"
            $isXML = $false
        }
        $pathPattern = "{0}`${{ucs}}\`${{yyyy}}`${{MM}}`${{dd}}-`${{HH}}`${{mm}}-{1}.{2}" -f @($basePath, $b, $ext)
        Write-Host -NoNewline ("`t{0}..." -f @($b))
        try
        {
            $mo = Backup-Ucs -Type $b -PathPattern $pathPattern -Ucs $ucs -Xml:$isXML | Out-Null
            Write-Host -ForegroundColor Gray "complete"
        }
        catch
        {
            Write-Host -ForegroundColor Red "failed"
        }
    }

    $a++
}
