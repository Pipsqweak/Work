$gpuModels = [System.Collections.Generic.SortedDictionary[System.String, System.String]]::new()
$gpuModels.Add("Nvidia P40", "nVidia P40")
$gpuModels.Add("nVidia T4 PG183-200", "nVidia T4")
$gpuModels.Add("PG171-200", "nVidia A16")
$gpuModels.Add("UCSB-GPU-P6-R", "nVidia P6")


ConnectTo ucs
$computePlatforms = [System.Collections.Generic.List[System.Object]]::new()

$blades = Get-UcsBlade -Ucs @($ucsManagers.Values)
$blades.ForEach({ $computePlatforms.Add($_) })
$rackMounts = Get-UcsRackUnit -Ucs @($ucsManagers.Values)
$rackMounts.ForEach({ $computePlatforms.Add($_) })
$procs = Get-UcsProcessorUnit -Ucs @($ucsManagers.Values)
$gpus = Get-UcsGraphicsCard -Ucs @($ucsManagers.Values)
$fis = Get-UcsNetworkElement -Ucs @($ucsManagers.Values)
$chassis = Get-UcsChassis -Ucs @($ucsManagers.Values)


$computeNodes = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $computePlatforms.Count)
{
    $d = "" | Select-Object AssetTag, Memory, MemorySpeed, Sockets, CPUModel, CPUSpeed, Cores, Name, Serial, Model, ManufactureDate, GPUModel, GPUCount

    $computeProcs = @($procs | Where-Object { ($_.Ucs -eq $computePlatforms[$a].Ucs) -and ($_.Dn -match $computePlatforms[$a].Dn) })
    $computeGPUs = @($gpus  | Where-Object { ($_.Ucs -eq $computePlatforms[$a].Ucs) -and ($_.Dn -match $computePlatforms[$a].Dn) })
    $d.AssetTag = $computePlatforms[$a].AssetTag
    $d.Memory = $computePlatforms[$a].TotalMemory
    $d.MemorySpeed = $computePlatforms[$a].MemorySpeed
    $d.Sockets = $computePlatforms[$a].NumOfCpus
    $d.CPUModel = $computeProcs | Select-Object -Unique -ExpandProperty Model | Select-Object -First 1
    $d.CPUSpeed = $computeProcs | Select-Object -Unique -ExpandProperty Speed | Select-Object -First 1
    $d.Cores = $computePlatforms[$a].NumOfCores
    $d.Name = $computePlatforms[$a].Name
    $d.Serial = $computePlatforms[$a].Serial
    $d.Model = $computePlatforms[$a].Model
    $d.ManufactureDate = @($computePlatforms[$a].MfgTime -split "T")[0]
    $d.GPUModel = $computeGPUs | Select-Object -Unique -ExpandProperty Model | Select-Object -First 1
    $d.GPUCount = $computeGPUs.Length
    if((-not [String]::IsNullOrEmpty($d.GPUModel)) -and ($gpuModels.ContainsKey($d.GPUModel)))
    {
        $d.GPUModel = $gpuModels[$d.GPUModel]
    }
    $computeNodes.Add($d)
    $a++
}

$fabricInterconnects = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $fis.Length)
{
    $d = "" | Select-Object Model, UCS, Name, Serial, InstallDate
    $d.Model = $fis[$a].Model
    $d.UCS = $fis[$a].Ucs
    $d.Name = $fis[$a].OobIfIp
    $d.Serial = $fis[$a].Serial
    $d.InstallDate = ""

    $fabricInterconnects.Add($d)
    $a++
}

$fabricInterconnects | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard


# Get NetApp Data...

Write-Host ("Collecting NetApp Cluster mode data..")

# Where we collect all EVDataPoints not already in $intersightData or $xClarityData
$cdotData = @()

$cdotControllers = @($cdot.Values)
$a = 0
while($a -lt $cdotControllers.Length)
{
    <#
        There are multiple CIs for NetApp clusters.
            The cluster itself: i.e. CDC-CDOTCLST01
            each node: CDC-NASA01, CDC-NASA02, etc...
            each disk shelf...
            each intercluster switch...
    #>

    $cdotController = $cdotControllers[$a]


    Write-Host ("Processing {0}..." -f @($cdotController.Name))
    $clusterMgmtLIFS = @(Get-NCNetInterface -Controller $cdotController | Where-Object { $_.FirewallPolicy -eq "mgmt" })

    # CI for Cluster
    $cluster = Get-NCCluster -Controller $cdotController

    # Create an EVDataPoint for the cluster
    $clusterDP = [EVDataPoint]::new()
    $clusterDP.SetName($cdotController.Name)
    $clusterDP.SetManufacturer("NetApp")
    $clusterDP.SetOperatingSystem("DataONTAP")
    $clusterDP.SetModel("VSERVER")

    $clusterDP.SetSerialNumber($cluster.ClusterSerialNumber)

    $mgmtLIFs = @($clusterMgmtLIFS | Where-Object { ($_.Role -eq "cluster_mgmt") })
    if($mgmtLIFs.Length -gt 0)
    {
        $clusterDP.SetIP($mgmtLIFs[0].Address)
    }

    Write-Host ("`t+Cluster: {0}, {1}, {2}" -f @($clusterDP.Name, $clusterDP.Model, $clusterDP.SerialNumber))
    $cdotData  += $clusterDP

    # CIs for Nodes

    $clusterNodes = @(Get-NCNode -Controller $cdotController)
    $clusterImages = @(Get-NCClusterImage -Controller $cdotController)

    $b = 0
    while($b -lt $clusterNodes.Length)
    {
        $cn = $clusterNodes[$b]

        $d = [EVDataPoint]::new()

        $d.SetName($cn.Node)
        $d.SetSerialNumber($cn.NodeSerialNumber)
        $d.SetOperatingSystem("DataONTAP")
        $d.SetManufacturer($cn.NodeVendor)
        $d.SetModel($cn.NodeModel)
        $ncImage = @($clusterImages | Where-Object { $_.NodeId -eq $cn.Node })
        if($ncImage.Length -gt 0)
        {
            $d.SetCurrentVersion($ncImage[0].CurrentVersion)

            # Set the cluster CurrentVersion if it is not set.
            if([String]::IsNullOrEmpty($clusterDP.CurrentVersion))
            {
                $clusterDP.SetCurrentVersion($ncImage[0].CurrentVersion)
            }
        }

        $nodeMgmtLIFs = @($clusterMgmtLIFS | Where-Object { ($_.Role -eq "node_mgmt") -and ($_.CurrentNode -eq $cn.Node) })
        if($nodeMgmtLIFs.Length -gt 0)
        {
            $d.SetIP($nodeMgmtLIFs[0].Address)
        }

        Write-Host ("`t+Node: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
        $cdotData += $d

        $b++
    }

    # CIs for Cluster Switches

    Write-Host "`tChecking for intercluster switches..."
    $clusterSwitches = @(Get-NCClusterSwitch -Controller $cdotController)

    $b = 0
    while($b -lt $clusterSwitches.Length)
    {
        $d = [EVDataPoint]::new($clusterSwitches[$b])

        Write-Host ("`t+Switch: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
        $cdotData += $d

        $b++
    }

    # CIs for storage shelves...

    # Get a master list of all shelves in the cluster.
    $storageShelves = @(Get-NcStorageShelf -Controller $cdotController)

    # Enumerate each node in the cluster, inventorying each node's shelves.
    $n = 0
    while($n -lt $clusterNodes.Length)
    {
        # Get the shelves attached to this node.
        #   Have to do this, because the data in the master shelf list does not have the firmware information.
        $nodeShelves = @(Get-NCShelf -Controller $cdotController -NodeName $clusterNodes[$n].Node)

        # For each of the node's shelves, match each one to a shelf in the master list and build a new [EVDataPoint] for it.
        $s = 0
        while($s -lt $nodeShelves.Length)
        {
            $storageShelf = $storageShelves | Where-Object { $_.ShelfUid -eq $nodeShelves[$s].ShelfUid }
            if($null -ne $storageShelf)
            {
                # Check to see if we have already inventoried this shelf.  Remember, each shelf *should* be connected to
                #   2 nodes
                if(@($cdotData | Where-Object { $_.SerialNumber -eq $storageShelf.SerialNumber }).Length -eq 0)
                {
                    $d = [EVDataPoint]::new()

                    # Added .StackId to the shelf name to make it unique when multiple shelves in a cluster have the same shelf ID
                    $d.SetName("{0}.SHELF.{1}.{2}" -f @($clusterDP.Name, $storageShelf.StackId, $storageShelf.ShelfId))
                    $d.SetSerialNumber($storageShelf.SerialNumber)
                    $d.SetOperatingSystem("N/A")
                    $d.SetManufacturer($storageShelf.VendorName)
                    $d.SetModel($storageShelf.ShelfModel.ToUpper())
                    $d.SetCurrentVersion($nodeShelves[$s].FirmwareRevA)

                    # Since a shelf does not have an IP address, we'll set the shelf location to the same as the cluster.
                    $d.SetLocation($clusterDP.Location)

                    Write-Host ("`t+Shelf: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
                    $cdotData += $d
                }
                else
                {
                    # Nothing, already inventoried this shelf.
                }
            }
            else
            {
                Write-Host -ForegroundColor Yellow ("Unable to locate shelf with UID: {0} in master storage shelf list for {1}." -f @($nodeShelves[$s].ShelfUid, $cdotController.Name))
            }

            $s++
        }

        $n++
    }

    $a++
}



class EVDataPoint
{
    [String] $Name = [String]::Empty
    [String] $IP = [String]::Empty
    [String] $SerialNumber = [String]::Empty
    [String] $CurrentVersion = [String]::Empty
    [String] $OperatingSystem = [String]::Empty
    [String] $Manufacturer = [String]::Empty
    [String] $Model = [String]::Empty
    [String] $Location = [String]::Empty

    EVDataPoint() { }

    # Initialize an [EVDataPoint] from an intercluter switch
    EVDataPoint([DataONTAP.C.Types.ClusterSwitch.ClusterSwitchInfo] $icsw)
    {
        $this.SetName($icsw.Device.ToUpper())
        $this.SetCurrentVersion($icsw.SwVersion)
        $this.SetIP($icsw.Address)
        $this.SetSerialNumber($icsw.SerialNumber)
        $this.SetManufacturer("NetApp")
        $this.SetModel($icsw.Model.ToUpper())
        $this.SetOperatingSystem("FASTPATH")
    }

    # Initialize an [EVDataPoint] from a VirtualMachine
    EVDataPoint([VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] $vm)
    {
        $this.SetName($vm.Name)

        if($vm.Version -match "^v(\d+)")
        {
            $this.SetCurrentVersion($Matches[1])
        }
        if (($null -ne $vm.Guest) -and (-not [String]::IsNullOrEmpty($vm.Guest.OSFullName)))
        {
            $this.SetOperatingSystem($vm.Guest.OSFullName)
        } `
        else # NOT (($null -ne $vm.ExtensionData.Guest) -and (-not [String]::IsNullOrEmpty($vm.ExtensionData.Guest.GuessFullName)))
        {
            $this.SetOperatingSystem($vm.GuestId)
        }

        if ([String]::IsNullOrEmpty($vm.ExtensionData.Guest.IpAddress))
        {
            $this.SetIP($vm.ExtensionData.Guest.IpAddress)
        } `
        else # NOT ([String]::IsNullOrEmpty($vm.ExtensionData.Guest.IpAddress))
        {
            # Nothing.
        }
        $this.SetSerialNumber($vm.BIOSNumber)
        $this.SetManufacturer("VMWare, Inc.")
        $this.SetModel("VMware Virtual Platform")
        $this.UpdateFromIPAMByName()
    }

    [void] SetManufacturer([String] $manufacturer)
    {
        $this.Manufacturer = $manufacturer
        if(-not [String]::IsNullOrEmpty($this.Manufacturer))
        {
            $this.Manufacturer = $this.Manufacturer.Trim().Replace("(WIST)","").Replace(" Inc","").Trim(@('.',',',' '))

            # Make sure the Manufacturer name "NetApp" is always spell "NetApp"
            if($this.Manufacturer -eq "NETAPP")    # Remember, in PS, string equality testing is case-insensitive unless we use -ceq
            {
                $this.Manufacturer = "NetApp"      # Now, ensure it's always capital N, lower et, capital A, lower pp...
            }
        }
    }

    [void] SetName($name)
    {
        $this.Name = $name
        if(-not [String]::IsNullOrEmpty($this.Name))
        {
            $this.Name = $this.Name.ToUpper().Replace(".POWERENG.COM","")

            if($this.Name.EndsWith("-RSM"))
            {
                $this.Name = $this.Name.Replace("-RSM","")
            }
        }
    }

    [void] SetIP($ip)
    {
        $this.IP = $ip
        $isIP = $true
        if(-not [String]::IsNullOrEmpty($this.IP))
        {
            if($this.IP -match "^\d+\.\d+\.\d+\.\d+$")
            {
                $octets = $this.IP -split "\."
                $o = 0
                while($isIP -and ($o -lt $octets.Length))
                {
                    try
                    {
                        [int] $ov = [int] $octets[$o]
                        $isIP = ($ov -ge 0) -and ($ov -le 255)
                    }
                    catch
                    {
                        $isIP = $false
                    }
                    $o++
                }
            }
            else
            {
                $isIP = $false
            }
        }
        else
        {
            $isIP = $false
        }
    }

    [void] SetOperatingSystem($os)
    {
        $this.OperatingSystem = $os
        if(-not [String]::IsNullOrEmpty($this.OperatingSystem))
        {
            if($this.OperatingSystem -match "NetApp Release ([^:]+)")
            {
                # Change $this.OperatingSystem to just the portion we want.
                $this.OperatingSystem = $Matches[1]
            }
            else
            {
                # Nothing, not a NetApp OS...
            }
        }
    }

    [void] SetCurrentVersion($cv)
    {
        $this.CurrentVersion = $cv

        # Some CurrentVersions like to append a date string on the end.  Filter it off here...
        #   ex: FBKTD1AUS [6/21/2018 12:00:00 AM]
        if($this.CurrentVersion -match "^([^\]]+)\s+\[[0-9/\s:APM]+]")
        {
            $this.CurrentVersion = $Matches[1]
        }

        # CurrentVersion field in EV is limited to 50 characters, so let's make sure it's 50 or less characters long.
        if ((-not [String]::IsNullOrEmpty($this.CurrentVersion) -and ($this.CurrentVersion.Length -gt 50)))
        {
            # TRUE

            # Sorry, we can only use the first 50 characters...
            $this.CurrentVersion = $this.CurrentVersion.Substring(0, 50)
        }
        else # NOT ((-not [String]::IsNullOrEmpty($this.CurrentVersion) -and ($this.CurrentVersion.Length -gt 50)))
        {
            # FALSE

            # Nothing.
        }
    }

    [void] SetSerialNumber($sn)
    {
        # As of now, nothing special for serial number
        $this.SerialNumber = $sn
    }

    [void] SetModel($mod)
    {
        # As of now, nothing special for model
        $this.Model = $mod
    }

    [void] SetLocation($loc)
    {
        # As of now, nothing special for Location
        $this.Location = $loc
    }

    [void] FixUp()
    {
        <#
            Sometimes data is not exactly correct.  This function is intended to be a last ditch effort to
            reformat, substitute, replace, etc any data that needs to be massaged.

            This function should be called for each defined [EVDataPoint] prior to exporting the data for use with EV.

            Since classes in PowerShell, at least as of now, do not support the idea of property setters and I can't
            guarantee properties aren't set directly, I'll call each of my faux setters here to make sure things are
            formatted/parsed right.
        #>

        # Fix up Name
        $this.SetName($this.Name)

        # Fix up Serial Number
        $this.SetSerialNumber($this.SerialNumber)

        # Fix up Model
        $this.SetModel($this.Model)

        # Fix up Current Version
        $this.SetCurrentVersion($this.CurrentVersion)

        # Fix up the Manufacturer
        $this.SetManufacturer($this.Manufacturer)

        # Fix up the Operating System
        $this.SetOperatingSystem($this.OperatingSystem)

        # Fix up IP
        $this.SetIP($this.IP)

        # Fix up Location
        $this.SetLocation($this.Location)
    }
}
