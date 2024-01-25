$vCtr = $vCenter
$vdiName = "DDC-VDISTD-092"  # & 92

# Note: {, }, and $ need to be escaped.
$getBootDiskTypeScript = "Get-Disk | Where-Object {{ `$_.IsBoot }} | Select-Object -ExpandProperty PartitionStyle"

$getBootDiskTypeScript = { Get-Disk | Where-Object { $_.IsBoot } }


$allRunningWin10VMs = @(Get-VM -Server $vCtr | Where-Object { ($_.Name -notmatch "^vCLS") -and ($_.PowerState -eq "PoweredOn") -and ($_.ExtensionData.Guest.GuestFullName -match "Windows 10") })
$win10VMsWithoutEFIBoot = [System.Collections.Generic.List[System.Object]]::new()
$win10VMsWithEFIBoot = [System.Collections.Generic.List[System.Object]]::new()

$allRunningWin10VMs | ForEach-Object {
    if($_.ExtensionData.Config.Firmware -eq "EFI")
    {
        $win10VMsWithEFIBoot.Add($_)
    }
    else
    {
        $win10VMsWithoutEFIBoot.Add($_)
    }
}

$win10VMNoData = [System.Collections.Generic.List[System.Object]]::new()
$win10VMBootDataMBR = [System.Collections.Generic.List[System.Object]]::new()
$win10VMBootDataGPT = [System.Collections.Generic.List[System.Object]]::new()
$win10VMBootDataUNK = [System.Collections.Generic.List[System.Object]]::new()
$win10VMBootDataNotCollected = [System.Collections.Generic.List[System.Object]]::new()
$win10VMBitlockerDataNotCollected = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $win10VMsWithoutEFIBoot.Count)
{
    $vm = $win10VMsWithoutEFIBoot[$a]
    Write-Host ("Collecting disk data from: {0}" -f @($vm.Name))
    $d = GetVM-DiskData -vm $vm

    if($null -ne $d)
    {
        if($null -ne $d.BootDisk)
        {
            Write-Host ("`tBoot partition style: {1}" -f @($d.Name, $d.BootDisk.PartitionStyle))
            if($d.BootDisk.PartitionStyle -eq "GPT")
            {
                $win10VMBootDataGPT.Add($d)
            }
            elseif($d.BootDisk.PartitionStyle -eq "MBR")
            {
                if($null -eq $d.BitlockerVolumes)
                {
                    Write-Host ("ERROR: Failed to retrieve BitLocker information from VM: {0}." -f @($d.VM.Name))
                    $win10VMBitlockerDataNotCollected.Add($d)
                }
                else
                {
                    Write-Host ("`tBitlocker volumes: {0}" -f @(@($d.BitlockerVolumes | Select-Object -ExpandProperty MountPoint) -join ", "))
                    $win10VMBootDataMBR.Add($d)
                }
            }
            else
            {
                Write-Host ("`tUnknown boot partition style.  Skipping {0}." -f @($d.VM.Name))
                $win10VMBootDataUNK.Add($d)
            }
        }
        else
        {
            Write-Host ("ERROR: Failed to retrieve boot disk information from VM: {0}." -f @($d.Name))
            $win10VMBootDataNotCollected.Add($d)
        }
    }
    else
    {
        Write-Host ("ERROR: Failed to retrieve any data from {0}." -f @($win10VMsWithoutEFIBoot[$a].Name))
        $win10VMNoData.Add($vm)
    }

    $a++
}


function GetVM-DiskData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VM.UniversalVirtualMachineImpl]
        $vm
    )

    $d = "" | Select-Object VM, BootDisk, BitlockerVolumes

    $d.VM = $vm
    try
    {
        $d.BootDisk = Invoke-Command -ComputerName $d.VM.Name -ScriptBlock { Get-Disk | Where-Object { $_.IsBoot } } -ErrorAction Stop
        # Write-Host ("`tBoot disk number: {0}" -f @($d.BootDisk.DiskNumber))

        # If the boot disk is not GPT, get partition and BitLocker data...
        if($d.BootDisk.PartitionStyle -ne "GPT")
        {
            try
            {
                <#
                    $d.BootPartition = Invoke-Command -ComputerName $d.VM.Name -ArgumentList $d.BootDisk.Path -ScriptBlock {
                        param ($diskID)
                        Get-Partition -DiskId $diskID | Where-Object { $_.IsBoot }
                    } -ErrorAction Stop
                #>

                try
                {
                    $d.BitlockerVolumes = @(Invoke-Command -ComputerName $d.VM.Name -ScriptBlock { Get-BitlockerVolume | Where-Object { $_.VolumeStatus -eq "FullyEncrypted" }} -ErrorAction Stop)
                }
                catch
                {
                    # Write-Host ("ERROR: Failed to retrieve BitLocker information from VM: {0}." -f @($d.VM.Name))
                }
            }
            catch
            {
                # Write-Host ("ERROR: Failed to retrieve parition data from {0} for disk path: {1}." -f @($d.VM.Name, $d.BootDisk.Path))
            }
        }
        else
        {
            # Nothing, Since the VM already uses EFI boot, we don't care about BitLocker...
        }
    }
    catch
    {
    }

    return @( , $d)
}

function ConvertComputer-ToGPT
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $computerName,

        [Parameter(Mandatory=$true,Position=0)]
        [int]
        $diskNumber
    )

    $retval = $false

    try
    {
        $validationOutput = [String]::Empty

        # First, validate MBR3GPT conversion...
        $validationOutput = Invoke-Command -Computer $computerName -ScriptBlock {
            param ($dNum)
            mbr2gpt /validate /disk:$dNum /allowFullOS
        } -ArgumentList $diskNumber -ErrorAction Stop

        if(-not [String]::IsNullOrEmpty($validationOutput) -and ($validationOutput -join "`r`n") -match "Validation completed successfully")
        {
            Write-Host ("MBR2GPT conversion validated for {0} disk number {1}" -f @($computerName, $diskNumber))
            Write-Host ("Converting disk {0} on {1} to GPT" -f @($diskNumber, $computerName))

            try
            {
                $conversionOutput = Invoke-Command -Computer $computerName -ScriptBlock {
                    param ($dNum)
                    mbr2gpt /convert /disk:$dNum /allowFullOS
                } -ArgumentList $diskNumber -ErrorAction Stop

                if(-not [String]::IsNullOrEmpty($conversionOutput) -and ($conversionOutput -join "`r`n") -match "Conversion completed successfully")
                {
                    Write-Host ("MBR2GPT conversion successful for {0} disk number {1}" -f @($computerName, $diskNumber))
                    $retval = $true
                }
                else
                {
                    Write-Host ("ERROR: Failed to convert MBR to GPT for {0} disk number {1}`r`n`t{2}" -f @($computerName, $diskNumber, ($validationOutput -join "`r`n`t")))
                }
            }
            catch
            {
                Write-Host ("EXCEPTION: Failed to convert MBR to GPT for {0} disk number {1}" -f @($computerName, $diskNumber))
            }
        }
        else
        {
            Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}`r`n`t{2}" -f @($computerName, $diskNumber, ($validationOutput -join "`r`n`t")))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}" -f @($computerName, $diskNumber))
    }

    return $retval
}

function ShutdownAndRestartVM
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VM.UniversalVirtualMachineImpl]
        $vm
    )
}
[Flags()]
enum UpdateStatus {
    ERROR = 0
    INCOMPLETE = 1
    MBR2GPT = 2
    EFIBOOT = 4
    VMTOOLS = 8
    HARDWARE = 16
    VTPM = 32
    COMPLETE = 62
}
<#
    PROCESS:

    1. Convert MBR to GPT
    2. Make sure VMTools is updated
    3.
#>

$updateStatus = [UpdateStatus]::INCOMPLETE
do
{

} while(($updateStatus -band [UpdateStatus]::INCOMPLETE) -eq [UpdateStatus]::INCOMPLETE)

function UpgradeWin10VM
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [VMware.VimAutomation.ViCore.Impl.V1.VM.UniversalVirtualMachineImpl]
        $vm,

        [Parameter(Mandatory=$true,Position=0)]
        [int]
        $diskNumber
    )

    $retval = [UpdateStatus]::INCOMPLETE

    # Only proceed to change VM to GPT boot if it uses bios firmware.
    if($vm.ExtensionData.Config.Firmware -eq "bios")
    {
        $d = GetVM-DiskData -vm $vm

        if($null -ne $d)
        {
            if($null -ne $d.BootDisk)
            {
                # VM says it uses BIOS (MBR), but just to be thorough...
                if($d.BootDisk.PartitionStyle -eq "MBR")
                {
                    # Convert MBR to GPT...
                    $successfulMBR2GPT = ConvertComputer-ToGPT -computerName $d.VM.Name -diskNumber $d.BootDisk.DiskNumber
                    if($successfulMBR2GPT)
                    {
                        $retval = $retval -bor [UpdateStatus]::MBR2GPT
                    }
                }
                elseif($d.BootDisk.PartitionStyle -eq "GPT")
                {
                    Write-Host ("{0} already uses EFI boot." -f @($d.VM.Name))
                    $retval = $retval -bor [UpdateStatus]::MBR2GPT
                }
                else
                {
                    Write-Host ("ERROR: {0} uses an unknown firmware: {1}." -f @($d.VM.Name, $d.ExtensionData.Config.Firmware))
                }
            }
            else
            {
                Write-Host ("ERROR: Failed to retrieve boot disk information from VM: {0}." -f @($d.VM.Name))
                $retval = [UpdateStatus]::ERROR
            }
        }
        else
        {
            Write-Host ("ERROR: Null data returned from GetVM-DiskData for VM: {0}." -f @($vm.Name))
            $retval = [UpdateStatus]::ERROR
        }
    }
    elseif($vm.ExtensionData.Config.Firmware -eq "efi")
    {
        # VM already set to EFI boot...Yes, I'm assuming the VM Guest boot disk is already GPT...
        $retval = $retval -bor [UpdateStatus]::MBR2GPT -bor [UpdateStatus]::EFIBOOT
    }

    if($d.VM.ExtensionData.Config.Tools.ToolsVersion -lt 12384)
    {
        # Upgrade VM Tools...
    }
    else
    {
        # VM Tools already upgraded...
    }

    return $retval

    # OLD ....

    try
    {
        $validationOutput = [String]::Empty

        $validationOutput = Invoke-Command -Computer $vm.Name -ScriptBlock {
            param ($dNum)
            mbr2gpt /validate /disk:$dNum /allowFullOS
        } -ArgumentList $diskNumber -ErrorAction Stop

        if(-not [String]::IsNullOrEmpty($validationOutput) -and ($validationOutput -join "`r`n") -match "Validation completed successfully")
        {
            Write-Host ("MBR2GPT conversion validated for {0} disk number {1}" -f @($vm.Name, $diskNumber))
            Write-Host ("Converting disk {0} on {1} to GPT" -f @($diskNumber, $vm.Name))

            try
            {
                $conversionOutput = Invoke-Command -Computer $vm.Name -ScriptBlock {
                    param ($dNum)
                    mbr2gpt /convert /disk:$dNum /allowFullOS
                } -ArgumentList $diskNumber -ErrorAction Stop

                if(-not [String]::IsNullOrEmpty($conversionOutput) -and ($conversionOutput -join "`r`n") -match "Conversion completed successfully")
                {
                    Write-Host ("MBR2GPT conversion successful for {0} disk number {1}" -f @($vm.Name, $diskNumber))
                    Write-Host ("Changing VM to EFI boot.")

                    # Change VM boot to EFI with secure boot.
                    $spec = [VMware.Vim.VirtualMachineConfigSpec]::new()
                    $spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
                    $spec.BootOptions = [VMware.Vim.VirtualMachineBootOptions]::new()
                    $spec.BootOptions.EfiSecureBootEnabled = $true

                    if($vm.Guest.ToolsVersion -ge "12.3.0")
                    {
                        # Schedule compatibility upgrade
                        $spec.ScheduledHardwareUpgradeInfo = [VMware.Vim.ScheduledHardwareUpgradeInfo]::new()
                        $spec.ScheduledHardwareUpgradeInfo.UpgradePolicy = [VMware.Vim.ScheduledHardwareUpgradeInfoHardwareUpgradePolicy]::onSoftPowerOff
                        $spec.ScheduledHardwareUpgradeInfo.VersionKey = “vmx-19”
                    }
                    else
                    {
                        # Schedule VM Tools upgrade
                        $spec.Tools = [VMware.Vim.ToolsConfigInfo]::new()
                        $spec.Tools.ToolsUpgradePolicy = "UpgradeAtPowerCycle"
                    }

                    # Reconfigure the VM
                    $vm.ExtensionData.ReconfigVM($spec)

                    # Add a virtual TPM to the VM.
                    $vm | New-VTpm
                }
                else
                {
                    Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}`r`n`t{2}" -f @($vm.Name, $diskNumber, ($validationOutput -join "`r`n`t")))
                }
            }
            catch
            {
                Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}" -f @($vm.Name, $diskNumber))
            }
        }
        else
        {
            Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}`r`n`t{2}" -f @($computerName, $diskNumber, ($validationOutput -join "`r`n`t")))
        }
    }
    catch
    {
        Write-Host ("ERROR: Failed to validate MBR2GPT conversion for {0} disk number {1}" -f @($computerName, $diskNumber))
    }
}
