class CIFSShare
{
    [String] $CIFSServer = [String]::Empty
    [String] $Path = [String]::Empty
    [String] $Name = [String]::Empty
    [String] $Volume = [String]::Empty
    [String] $vServer = [String]::Empty
    [String] $MountPoint = [String]::Empty
    [Boolean] $check = $true  # Unless told otherwise, all shares are checked.
    [System.Collections.Generic.List[String]] $pathsToAvoid = [System.Collections.Generic.List[String]]::new()

    CIFSShare([DataONTAP.C.Types.Cifs.CifsShare] $share)
    {
        $this.CIFSServer = $share.CifsServer
        $this.Path = $share.Path
        $this.Name = $share.ShareName
        $this.Volume = $share.Volume
        $this.vServer = $share.Vserver
    }

    CIFSShare([DataONTAP.Types.Cifs.CifsShareInfo] $share, [String] $cifsServerName)
    {
        $this.CIFSServer = $cifsServerName
        $this.Name = $share.ShareName
        $this.MountPoint = $share.MountPoint
    }

    [void] AddPathToAvoid([String] $pathToAvoid)
    {
        if(-not [String]::IsNullOrEmpty($pathToAvoid))
        {
            $p2Avoid = $pathToAvoid.Replace("/","\")
            if(-not $p2Avoid.ToLower().StartsWith(("\\{0}" -f @($this.CIFSServer))))
            {
                $p2Avoid = "\\{0}{1}" -f @($this.CIFSServer, $p2Avoid)
            }
            else
            {
                # Nothing, path already contains CIFS Server name...
            }
            $idx = $this.pathsToAvoid.BinarySearch($p2Avoid)
            if($idx -lt 0)
            {
                $this.pathsToAvoid.Insert(-bnot $idx, $p2Avoid)
                [Log]::Info("Avoiding path {0}" -f @($p2Avoid))
            }
            else
            {
                # Nothing, no need for duplicate paths.
            }
        }
        else
        {
            [Log]::Error("Null/empty path to avoid in {0}" -f @($MyInvocation.MyCommand))
        }
    }

    [Boolean] Eq([CIFSShare] $otherShare)
    {
        [Boolean] $retval = $false

        if($null -ne $otherShare)
        {
            $retval = ($this.GetType().Equals($otherShare.GetType())) -and ($this.MountPoint.Equals($otherShare.MountPoint) -and $this.Name.Equals($otherShare.Name) -and $this.Path.Equals($otherShare.Path) -and $this.Volume.Equals($otherShare.Volume) -and $this.vServer.Equals($otherShare.vServer))
        }
        else
        {
            # Nothing... return $false
        }

        return [Boolean] $retval
    }

    [Boolean] Ne([CIFSShare] $otherShare)
    {
        return -not $this.Eq($otherShare)
    }
}
