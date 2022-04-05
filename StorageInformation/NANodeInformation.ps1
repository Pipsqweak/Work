class NAVolumeInformation8
{
    [DataONTAP.Types.Volume.VolumeInfo] $volume = $null
    [System.Collections.Generic.List[DataONTAP.Types.Snapshot.SnapshotInfo]] $snapshots = $null
    [NetApp.Ontapi.Filer.NaController] $node = $null

    NAVolumeInformation8([NetApp.Ontapi.Filer.NaController] $node, [DataONTAP.Types.Volume.VolumeInfo] $volume)
    {
        $this.node = $node
        $this.volume = $volume
        $this.snapshots = [System.Collections.Generic.List[DataONTAP.Types.Snapshot.SnapshotInfo]]::new()

        Write-Host -NoNewline ("`t`tgetting snapshots for {0}..." -f @($this.volume.Name))
        try
        {
            Get-NaSnapshot -Controller $this.node -TargetName $this.volume.Name -ErrorAction Stop | ForEach-Object {
                $this.snapshots.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.snapshots.Count))
    }
}

class NANodeInformation8
{
    [NetApp.Ontapi.Filer.NaController] $node = $null
    [System.Collections.Generic.List[DataONTAP.Types.Aggr.AggrInfo]] $aggregates = $null
    [System.Collections.Generic.List[NAVolumeInformation8]] $volumes = $null
    [System.Collections.Generic.List[DataONTAP.Types.Snapvault.SnapvaultConfigurationInfo]] $snapvaults = $null
    [System.Collections.Generic.List[DataONTAP.Types.Snapmirror.SnapmirrorStatusInfo]] $snapmirrors = $null
    [System.Collections.Generic.List[DataONTAP.Types.Cifs.CifsShareInfo]] $shares = $null
    [System.Collections.Generic.List[DataONTAP.Types.Nfs.ExportsRuleInfo2]] $nfsExports = $null
    [System.Collections.Generic.List[DataONTAP.Types.Net.InterfaceConfigInfo]] $netInterfaces = $null

    NANodeInformation8([NetApp.Ontapi.Filer.NaController] $node)
    {
        $this.node = $node
        Write-Host ("Loading data for {0}..." -f @($this.node.Name))

        $this.netInterfaces = [System.Collections.Generic.List[DataONTAP.Types.Net.InterfaceConfigInfo]]::new()
        $this.aggregates = [System.Collections.Generic.List[DataONTAP.Types.Aggr.AggrInfo]]::new()
        $this.volumes = [System.Collections.Generic.List[NAVolumeInformation8]]::new()
        $this.snapvaults = [System.Collections.Generic.List[DataONTAP.Types.Snapvault.SnapvaultConfigurationInfo]]::new()
        $this.snapmirrors = [System.Collections.Generic.List[DataONTAP.Types.Snapmirror.SnapmirrorStatusInfo]]::new()
        $this.shares = [System.Collections.Generic.List[DataONTAP.Types.Cifs.CifsShareInfo]]::new()
        $this.nfsExports = [System.Collections.Generic.List[DataONTAP.Types.Nfs.ExportsRuleInfo2]]::new()

        Write-Host -NoNewline ("`tgetting network interfaces...")
        try {
            Get-NaNetInterface -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $this.netInterfaces.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.netInterfaces.Count))

        Write-Host -NoNewline ("`tgetting aggregates...")
        try
        {
            Get-NaAggr -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $this.aggregates.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.aggregates.Count))

        Write-Host ("`tgetting volumes...")
        try
        {
            Get-NaVol -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $v = [NAVolumeInformation8]::new($this.node, $_)
                $this.volumes.Add($v)
            }
        }
        catch {}
        Write-Host ("`t{0} volumes" -f @($this.volumes.Count))

        Write-Host -NoNewline ("`tgetting snapvaults...")
        try
        {
            Get-NaSnapvault -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $this.snapvaults.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.snapvaults.Count))

        Write-Host -NoNewline ("`tgetting snapmirrors...")
        try
        {
            Get-NaSnapmirror -Controller $this.node -ErrorAction Stop | ForEach-Object { 
                $this.snapmirrors.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.snapmirrors.Count))

        Write-Host -NoNewline ("`tgetting shares...")
        try
        {
            Get-NaCifsShare -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $this.shares.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.shares.Count))

        Write-Host -NoNewline ("`tgetting NFS exports...")
        try
        {
            Get-NaNfsExport -Controller $this.node -ErrorAction Stop | ForEach-Object {
                $this.nfsExports.Add($_)
            }
        }
        catch {}
        Write-Host ("{0}" -f @($this.nfsExports.Count))
    }
}