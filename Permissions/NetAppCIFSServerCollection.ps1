class NetAppCIFSServerCollection
{
    [System.Collections.Generic.List[NetAppCIFSServer]] $naCIFSServers

    [System.Int32] IndexOf([NetAppCIFSServer] $svr)
    {
        [System.Int32] $idx = -1

        if($null -ne $this.naCIFSServers)
        {
            for($a = 0; ($idx -eq -1) -and ($a -lt $this.naCIFSServers.Count); $a++)
            {
                if($this.naCIFSServers[$a].Eq($svr))
                {
                    $idx = $a
                }
                else
                {
                    # Keep looking...
                }
            }
        }
        else
        {
            # Nothing, naCIFSServers is null...
        }

        return $idx
    }

    [void] Add([System.Object] $srcObject, [Boolean] $populateShares)
    {
        if($null -ne $srcObject)
        {
            [NetAppCIFSServer] $cs = $null

            if($srcObject -is [NetApp.Ontapi.Filer.NaController])
            {
                $cs = [NetAppCIFSServer]::new([NetApp.Ontapi.Filer.NaController] $srcObject, $populateShares)
            }
            elseif ($srcObject -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
            {
                $cs = [NetAppCIFSServer]::new([DataONTAP.C.Types.Cifs.CifsServerConfig] $srcObject, $populateShares)
            }
            elseif ($srcObject -is [NetApp.Ontapi.Filer.C.NcController])
            {
                $cluster = [NetApp.Ontapi.Filer.C.NcController] $srcObject
                $cifsServers = @(Get-NcCifsServer -Controller $cluster)

                for($b = 0; $b -lt $cifsServers.Length; $b++)
                {
                    $this.Add($cifsServers[$b], $populateShares)
                }
            }
            elseif($srcObject -is [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]])
            {
                $cDict = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]] $srcObject
                for($a = 0; $a -lt @($cDict.Keys).Length; $a++)
                {
                    $clusterName = @($cDict.Keys)[$a]
                    [Log]::Info("Adding cluster: {0}" -f @($clusterName))
                    $this.Add($cDict[$clusterName], $populateShares)
                }
            }
            elseif($srcObject -is [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]])
            {
                $sNodes = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]] $srcObject
                for($a = 0; $a -lt @($sNodes.Keys).Length; $a++)
                {
                    $nasName = @($sNodes.Keys)[$a]

                    [Log]::Info("Adding filer: {0}" -f @($nasName))
                    $this.Add($sNodes[$nasName], $populateShares)
                }
            }
            else
            {
                [Log]::Error("Unable to create new NetAppCIFSServer object from source type [{0}]" -f @($srcObject.GetType().FullName))
            }

            if($null -ne $cs)
            {
                if($null -eq $this.naCIFSServers)
                {
                    $this.naCIFSServers = [System.Collections.Generic.List[NetAppCIFSServer]]::new()
                }
                else
                {
                    # Nothing, list already created.
                }

                if($this.IndexOf($cs) -eq -1)
                {
                    $this.naCIFSServers.Add($cs)
                    [Log]::Info("Added NetAPPCIFSServer {0}" -f @($cs.name))
                }
                else
                {
                    # Nothing, don't add dupes...
                }
            }
            else
            {
                # Nothing... would have already logged a message...
            }
        }
        else
        {
            [Log]::Warning("Cannot add null source to NetAppCIFSServerCollection")
        }
    }

    [void] PopulateShares()
    {
        if($null -ne $this.naCIFSServers)
        {
            for($a = 0; $a -lt $this.naCIFSServers.Count; $a++)
            {
                if($null -eq $this.naCIFSServers[$a].shares)
                {
                    $this.naCIFSServers[$a].PopulateShares()
                }
                else
                {
                    # Nothing, no need to re-populate the shares...
                }
            }
        }
        else
        {
            # Nothing, don't have any NetAppCIFSServers yet.
        }
    }

    [NetAppCIFSServer] FindNetAppCIFSServerFromPathToCheck([String] $testPath)
    {
        [NetAppCIFSServer] $cifsServer = $null
        $cifsServerIdx = 0
        $shareIdx = 0
        $shareFound = $false

        while((-not $shareFound) -and ($cifsServerIdx -lt $this.naCIFSServers.Count))
        {
            $shareIdx = 0
            while((-not $shareFound) -and ($shareIdx -lt $this.naCIFSServers[$cifsServerIdx].shares.Count))
            {
                $sharePath = "\\{0}\{1}" -f @($this.naCIFSServers[$cifsServerIdx].shares[$shareIdx].CIFSServer, $this.naCIFSServers[$cifsServerIdx].shares[$shareIdx].name)
                if($testPath -eq $sharePath)
                {
                    $shareFound = $true
                }
                else
                {
                    $shareIdx++
                }
            }

            if(-not $shareFound)
            {
                $cifsServerIdx++
            }
            else
            {
                # Nothing, share found
            }
        }

        if($shareFound)
        {
            $cifsServer = $this.naCIFSServers[$cifsServerIdx]
        }
        else
        {
            # Nothing, did not locate a NetAppCIFSServer for the path
        }

        return $cifsServer
    }

    [void] UpdateDB([String] $dbServer, [String] $dbName)
    {
        if($this.naCIFSServers.Count -gt 0)
        {
            if(-not [String]::IsNullOrEmpty($dbServer))
            {
                if(-not [String]::IsNullOrEmpty($dbName))
                {
                    $connectionString = "Data Source={0};Initial Catalog={1};Integrated Security=True" -f @($dbServer, $dbName)
                    # Initialize the connection to the database
                    [DataAccess]::Init($connectionString)

                    for($a = 0; $a -lt $this.naCIFSServers.Count; $a++)
                    {
                        UpdateCIFSData $this.naCIFSServers[$a]
                    }
                }
                else
                {
                    [Log]::Error("Missing database name.")
                }
            }
            else
            {
                [Log]::Error("Missing database server name.")
            }
        }
        else
        {
            [Log]::Warning("Database update not required.  No CIFS server data present.")
        }
    }

    [Object[]] GetSharesToCheck([int] $maxShares=-1)
    {
        if($maxShares -eq -1)
        {
            $maxShares = [int]::MaxValue
        }
        else
        {
            # Nothing, leave $maxShares as is.
        }
        $sharesToCheck = @()
        for($a = 0; ($sharesToCheck.Length -lt $maxShares) -and ($a -lt $this.naCIFSServers.Count); $a++)
        {
            for($b = 0; ($sharesToCheck.Length -lt $maxShares) -and ($b -lt $this.naCIFSServers[$a].shares.Count); $b++)
            {
                if($this.naCIFSServers[$a].shares[$b].check)
                {
                    $s2Check = "" | Select-Object Filer, CIFSShare
                    if($this.naCIFSServers[$a].sourceObject -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
                    {
                        $s2Check.Filer = $this.naCIFSServers[$a].sourceObject.NcController.Name
                    }
                    elseif($this.naCIFSServers[$a].sourceObject -is [NetApp.Ontapi.Filer.NaController])
                    {
                        $s2Check.Filer = $this.naCIFSServers[$a].sourceObject.Name
                    }
                    else
                    {
                        [Log]::Warning("Unknown type of source object for CIFS Server: {0}" -f @($this.naCIFSServers[$a].name))
                    }

                    if(-not [String]::IsNullOrEmpty($s2Check.Filer))
                    {
                        $s2Check.CIFSShare = $this.naCIFSServers[$a].shares[$b]

                        $sharesToCheck += $s2Check
                    }
                    else
                    {
                        # Nothing, already logged a message, so just skip this share.
                    }
                }
                else
                {
                    # Nothing, not checking this share.
                }
            }
        }

        return $sharesToCheck
    }

    NetAppCIFSServerCollection()
    {
    }
}
