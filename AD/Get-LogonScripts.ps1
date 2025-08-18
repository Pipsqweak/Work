# Check GPOs...

$GPOs = Get-GPO -All -Server "CDC-DC01"

$DriveMappings = @()

foreach ($GPO in $GPOs) {
    $gpoReport = $GPO | Get-GPOReport -ReportType Xml -Server "CDC-DC01"
    $GPOXml = [xml]$gpoReport
    $GPOName = $GPOXml.GPO.Name
    Write-Host ("Checking: {0}" -f @($GPOName))
    foreach ($ExtensionData in $GPOXml.GPO.User.ExtensionData) {
        if ($ExtensionData.Name -eq "Drive Maps") {
            foreach ($Mapping in $ExtensionData.Extension.DriveMapSettings.Drive)
            {
                $DriveMapping = "" | Select-Object GPO, DriveLetter, Label, Path
                $DriveMapping.GPO = $GPOName
                $DriveMapping.DriveLetter = $Mapping.Properties.Letter + ":"
                $DriveMapping.Label = $Mapping.Properties.label
                $DriveMapping.Path = $Mapping.Properties.Path

                Write-Host ("`tLetter: {0}`tLabel: {1}`tPath: {2}" -f @($DriveMapping.DriveLetter, $DriveMapping.Label, $DriveMapping.Path))
                $DriveMappings += $DriveMapping
            }
        }
    }
}


# Check logon scripts
$users = Get-ADUser -Filter "*" -Properties scriptPath
$uniqueScripts = @($users | Where-Object { -not [String]::IsNullOrEmpty($_.scriptPath) } | Select-Object -Unique -ExpandProperty scriptPath | ForEach-Object { $_.Trim() })

$uniqueDriveMappings = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $uniqueScripts.Length)
{
    $script = Get-Content -path ("\\powereng.com\NETLOGON\{0}" -f @($uniqueScripts[$a]))

    $driveMappings = $script -match "net\s+use\s+(.)\:\s*(\\\\[^\s]+)"

    $b = 0
    while($b -lt $driveMappings.Length)
    {
        if($driveMappings[$b] -match "net\s+use\s+(.)\:\s*([^\s]+)")
        {
            $d = "" | Select-Object Drive, MapPath, ScriptName
            $d.ScriptName = $uniqueScripts[$a]
            $d.Drive = $Matches[1].ToLower()
            $d.MapPath = $Matches[2]
            $s = $d.MapPath.Split('\', [System.StringSplitOptions]::RemoveEmptyEntries)
            $d.MapPath = "{0}\{1}" -f @(("\\{0}.powereng.com" -f @($s[0])).ToLower(), $s[1])

            if(($uniqueDriveMappings | Where-Object { ($_.ScriptName -eq $d.ScriptName) -and ($_.Drive -eq $d.Drive) -and ($_.MapPath -eq $d.MapPath) }).Length -eq 0)
            {
                $uniqueDriveMappings.Add($d)
            }
        }
        $b++
    }
    $a++
}
