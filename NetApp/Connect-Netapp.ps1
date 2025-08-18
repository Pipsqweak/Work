$Global:promptedCredentials = $null

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

    # Temp variable for the filer connection
    $b = $null

    # Clear the credentials
    $cred = $null
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

            # Since we connect to 7-Mode via RPC, use a dummy credential
            $cred = [System.Management.Automation.PSCredential]::new("a", [SecureString]::new())
        }
        else
        {
            # Nothing, only know of 2 modes: CLUSTER and 7-MODE
        }

        if($null -ne $connector)
        {
            # If we don't have credentials for the connection...
            if($null -eq $cred)
            {
                Write-Host ("Acquiring credentials for {0}..." -f @($name))

                $nccreds = $null
                $cred = $null
                # Get-NcCredential outputs a character to the console, I don't like it, but couldn't figure out how to stop it.
                try
                {
                    $nccreds = Get-NcCredential -Controller $name -ErrorAction Stop
                    $cred = $nccreds.Credential
                }
                catch
                {
                    Write-Host ("No cached credentials for {0}..." -f @($name))
                }
            }
            else
            {
                # Set $nccreds to something so we don't try to cache them again.
                $nccreds = $cred
            }

            # Flag to track if the user cancelled the log in attempt.  Only pertinent if user is prompted for credentials
            $userCancelled = $false

            while((-not $userCancelled) -and ($null -eq $b))
            {
                # No stored credentials for $name, so prompt for them.
                # First try to connect using Global prompted credentials, if available

                # Do we have credentials for the connection attempt?
                if($null -eq $cred)
                {
                    # No.  Do we have prompted credentials?
                    if($null -ne $Global:promptedCredentials)
                    {
                        # Yes, use them...
                        $cred = $Global:promptedCredentials
                    }
                    else
                    {
                        # No, no prompted credentials, so let's ask...
                        $tempCredentials = Get-Credential -Message ("Provide credentials for {0}" -f @($name))

                        # Did the user cancel the prompt?
                        if($null -ne $tempCredentials)
                        {
                            # No, set the prompted credentials, and use them...
                            $Global:promptedCredentials = $tempCredentials
                            $cred = $Global:promptedCredentials
                        }
                        else
                        {
                            # Yes, the user cancelled the prompt for credentials.
                            Write-Host ("User cancelled connection to {0}..." -f @($name))
                            $userCancelled = $true
                        }
                    }
                }
                else
                {
                    # Try to connect using $cred...

                    Write-Host ("Attempting to connect to {0}..." -f @($name))

                    $connectionArgs = @{
                        Name = $Name
                        Credential = $cred
                        Transient = $true
                    }

                    if($mode -eq "7-MODE")
                    {
                        # Use RPC connection
                        $connectionArgs.Add("RPC", $true)
                    }
                    else
                    {
                        # For cluster mode, use HTTPS
                        $connectionArgs.Add("HTTPS", $true)
                    }

                    # Try to connect...
                    $b = & $connector @connectionArgs

                    # If I got connected...
                    if($null -ne $b)
                    {
                        Write-Host ("`tsuccess")

                        # ...and there were no saved credentials for $b, add them.
                        if($null -eq $nccreds)
                        {
                            Write-Host ("`tCaching credentials for {0}" -f @($name))
                            Add-NcCredential -Name $name -Credential $cred | Out-Null
                        }
                        else
                        {
                            # Nothing, no need to add the credentials twice...
                        }
                    }
                    else
                    {
                        Write-Host ("`tfailed")

                        if($null -ne $Global:promptedCredentials)
                        {
                            # if $cred -eq $Global:promptedCredentials then we just tried the prompted credentials...
                            if(($cred.UserName -eq $Global:promptedCredentials.UserName) -and ($cred.GetNetworkCredential().Password -eq $Global:promptedCredentials.GetNetworkCredential().Password))
                            {
                                # ...so clear them too...
                                $Global:promptedCredentials = $null
                            }
                            else
                            {
                                # Nothing, we have not tried the prompted credentials yet.
                            }
                        }

                        # Reset $cred to try again,
                        $cred = $null
                    }
                }
            }
        }
        else
        {
            Write-Host ("Unknown connection mode: {0}:{1}." -f @($name, $mode))
        }
    }
    else
    {
        Write-Host ("No system name specified in call to {0}." -f @($MyInvocation.MyCommand))
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
                    Write-Host ("Missing list of systems to connect to in call to {0}." -f @($MyInvocation.MyCommand))
                }
            }
            else
            {
                # Nothing, already connected to $name
            }
        }
        else
        {
            Write-Host ("Missing dictionary of connected systems in call to {0}." -f @($MyInvocation.MyCommand))
        }
    }
    else
    {
        Write-Host ("No system name specified in call to {0}." -f @($MyInvocation.MyCommand))
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
    $clusters = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()

    if(-not [String]::IsNullOrEmpty($seedCluster))
    {
        # List of clusters we need to connect to
        $clustersToConnectTo = [System.Collections.Generic.List[System.Object]]::new()

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
                Write-Host ("`tGetting list of all peers for {0}..." -f @($b.Name))
                $peers = @(Get-NcClusterPeer -Controller $b)

                # Try to connect to each of the peers...
                for($i = 0; $i -lt $peers.Length; $i++)
                {
                    Write-Host ("`t`tPeer: {0}" -f @($peers[$i].ClusterName))

                    # Make sure the peer is available...
                    if($peers[$i].Availability -in @("available","partial"))
                    {
                        Add-SystemToConnectTo $peers[$i].ClusterName $clustersToConnectTo @($clusters.Keys)
                    }
                    else
                    {
                        Write-Host ("`t`t`tnot available.")
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
        Write-Host ("No seed cluster specified in call to {0}." -f @($MyInvocation.MyCommand))
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

    if($null -ne $Global:smNodes)
    {
        $smNodes = $Global:smNodes
    }
    else
    {
        $smNodes = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]]::new()
    }

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

                # If I'm already connected, don't try again.
                if(-not $smNodes.ContainsKey($nodeName))
                {
                    $node = Connect-NetApp $nodeNames[$a] "7-MODE"

                    if($null -ne $node)
                    {
                        $smNodes.Add($nodeName, $node)
                    }
                    else
                    {
                        Write-Host ("Failed to connect to node: {0}." -f @($nodeName))
                    }
                }
                else
                {
                    Write-Host ("Already connected to node: {0}." -f @($nodeName))
                }
            }
        }
        else # NOT (Test-Path -Path $sysMgrConfigPath)
        {
            Write-Host ("Failed to load System Manager configuration file from {0}." -f @($sysMgrConfigPath))
        }
    }
    else
    {
        Write-Host ("No system manager configuration file specified.")
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
        $Global:cdot = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()
    }
    else
    {
        # Nothing, Dictionary already exists
    }

    if($null -eq $Global:smNodes)
    {
        $Global:smNodes = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.NaController]]::new()
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
                Write-Host ("Unknown NetApp system type: {0}" -f @($nasList[$a].mode))
            }

        }
    }
    else
    {
        Write-Host ("NAS list contains no system names.")
    }
}

<#
    # I think I can get all the nodes via snapmirror/snapvault sources...

    $seedCluster = "BDC-CDOTCLST01"
    $sysMgrConfigPath = "C:\Users\kbriney-adm\NetApp\SystemManager\SystemManager.config"
    $doDebug = $true
    $cdot = Connect-NCAll -seedCluster $seedCluster -maxAttempts 1
    $smNodes = Connect-NAAll -sysMgrConfigPath $sysMgrConfigPath
#>
