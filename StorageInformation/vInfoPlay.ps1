# $vol = Get-NCVol -Controller $cDot['ADC-CDOTCLST01'] -Vserver "ADC-SVMA01" -Name "vol_SMB_REPLICATE_01"
# $vi = [StorageInformation]::new($vol)

# Reset [StorageInformation]
Measure-Command {
    [StorageInformation]::Reset()
    [StorageInformation]::Collect(@($cDot.Values), $vCenter)
}

Clear-Host
$Global:aggrSnapshotEstimates = [System.Collections.Generic.SortedDictionary[[System.String], [double]]]::new()
$Global:volSnapshotEstimates = [System.Collections.Generic.SortedDictionary[[System.String], [double]]]::new()

$slVIs = @($vInfos | Where-Object { $_.IsSnaplocked() })

ShowVIs $vInfos $true

ShowVIs $slVIs $true

function ShowVIs($viData, $calcSnapData=$false)
{
    $a = 0
    while($a -lt $viData.Count)
    {
        $snaplockIndicator = ""
        if($viData[$a].IsSnaplocked())
        {
            $snaplockIndicator = "`tsnaplocked"
        }
        Write-Host ("{0}:{1}:{2} [{3} snapshots]{4}" -f @($viData[$a].baseVolume.NcController.Name, $viData[$a].baseVolume.Vserver, $viData[$a].baseVolume.Name, $viData[$a].snapshots.Count, $snaplockIndicator))

        ShowMirrors $viData[$a] 1 $calcSnapData

        if($viData[$a].volumeShares.Count -gt 0)
        {
            Write-Host "`tShares:"
            $b = 0
            while($b -lt $viData[$a].volumeShares.Count)
            {
                Write-Host ("`t`t\\{0}\{1} [{2}]" -f @($viData[$a].volumeShares[$b].CifsServer,$viData[$a].volumeShares[$b].ShareName, $viData[$a].volumeShares[$b].Path))
                $b++
            }
            Write-Host
        }

        if($viData[$a].volumeDatastores.Count -gt 0)
        {
            Write-Host "`tDatastores:"
            $b = 0
            while($b -lt $viData[$a].volumeDatastores.Count)
            {
                Write-Host ("`t`t{0} [{1}{2}]" -f @($viData[$a].volumeDatastores[$b].Name, $viData[$a].volumeDatastores[$b].RemoteHost[0], $viData[$a].volumeDatastores[$b].RemotePath))
                $b++
            }
            Write-Host
        }

        if($viData[$a].volumeVMs.Count -gt 0)
        {
            Write-Host "`tVMs:"
            $b = 0
            while($b -lt $viData[$a].volumeVMs.Count)
            {
                Write-Host ("`t`t{0} {1}" -f @($viData[$a].volumeVMs[$b].Name, $viData[$a].volumeVMs[$b].PowerState))
                $b++
            }
        }
        Write-Host

        $a++
    }
}

function ShowMirrors($vi, $lvl=0, $calcSnapData=$false)
{
    $indent = [String]::new([char]9, $lvl)
    $b = 0
    while($b -lt $vi.snapmirrorDestinationVolumes.Count)
    {
        $volKey = "{0}:{1}:{2}" -f @($vi.snapmirrorDestinationVolumes[$b].baseVolume.NcController.Name, $vi.snapmirrorDestinationVolumes[$b].baseVolume.Vserver, $vi.snapmirrorDestinationVolumes[$b].baseVolume.Name)
        $snapOutput = [String]::Empty
        if($calcSnapData)
        {
            $snapshotData = $vi.snapmirrorDestinationVolumes[$b].snapshots | Measure-Object -Property Total -Average
            if($vi.snapmirrorDestinationVolumes[$b].baseVolume.Name.StartsWith("SL_"))
            {
                if(-not $Global:volSnapshotEstimates.ContainsKey($volKey))
                {
                    $Global:volSnapshotEstimates.Add($volKey, ($snapshotData.Average * 180))
                }

                if(-not $Global:aggrSnapshotEstimates.ContainsKey($vi.snapmirrorDestinationVolumes[$b].baseVolume.Aggregate))
                {
                    $Global:aggrSnapshotEstimates.Add($vi.snapmirrorDestinationVolumes[$b].baseVolume.Aggregate, 0.0)
                }
                $Global:aggrSnapshotEstimates[$vi.snapmirrorDestinationVolumes[$b].baseVolume.Aggregate] += ($snapshotData.Average * 180)

                $snapOutput = ", Avg: {0}, 180day est: {1}" -f @((Format-StorageNumber $snapshotData.Average), (Format-StorageNumber ($snapshotData.Average * 180)))
            }
        }
        Write-Host ("{0}==> {1} [{2} snapshots{3}]" -f @($indent, $volKey, $vi.snapmirrorDestinationVolumes[$b].snapshots.Count, $snapOutput))
        ShowMirrors $vi.snapmirrorDestinationVolumes[$b] ($lvl + 1) $calcSnapData
        $b++
    }
}

function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","K","M","G","T","P","E","Z","Y")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2}{1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}


$slVIs = $vInfos | Where-Object { $_.IsSnaplocked() }

$spaceData = @(
    $a = 0
    while($a -lt $slVIs.Length)
    {
        $b = 0
        $slVols = $slVIs[$a].GetSnaplockVolumes()
        $baseAvgSnapshotSize = $slVIs[$a].baseVolume.VolumeSpaceAttributes.SizeUsedBySnapshots / $slVIs[$a].baseVolume.VolumeSnapshotAttributes.SnapshotCount
        while($b -lt $slVols.Length)
        {
            $median = 0
            $snSizes = @($slVols[$a].snapshots | Select-Object -ExpandProperty Total | Sort-Object)
            if(([double] ($snSizes.Length / 2)) -eq ([int] ($snSizes.Length / 2 )))
            {
                $mid = [Math]::Floor($snSizes.Length / 2)
                $median = ($snSizes[$mid - 1] + $snSizes[$mid]) / 2
            }
            else
            {
                $median = $snSizes[$snSizes.Length / 2]
            }
            $avg = ($snSizes | Measure-Object -Average).Average

            $d = "" | Select-Object Cluster,VServer,Aggregate,Volume,SizeUsed,SLSnapshotCount,SLSnapshotUsed,BaseSnapshotCount,BaseSnapshotUsed
            $d.Cluster = $slVols[$b].baseVolume.NcController.Name
            $d.VServer = $slVols[$b].baseVolume.Vserver
            $d.Aggregate = $slVols[$b].baseVolume.Aggregate
            $d.Volume = $slVols[$b].baseVolume.Name
            $d.SizeUsed = $slVols[$b].baseVolume.VolumeSpaceAttributes.SizeUsed

            $l = $t = @($slVols[$b].snapshots | Where-Object { -not $_.Name.StartsWith("snapmirror") })
            foreach($k in $l)
            {
                Write-Host ("{0} : {1}" -f @($k.Name, (Format-StorageNumber $k.Total)))
            }
            Write-Host ("----------------------------------------------------------------------")
            $t = @($slVols[$b].snapshots | Where-Object { $_.Name.StartsWith("snapmirror") })
            $d.SLSnapshotCount = $slVols[$b].baseVolume.VolumeSnapshotAttributes.SnapshotCount - $t.Length
            foreach($k in $t)
            {
                Write-Host ("{0} : {1}" -f @($k.Name, (Format-StorageNumber $k.Total)))
            }
            Write-Host ("======================================================================`r`n")
            $d.SLSnapshotUsed = $slVols[$b].baseVolume.VolumeSpaceAttributes.SizeUsedBySnapshots # - ($t | Measure-Object -Property Total -Sum).Sum

            $d.BaseSnapshotCount = $slVIs[$a].baseVolume.VolumeSnapshotAttributes.SnapshotCount
            $d.BaseSnapshotUsed = $slVIs[$a].baseVolume.VolumeSpaceAttributes.SizeUsedBySnapshots

            $d


            $b++
        }



        $a++
    }
)

$spaceData | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard

$a = 0
while($a -lt $ssUUIDs.Length)
{
    $ss = @($snapshots | Where-Object { $_.SnapshotInstanceUuid -eq $ssUUIDs[$a].SnapshotInstanceUuid })
    if($ss.Length -gt 1)
    {
        Write-Host ("{0}: {1} snapshots" -f @($ssUUIDs[$a].SnapshotInstanceUuid, $ss.Length))
    }
    $a++
}



[StorageInformation]::volumes | Where-Object { $_.Name.StartsWith("LSM_") } | Select-Object Name,@{N="IsClusterVolume";E={$_.VolumeStateAttributes.IsClusterVolume}},@{N="IsNodeRoot";E={$_.VolumeStateAttributes.IsNodeRoot}},@{N="IsVserverRoot";E={$_.VolumeStateAttributes.IsVserverRoot}} | ft -AutoSize

$srcVols | Select-Object Name,@{N="IsClusterVolume";E={$_.VolumeStateAttributes.IsClusterVolume}},@{N="IsNodeRoot";E={$_.VolumeStateAttributes.IsNodeRoot}},@{N="IsVserverRoot";E={$_.VolumeStateAttributes.IsVserverRoot}} | ft -AutoSize


$volumeData = [System.Collections.Generic.List[VolumeExportRecord]]::new()
$snapmirrorData = [System.Collections.Generic.List[SnapmirrorExportRecord]]::new()
$snapshotData = [System.Collections.Generic.List[SnapshotExportRecord]]::new()
$shareData = [System.Collections.Generic.List[ShareExportRecord]]::new()
$datastoreData = [System.Collections.Generic.List[DatastoreExportRecord]]::new()
$vmData = [System.Collections.Generic.List[VirtualMachineExportRecord]]::new()


$a = 0
while($a -lt [StorageInformation]::storageInfo.Count)
{
    Write-Host ("Processing {0}: {1}:{2}:{3}..." -f @($a, [StorageInformation]::storageInfo[$a].baseVolume.NcController.Name, [StorageInformation]::storageInfo[$a].baseVolume.Vserver, [StorageInformation]::storageInfo[$a].baseVolume.Name))
    $eData = [StorageInformation]::storageInfo[$a].ExportToCSV()

    if($eData.VolumeData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} volume records" -f @($eData.VolumeData.Count))
        $b = 0
        # Merge volume export data
        $eData.VolumeData | ForEach-Object {
            $i = $volumeData.BinarySearch($_)
            if($i -lt 0)
            {
                $volumeData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    if($eData.SnapmirrorData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} snapmirror records" -f @($eData.SnapmirrorData.Count))
        $b = 0
        # Merge snapmirror export data
        $eData.SnapmirrorData | ForEach-Object {
            $i = $snapmirrorData.BinarySearch($_)
            if($i -lt 0)
            {
                $snapmirrorData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    if($eData.SnapshotData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} snapshot records" -f @($eData.SnapshotData.Count))
        $b = 0
        # Merge snapshot export data
        $eData.SnapshotData | ForEach-Object {
            $i = $snapshotData.BinarySearch($_)
            if($i -lt 0)
            {
                $snapshotData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    if($eData.ShareData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} share records" -f @($eData.ShareData.Count))
        $b = 0
        # Merge share export data
        $eData.ShareData | ForEach-Object {
            $i = $shareData.BinarySearch($_)
            if($i -lt 0)
            {
                $shareData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    if($eData.DatastoreData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} datastore records" -f @($eData.DatastoreData.Count))
        $b = 0
        # Merge datastore export data
        $eData.DatastoreData | ForEach-Object {
            $i = $datastoreData.BinarySearch($_)
            if($i -lt 0)
            {
                $datastoreData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    if($eData.VMData.Count -gt 0)
    {
        Write-Host ("`tmerging {0} VM records" -f @($eData.VMData.Count))
        $b = 0
        # Merge virual machine export data
        $eData.VMData | ForEach-Object {
            $i = $vmData.BinarySearch($_)
            if($i -lt 0)
            {
                $vmData.Insert(-bnot $i, $_)
                $b++
            }
        }
        Write-Host ("`t`t{0} merged records" -f @($b))
    }

    Write-Host
    $a++
}

$exportFolder = "C:\Temp\StorageInformation"
[StorageInformation]::ExportStaticData($exportFolder)
$volumeData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_volumeData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force
$snapmirrorData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_snapmirrorData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force
$snapshotData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_snapshotData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force
$shareData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_shareData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force
$datastoreData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_datastoreData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force
$vmData | Export-Csv -Delimiter "," -NoTypeInformation -Path ("{0}\{1}_vmData.csv" -f @($exportFolder,[StorageInformation]::dataCollectionTimestamp)) -Force


$a = 0

while($a -lt $vInfos.Count)
{
    Write-Host ("{0}: {1}:{2}:{3}" -f @($a, $vInfos[$a].baseVolume.NcController.Name, $vInfos[$a].baseVolume.Vserver, $vInfos[$a].baseVolume.Name))
    $a++
}
