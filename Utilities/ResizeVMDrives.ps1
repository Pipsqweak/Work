
$scriptText = @"
`$driveLetter = 'C'
Write-Host -NoNewline (`"Drive {0}: can `" -f @(`$driveLetter))
`$partition = Get-Partition -DriveLetter `$driveLetter
`$partitionSupportedSizes = Get-PartitionSupportedSize -DiskNumber `$partition.DiskNumber -PartitionNumber `$partition.PartitionNumber
if(`$partition.Size -lt `$partitionSupportedSizes.SizeMax)
{
    # Nothing
}
else
{
    Write-Host -NoNewline `" NOT `"
}
Write-Host (`"be resized`")
"@



$scriptText = @"
`$driveLetter = 'C'
`$partition = Get-Partition -DriveLetter `$driveLetter
`$partitionSupportedSizes = Get-PartitionSupportedSize -DiskNumber `$partition.DiskNumber -PartitionNumber `$partition.PartitionNumber
if(`$partition.Size -lt `$partitionSupportedSizes.SizeMax)
{
    Resize-Partition -DiskNumber `$partition.DiskNumber -PartitionNumber `$partition.PartitionNumber -Size `$partitionSupportedSizes.SizeMax -Confirm:`$false
}
else
{
    # Nothing, partition cannot be resized
}
"@

$vmsToResize = @(
    "DDC-VDI-SAS-01",
    "DDC-VDI-SAS-03",
    "DDC-VDI-SAS-07",
    "DDC-VDI-SAS-08",
    "DDC-VDI-SAS-10",
    "DDC-VDI-SAS-12",
    "DDC-VDI-SAS-13"
)

$vm = Get-VM -Name "BOI-VCAD-SP-001"

$boiVCadVMs = Get-VM | Where-Object { $_.Name -match "BOI\-VCAD\-SP" }
$resizeByGB = 20
foreach($vm in $boiVCadVMs)
{
    $hd = Get-HardDisk -VM $vm -Name "Hard disk 1"

    if($null -ne $hd)
    {
        $newCapacityGB = $hd.CapacityGB + $resizeByGB
        Set-HardDisk -HardDisk $hd -CapacityGB $newCapacityGB -Confirm:$false
        Invoke-VMScript -VM $vm -ScriptText $scriptText
    }
}


$testScriptBlock = {
    $driveLetter = 'C'
    $sb = [System.Text.StringBuilder]::new()
    [void] $sb.Append(("Drive {0}: can" -f @($driveLetter)))
    $partition = Get-Partition -DriveLetter $driveLetter
    $partitionSupportedSizes = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
    if($partition.Size -lt $partitionSupportedSizes.SizeMax)
    {
        # Nothing
    }
    else
    {
        [void] $sb.Append(" NOT ")
    }
    [void] $sb.AppendLine(" be resized")

    Write-Host $sb.ToString()
}

$testScriptBlock2 = {
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [char]
        $driveLetter,

        [Parameter(Mandatory=$true,Position=1)]
        [int]
        $resizeByGB,

        [Parameter(Mandatory=$false,Position=2)]
        [bool]
        $doResize=$false
    )
    # $driveLetter = 'C'
    $sb = [System.Text.StringBuilder]::new()
    [void] $sb.Clear()
    $requiredUnallocatedSpace = (($resizeByGB * 1GB) * 0.90)
    $partition = Get-Partition -DriveLetter $driveLetter
    [void] $sb.AppendLine("Current {0}: drive partition size: {1:N2} GB" -f @($driveLetter, ($partition.Size / 1GB)))
    [void] $sb.AppendLine("  Unallocated space required for partition resize: {0:N2} GB" -f @($requiredUnallocatedSpace / 1GB))
    $partitionSupportedSizes = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
    $unallocatedSpaceAvailable = $partitionSupportedSizes.SizeMax - $partition.Size
    [void] $sb.AppendLine("  Space available to resize: {0:N2} GB" -f @($unallocatedSpaceAvailable / 1GB))
    if($doResize)
    {
        if($unallocatedSpaceAvailable -gt $requiredUnallocatedSpace)
        {
            [void] $sb.AppendLine("  Resizing partition to {0:N2} GB" -f @($partitionSupportedSizes.SizeMax / 1GB))
            # Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $partitionSupportedSizes.SizeMax -Confirm:$false
            $postResizePartition = Get-Partition -DriveLetter $driveLetter
            if($postResizePartition.Size -ne $partition.Size)
            {
                [void] $sb.AppendLine("  {0}: drive expanded successfully." -f @($driveLetter))
            }
            else
            {
                [void] $sb.AppendLine("  Check {0}: drive, resize appears to have failed." -f @($driveLetter))
            }
        }
        else
        {
            [void] $sb.Append("  Insufficent space available after {0}: drive partition for resize operation." -f @($driveLetter))
        }
    }
    else
    {
        [void] $sb.AppendLine("  Skipping partition resize.")
    }

    Write-Host $sb.ToString()
}

Invoke-Command -ComputerName "47888L" -ScriptBlock $testScriptBlock2 -ArgumentList @('C', 30, $true)


$a = 0
Write-Host ("Checking {0}..." -f @($vmsToResize[$a]))
Invoke-Command -ComputerName $vmsToResize[$a] -ScriptBlock $testScriptBlock2 -ArgumentList @('C', 20)
$a++
