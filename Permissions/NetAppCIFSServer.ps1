class NetAppCIFSServer
{
    [String] $name
    [String] $dnsDomainName
    [System.Collections.Generic.List[String]] $aliases = $null
    [System.Collections.Generic.List[CIFSShare]] $shares = $null
    [System.Object] $sourceObject = $null

    hidden [String] ReplaceFirst([String] $text, [String] $search, [String] $replace)
    {
        $retval = $text
        $pos = $text.IndexOf($search)
        if ($pos -ge 0)
        {
            $retval = $text.Substring(0, $pos) + $replace + $text.Substring($pos + $search.Length)
        }

        return $retval
    }

    hidden [void] PopulateAliases()
    {
        if(-not [String]::IsNullOrEmpty($this.name))
        {
            if(-not [String]::IsNullOrEmpty($this.dnsDomainName))
            {
                if($null -eq $this.aliases)
                {
                    $this.aliases = [System.Collections.Generic.List[String]]::new()
                }
                else
                {
                    # Nothing....already created $this.aliases
                }

                # Get a list of all the various servicePrincipalNames that exist for $cifsServers[$a]
                $computerObj = Get-ADComputer -Identity $this.name -Server $this.dnsDomainName -Properties servicePrincipalName
                if($null -ne $computerObj)
                {
                    $cifsSPNs = @($computerObj.servicePrincipalName | Where-Object { ($_.StartsWith("HOST")) -and ($_ -match $this.dnsDomainName) })
                    for($b = 0; $b -lt $cifsSPNs.Length; $b++)
                    {
                        $n = $cifsSPNs[$b].Replace("HOST/","")

                        $idx = $this.aliases.BinarySearch($n)
                        if($idx -lt 0)
                        {
                            $this.aliases.Insert(-bnot $idx, $n)
                        }
                        else
                        {
                            # Nothing, no dupes...
                        }
                    }
                }
                else
                {
                    [Log]::Warning("Unable to retrieve computer object for {0} in {1}." -f @($this.name, $MyInvocation.MyCommand))
                }
            }
            else
            {
                [Log]::Warning("Missing DNS domain for {0} in {1}", @($this.name, $MyInvocation.MyCommand))
            }
        }
        else
        {
            [Log]::Warning("Computer name missing in {0}." -f @($MyInvocation.MyCommand))
        }
    }

    hidden [void] PopulateSharesFromCifsServerConfig()
    {
        if($null -eq $this.shares)
        {
            [DataONTAP.C.Types.Cifs.CifsServerConfig] $cifsServerConfig = $this.sourceObject

            if($null -ne $cifsServerConfig)
            {
                $cntrlr = $cifsServerConfig.NcController

                # Get an array of all the mounted volumes on the controller.
                $mountedVols = @(Get-NcVol -Controller $cntrlr | Where-Object { ($_.State -eq "online") -and (-not [String]::IsNullOrEmpty($_.JunctionPath)) })

                $canSnapMirror = $false
                $snapMirrors = @()

                # Get the licenses on the controller
                $licenses = @(Get-NcLicense -Controller $cntrlr)

                # Get the CIFS licenses on the controller...
                $cifsLicenses = @($licenses | Where-Object { $_.Package -eq "cifs" })

                # Make sure there are CIFS licenses on the controller
                if($cifsLicenses.Length -gt 0)
                {
                    # Get the snapmirror licenses...
                    $snapMirrorLicenses = @($licenses | Where-Object { $_.Package -eq "snapmirror" })

                    # Make sure there is a snapmirror license on the same SVM where CIFS is running
                    $canSnapMirror = (@($cifsLicenses | Where-Object { @($snapMirrorLicenses | Select-Object -ExpandProperty Owner) -contains $_.Owner }).Length -gt 0)
                }
                else
                {
                    # Nothing, no reason to continue if there are no CIFS licenses on the controller...
                }

                $smsvVols = @()
                if($canSnapMirror)
                {
                    $snapMirrors = @(Get-NcSnapmirror -Controller $cntrlr)
                    for($s = 0; $s -lt $snapMirrors.Length; $s++)
                    {
                        $sVols = @($mountedVols | Where-Object { $_.Name -eq $snapMirrors[$s].DestinationVolume })
                        foreach($sVol in $sVols)
                        {
                            if(@($smsvVols | Where-Object { $_.Name -eq $sVol.Name }).Length -eq 0)
                            {
                                $smsvVols += $sVol
                            }
                            else
                            {
                                # Nothing, don't add dupes
                            }
                        }
                    }
                }
                else
                {
                    # Nothing, can't get snapmirrors without a license...
                }

                # Go through each of the shares adding any we need to check...
                $ncShares = @(Get-NcCifsShare -Controller $cntrlr -CifsServer $cifsServerConfig.CifsServer | Where-Object { $_.Path -ne "/" } | Sort-Object Path)
                for($a = 0; $a -lt $ncShares.Length; $a++)
                {
                    $check = $true

                    # If the share is based on a snapmirror or snapvault destination, do not check it.
                    #   Check against each snapmirror/snapvault volume.
                    for($m = 0; ($check) -and ($m -lt $smsvVols.Length); $m++)
                    {
                        $check = -not $ncShares[$a].Path.Contains($smsvVols[$m].Name)
                    }

                    if($check)
                    {
                        $newShare = [CIFSShare]::new($ncShares[$a])
                        $newShare.check = $true

                        # 20191009: I want to change this process.  Rather than trying to reduce the number of shares to enumerate by only enumerating the shares that are not nested within other shares,
                        #   I want to enumerate each share and added nested shares to the list of pathsToAvoid of parent shares.
                        #
                        #   Example:
                        #      \\server\share1  =  C:\shares\share1
                        #      \\server\share2  =  c:\shares\share1\HR\Documents.
                        #
                        #   Instead of not enumerating \\server\share2, the script will enumerate both of the shares, and just add c:\shares\share1\HR\Documents to the list of pathsToAvoid
                        #      for \\server\share1.  This will reduce the time to enumerate shares higher up the path while still ensuring paths are only enumerated one.

                        $shareSMSVs = @(@($smsvVols | Where-Object { ($_.JunctionPath.StartsWith($newShare.Path)) -and ($_.VServer -eq $cifsServerConfig.Vserver) }) | Where-Object { @($snapMirrors | Select-Object -ExpandProperty DestinationVolume) -contains $_.Name })

                        # Add paths to avoid during enumeration of files and folders

                        # First skip all the folders that are snapmirror/vault destinations
                        #    The idea is that these folders will be enumerated from the source.

                        # Start with an array of all the snapmirror/snapvault volume JunctionPaths
                        $smsvJunctionPaths = @($shareSMSVs | Select-Object -ExpandProperty JunctionPath)
                        foreach($smsvJunctionPath in $smsvJunctionPaths)
                        {
                            # Construct a partial share path from the JunctionPath
                            $partialSharePath = $smsvJunctionPath.Replace($newShare.Path,"/{0}" -f @($newShare.Name))

                            # Now add the partial path to the list of pathsToAvoid...
                            $newShare.AddPathToAvoid($partialSharePath)
                        }

                        for($c = 0; $c -lt $this.shares.Count; $c++)
                        {
                            # If there are other shares rooted on one of the child folders of this share, add them to the paths to avoid
                            if($this.shares[$c].Path.StartsWith($newShare.Path))
                            {
                                # $this.shares[$c] is rooted on a child folder of $newShare... so add $this.shares[$c] to $newShare's list of paths to avoid...
                                $t = $this.ReplaceFirst($this.shares[$c].Path, $newShare.Path, ("/{0}" -f @($newShare.Name)))

                                $newShare.AddPathToAvoid($t)
                            }
                            else
                            {
                                # Nothing, $this.shares[$c] is NOT rooted on a child folder of $this.shares[$b]...
                            }

                            # If the new share is rooted on a child folder of another share, add the new share path to the list of paths to void on the other share
                            if($newShare.Path.StartsWith($this.shares[$c].Path))
                            {
                                # $this.shares[$c] is rooted on a child folder of $newShare... so add $this.shares[$c] to $newShare's list of paths to avoid...
                                $t = $this.ReplaceFirst($newShare.Path, $this.shares[$c].Path, ("/{0}" -f @($this.shares[$c].Name)))

                                $this.shares[$c].AddPathToAvoid($t)
                            }
                            else
                            {
                                # Nothing, $this.shares[$c] is NOT rooted on a child folder of $this.shares[$b]...
                            }
                        }

                        $this.AddShare($newShare)
                    }
                }
            }
            else
            {
                [Log]::Error("Null CIFS server config in {0}" -f @($MyInvocation.MyCommand))
            }
        }
        else
        {
            # Nothing, shares have already been populated
        }
    }

    hidden [void] PopulateSharesFromNaController()
    {
        if($null -eq $this.shares)
        {
            [NetApp.Ontapi.Filer.NaController] $filer = $this.sourceObject

            $naOptions = @(Get-NAOption -Controller $filer)

            $snapMirrors = @()

            $snapMirrorOption = $naOptions | Where-Object { $_.Name -eq "snapmirror.enable" }
            if(($null -ne $snapMirrorOption) -and ($snapMirrorOption.Value -eq "on"))
            {
                $snapMirrors = @(Get-NaSnapmirror -Controller $filer)
            }
            else
            {
                # Nothing, snapmirror not enabled on the node
            }

            $snapVaults = @()
            $snapVaultOption = $naOptions | Where-Object { $_.Name -eq "snapvault.enable" }
            if(($null -ne $snapVaultOption) -and ($snapVaultOption.Value -eq "on"))
            {
                $snapVaults = @(Get-NaSnapvault -Controller $filer)
            }
            else
            {
                # Nothing, snapvault not enabled on the node
            }

            $naShares = @(Get-NaCifsShare -Controller $filer | Where-Object { $_.MountPoint.StartsWith("/vol/") } | Sort-Object MountPoint)
            for($a = 0; $a -lt $naShares.Length; $a++)
            {
                if($null -eq $this.shares)
                {
                    $this.shares = [System.Collections.Generic.List[CIFSShare]]::new()
                }
                else
                {
                    # Nothing already created the shares list.
                }

                $this.AddShare([CIFSShare]::new($naShares[$a], $this.name))
            }
<#
            Need to update this logical to work like CDOT...avoid nested paths where another share will cover it.
#>
            for($a = 0; $a -lt $this.shares.Count; $a++)
            {
                # Filter out shares that are based on snapmirror destinations.
                $volName = $this.shares[$a].MountPoint.Replace("/vol/","{0}:" -f $filer.Name)
                $volumeSnapmirrors = @($snapMirrors | Where-Object { $_.Destination -eq $volName })
                if($volumeSnapmirrors.Length -eq 0)
                {
                    # Filter out shares for snapvault destinations...
                    $volumeSnapvaults = @($snapVaults | Where-Object { $_.SecondaryPath.StartsWith($this.shares[$a].MountPoint) })
                    if($volumeSnapvaults.Length -eq 0)
                    {
                        for($b = 0; $b -lt $this.shares.Count; $b++)
                        {
                            # Don't compare to myself...
                            if($b -ne $a)
                            {
                                # Is $this.shares[$b] rooted on a child folder of $this.shares[$a]?
                                #    ex: Does "/vol/nonreplicate/cae-apps" start with "/vol/nonreplicate"
                                if($this.shares[$b].MountPoint.StartsWith($this.shares[$a].MountPoint))
                                {
                                    # Yes, $this.shares[$b] is rooted on a child folder of $this.shares[$a], so add a path to avoid
                                    #    to $this.shares[$a] so the folder permission scanner script does not scan a path that another
                                    #    job will scan.

                                    # "/vol/nonreplicate/cae-apps".Replace("/vol/nonreplicate","\\atlprdnas2\g$")
                                    $pathToAvoid = $this.shares[$b].MountPoint.Replace($this.shares[$a].MountPoint, ("\\{0}\{1}" -f @($this.shares[$a].CIFSServer, $this.shares[$a].Name)))

                                    # "\\atlprdnas2\g$/cae-apps".Replace("/","\")
                                    $pathToAvoid = $pathToAvoid.Replace("/", "\")

                                    # Add $pathToAvoid to the
                                    $this.shares[$a].AddPathToAvoid($pathToAvoid)
                                }
                            }
                        }

                        [Log]::Info("Checking \\{0}\{1}   ({2})" -f @($this.name, $this.shares[$a].Name, $this.shares[$a].MountPoint))
                    }
                    else
                    {
                        # Nothing, this share is a snapvault destination
                        $this.shares[$a].check = $false
                        [Log]::Info("Skipping \\{0}\{1}, it is a snapvault destination for:" -f @($this.name, $this.shares[$a].Name))
                        foreach($sv in $volumeSnapvaults)
                        {
                            [Log]::Info("    {0}:{1}" -f @($sv.PrimarySystem ,$sv.PrimaryPath))
                        }
                    }
                }
                else
                {
                    # Nothing, this share is a snapmirror destination
                    $this.shares[$a].check = $false
                    [Log]::Info("Skipping \\{0}\{1}, it is a snapmirror destination for:" -f @($this.name, $this.shares[$a].Name))
                    foreach($sm in $volumeSnapmirrors)
                    {
                        [Log]::Info("    {0}" -f @($sm.Source))
                    }
                }
            }
        }
        else
        {
            # Nothing, shares have already been populated
        }
    }

    [void] PopulateShares()
    {
        if($null -eq $this.shares)
        {
            if($null -ne $this.sourceObject)
            {
                if($this.sourceObject -is [NetApp.Ontapi.Filer.NaController])
                {
                    $this.PopulateSharesFromNaController()
                }
                elseif ($this.sourceObject -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
                {
                    $this.PopulateSharesFromCifsServerConfig()
                }
                else
                {
                    [Log]::Warning("Unable to populate shares from source object of type [{0}]" -f @($this.sourceObject.GetType().FullName))
                }
            }
            else
            {
                [Log]::Warning("Unable to populate shares from null source")
            }
        }
        else
        {
            # Nothing, shares have already been populated.
        }
    }

    [System.Int32] IndexOfShare([CIFSShare] $otherShare)
    {
        [System.Int32] $retval = -1

        for($i = 0; ($retval -eq -1) -and ($i -lt $this.shares.Count); $i++)
        {
            if($this.shares[$i].Eq($otherShare))
            {
                $retval = $i
            }
            else
            {
                # Nothing, keep looking
            }
        }

        return $retval
    }

    [void] AddShare([CIFSShare] $newShare)
    {
        if($null -eq $this.shares)
        {
            $this.shares = [System.Collections.Generic.List[CIFSShare]]::new()
        }
        else
        {
            # Nothing, already created the list.
        }

        if($null -ne $this.shares)
        {
            if($this.IndexOfShare($newShare) -eq -1)
            {
                $this.shares.Add($newShare)
                [Log]::Info("Added share \\{0}\{1}" -f @($this.name, $newShare.Name))
            }
            else
            {
                [Log]::Warning("Attempt to add duplicate share to {0}.  Share [\\{1}\{2}]" -f @($this.name, $newShare.CIFSServer, $newShare.Name))
            }
        }
        else
        {
            [Log]::Error("Shares list not initialized prior to adding share.")
        }
    }

    [String] FixResultPath([String] $resultPath)
    {
        $shareFixed = $false
        $resPath = [String]::Empty

        if(-not [String]::IsNullOrEmpty($resultPath))
        {
            $resPath = $resultPath.ToLower()
            for($s = 0; (-not $shareFixed) -and ($s -lt $this.shares.Count); $s++)
            {
                $sharePath = "\\{0}\{1}" -f $this.shares[$s].CIFSServer.ToLower(), $this.shares[$s].Name.ToLower()
                if($resPath.StartsWith($sharePath))
                {
                    $resPath = $resPath.Replace(("\{0}" -f $this.shares[$s].Name.ToLower()), $this.shares[$s].Path.ToLower().Replace("/","\"))

                    for($z = $s + 1; (-not $shareFixed) -and ($z -lt $this.shares.Count); $z++)
                    {
                        $sharePath = "\\{0}{1}" -f $this.shares[$z].CIFSServer.ToLower(), $this.shares[$z].Path.ToLower().Replace("/","\")
                        if($resPath.StartsWith($sharePath))
                        {
                            $resPath = $resPath.Replace(("{0}" -f $this.shares[$z].Path.ToLower().Replace("/","\")), ("\{0}" -f $this.shares[$z].Name.ToLower()))
                            $shareFixed = $true
                        }
                        else
                        {
                            # Nothing
                        }
                    }
                }
                else
                {
                    # Nothing
                }
            }
        }
        else
        {
            # Nothing, can't fix a result path if a starting point isn't provided.
        }

        if(-not $shareFixed)
        {
            $resPath = $resultPath
        }
        else
        {
            # Nothing, leave the fixed path alone.
        }

        return $resPath.ToLower()
    }

    [Boolean] Eq([NetAppCIFSServer] $other)
    {
        [Boolean] $retval = $false

        if($null -ne $other)
        {
            $retval = ($this.GetType().Equals($other.GetType())) -and ($this.name.Equals($other.name) -and $this.dnsDomainName.Equals($other.dnsDomainName))
        }
        else
        {
            # Nothing... return $false
        }

        return [Boolean] $retval
    }

    NetAppCIFSServer([DataONTAP.C.Types.Cifs.CifsServerConfig] $cifsServerConfig, $populateShares)
    {
        if($null -ne $cifsServerConfig)
        {
            $this.sourceObject = $cifsServerConfig
            $this.name = $cifsServerConfig.CifsServer
            $this.dnsDomainName = $cifsServerConfig.Domain
            $this.PopulateAliases()
            if($populateShares)
            {
                $this.PopulateShares()
            }
            else
            {
                # Nothing, don't populate shares yet.
            }
        }
        else
        {
            [Log]::Error("Null CIFS server config in {0}" -f @($MyInvocation.MyCommand))
        }
    }

    NetAppCIFSServer([NetApp.Ontapi.Filer.NaController] $filer, $populateShares)
    {
        if($null -ne $filer)
        {
            $this.sourceObject = $filer
            $cifsInfo = Get-NACIFS -Controller $filer

            if($null -ne $cifsInfo)
            {
                $this.name = $cifsInfo.NetBIOSServername.Trim().ToLower()
                $this.dnsDomainName = $cifsInfo.DNSDomainname.Trim().ToLower()
                $this.PopulateAliases()
                if($populateShares)
                {
                    $this.PopulateShares()
                }
            }
            else
            {
                [Log]::Error("Unable to get CIFS info for {0} in {1}." -f @($filer.Name, $MyInvocation.MyCommand))
            }
        }
        else
        {
            [Log]::Error("Null filer in {0}" -f @($MyInvocation.MyCommand))
        }
    }
}
