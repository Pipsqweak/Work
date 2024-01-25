ConnectTo cdot
$nodes = @(Get-NcNode -Controller @($cDot.Values))
$shelves = @(Get-NcStorageShelf -Controller @($cDot.Values))
$switches = @(Get-NcClusterSwitch -Controller @($cDot.Values))
$disks = @(Get-NCDisk -Controller @($cDot.Values))

$shelfFW = [System.Collections.Generic.List[System.Object]]::new()

$nodes | ForEach-Object {
     $ss = @(Get-NCShelf -Controller $_.NCController -NodeName $_.Node)
     $ss | Foreach-Object {
        $shelfFW.Add($_)
     }
}

$shelfFW | Sort-Object NodeName, ChannelName | Foreach-Object {
    $o = $_
    $d = "" | Select-Object NodeName,ChannelName,FirmwareRevA,FirmwareRevB,Model
    $d.NodeName = $_.NodeName
    $d.ChannelName = $_.ChannelName
    $d.FirmwareRevA = $_.FirmwareRevA
    $d.FirmwareRevB = $_.FirmwareRevB

    $s = @($shelves | Where-Object { $_.ShelfUid -eq $o.ShelfUid })
    if($s.Length -eq 1)
    {
        $d.Model = $s[0].ShelfModel
    }
    $d
}

<#
    cn1610:
        eos: 20250131
        eoa: 20191212

    DS212-12
        eos: -
        eoa: -

    DS2246
        eos: 20250131
        eoa: 20191209

    DS4246
        eos: 20250131
        eoa: 20191212

    DS224-12
        eos: -
        eoa: -

    DS2126
        eos: 20250131
        eoa: 20191212

    DS460-12
        eos: -
        eoa: -

#>
