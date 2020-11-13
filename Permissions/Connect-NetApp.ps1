function Connect-NetApp
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $name,

        [Parameter(Position=1)]
        [String]
        $mode = "CLUSTER"
    )

    # Temp variable for the cluster connection
    $b = $null

    if(-not [String]::IsNullOrEmpty($name))
    {
        # Dynamically determine which Connect... cmdlet we need to call...
        $connector = $null
        if($mode -eq "CLUSTER")
        {
            $connector = Get-Command -Name "Connect-NCController"
        }
        elseif($mode -eq "7-MODE")
        {
            $connector = Get-Command -Name "Connect-NAController"
        }
        else
        {
            # Nothing, only know of 2 modes: CLUSTER and 7-MODE
        }

        if($null -ne $connector)
        {
            # Get-NcCredential outputs a character to the console, I don't like it, but couldn't figure out how to stop it.
            $nccreds = Get-NcCredential -Name *
            [Log]::Info("Attempting to connect to {0}..." -f @($name))

            # Get the credentials for the system...
            $c = @($nccreds | Where-Object { $_.Name -eq $name })

            # If credentials for the system were found, use them...
            if($c.Length -eq 1)
            {
                $b = & $connector -Name $name -Credential $c[0].Credential -Transient
            }
            elseif($nccreds.Length -gt 0) # No credentials found for the system.  If there are any NC credentials, try to use the first 1.
            {
                $b = & $connector -Name $name -Credential $nccreds[0].Credential -Transient
            }
            else # Hrm... no NC credentials, guess I prompt the user...
            {
                $b = & $connector -Name $name
            }

            # If I got connected...
            if($null -ne $b)
            {
                [Log]::Info("`tsuccess")

                # ...and there were no saved credentials for $b, add them.
                if($c.Length -eq 0)
                {
                    Add-NcCredential -Controller $b | Out-Null
                }
                else
                {
                    # Nothing, no need to add the credentials twice...
                }
            }
            else
            {
                [Log]::Info("`tfailed")
            }
        }
        else
        {
            [Log]::Info("Unknown connection mode: {0}:{1}." -f @($name, $mode))
        }
    }
    else
    {
        [Log]::Info("No system name specified in call to {0}." -f @($MyInvocation.MyCommand))
    }

    return $b
}

function Add-SystemToConnectTo
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $name,

        [Parameter(Mandatory=$true,Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $needToConnectTo,

        [Parameter(Mandatory=$true,Position=2)]
        [AllowEmptyCollection()]
        [System.String[]]
        $connectedSystemNames
    )

    # Temp variable for the new system connection
    $d = $null

    if(-not [String]::IsNullOrEmpty($name))
    {
        if($null -ne $connectedSystemNames)
        {
            # Make sure I'm not already connected to $name...
            if($connectedSystemNames -notcontains $name)
            {
                if($null -ne $needToConnectTo)
                {
                    # Make sure $name is not already in the list of systems I still need to connect to...
                    if(@($needToConnectTo | Where-Object { $_.Name -eq $name }).Length -eq 0)
                    {
                        # Create a new record for the system we need to connect to.
                        $d = "" | Select-Object Name, Attempts
                        $d.Name = $name
                        $d.Attempts = 0

                        $needToConnectTo.Add($d)
                    }
                    else
                    {
                        # Nothing, no need to have $name listed twice...
                    }
                }
                else
                {
                    [Log]::Info("Missing list of systems to connect to in call to {0}." -f @($MyInvocation.MyCommand))
                }
            }
            else
            {
                # Nothing, already connected to $name
            }
        }
        else
        {
            [Log]::Info("Missing dictionary of connected systems in call to {0}." -f @($MyInvocation.MyCommand))
        }
    }
    else
    {
        [Log]::Info("No system name specified in call to {0}." -f @($MyInvocation.MyCommand))
    }
}

# Function to connect to all CDOT clusters discovered via connected peers from a seed cluster name
function Connect-NCAll
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $seedCluster,

        [Parameter(Position=1)]
        [System.Int32]
        $maxAttempts=1
    )

    # Make a dictionary object for the connected clusters
    $clusters = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]'

    if(-not [String]::IsNullOrEmpty($seedCluster))
    {
        # List of clusters we need to connect to
        $clustersToConnectTo = New-Object 'System.Collections.Generic.List[System.Object]'

        # Seed the list of clusters to connect to with $seedCluster
        Add-SystemToConnectTo $seedCluster $clustersToConnectTo @($clusters.Keys)

        # while there are still cluster we need to attempt to connect to...
        while(($needToConnectTo = @($clustersToConnectTo | Where-Object { (-not $clusters.ContainsKey($_.Name)) -and ($_.Attempts -lt $maxAttempts) })).Length -gt 0)
        {
            # Try to connect to the cluster...
            $b = Connect-NetApp $needToConnectTo[0].Name "Cluster"

            # Bump the connect attempts counter for this cluster (NOTE: If the connection succeeds, the cluster will be added to the dictionary and
            #                                                           on the next loop iteration, will not be in the list of clusters that need to be connected to.
            $needToConnectTo[0].Attempts++

            # If we connected to the cluster
            if($null -ne $b)
            {
                # ... add it to $clusters
                $clusters.Add($b.Name, $b)

                # Get all the peers for this cluster...
                [Log]::Info("`tGetting list of all peers for {0}..." -f @($b.Name))
                $peers = @(Get-NcClusterPeer -Controller $b)

                # Try to connect to each of the peers...
                for($i = 0; $i -lt $peers.Length; $i++)
                {
                    [Log]::Info("`t`tPeer: {0}" -f @($peers[$i].ClusterName))

                    # Make sure the peer is available...
                    if($peers[$i].Availability -eq "available")
                    {
                        Add-SystemToConnectTo $peers[$i].ClusterName $clustersToConnectTo @($clusters.Keys)
                    }
                    else
                    {
                        [Log]::Info("`t`t`tnot available.")
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
        [Log]::Info("No seed cluster specified in call to {0}." -f @($MyInvocation.MyCommand))
    }

    return $clusters
}

# Function to connect to all 7-mode filers based on the contents of a System Manager configuration (XML) file...
function Connect-NAAll
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $sysMgrConfigPath
    )

    $smNodes = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]'

    if(-not [String]::IsNullOrEmpty($sysMgrConfigPath))
    {
        if (Test-Path -Path $sysMgrConfigPath)
        {
            # Load the system manager configuration file into an XML object so we can get a list of the nodes.
            $xml = New-Object Xml
            $xml.Load($sysMgrConfigPath)
            $nodeNames = @($xml.'configuration-data'.'managed-storage-systems'.'storage-system' | Select-Object -ExpandProperty system-name)

            # Connect to each of the nodes...
            for($a = 0; $a -lt $nodeNames.Length; $a++)
            {
                $nodeName = $nodeNames[$a]
                if($nodeName -match "^([^\.]+)")
                {
                    $nodeName = $Matches[1]
                }
                $node = Connect-NetApp $nodeNames[$a] "7-MODE"

                if($null -ne $node)
                {
                    if(-not $smNodes.ContainsKey($nodeName))
                    {
                        $smNodes.Add($nodeName, $node)
                    }
                    else
                    {
                        # Nothing, but WTH??  How did the node get added to the dictionary??
                    }
                }
                else
                {
                    [Log]::Info("Failed to connect to node: {0} in call to {1}." -f @($nodeName, $MyInvocation.MyCommand))
                }
            }
        }
        else # NOT (Test-Path -Path $sysMgrConfigPath)
        {
            [Log]::Info("Failed to load System Manager configuration file from {0} in call to {1}." -f @($sysMgrConfigPath, $MyInvocation.MyCommand))
        }
    }
    else
    {
        [Log]::Info("No system manager configuration file specified in call to {0}." -f @($MyInvocation.MyCommand))
    }

    return $smNodes
}

function Connect-NetAppFromList
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [Object[]]
        $nasList
    )

    if($null -eq $Global:cdot)
    {
        $Global:cdot = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]'
    }
    else
    {
        # Nothing, Dictionary already exists
    }

    if($null -eq $Global:smNodes)
    {
        $Global:smNodes = New-Object 'System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]'
    }
    else
    {
        # Nothing, Dictionary already exists
    }

    $dict = @( @{"CLUSTER"=$Global:cdot}, @{"7-MODE"=$Global:smNodes})

    if($nasList.Length -gt 0)
    {
        for($a = 0; $a -lt $nasList.Length; $a++)
        {
            if($dict.Keys -contains $nasList[$a].mode)
            {
                $alreadyConnected = $false
                $dict.Keys | ForEach-Object { $alreadyConnected = ($alreadyConnected -or ($dict.$($_).ContainsKey($nasList[$a].name))) }

                if(-not $alreadyConnected)
                {
                    $c = Connect-NetApp $nasList[$a].name $nasList[$a].mode
                    if($null -ne $c)
                    {
                        $dict.$($nasList[$a].mode).Add($c.Name, $c)
                    }
                    else
                    {
                        # Nothing, Connect-NetApp logged an error
                    }
                }
                else
                {
                    # Nothing, already connected
                }
            }
            else
            {
                [Log]::Warning("Unknown NetApp system type: {0}" -f @($nasList[$a].mode))
            }

        }
    }
    else
    {
        [Log]::Warning("NAS list contains no system names.")
    }
}

<#
    # I think I can get all the nodes via snapmirror/snapvault sources...

    $seedCluster = "BDC-CDOTCLST01"
    $sysMgrConfigPath = "\\ddc-dfm01\c$\Users\kbriney-adm\NetApp\SystemManager\SystemManager.config"
    $doDebug = $true
    $cdot = Connect-NCAll -seedCluster $seedCluster -maxAttempts 1
    $smNodes = Connect-NAAll -sysMgrConfigPath $sysMgrConfigPath
#>
