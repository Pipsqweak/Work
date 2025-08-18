$controller = $cdcCDOT


if($controller.Name -match "CDC")
{
    # CDC
    $oldShelfNumbers =  @(0,1,2,3,4,5,30,31,32,50,51)
    $tenTBShelves = @(40..46)
} `
else
{
    # DDC
    $oldShelfNumbers = @(0,1,2,3,4,5,6,31,32,33,50,51,52)
    $tenTBShelves = @(40..49)
}

$vols = Get-NCVol -Controller $controller
$slVols = $vols | Where-Object { ($null -ne $_.VolumeSnaplockAttributes) -and ($_.VolumeSnaplockAttributes.SnaplockType -ne "non_snaplock") }
$slUsed = 0; $slVols.ForEach({ $slUsed += ($_.VolumeSpaceAttributes.SizeUsedBySnapshots + $_.VolumeSpaceAttributes.SizeUsed) })

<#
$ddcVols = Get-NCVol -Controller $ddcCDOT
$ddcSLVols = $ddcVols | Where-Object { $_.VolumeSnaplockAttributes.SnaplockType -ne "non_snaplock" }
$ddcSLUsed = 0; $ddcSLVols.ForEach({ $ddcSLUsed += ($_.VolumeSpaceAttributes.SizeUsedBySnapshots + $_.VolumeSpaceAttributes.SizeUsed) })
$ddcSLUsed / 1TB
#>

$disks = Get-NCDisk -Controller $controller

$uniqueDisks = [System.Collections.Generic.SortedDictionary[System.String,System.Object]]::new()

$disks.ForEach({
    $sn = $_.DiskInventoryInfo.SerialNumber
    if(-not $uniqueDisks.ContainsKey($sn))
    {
        $uniqueDisks.Add($sn, $_)
    }
})

$tenTBDisks = @($uniqueDisks.Values) | Where-Object { ($_.Shelf -in $tenTBShelves) -and ($_.DiskOwnershipInfo.OwnerNodeName -match "[BC]DC\-NASA0") }
$tenTBAggrNames = $tenTBDisks | Group-Object Aggregate | Select-Object -ExpandProperty Name | Where-Object { $_ -match "^aggr_" } | Sort-Object

$tenTBAggrs = Get-NCAggr -Controller $controller | Where-Object { $_.Name -in $tenTBAggrNames }

$tenTBAvailable = ($tenTBAggrs | Measure-Object -Sum -Property Available).Sum
$tenTBShelfUsable = (($tenTBAggrs | Measure-Object -Sum -Property TotalSize).Sum / $tenTBShelves.Length / 1TB)

$oldDisks = @($uniqueDisks.Values) | Where-Object { ($_.Shelf -in $oldShelfNumbers ) -and ($_.DiskOwnershipInfo.OwnerNodeName -match "[BC]DC\-NASA0") }

$oldAggrNames = $oldDisks | Group-Object Aggregate | Select-Object -ExpandProperty Name | Where-Object { -not [String]::IsNullOrEmpty($_) } | Sort-Object

$oldAggrs = Get-NCAggr -Controller $controller | Where-Object { $_.Name -in $oldAggrNames }

# $oldAggrs | Select-Object Name, @{N='Size';E={"{0,7:N2}TB" -f @(($_.AggrSpaceAttributes.SizeTotal / 1TB))}}, @{N='Used';E={"{0,7:N2}TB" -f @(($_.AggrSpaceAttributes.SizeUsed / 1TB))}}

$oldAggrUsed = 0; $oldAggrs.ForEach({ $oldAggrUsed += $_.AggrSpaceAttributes.SizeUsed })

$oldVols = $vols | Where-Object { $oldAggrNames -contains $_.Aggregate }
$oldVolUsed = 0; $oldVols.ForEach({ $oldVolUsed += ($_.VolumeSpaceAttributes.SizeUsedBySnapshots + $_.VolumeSpaceAttributes.SizeUsed) })

# $oldVols | Select-Object Name, Aggregate, @{N='Size';E={"{0,7:N2}TB" -f @(($_.VolumeSpaceAttributes.SizeTotal / 1TB))}}, @{N='Used';E={"{0,7:N2}TB" -f @((($_.VolumeSpaceAttributes.SizeUsed + $_.VolumeSpaceAttributes.SizeUsedBySnapshots) / 1TB))}} | Sort-Object Aggregate, Name

$sb = [System.Text.StringBuilder]::new()

[void] $sb.AppendLine(("{0}:" -f @($controller.Name.Substring(0,3))))
[void] $sb.AppendLine(("`tOld shelves: {0}" -f @(($oldShelfNumbers -join ", "))))
[void] $sb.AppendLine(("`tSnaplock used: {0:N2}TB" -f @(($slUsed / 1TB))))
[void] $sb.AppendLine(("`t10TB Available: {0:N2}TB" -f @(($tenTBAvailable / 1TB))))
if($oldVolUsed -gt ($slUsed + $tenTBAvailable))
{
    [void] $sb.AppendLine(("`tAdditional space needed to cover data on old shelves (old volume used - (snaplock used + 10TB avail)): {0:N2}TB" -f @(($oldVolUsed - ($slUsed + $tenTBAvailable)) / 1TB)))
} `
else
{
    [void] $sb.AppendLine(("`tExtra space ((snaplock used + 10TB avail) - old volume used): {0:N2}TB" -f @((($slUsed + $tenTBAvailable) - $oldVolUsed) / 1TB)))
}

[void] $sb.AppendLine("`r`n`tAggregates on old shelves:`r`n")

$aggrMaxNameLength = $oldAggrNames | Select-Object -ExpandProperty Length | Sort-Object Descending | Select-Object -First 1
$aggrMaxSizeLength = $oldAggrs | Select-Object @{N='Size';E={"{0,7:N2}TB" -f @(($_.AggrSpaceAttributes.SizeTotal / 1TB))}} | Select-Object -ExpandProperty Size | Select-Object -ExpandProperty Length | Sort-Object Descending | Select-Object -First 1
$aggrMaxUsedLength = $oldAggrs | Select-Object @{N='Used';E={"{0,7:N2}TB" -f @(($_.AggrSpaceAttributes.SizeUsed / 1TB))}} | Select-Object -ExpandProperty Used | Select-Object -ExpandProperty Length | Sort-Object Descending | Select-Object -First 1
$aggrFmtStr = "`t`t{{0,-{0}}} {{1,{1}:N2}}TB {{2,{2}:N2}}TB" -f @($aggrMaxNameLength, ($aggrMaxSizeLength - 2), ($aggrMaxUsedLength - 2))

[void] $sb.AppendLine(("`t`t{0,-$aggrMaxNameLength} {1,-$aggrMaxSizeLength} {2,-$aggrMaxUsedLength}" -f @("Name", "Size", "Used")))
[void] $sb.AppendLine(("`t`t{0} {1} {2}" -f @([String]::new('-', $aggrMaxNameLength), [String]::new('-', $aggrMaxSizeLength), [String]::new('-', $aggrMaxUsedLength))))
$oldAggrs.ForEach({
    [void] $sb.AppendLine(($aggrFmtstr -f @($_.Name,($_.AggrSpaceAttributes.SizeTotal / 1TB),($_.AggrSpaceAttributes.SizeUsed / 1TB))))
})

[void] $sb.AppendLine(("`r`n`tOld aggregates used: {0:N2}TB`r`n" -f @(($oldAggrUsed / 1TB))))

[void] $sb.AppendLine("`tVolumes on old shelves:`r`n")

$volMaxNameLength = 0
$volMaxAggrLength = 0
$volMaxSizeLength = 0
$volMaxUsedLength = 0
$oldVols.ForEach({
    if($volMaxNameLength -lt $_.Name.Length)
    {
        $volMaxNameLength = $_.Name.Length
    }
    if($volMaxAggrLength -lt $_.Aggregate.Length)
    {
        $volMaxAggrLength = $_.Aggregate.Length
    }
    $sizeStr = "{0:N2}TB" -f @(($_.VolumeSpaceAttributes.SizeTotal / 1TB))
    if($volMaxSizeLength -lt $sizeStr.Length)
    {
        $volMaxSizeLength = $sizeStr.Length
    }
    $usedStr = "{0:N2}TB" -f @((($_.VolumeSpaceAttributes.SizeUsedBySnapshots + $_.VolumeSpaceAttributes.SizeUsed) / 1TB))
    if($volMaxUsedLength -lt $usedStr.Length)
    {
        $volMaxUsedLength = $usedStr.Length
    }
})

$volFmtStr = "`t`t{{0,-{0}}} {{1,-{1}}} {{2,{2}:N2}}TB {{3,{3}:N2}}TB" -f @($volMaxNameLength, $volMaxAggrLength, ($volMaxSizeLength - 2), ($volMaxUsedLength - 2))

[void] $sb.AppendLine(("`t`t{0,-$volMaxNameLength} {1,-$volMaxAggrLength} {2,-$volMaxSizeLength} {3,-$volMaxUsedLength}" -f @("Name", "Aggregate", "Size", "Used")))
[void] $sb.AppendLine(("`t`t{0} {1} {2} {3}" -f @([String]::new('-', $volMaxNameLength), [String]::new('-', $volMaxAggrLength), [String]::new('-', $volMaxSizeLength), [String]::new('-', $volMaxUsedLength))))
$oldVols.ForEach({
    [void] $sb.AppendLine(($volFmtstr -f @($_.Name,$_.Aggregate, ($_.VolumeSpaceAttributes.SizeTotal / 1TB),(($_.VolumeSpaceAttributes.SizeUsedBySnapshots + $_.VolumeSpaceAttributes.SizeUsed) / 1TB))))
})

[void] $sb.AppendLine(("`r`n`tOld volume Used: {0:N2}TB`r`n" -f @(($oldVolUsed / 1TB))))

$sb.ToString().Replace("`t","    ") | Set-Clipboard
