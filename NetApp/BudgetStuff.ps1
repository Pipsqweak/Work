$ctrlr = $ddcCDOT
$aggrs = @(Get-NCAggr -Controller $ctrlr | Where-Object { $_.AggregateName -notmatch "ROOT_" })

$aggrs | Sort-Object -Property AggregateName | Select-Object -Property AggregateName, Disks, TotalSize, RaidType, @{N='RAIDGroupSize';E={$_.RaidSize}}, @{N='Plexes';E={$_.AggrRaidAttributes.PlexCount }}, @{N='RAIDGroups';E={$_.AggrRaidAttributes.Plexes[0].Raidgroups.Count }} | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
$disks = @(Get-NCDisk -Controller $ctrlr)


$stPools = @(Get-NcStoragePool -Controller $ctrlr)
$stPoolDisks = @(Get-NcStoragePoolDisk -Controller $ctrlr)




$disks | Sort-Object Aggregate,Shelf,Bay | ft -AutoSize
$disks | Sort-Object Aggregate,Shelf,Bay | Where-Object { $_.Aggregate -eq "aggr_CDC_NASA02_SATA_02" } |  ft -AutoSize

$disks | Sort-Object Aggregate,Shelf,Bay | Where-Object { $_.Aggregate -eq "aggr_DDC_NASB01_SSD_01" } | Group-Object Shelf

$disks | Sort-Object Aggregate,Shelf,Bay | Group-Object Shelf

$disks | Sort-Object Aggregate,Shelf,Bay | Where-Object { $_.Position -eq "shared" } | ft -AutoSize

$disks | Sort-Object Aggregate,Shelf,Bay | Where-Object { $_.DiskOwnershipInfo.OwnerNodeName -match "BDC-NASA" } | Select-Object -Unique Shelf,Bay
