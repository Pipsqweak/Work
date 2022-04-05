
$myVols = @(
    $a = 0
    while($a -lt $smbVIs.Length)
    {
        $slVols = $smbVIs[$a].GetSnaplockVolumes()

        $b = 0
        while($b -lt $slVols.Count)
        {
            $snapData = $slVols[$b].snapshots | Measure-Object -Average -Sum -Property Total

            $d = "" | Select-Object Cluster,VServer,Volume,Count,Average,Sum,Retention

            $d.Cluster = $slVols[$b].baseVolume.NcController.Name
            $d.VServer = $slVols[$b].baseVolume.Vserver
            $d.Volume = $slVols[$b].baseVolume.Name
            $d.Count = $snapData.Count
            $d.Average = $snapData.Average
            $d.Sum = $snapData.Sum

            if(($d.Volume -notmatch "SQL") -and ($d.Volume -notmatch "Backup"))
            {
                # $volSLAttrs = Set-NcSnaplockVolAttr -Controller $slVols[$b].baseVolume.NcController -VserverContext $slVols[$b].baseVolume.Vserver -Volume $slVols[$b].baseVolume.Name -MaximumRetentionPeriod "14days"
                $volSLAttrs = Get-NcSnaplockVolAttr -Controller $slVols[$b].baseVolume.NcController -VserverContext $slVols[$b].baseVolume.Vserver -Volume $slVols[$b].baseVolume.Name
                $d.Retention = $volSLAttrs.MaximumRetentionPeriod

                $d
            }

            Write-Host ("{0}) {1}:{2}:{3}  SL: {4}:{5}:{6} [Cnt: {7}, Avg: {8}, Sum: {9}]" -f @($b, $smbVIs[$a].baseVolume.NcController.Name, $smbVIs[$a].baseVolume.Vserver, $smbVIs[$a].baseVolume.Name, $slVols[$b].baseVolume.NcController.Name, $slVols[$b].baseVolume.Vserver, $slVols[$b].baseVolume.Name, $snapData.Count, (Format-StorageNumber $snapData.Average), (Format-StorageNumber $snapData.Sum)))
            $b++
        }

        $a++
    }
)
