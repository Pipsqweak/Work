class clsUCSCompute
{
    [string] $serial
    [string] $vmHostName

    clsUCSCompute([string] $serial, [string] $vmHostName)
    {
        $this.serial = $serial
        $this.vmHostName = $vmHostName
    }
}   # clsUCSCompute
