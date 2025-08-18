class SnapmirrorRelationship2
{
    [DataONTAP.C.Types.Volume.VolumeAttributes] $DestinationVolume = $null
    [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $Snapmirror = $null
    [System.Collections.Generic.List[[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]] $Datastores = $null

    SnapmirrorRelationship2([DataONTAP.C.Types.Volume.VolumeAttributes] $volume, [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $snapmirror, [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]] $datastores)
    {
        if($null -ne $volume)
        {
            $this.DestinationVolume = $volume
        }
        else
        {
            throw [System.NullReferenceException]::new("Volume object required for SnapmirrorRelationship.")
        }

        if($null -ne $snapmirror)
        {
            $this.Snapmirror = $snapmirror
        }
        else
        {
            throw [System.NullReferenceException]::new("Snapmirror object required for SnapmirrorRelationship.")
        }

        $this.Datastores = [System.Collections.Generic.List[[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]]::new()
        if($datastores.Length -gt 0)
        {
            $this.Datastores.AddRange($datastores)
        }
        else
        {
            # Nothing, no datastores associated with this destination volume
        }
    }
}

class MySnapmirror3
{
    [DataONTAP.C.Types.Volume.VolumeAttributes] $OriginalSourceVolume = $null
    [DataONTAP.C.Types.Volume.VolumeAttributes] $SourceVolume = $null
    [System.Collections.Generic.List[[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]] $Datastores = $null
    [System.Collections.Generic.List[SnapmirrorRelationship2]] $Relationships = $null

    MySnapmirror3([DataONTAP.C.Types.Volume.VolumeAttributes] $srcVolume, [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]] $datastores)
    {
        if($null -ne $srcVolume)
        {
            $this.OriginalSourceVolume = $srcVolume
            $this.SourceVolume = $srcVolume    # I think I can do this better.  Since we are capturing $srcVolume in .OriginalSourceVolume, I think I can wait to set .SourceVolume when I "fix" the new snapmirrors.
        }
        else
        {
            throw [System.NullReferenceException]::new("Source volume object required for MySnapmirror.")
        }

        $this.Datastores = [System.Collections.Generic.List[[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]]::new()
        if($datastores.Length -gt 0)
        {
            $this.Datastores.AddRange($datastores)
        }
        else
        {
            # Nothing, no datastores associated with this source volume
        }
        $this.Relationships = [System.Collections.Generic.List[SnapmirrorRelationship2]]::new()
    }

    [SnapmirrorRelationship2] AddRelationship([DataONTAP.C.Types.Volume.VolumeAttributes] $volume, [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo] $snapmirror, [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]] $datastores)
    {
        $_tmp = [SnapmirrorRelationship2]::new($volume, $snapmirror)
        $this.Relationships.Add($_tmp)

        return $_tmp
    }
}
