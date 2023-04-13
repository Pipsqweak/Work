function t1
{
    [CmdletBinding(DefaultParameterSetName='None')]
    Param(
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [String]
        $configFileName=$null,

        [Parameter(Mandatory=$false)]
        [String]
        $Description,

        [Parameter(Mandatory=$false)]
        [Switch]
        $TrackOverallElapsed,

        [Parameter(Mandatory=$false, ParameterSetName="Riverbed")]
        [Switch]
        $Riverbed,

        [Parameter(Mandatory=$true, ParameterSetName="Riverbed")]
        [String[]]
        $RiverbedOffices
    )

    Write-Host $RiverbedOffices.Length

}

$efiBootSpec = [VMware.Vim.VirtualMachineConfigSpec]::new()
$efiBootSpec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
$bootSpec = [VMware.Vim.VirtualMachineBootOptions]::new()
$bootSpec.EfiSecureBootEnabled = $false
$efiBootSpec.BootOptions = $bootSpec

$win22SecureBootVMs = @(Get-VM -Server $vCenter | Where-Object { ($_.ExtensionData.Config.GuestFullName -match "2022") -and ($_.ExtensionData.Config.BootOptions.EfiSecureBootEnabled)})
$win22SecureBootVMs | ForEach-Object {
    $testVM = $_
    $wasPoweredOn = $false
    if($testVM.PowerState -ne 'PoweredOff')
    {
        $wasPoweredOn = $true
        $testVM.ExtensionData.ShutdownGuest()
        do
        {
            $testVM = Get-VM -Server $vCenter -Name $testVM.Name
            if($testVM.PowerState -ne 'PoweredOff')
            {
                Start-Sleep -Seconds 5
            }
        } until($testVM.PowerState -eq 'PoweredOff')
    }
    $testVM.ExtensionData.ReconfigVM($efiBootSpec)
    if($wasPoweredOn)
    {
        $testVM.ExtensionData.PowerOnVM_Task($testVM.VMHost.ExtensionData.MoRef)
    }
}
