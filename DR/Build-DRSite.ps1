# Script to build DR rehydration script...

# Assumptions:
#    $vcPrd = Connect-VIServer -Server [PRODUCTION_VCENTER]
#    $vcDr = Connect-VIServer -Server [DR_VCENTER]
#    $cdot01 = Connect-NCServer -Server [PRODUCTION_CLUSTER]
#    $cdot02 = Connect-NCServer -Server [DR_CLUSTER]

$cdot01 = $labCDOT
$cdot02 = $ddcCDOT

# Notes: Need to modify mirror location to be secondary mirror aware.
#    This might need to be an option.  Think DR "Test" vs real DR.

$prodSVMName = "LAB-NFS01"
$drSVMName = "LABDR-NFS01"

$prodDatacenter = "Lab"
$drDatacenter = "DDC"

$drVMDistributedSwitchBaseName = "dsVirtualMachines"

$useSIMSwitch = $true

$nfsVLAN = 11

# Need to:
#    Determine snapmirrors to break
#    Volumes to mount to DR
#    Mount volume to DR
#    Determine VMs part of DR volumes
#    Determine Network to Network mappings (VM Network)
#

# Display usage information.
function Usage($whichFunction)
{
    if(![String]::IsNullOrEmpty($whichFunction) -and ($whichFunction.ToUpper() -in @("CREATEDRMAP", "DODR")))
    {
        Write-Host "Prior to performing $($whichFunction.ToUpper()), the following variables must be set:"

        # Check for variables used only during creation of the DR data map
        if($whichFunction.ToUpper() -eq "CREATEDRMAP")
        {
            Write-Host "`t`$cdot01 must be a connection to the production NetApp Cluster."
            Write-Host "`t`$vcPrd must be a connection to the production vSphere."
            Write-Host "`t`$prodSVMName must be set to the name of the production NetApp Cluster Storage Virtual Machine (SVM)."
            Write-Host "`t`$prodDatacenter must be set to the name of the production vSphere datacenter containing DR VMs."
            Write-Host "`t`$nfsVLAN must be set to the VLAN ID used to identify which network address on the DR NetApp Cluster SVM is used for NFS exports."
        }
        Write-Host "`t`$cdot02 must be a connection to the DR NetApp Cluster."
        Write-Host "`t`$vcDR must be a connection to the DR vSphere."
        Write-Host "`t`$drSVMName must be set to the name of the DR NetApp Cluster Storage Virtual Machine (SVM)."
        Write-Host "`t`$drDatacenter must be set to the name of the DR vSphere datacenter where DR VMs will be rehydrated."
        Write-Host "`t`$drVMDistributedSwitchName must be set to the name of a distributed switch in DR where DR VMs will be connected."
    }
    else
    {
        Write-Host "Unable to determine script function from [$whichFunction]."
    }
}

function HaveGlobals($whichFunction)
{
    if(![String]::IsNullOrEmpty($whichFunction) -and ($whichFunction.ToUpper() -in @("CREATEDRMAP", "DODR")))
    {
        # Check for variables used only during creation of the DR data map
        if($whichFunction.ToUpper() -eq "CREATEDRMAP")
        {
            if($null -eq $cdot01)
            {
                Write-Host "Not connected to production NetApp Cluster via `$cdot01."
                return $false
            }

            if($cdot01 -isnot [NetApp.Ontapi.Filer.C.NcController])
            {
                Write-Host "`$cdot01 is not an instance of [NetApp.Ontapi.Filer.C.NcController]."
                return $false
            }

            if([String]::IsNullOrEmpty($prodSVMName))
            {
                Write-Host "Missing production SVM name via `$prodSVMName."
                return $false
            }

            if([String]::IsNullOrEmpty($nfsVLAN))
            {
                Write-Host "Missing NFS VLAN identifier via `$nfsVLAN."
                return $false
            }

            $prodSVM = Get-NcVserver -Controller $cdot01 -Name $prodSVMName
            if($null -eq $prodSVM)
            {
                Write-Host "Unable to connect to production SVM named: $($prodSVMName)."
                return $false
            }

            if($null -eq $vcPrd)
            {
                Write-Host "Not connected to production vSphere via `$vcPrd!"
                return $false
            }

            if([String]::IsNullOrEmpty($prodDatacenter))
            {
                Write-Host "Missing production vSphere datacenter name via `$prodDatacenter."
                return $false
            }
        }

        # Check for required variables used in either function.
        if($null -eq $cdot02)
        {
            Write-Host "Not connected to DR NetApp Cluster via `$cdot02."
            return $false
        }

        if($cdot02 -isnot [NetApp.Ontapi.Filer.C.NcController])
        {
            Write-Host "`$cdot02 is not an instance of [NetApp.Ontapi.Filer.C.NcController]."
            return $false
        }

        if($null -eq $vcDR)
        {
            Write-Host "Not connected to DR vSphere via `$vcDR!"
            return $false
        }

        if([String]::IsNullOrEmpty($drSVMName))
        {
            Write-Host "Missing DR SVM name via `$drSVMName."
            return $false
        }

        $drSVM = Get-NcVserver -Controller $cdot02 -Name $drSVMName
        if($null -eq $drSVM)
        {
            Write-Host "Unable to connect to DR SVM named: $($drSVMName)."
            return $false
        }

        if([String]::IsNullOrEmpty($drVMDistributedSwitchName))
        {
            Write-Host "Missing DR distributed switch name via `$drVMDistributedSwitchName."
            return $false
        }
    }
    else
    {
        Write-Host "Unable to determine script function from [$($whichFunction)]."
        return $false
    }

    return $true
}

function CheckForOneAndOnlyOne($arrToCheck, $objName, $msgTooMany, $msgNone)
{
    $justOne = $false

    if($arrToCheck -is [Array])
    {
        if($arrToCheck.Length -eq 1)
        {
            $justOne = $true
        }
        elseif($arrToCheck.Length -eq 0)
        {
            if(![String]::IsNullOrEmpty($msgNone))
            {
                Write-Host "$($msgNone)"
            }
        }
        else
        {
            if(![String]::IsNullOrEmpty($msgTooMany))
            {
                Write-Host "$($msgTooMany)"
            }
        }
    }
    else
    {
        Write-Host "`$$($objName) sent to CheckForOneAndOnlyOne is not an array!"
    }

    return $justOne
}

function MakeVMFolderPath($vm)
{
    # Create a generic list to hold each of the VMs parent folders
    $folderList = New-Object 'System.Collections.Generic.List[System.Object]'

    # Add each of the parent folders to the list, starting with the VM's direct folder
    $vmFolder = $vm.Folder
    while($vmFolder.Name -ne "vm")
    {
        $folderList.Add($vmFolder)
        $vmFolder = $vmFolder.Parent
    }

    # Reverse the list so we check them in the order of existance (or non-existance)
    $folderList.Reverse()

    $folderPath = @($folderList | Select-Object -ExpandProperty Name) -join "\"

    return $folderPath
}

function GetDRPortGroups()
{
    # The DR virtual machine distributed switch
    $drVMDistributedSwitch = $null

    # Array of all DR Virtual Machine distributed port groups
    $drPortGroups = @()

    if(![String]::IsNullOrEmpty($drVMDistributedSwitchName))
    {
        # Get the DR virtual machine distributed switch
        Write-Host "Loading distributed switch $($vcDR.Name):\\$($drDatacenter)\$($drVMDistributedSwitchName)..."
        $drVMDistributedSwitch = Get-VDSwitch -Server $vcDr -Name $drVMDistributedSwitchName

        if($null -ne $drVMDistributedSwitch)
        {
            # Get an array of all DR Virtual Machine distributed port groups
            Write-Host "Loading all distributed port groups from $($vcDR.Name):\\$($drDatacenter)\$($drVMDistributedSwitch.Name)..."
            $drPortGroups = @(Get-VDPortgroup -VDSwitch $drVMDistributedSwitch)
        }
        else
        {
            Write-Host "ERROR: Failed to retrieve DR distributed switch named: $($drVMDistributedSwitchName)."
        }
    }
    else
    {
        Write-Host "ERROR: DR virtual machine distributed switch name not provided."
    }

    return $drPortGroups
}

function CreateDRMapFromProduction()
{
    # Build a hashtable array for the following:
    #   production datastore
    #   production VMs
    #   production storage volume
    #   DR storage volume

    # Array of all production datastores
    $prodDatastores = $null

    # Array of all the NetApp Volumes on the production SVM
    $prodVolumes = $null

    # Array of all DR Cluster's aggregates
    $drAggregates = $null

    # Array of all DR Cluster's disks
    $drDisks = $null

    # Array of all the NetApp Volumes on the DR SVM
    $drVolumes = $null

    # Array of all the DR Cluster's network ports
    $drNetPorts = $null

    # Array of all the DR SVM's network interfaces
    $drInterfaces = $null

    # Array of all export policies on the DR SVM
    $drExportPolicies = $null

    # Array of all the NetApp SnapMirrors from the DR SVM that have source vServer = $prodSVMName
    $drSnapMirrors = $null

    # Array of all the production virtual machines
    $prodVMs = $null

    # The DR virtual machine distributed switch
    $drVMDistributedSwitch = $null

    # Array of all DR Virtual Machine distributed port groups
    $drPortGroups = $null

    # Flag to track if all data is loaded correctly.  Until all data is loaded, assume we are missing information.
    $haveRequiredData = $false

    # Get an array of all production datastores
    Write-Host "Loading all NFS datastores from $($vcPrd.Name)\$($prodDatacenter)..."
    if(($prodDatastores = @(Get-Datastore -Location $prodDatacenter -Server $vcPrd | Where-Object { $_.Type -eq "NFS" })).Length -gt 0)
    {
        # Get an array of all the NetApp Volumes on the production SVM
        Write-Host "Loading all volumes from $($cdot01.Name)://$($prodSVMName)..."
        if(($prodVolumes = @(Get-NcVol -Controller $cdot01 -Vserver $prodSVMName)).Length -gt 0)
        {
            # Get an array of all export policies on the DR SVM
            Write-Host "Loading all export policies from $($cdot02.Name)://$($drSVMName)..."
            if(($drExportPolicies = @(Get-NcExportPolicy -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
            {
                # Get an array of all the NetApp SnapMirrors from the DR SVM that have source vServer = $prodSVMName
                Write-Host "Loading all snapmirrors from $($cdot02.Name)://$($drSVMName) having $($prodSVMName) as a source SVM..."
                if(($drSnapMirrors = @(Get-NcSnapmirror -Controller $cdot02 | Where-Object { ($_.SourceVserver -eq $prodSVMName) -and ($_.DestinationVserver -eq $drSVMName) })).Length -gt 0)
                {
                    # Get an array of all the production virtual machines
                    Write-Host "Loading all VMs from $($vcPrd.Name)\$($prodDatacenter)..."
                    if(($prodVMs = @(Get-VM -Location $prodDatacenter -Server $vcPrd)).Length -gt 0)
                    {
                        # Get an array of all DR Virtual Machine distributed port groups
                        if(($drPortGroups = GetDRPortGroups).Length -gt 0)
                        {
                            # Get an array of all the NetApp Volumes on the DR SVM
                            Write-Host "Loading all volumes from $($cdot02.Name)://$($drSVMName)..."
                            if(($drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
                            {
                                # Get an array of all DR Cluster's aggregates
                                Write-Host "Loading all aggregates from $($cdot02.Name)..."
                                if(($drAggregates = @(Get-NCAggr -Controller $cdot02)).Length -gt 0)
                                {
                                    # Get an array of all DR Cluster's disks
                                    Write-Host "Loading all disk drives from $($cdot02.Name)..."
                                    if(($drDisks = @(Get-NCDisk -Controller $cdot02)).Length -gt 0)
                                    {
                                        # Get an array of all the DR Cluster's network ports
                                        Write-Host "Loading all network ports from $($cdot02.Name)..."
                                        if(($drNetPorts = @(Get-NcNetPort -Controller $cdot02)).Length -gt 0)
                                        {
                                            # Get an array of all the DR SVM's network interfaces
                                            Write-Host "Loading all network interfaces from $($cdot02.Name)://$($drSVMName)..."
                                            if(($drInterfaces = @(Get-NcNetInterface -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
                                            {
                                                $haveRequiredData = $true
                                            }
                                            else
                                            {
                                                Write-Host "`tNo network interfaces located on $($cdot02.Name)://$($drSVMName)..."
                                            }
                                        }
                                        else
                                        {
                                            Write-Host "`tNo network ports located on $($cdot02.Name)..."
                                        }
                                    }
                                    else
                                    {
                                        Write-Host "`tNo disks located on $($cdot02.Name)..."
                                    }
                                }
                                else
                                {
                                    Write-Host "`tNo aggregates located on $($cdot02.Name)..."
                                }
                            }
                            else
                            {
                                Write-Host "`tNo volumes located on $($cdot02.Name)://$($drSVMName)..."
                            }
                        }
                        else
                        {
                            Write-Host "ERROR: Failed to get a list of all DR VM port groups."
                        }
                    }
                    else
                    {
                        Write-Host "`tNo virtual machine located on $($vcPrd.Name)."
                    }
                }
                else
                {
                    Write-Host "`tNo snapmirrors found on $($cdot02.Name)://$($drSVMName) having $($prodSVMName) as a source SVM."
                }
            }
            else
            {
                Write-Host "`tNo export policies loaded from $($cdot01.Name)://$($prodSVMName)..."
            }
        }
        else
        {
            Write-Host "`tNo volumes located on $($cdot01.Name)://$($prodSVMName)..."
        }
    }
    else
    {
        Write-Host "`tNo production datastores found on $($vcPrd.Name)."
    }

    #
    #
    #    Reorganize the following code ....
    #
    #
    #


    $drMap = @(
        if($haveRequiredData)
        {
            Write-Host "`r`nBuilding DR data map..."
            foreach($ds in $prodDatastores)
            {
                if($null -ne $ds)
                {
                    Write-Host "`r`nProcessing data store: $($vcPrd)\$($prodDatacenter)\$($ds.Name)"
                    $prodVol = @($prodVolumes | Where-Object { ![String]::IsNullOrEmpty($_.JunctionPath) -and ($ds.RemotePath -eq $_.JunctionPath) })
                    if(CheckForOneAndOnlyOne $prodVol "prodVol" "`tERROR: Too many production volumes found for datastore: $($ds.Name)!" "`tERROR: No production volumes found for datastore: $($ds.Name)!")
                    {
                        $prodVol = $prodVol[0]

                        Write-Host "`tproduction NetApp volume: $($cdot01.Name):\\$($prodSVMName)\$($prodVol.Name)..."

                        $snapmirror = @($drSnapMirrors | Where-Object { $_.SourceVolume -eq $prodVol.Name })
                        if(CheckForOneAndOnlyOne $snapmirror "snapmirror" "`tERROR: Too many snapmirrors found for production volume: $($prodVol.Name) on $($drSVMName)" "`tINFO: Skipping, no snapmirror on $($cdot02.Name):\\$($drSVMName) for $($cdot01.Name):\\$($prodSVMName)\$($prodVol.Name)" )
                        {
                            $snapmirror = $snapmirror[0]

                            Write-Host "`tsnapmirror destination: $($cdot02.Name):\\$($drSVMName)\$($snapmirror.DestinationVolume)..."
                            # Make sure there is an export policy on the DR SVM that matches the production volume's export policy...
                            $drExportPolicy = @($drExportPolicies | Where-Object { $_.PolicyName -eq $prodVol.VolumeExportAttributes.Policy })
                            if(CheckForOneAndOnlyOne $drExportPolicy "drExportPolicy" "ERROR: Too many export policies set for $($prodVol.Name) on $($drSVMName)" "`tERROR: Missing export policy: $($prodVol.VolumeExportAttributes.Policy) on $($drSVMName)!")
                            {
                                $drExportPolicy = $drExportPolicy[0]

                                Write-Host "`texport policy $($drExportPolicy.PolicyName)..."
                                $drVol = @($drVolumes | Where-Object { $_.Name -eq $snapmirror.DestinationVolume })
                                if(CheckForOneAndOnlyOne $drVol "drVol" "`tERROR: Too many DR volumes found for DR snapmirror destination volume: $($snapmirror.DestinationVolume)!" "`tERROR: Unable to find DR volume for snapmirror destination volume: $($snapmirror.DestinationVolume)!" )
                                {
                                    $drVol = $drVol[0]
                                    Write-Host "`tdestination volume confirmed..."

                                    # Find the DR aggregate object the DR volume is on.
                                    $aggr = @($drAggregates | Where-Object { $_.Name -eq $drVol.Aggregate })
                                    if(CheckForOneAndOnlyOne $aggr "aggr" "Too many aggregrate located for DR volume: $($drVol.Name)!" "No DR aggregate found for DR volume: $($drVol.Name)!")
                                    {
                                        $aggr = $aggr[0]

                                        Write-Host "`tDR aggregate: $($aggr.Name)..."

                                        # Get a list of the disks used in the DR aggregate so we can determine the volume type.
                                        $aggrDisks = @($drDisks | Where-Object { $_.DiskRaidInfo.DiskAggregateInfo.AggregateName -eq $aggr.Name })
                                        if($aggrDisks.Length -gt 0)
                                        {
                                            Write-Host "`t`tconsists of $($aggrDisks.Length) drives..."
                                            $volType = @($aggrDisks | Select-Object -Unique @{N="DiskType";E={$_.DiskRaidInfo.EffectiveDiskType}} | Select-Object -ExpandProperty DiskType)
                                            if(CheckForOneAndOnlyOne $volType "volType" "`tERROR: Too many volume types found for DR aggregate: $($aggr.Name)!" "`tERROR: Unable to determine volume type for DR aggregate: $($aggr.Name)!")
                                            {
                                                $volType = $volType[0]

                                                Write-Host "`t`taggregate type: $($volType)..."

                                                # Get a list of the network ports on the node associated with the NFS VLAN
                                                $netPorts = @($drNetPorts | Where-Object { ($_.Node -eq $aggr.AggrOwnershipAttributes.HomeName) -and ($_.VlanIdSpecified) -and ($_.VlanId -eq $nfsVLAN) })
                                                if($netPorts.Length -gt 0)
                                                {
                                                    foreach($np in $netPorts)
                                                    {
                                                        Write-Host "`tchecking network port $($aggr.AggrOwnershipAttributes.HomeName):$($np.Port) for NFS data protocol..."

                                                        # Get a list of DR SVM network interfaces associated with this network port on $node configured for data protocol NFS...
                                                        $portInterface = @($drInterfaces | Where-Object { $_.HomePort -eq $np.Port -and $_.HomeNode -eq $np.Node -and $_.DataProtocols.Contains("nfs") <# -and $_.InterfaceName.EndsWith("$($aggr.AggrOwnershipAttributes.HomeName.ToLower())_01") #> })
                                                        if(CheckForOneAndOnlyOne $portInterface "portInterface" "Too many network interfaces found for $($np.Node)/$($np.Port)!" "No network interfaces found for $($np.Node)/$($np.Port)!" )
                                                        {
                                                            $portInterface = $portInterface[0]
                                                            Write-Host "`tusing network interface $($portInterface.InterfaceName) address: $($portInterface.Address)..."

                                                            # Flag to track if all data is present in $d before outputting it...
                                                            $outputData = $true
                                                            $d = "" | Select-Object Datastore, JunctionPath, DestinationVolume, ExpPolicy, DRInfAddr, VolType, VMs
                                                            $d.VMs = New-Object 'System.Collections.Generic.List[System.Object]'

                                                            $d.Datastore = $ds.Name
                                                            $d.JunctionPath = $prodVol.JunctionPath
                                                            $d.DestinationVolume = $drVol.Name
                                                            $d.ExpPolicy = $drExportPolicy.PolicyName
                                                            $d.DRInfAddr = $portInterface.Address
                                                            $d.VolType = $volType

                                                            if($null -ne $ds.ExtensionData)
                                                            {
                                                                if($ds.ExtensionData.Vm -is [Array])
                                                                {
                                                                    # Since we have a datastore on the production storage cluster that is snapmirrored to DR, process the VMs, if there are any...
                                                                    # Get all VMs stored on the datastore

                                                                    foreach($vm in $ds.ExtensionData.Vm)
                                                                    {
                                                                        Write-Host "`t`t`t`tDR distributed switch port $($drVMDistributedSwitchName):$($drPortGroup.Name)..."

                                                                        Write-Host "`r`n`tlocating VM with ID: VirtualMachine-$($vm.Value)..."
                                                                        $prodVM = @($prodVMs | Where-Object { $_.Id -eq "VirtualMachine-$($vm.Value)" })
                                                                        if(CheckForOneAndOnlyOne $prodVM "prodVM" "`tERROR: Multiple production VMs found with ID: VirtualMachine-$($vm.Value)!" "ERROR: Can't find production VM with ID: VirtualMachine-$($vm.Value)!" )
                                                                        {
                                                                            $prodVM = $prodVM[0]

                                                                            $vmData = "" | Select-Object VM, Name, OS, PowerState, Folder, NetAdapters
                                                                            $vmData.NetAdapters = New-Object 'System.Collections.Generic.List[System.Object]'

                                                                            $vmData.VM = $null  # This is used as a placeholder so during DR, it can be populated
                                                                            $vmData.Name = $prodVM.Name
                                                                            $vmData.OS = $prodVM.Guest.OSFullName
                                                                            $vmData.PowerState = $prodVM.PowerState.ToString()
                                                                            $vmData.Folder = MakeVMFolderPath $prodVM

                                                                            Write-Host "`t`tchecking network adapters on $($prodVM.Name)..."
                                                                            # Check each network adapter on the VM
                                                                            $vmNetAdapters = Get-NetworkAdapter -VM $prodVM
                                                                            foreach($netAdapter in $vmNetAdapters)
                                                                            {
                                                                                $n = "" | Select-Object ID, Name, PortGroup
                                                                                Write-Host "`t`t`t$($netAdapter.NetworkName)..."
                                                                                $drPortGroup = @($drPortGroups | Where-Object { $_.Name -eq $netAdapter.NetworkName } )
                                                                                if(CheckForOneAndOnlyOne $drPortGroup "drPortGroup" "Too many DR port groups matching: $($netAdapter.NetworkName)!" "Missing DR port group: $($netAdapter.NetworkName)!")
                                                                                {
                                                                                    $drPortGroup = $drPortGroup[0]

                                                                                    $n.ID = $netAdapter.ExtensionData.Key
                                                                                    $n.Name = $drPortGroup.Name
                                                                                    $n.PortGroup = $null  # This is used as a placeholder so during DR, it can be populated

                                                                                    $vmData.NetAdapters.Add($n)
                                                                                }
                                                                            }

                                                                            # Add $vmData to the datastores VM list
                                                                            $d.VMs.Add($vmData)
                                                                        }
                                                                    }
                                                                }
                                                                else
                                                                {
                                                                    Write-Host "$($ds.Name)'s ExtensionData.Vm contains no VM IDs!"
                                                                    $outputData = $false
                                                                }
                                                            }
                                                            else
                                                            {
                                                                Write-Host "$($ds.Name)'s ExtensionData is null!"
                                                                $outputData = $false
                                                            }

                                                            # If we loaded $d with all the data we need, drop it on the pipeline.
                                                            if($outputData)
                                                            {
                                                                $d
                                                            }

                                                            # Since a network interface was found that fit what we need, skip the rest of the possible network ports...
                                                            break
                                                        }
                                                    }
                                                }
                                                else
                                                {
                                                    Write-Host "No network ports on $($node) associated with NFS VLAN $($nfsVLAN)!"
                                                }
                                            }
                                        }
                                        else
                                        {
                                            Write-Host "WTH!!  No disks assigned to aggregate: $($drSVMName)/$($a.Name)"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                else
                {
                    Write-Host "Null datastore in production datastore list!"
                }
            }
        }
        else
        {
            # Nothing, already threw an error above...
        }
    )

    return $drMap
}

function RehydrateDRMap($configFile)
{
    $drMap = @()
    if(Test-Path -Path $configFile)
    {
        $tmpDRMap = Get-Content -Path $configFile | ConvertFrom-Json
        if($tmpDRMap.Length -gt 0)
        {
            # Get an array of all DR Virtual Machine distributed port groups
            if(($drPortGroups = GetDRPortGroups).Length -gt 0)
            {
                # Array of all the NetApp Volumes on the DR SVM
                $drVolumes = $null

                # Get an array of all the NetApp Volumes on the DR SVM
                Write-Host "Loading all volumes from $($cdot02.Name)://$($drSVMName)..."
                if(($drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
                {
                    $drMap = @(
                        for($i = 0; $i -lt $tmpDRMap.Length; $i++)
                        {
                            $d = $tmpDRMap[$i]
                            $d.DestinationVolume = @($drVolumes | Where-Object { $_.Name -eq $tmpDRMap[$i].DestinationVolume })
                            if(CheckForOneAndOnlyOne $d.DestinationVolume "d.DestinationVolume" "Too many DR volumes found for destination volume name: $($tmpDRMap[$i].DestinationVolume)!" "Unable to find DR volume for destination volume name: $($tmpDRMap[$i].DestinationVolume)!" )
                            {
                                $d.DestinationVolume = $d.DestinationVolume[0]

                                for($v = 0; $v -lt $tmpDRMap[$i].VMs.Length; $v++)
                                {
                                    for($a = 0; $a -lt $tmpDRMap[$i].VMs[$v].NetAdapters.Length; $a++)
                                    {
                                        if($useSIMSwitch)
                                        {
                                            $portGroupName = "$($tmpDRMap[$i].VMs[$v].NetAdapters[$a].Name) (sim)"
                                        }
                                        else
                                        {
                                            $portGroupName = "$($tmpDRMap[$i].VMs[$v].NetAdapters[$a].Name)"
                                        }
                                        $tmpPG = @($drPortGroups | Where-Object { $_.Name -eq $portGroupName })
                                        if(CheckForOneAndOnlyOne $tmpPG $portGroupName "Too many DR networks found for network name: $($portGroupName)!" "Unable to find DR network for network name: $($portGroupName)!" )
                                        {
                                            $d.VMs[$v].NetAdapters[$a].PortGroup = $tmpPG[0]
                                        }
                                    }
                                }
                            }

                            $d
                        }
                    )
                }
                else
                {
                    Write-Host "`tNo volumes located on $($cdot02.Name)://$($drSVMName)..."
                }
            }
            else
            {
                Write-Host "ERROR: Failed to get a list of all DR VM port groups."
            }
        }
        else
        {
            Write-Host "ERROR: No DR data imported from: $($configFile)."
        }
    }
    else
    {
        Write-Host "Missing config file: $($configFile)!"
    }

    return $drMap
}

function BreakSnapmirror($volume)
{
    # Flag for success...
    $successful = $false

    if($null -ne $volume)
    {
        if($volume -is [DataONTAP.C.Types.Volume.VolumeAttributes])
        {
            if($null -ne $volume.VolumeMirrorAttributes)
            {
                if($volume.VolumeMirrorAttributes.IsDataProtectionMirrorSpecified -and $volume.VolumeMirrorAttributes.IsDataProtectionMirror)
                {
                    Write-Host "`t`tLoading local copy of volume $($cdot02):\\$($drSVMName)\$($volume.Name)..."
                    # Get a local copy of the volume from NetApp so we can monitor the transfer status if necessary...
                    $vol = @(Get-NCVol -Controller $cdot02 -Vserver $drSVMName -Name $volume.Name)

                    if(CheckForOneAndOnlyOne $vol "vol" "Too many volumes returned from $($cdot02.Name)://$($drSVMName) for volume name: $($volume.Name)!" "No volume found on $($cdot02.Name)://$($drSVMName) for volume name: $($volume.Name)!")
                    {
                        $vol = $vol[0]

                        # If the volume is currently involved in a transfer, display a message and wait for it to complete
                        if($vol.VolumeMirrorAttributes.MirrorTransferInProgressSpecified -and $volume.VolumeMirrorAttributes.MirrorTransferInProgress)
                        {
                            Write-Host "`t`tWaiting for current snapmirror transfer to complete for $($cdot02.Name)://$($drSVMName)/$($vol.Name)..."
                            do
                            {
                                # Pause for 5 seconds to allow for station identification...
                                Start-Sleep -Seconds 5

                                # Get the volume object again so we can check to see if it's still transferring...
                                Write-Host "`t`t`tReloading local copy of volume $($cdot02):\\$($drSVMName)\$($volume.Name)..."
                                $vol = Get-NCVol -Controller $cdot02 -Vserver $drSVMName -Name $volume.Name

                            } while($vol.VolumeMirrorAttributes.MirrorTransferInProgressSpecified -and $volume.VolumeMirrorAttributes.MirrorTransferInProgress)
                        }
                        else
                        {
                            # Nothing, volume is not involved with a transfer...
                        }

                        try
                        {
                            Write-Host "`t`tInvoking snapmirror break for volume $($cdot02):\\$($drSVMName)\$($vol.Name)..."
                            # Now that we have all the particulars and know the volume is not involved with a transfer, break the mirror...
                            Invoke-NcSnapmirrorBreak -Controller $cdot02 -DestinationVserver $drSVMName -DestinationVolume $vol -Confirm:$false

                            # Count the number of attempts to update the volume until we decide to give up...
                            $tries = 0
                            do
                            {
                                # One more try...
                                $tries++

                                # Get a list of DR volumes in hopes of picking up the new status of the volume.
                                Write-Host "`t`t`tRefreshing DR volumes from $($cdot02.Name):\\$($drSVMName) to verify snapmirror was broken..."
                                $drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)

                                # Pick out the volume of interest
                                $vol = $drVolumes | Where-Object { $_.Name -eq $volume.Name }

                                # Success is determined by whether or not the volume is no longer a data protection mirror...
                                $successful = !$vol.VolumeMirrorAttributes.IsDataProtectionMirror

                                # If not successful, assume the break process is still in operation and more time is needed to complete...
                                if(!$successful)
                                {
                                    Write-Host "`t`t`t`tPausing to to allow more time for NetApp to complete the snapmirror break..."

                                    # Give the snapmirror more time to break...
                                    Start-Sleep -Seconds 2
                                }
                                else
                                {
                                    # Nothing, snapmirror was broken...
                                }
                            # While the volume is still a data protection mirror, and we haven't exhausted our attempts, keep trying...
                            } while(($vol.VolumeMirrorAttributes.IsDataProtectionMirror) -and ($tries -lt 10))
                        }
                        catch
                        {
                            Write-Host "Attempt to break the snapmirror for $($cdot02.Name)://$($drSVMName)/$($vol.Name) threw an exception."
                        }
                        # We either succeeded, or exhausted the attempts to update the volume.  $successful is set to the result...
                    }
                    else
                    {
                        # Nothing, CheckForOneAndOnlyOne would have displayed any error
                    }
                }
                else
                {
                    # Nothing, $volume is not a data protection mirror, so simulate a successful snapmirror break
                    $successful = $true
                }
            }
            else
            {
                Write-Host "Volume sent to BreakSnapmirror [$($volume.Name)] has not VolumeMirrorAttributes."
            }
        }
        else
        {
            Write-Host "Volume sent to BreakSnapmirror is not of type DataONTAP.C.Types.Volume.VolumeAttributes."
        }
    }
    else
    {
        Write-Host "Null volume sent to BreakSnapmirror."
    }

    return $successful
}

function BreakSnapmirrors($map)
{
    $successful = $true

    Write-Host "Breaking snapmirrors for DR volumes..."

    for($v = 0; ($successful) -and ($v -lt $map.Length); $v++)
    {
        if($map[$v].DestinationVolume.VolumeMirrorAttributes.IsDataProtectionMirror)
        {
            Write-Host "`tBreaking snapmirror for $($cdot02)://$($drSVMName)/$($map[$v].DestinationVolume.Name) ..."
            $successful = BreakSnapmirror $map[$v].DestinationVolume
        }
    }

    return $successful
}

function SetDRVMWareExportPolicy($volume)
{
    $successful = $true
    # Array of all the NetApp Volumes on the DR SVM
    $drVolumes = $null

    # Make sure a volume was sent to the function
    if($null -ne $volume)
    {
        # Get an array of all the NetApp Volumes on the DR SVM
        Write-Host "Loading all volumes from $($cdot02.Name)://$($drSVMName)..."
        if(($drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
        {
            $vol = @($drVolumes | Where-Object { $_.Name -eq $volume.Name } )
            if(CheckForOneAndOnlyOne $vol "vol" "Too many DR volumes with name: $($volume.Name)!" "No DR volume with name: $($volume.Name) found!")
            {
                $vol = $vol[0]

                if(($null -ne $vol.VolumeExportAttributes) -and (![String]::IsNullOrEmpty($vol.VolumeExportAttributes.Policy)) -and ($vol.VolumeExportAttributes.Policy -ne "exp_vmware_01"))
                {
                    # Get an attribute template from the DR SVM
                    $attr = Get-NcVol -Template -Controller $cdot02 -VserverContext $drSVMName

                    # Initialize the VolumeExportAttributes property
                    Initialize-NcObjectProperty -Object $attr -Name VolumeExportAttributes

                    # Set the policy to exp_vmware_01
                    $attr.VolumeExportAttributes.Policy = "exp_vmware_01"

                    # Get a query template from the DR SVM
                    $query = Get-NcVol -Template -Controller $cdot02 -VserverContext $drSVMName

                    # Set the query to look for volume named : $volume.Name on $drSVMName
                    $query.Name = $vol.Name
                    $query.Vserver = $drSVMName

                    Write-Host "`t`tSetting $($cdot02.Name)://$($drSVMName)/$($volume.Name) export policy to exp_vmware_01..."

                    # Update any matching volumes...
                    Update-NcVol -Controller $cdot02 -VserverContext $drSVMName -Query $query -Attributes $attr | Out-Null

                    # Refresh the DR volumes list
                    Write-Host "`t`tRefreshing DR volumes to ensure volume $($cdot02.Name)://$($drSVMName)/$($volume.Name) export policy was updated correctly..."
                    $drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)
                }
            }
            else
            {
                $successful = $false
            }
        }
        else
        {
            Write-Host "`tNo volumes located on $($cdot02.Name)://$($drSVMName)..."
        }
    }
    else
    {
        Write-Host "Null volume sent to SetDRVMWareExportPolicy!"
        $successful = $false
    }

    return $successful
}

function CheckAndMountDRVMWareVolume($mapData)
{
    # Flag to signal the mount exists and export policy is set...
    $successful = $true

    # Array of all the NetApp Volumes on the DR SVM
    $drVolumes = $null

    if($null -ne $mapData)
    {
        # Get an array of all the NetApp Volumes on the DR SVM
        Write-Host "Loading all volumes from $($cdot02.Name)://$($drSVMName)..."
        if(($drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)).Length -gt 0)
        {
            # Break up the different pieces of the source volume's junction path.
            $jps = $mapData.JunctionPath.Split("/",[System.StringSplitOptions]::RemoveEmptyEntries)

            # Build an array of the parts required to make the destination volume's junction path.
            #   NOTE: "" is in front to ensure String::Join always creates a string that starts with /
            $jpParts = @("","vmware",$mapData.VolType,$($jps[$jps.Length - 1]))

            # Cycle through all but the final junction path checking to make sure DR has all the prerequisite junction paths
            $haveRequiredJPs = $true
            for($i = 2; ($haveRequiredJPs) -and ($i -lt $jpParts.Length); $i++)
            {
                $junctionPath = [String]::Join("/", $jpParts, 0, $i)
                $jp = @($drVolumes | Where-Object { (![String]::IsNullOrEmpty($_.JunctionPath)) -and ($_.JunctionPath -eq $junctionPath) })
                $haveRequiredJPs = $jp.Length -eq 1
            }

            # If all of the prerequisite junction paths are present, check for the final one, create it and set the export policy if it's not found...
            if($haveRequiredJPs)
            {
                # Create the final junction path
                $junctionPath = [String]::Join("/", $jpParts, 0, $jpParts.Length)

                # Check for a volume with the final junction path
                $jp = @($drVolumes | Where-Object { (![String]::IsNullOrEmpty($_.JunctionPath)) -and ($_.JunctionPath -eq $junctionPath) })

                # If no volumes were found for junction path...
                if($jp.Length -eq 0)
                {
                    Write-Host "`tMounting $($mapData.DestinationVolume.Name) as $($junctionPath) on $($cdot02.Name)://$($drSVMName)"

                    # Mount the destination volume as the junction path on the DR SVM
                    Mount-NcVol -Controller $cdot02 -VserverContext $drSVMName -Name $mapData.DestinationVolume.Name -JunctionPath $junctionPath -JunctionActive:$true | Out-Null

                    # Refresh the DR volume list
                    Write-Host "`tRefreshing DR volumes to ensure volume $($cdot02.Name)://$($drSVMName)/$($mapData.DestinationVolume.Name) was mounted correctly..."
                    $drVolumes = @(Get-NcVol -Controller $cdot02 -Vserver $drSVMName)

                    # Check to make sure the mount succeeded...
                    $jp = @($drVolumes | Where-Object { (![String]::IsNullOrEmpty($_.JunctionPath)) -and ($_.JunctionPath -eq $junctionPath) })
                    if($jp.Length -eq 1)
                    {
                        # If the mount succeeded, then update the export policy...
                        $successful = SetDRVMWareExportPolicy $jp[0]
                    }
                    else
                    {
                        Write-Host "Failed to mount $($mapData.DestinationVolume.Name) as $($junctionPath) on $($drSVMName)!"
                        $successful = $false
                    }
                }
                elseif($jp.Length -gt 1)
                {
                    Write-Host "WTH!!  Multiple volumes mounted as junction path: $($junctionPath)!"
                    $successful = $false
                }
                else
                {
                    # The final junction path already exists, so check and/or update the export policy
                    $successful = SetDRVMWareExportPolicy $jp[0]
                }
            }
            else
            {
                Write-Host "Missing some or all of the prerequisite junction paths on $($drSVMName)."
                $successful = $false
            }
        }
        else
        {
            Write-Host "`tNo volumes located on $($cdot02.Name)://$($drSVMName)..."
        }
    }
    else
    {
        Write-Host "Null volume data sent to CheckAndMountDRVMWareVolume."
        $successful = $false
    }

    return $successful
}

function CheckAndMountDRVMWareVolumes($map)
{
    $successful = $true

    for($v = 0; ($successful) -and ($v -lt $map.Length); $v++)
    {
        Write-Host "Checking and/or mounting $($map[$v].DestinationVolume.Name) on $($cdot02)://$($drSVMName)..."
        $successful = CheckAndMountDRVMWareVolume $map[$v]
    }

    return $successful
}

function AddDRDatastore($mapData)
{
    # Flag for success
    $successful = $false

    # Initialize $drDS to $null
    $drDS = $null

    # Array of all DR datastores
    $drDatastores = $null

    # Array of DR VM Hosts
    $drVMHosts = $null

    # Get an array of all DR datastores
    Write-Host "`tLoading all non-local datastores from $($vcDR.Name):\\$($drDatacenter)..."
    $drDatastores = @(Get-Datastore -Location $drDatacenter -Server $vcDr | Where-Object { !$_.Name.ToUpper().Contains("LOCAL") })

    # Make sure data was sent in...
    if($null -ne $mapData)
    {
        # Get a list of DR VM Hosts
        Write-Host "`tLoading all VM hosts from $($vcDR.Name)\$($drDatacenter)..."
        if(($drVMHosts = @(Get-VMHost -Server $vcDR -Location $drDatacenter)).Length -gt 0)
        {
            # Break apart the junction path to help in constructing the datastore name and NFS Path...
            $jpParts = $mapData.JunctionPath.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)

            # Make sure there are "parts" in the junction path
            if($jpParts.Length -gt 0)
            {
                # The final "part" of the junction path show be contained in the volume name, so check for that...
                if($mapData.DestinationVolume.Name.ToUpper().Contains($jpParts[$jpParts.Length-1].ToUpper()))
                {
                    # Datastore names are SVMNAME_VOLUMETYPE_JUNCTIONPATH
                    #   I did it this way so I could use the array to build the datastore name, the NFS path, and check for Datastore folder in vCenter...
                    $dsNameParts = @($drSVMName, $mapData.VolType, $jpParts[$jpParts.Length-1])

                    # Construct the datastore name...
                    $dsName = [String]::Join("_", $dsNameParts)

                    # Construct the NFS path.  Append all but the first parts of the name to "/vmware/" to build the nfs path
                    $nfsPath = "/vmware/$([String]::Join("/",$dsNameParts,1,$dsNameParts.Length - 1))"

                    # First off, check to see if there is a datastore with the name $dsName already...
                    $drDS = @($drDatastores | Where-Object { $_.Name -eq $dsName })
                    if($drDS.Length -eq 0)
                    {
                        Write-Host "`tMounting NFS://$($mapData.DRInfAddr)$($nfsPath) to DR VM Hosts as ($dsName)..."
                        # There is no datastore named $dsName, so create it...
                        New-Datastore -Server $vcDR -VMHost $drVMHosts -Name $dsName -Nfs -NfsHost $mapData.DRInfAddr -Path $nfsPath -WarningAction SilentlyContinue | Out-Null

                        # Refresh the DR datastore list...
                        Write-Host "`tRefreshing DR datastores to ensure NFS://$($mapData.DRInfAddr)$($nfsPath) was properly mounted..."
                        $drDatastores = @(Get-Datastore -Location $drDatacenter -Server $vcDr | Where-Object { !$_.Name.ToUpper().Contains("LOCAL") })

                        # Now recheck for the datastore...
                        $drDS = @($drDatastores | Where-Object { $_.Name -eq $dsName })
                    }

                    # Either we found a matching datastore or tried to create it.  So check to see if we have one...
                    if($drDS.Length -eq 1)
                    {
                        # We do have an datastore with name $dsName... now check the particulars...
                        # But first, shorten the variable...
                        $drDS = $drDS[0]

                        # Make sure the datastore is NFS, if it's not, then the datastore doesn't match what we need...
                        if($drDS.Type -eq "NFS")
                        {
                            # Make sure the NFS datastore is mounted from the correct NFSHost, if it's not, then the datastore doesn't match what we need...
                            if($drDS.RemoteHost[0] -eq $mapData.DRInfAddr)
                            {
                                # Make sure the NFS datastore mount is connected to the correct nfs path, if it's not, then the datastore doesn't match what we need...
                                if($drDS.RemotePath -eq $nfsPath)
                                {
                                    # Now that the NFS information has all been verified, make sure all VM hostsis are connected.  If one isn't, we'll attempt to connect it...

                                    # Get a list of all VM host IDs the datastore is connected to...
                                    $hostKeys = @($drDS.ExtensionData.Host | Select-Object -ExpandProperty Key)

                                    # Assume success until we verify not...
                                    $successful = $true

                                    # Check each VM host...
                                    for($i = 0; ($successful) -and ($i -lt $drVMHosts.Count); $i++)
                                    {
                                        # Temp variable to make things easier...
                                        $vmhost = $drVMHosts[$i]

                                        # if this vm host isn't connected, try to connect it...
                                        if(!$hostKeys.Contains($vmhost.Id))
                                        {
                                            Write-Host "`t`t$($drDS.Name) is not attached to $($vmhost.Name)."
                                            Write-Host "`t`tAttaching $($vmhost.Name) to $($drDS.Name)..."
                                            New-Datastore -Server $vcDR -VMHost $vmhost -Name $drDS.Name -Nfs -NfsHost $drDS.RemoteHost[0] -Path $drDS.RemotePath -WarningAction SilentlyContinue | Out-Null

                                            # Refresh the DR datastore list...
                                            Write-Host "`t`tRefreshing DR datastores to ensure NFS://$($mapData.DRInfAddr)/$($nfsPath) was properly mounted..."
                                            $drDatastores = @(Get-Datastore -Location $drDatacenter -Server $vcDr | Where-Object { !$_.Name.ToUpper().Contains("LOCAL") })

                                            # Refresh the datastore variable the datastore...
                                            $drDS = $drDatastores | Where-Object { $_.Name -eq $drDS.Name }

                                            # refresh host keys...
                                            $hostKeys = @($drDS.ExtensionData.Host | Select-Object -ExpandProperty Key)

                                            $successful = $hostKeys.Contains($vmhost.Id)
                                            if(!$successful)
                                            {
                                                Write-Host "`t`tFailed to mount NFS://$($mapData.DRInfAddr)/$($nfsPath) to $($vmhost.Name)."
                                            }
                                        }
                                        else
                                        {
                                            # Nothing, this vmhost is properly connected.
                                        }
                                    }

                                    # If everything was checked successfully, then relocate the datastore to the correct
                                    #    DS folder.  NOTE: Even if relocating the datastore fails, the operation is still successful.  Moving the datastore is purely cosmetic.
                                    if($successful)
                                    {
                                        # Replace the Datastore name that was stored in $mapData with the real datastore...
                                        $mapData.Datastore = $drDS

                                        # See if the datastore needs to be moved.
                                        if($drDS.ParentFolder.Name -ne $dsNameParts[$dsNameParts.Length - 2])
                                        {
                                            # The datastore needs to be moved...

                                            # Now, check for the datastore folders needed to relocate the datastore...
                                            #   Need to check all but the last part ...
                                            $dLoc = "datastore"
                                            $fName = "datastore"
                                            $haveFolders = $true
                                            for($i = 0; ($haveFolders) -and ($i -lt ($dsNameParts.Length - 1)); $i++)
                                            {
                                                # Get the datastore folders at $dLoc with no recursion...
                                                $folders = @(Get-Folder -Server $vcDR -Type Datastore -NoRecursion -Location $dLoc)

                                                # Find the folder matching $dsNameParts[$i]...
                                                $f = @($folders | Where-Object { $_.Name -eq $dsNameParts[$i] })

                                                # If the folder for $dsNameParts[$i] was not found, try to create it, and recheck for it.
                                                if($f.Length -eq 0)
                                                {
                                                    # Try to create the new folder
                                                    Write-Host "`tCreating new datastore folder named $($dsNameParts[$i]) under $($fName)..."
                                                    New-Folder -Server $vcDR -Location $dLoc -Name $dsNameParts[$i] | Out-Null

                                                    # Refresh the list of folders at $dLoc
                                                    $folders = @(Get-Folder -Server $vcDR -Type Datastore -NoRecursion -Location $dLoc)

                                                    # Again, try to find a folder for $dsNameParts[$i]...
                                                    $f = @($folders | Where-Object { $_.Name -eq $dsNameParts[$i] })
                                                }

                                                # This may seem repetitive, but if the folder for $dsNameParts[$i] didn't initially exist, then we just tried to create
                                                #    it, so here, we are check to make sure it was created if necessary.
                                                if($f.Length -eq 1)
                                                {
                                                    # We have the folder for $dsNameParts[$i], so set $dLoc to the folder so we can continue checking...
                                                    $dLoc = $f[0]
                                                    $fName = $f[0].Name
                                                }
                                                else
                                                {
                                                    $haveFolders = $false
                                                    Write-Host "`tNo datastore folder found for $($dsNameParts[$i]) and I was unable to create one."
                                                    break
                                                }
                                            }

                                            # If all required folder exist, then add the datastore to the VM hosts...
                                            if($haveFolders)
                                            {
                                                Write-Host "`tRelocating $($drDS.Name) to $($fName)..."
                                                Move-Datastore -Server $vcDR -Datastore $drDS -Destination $dLoc | Out-Null

                                                # Refresh the DR datastore list...
                                                Write-Host "`t`tRefreshing DR datastores to ensure NFS://$($mapData.DRInfAddr)/$($nfsPath) was properly mounted..."
                                                $drDatastores = @(Get-Datastore -Location $drDatacenter -Server $vcDr | Where-Object { !$_.Name.ToUpper().Contains("LOCAL") })
                                            }
                                            else
                                            {
                                                # Nothing, an error would already have been displayed.
                                            }
                                        }
                                        else
                                        {
                                            # Nothing, the datastore is already in the right folder
                                        }
                                    }
                                    else
                                    {
                                        # Nothing, not going to try to relocate the datastore unless all is well.
                                    }
                                }
                                else
                                {
                                    Write-Host "Mounted NFS Datastore [$($drDS.Name)] is not connected to path $($nfsPath)!"
                                }
                            }
                            else
                            {
                                Write-Host "NFS Datastore [$($drDS.Name)] is not mounted from $($mapData.DRInfAddr)!"
                            }
                        }
                        else
                        {
                            Write-Host "Datastore [$($drDS.Name)] is not an NFS datastore!"
                        }
                    }
                    else
                    {
                        Write-Host "Failed to create new datastore [$($dsName)] connected to NFS://$($mapData.DRInfAddr)$($nfsPath)!"
                        $drDS = $null
                    }
                }
                else
                {
                    Write-Host "Junction path [$($mapData.JunctionPath)] for $($mapData.DestinationVolume.Name) seems incorrect."
                }
            }
            else
            {
                Write-Host "Junction path [$($mapData.JunctionPath)] for $($mapData.DestinationVolume.Name) seems incorrect."
            }
        }
        else
        {
            Write-Host "`tNo ESXi hosts located on $($vcDR.Name)/$($drDatacenter)."
        }
    }
    else
    {
        Write-Host "Null map data sent to AddDRDatastore!"
    }

    return $successful
}

function AddDRDatastores($map)
{
    # Flag for success
    $successful = $true

    for($v = 0; ($successful) -and ($v -lt $map.Length); $v++)
    {
        Write-Host "Adding datastore to $($vcDr.Name) for $($cdot02)://$($drSVMName)/$($map[$v].DestinationVolume.Name) ..."
        $successful = AddDRDatastore $map[$v]
    }

    return $successful
}

function MakeVMFolderTree($folderPath)
{
    # Split the path into individual pieces.
    $folderList = $folderPath.Split("\",[System.StringSplitOptions]::RemoveEmptyEntries)

    # Flag to signal the VM's folder structure exists...
    $successful = $true

    # Start looking at the root VM folder...
    $dLoc = "vm"

    # For each of the folder in the list, check to make sure they exist as they should and recreate them if needed
    for($i = 0; $i -lt $folderList.Length; $i++)
    {
        # Temp variable to the current folder...
        $pf = $folderList[$i]

        # Get all the DR VM Folders that exist under $dLoc ... do not get sub folders...
        $dFolders = @(Get-Folder -Server $vcDr -Location $dLoc -NoRecursion)

        # No need to check for the existence of folders at $dLoc in general, since we are really
        #    looking for a specific folder in the list, and we can search an empty array.. it will just
        #    always return nothing... as in we need to create the folder.

        # Now check to see if $dFolders contains a folder named the same as $pf
        $df = @($dFolders | Where-Object { $_.Name -eq $pf })

        # If no folder with the name $pf was found under $dLoc, create one...
        if($df.Length -eq 0)
        {
            # Create the new folder...
            New-Folder -Server $vcDr -Location $dLoc -Name $pf | Out-Null

            # Refresh the DR VM folder list
            $dFolders = (Get-Folder -Server $vcDr -Location $dLoc -NoRecursion)

            # Check to make sure we successfully created a new folder...
            $df = @($dFolders | Where-Object { $_.Name -eq $pf })
        }

        # If $df.Length -eq 1, then there is a folder named $pf under $dloc...
        #   NOTE: Not using an else clause here because if in the previous if block we tried to create
        #         a folder, then searched for it again, this if will also serve to check that search...
        if($df.Length -eq 1)
        {
            # ...So set the DR folder location to the folder just found and/or created...
            $dLoc = $df[0]
        }
        else
        {
            $successful = $false
            break
        }
    }

    return @($successful, $dLoc)
}

function CreateAllVMFolders($map)
{
    # Flag for success...
    $successful = $true

    # Build an array of unique VM folders [strings] where the datastore property is an actual datastore...
    $vmFolders = @($map | Where-Object { $_.Datastore -is [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl] } | Select-Object -ExpandProperty VMs | Select-Object -Unique @{N="Folder";E={ $_.Folder }} | Select-Object -ExpandProperty Folder | Sort-Object)
    #$vmFolders = @($map | ? { $_.Datastore -is [System.String] } | Select -ExpandProperty VMs | Select -Unique @{N="Folder";E={ $_.Folder }} | Select -ExpandProperty Folder | Sort)

    # Check each of the unique VMs...
    for($m = 0; ($successful) -and ($m -lt $vmFolders.Length); $m++)
    {
        Write-Host "Checking/Creating folder structure for: $($vmFolders[$m]) on $($vcDR.Name)"
        $o = MakeVMFolderTree $vmFolders[$m]
        $successful = $o[0]

        # If the folder/path was created successfully, then change the .Folder property for all matching VM Folders to the actual folder...
        if($successful)
        {
            for($i = 0; $i -lt $map.Length; $i++)
            {
                for($v = 0; $v -lt $map[$i].VMs.Length; $v++)
                {
                    # If $map[$i].VMs[$v].Folder is still a string, and it matches $vmFolders[$m], then change it to the actual folder
                    if(($map[$i].VMs[$v].Folder -is [System.String]) -and (![String]::IsNullOrEmpty($map[$i].VMs[$v].Folder) -and ($map[$i].VMs[$v].Folder -eq $vmFolders[$m])))
                    {
                        $map[$i].VMs[$v].Folder = $o[1]
                    }
                }
            }
        }
    }

    return $successful
}

function GetVMNameFromVMXFile($vmxFile)
{
    # Initialize VMName to nothing
    $vmName = [String]::Empty

    # If there is a temporary vmxFile.txt, delete it...
    if(Test-Path -Path "C:\TMP\vmxFile.txt")
    {
        Remove-Item -Path "C:\TMP\vmxFile.txt" -Confirm:$false -Force | Out-Null
    }
    else
    {
        # Nothing, no temp file, nothing to remove...
    }

    # Copy the vmxfile to a temporary local file.
    Copy-DatastoreItem -Item $vmxFile -Destination "C:\TMP\vmxFile.txt" -Force | Out-Null

    # If the copy was successful...
    if(Test-Path -Path "C:\TMP\vmxFile.txt")
    {
        # Read the contents so we can extract the displayName entry...
        $content = @(Get-Content -Path "C:\TMP\vmxFile.txt")

        # Make sure we read something from the temp file.
        if($content.Length -gt 0)
        {
            # Try to grab the displayName entry...
            $displayName = @($content | Where-Object { $_.ToUpper().StartsWith("DISPLAYNAME") })

            # If we found the displayName entry, parse it...
            if($displayName.Length -eq 1)
            {
                # Match the displayName entry to a regular expression so we can extract the VM name...
                if($displayName[0] -match "displayName\s+\=\s+\`"([^`"]+)\`"") # """   Comment used to fix highlighting issue in Notepad++
                {
                    # The displayName entry matched the regular expression, so grab the VM name from $Matches[1]...
                    $vmName = $Matches[1]
                }
                else
                {
                    Write-Host "Unable to determine VM display name from [$($displayName[0])]!"
                }
            }
            else
            {
                Write-Host "Unable to determine VM display name from VMX file [$($vmxFiles[$v].DatastoreFullPath)]!"
            }
        }
        else
        {
            Write-Host "Failed to read contents of temporary vmxFile!"
        }

        # Finally, remove the temp file...
        Remove-Item -Path "C:\TMP\vmxFile.txt" -Confirm:$false -Force | Out-Null
    }
    else
    {
        Write-Host "Failed to copy vmx file to temporary location."
    }

    return $vmName
}

function RelocateVM($vmData)
{
    # Success really doesn't matter, since the VM can run from whatever folder.  Relocating it is purely cosmetic.

    # Now relocate the registered VM to the proper folder...
    if($null -ne $vmData)
    {
        if($null -ne $vmData.VM)
        {
            if($null -ne $vmData.Folder)
            {
                if($vmData.VM -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl])
                {
                    if($vmData.Folder -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl])
                    {
                        Move-VM -VM $vmData.VM -Destination $vmData.Folder -Server $vcDR -Confirm:$false | Out-Null
                    }
                    else
                    {
                        Write-Host "`t`tWARNING: `$vmData.Folder is not a VM folder object in RelocateVM."
                    }
                }
                else
                {
                    Write-Host "`t`tWARNING: `$vmData.VM is not a VM object in RelocateVM."
                }
            }
            else
            {
                Write-Host "`t`tWARNING: `$vmData.Folder is null in RelocateVM."
            }
        }
        else
        {
            Write-Host "`t`tWARNING: `$vmData.VM is null in RelocateVM."
        }
    }
    else
    {
        Write-Host "`t`tWARNING: null `$vmData sent to RelocateVM."
    }
}

function Add_DR_DS_VMs_To_Inventory($mapData, $cluster, $drVMs)
{
    # Flag for success
    $successful = $true

    # Make sure $mapData contains data...
    if($null -ne $mapData)
    {
        # Since AddDRVMsToInventory sends $mapData in having all Datastores the same, we can safely extract 1 using the following..
        $datastore = @($mapData | Select-Object -Unique -ExpandProperty Datastore)[0]

        # Make sure the $dataStore is a datastore object
        if($dataStore -is [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl])
        {
            # Make sure we have a cluster...
            if(($null -ne $cluster) -and ($cluster -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl]))
            {
                # Get a list of all VM Names and paths to their vmx files
                $existingVMsAndPaths = @($drVMs | Select-Object Name,@{N="DatastoreFullPath";E={$_.ExtensionData.Config.Files.VmPathName}})

                # Search for all .vmx files on the datastore
                Write-Host "`tSearching for vmx files in $($dataStore.DatastoreBrowserPath)..."
                $vmxFiles = @(Get-ChildItem -Path $dataStore.DatastoreBrowserPath -Recurse -Filter "*.vmx")

                # Now register each of the VMs found on the datastore in vSphere (if it can be), as long as an error doesn't happen
                for($v = 0; ($successful) -and ($v -lt $vmxFiles.Length); $v++)
                {
                    # Get the VM name that would be registered from the VMX file...
                    Write-Host "`t`tExtracting VM name from vmx file: $($vmxFiles[$v].DatastoreFullPath)..."
                    $vmName = GetVMNameFromVMXFile $vmxFiles[$v]

                    # Just to be extra sure test $vmName for null...
                    if(![String]::IsNullOrEmpty($vmName))
                    {
                        # Find the index of the VM in $mapData.VMs..
                        $vmIdx = $mapData.VMs.IndexOf(($mapData.VMs | Where-Object { $_.Name -eq $vmName }))

                        # Make sure a matching VM was found...
                        if($vmIdx -ge 0)
                        {
                            # The following process is a little confusing to say the least.  There are 4 potential scenarios that can arise:
                            #
                            #    1. No VM registered in vSphere named $vmName and no registered VM using $vmxFiles[$v] as it's config file
                            #
                            #    2. No VM registered in vSphere named $vmName but there is a VM using $vmxFiles[$v] as it's config file
                            #
                            #    3. A VM registered in vSphere named $vmName but does not use $vmxFiles[$v] as it's config file
                            #
                            #    4. A VM registered in vSphere named $vmName and uses $vmxFiles[$v] as it's config file
                            #
                            # In all likelihood, only #1 and #4 will exist.
                            #
                            #    1. $vmxFiles[$v] represents a new VM to be registered in vSphere.  Register the new VM.
                            #
                            #    2. A conflict between displayName in the config file and the name of the VM using $vmxFiles[$v].
                            #       I'm not sure how, or even if this can happen, but I'll still check and display a warning if I detect it.
                            #       This would be detected when looking for a registered VM using $vmxFiles[$v] as it's config file, one is found,
                            #       but it's name does not match $vmName.
                            #
                            #    3. Similar to #2 except detected in the opposite way.  This would be detected by looking for a registered VM
                            #       with name $vmName, finding one, but it's config file is not $vmxFiles[$v].
                            #
                            #    4. A previously registered VM named $vmName and using $vmxFiles[$v] as it's config file.  Perhaps an error occurred
                            #       when running this script, the error was corrected, and the script is running again, this time with some of the DR
                            #       VMs already having been registered.  Just skip these.


                            # Get all entries from $existingVMsAndPaths where DatastoreFullPath matches $vmxFiles[$v].DatastoreFullPath
                            #    This will determine if a VM is already using $vmxFiles[$v].DatastoreFullPath
                            Write-Host "`tTesting for existing VMs named $($vmName) or registered with VMX file: $($vmxFiles[$v].DatastoreFullPath)..."
                            $vmWithMatchingDatastoreFullPathOrName = @($existingVMsAndPaths | Where-Object { ($_.DatastoreFullPath -eq $vmxFiles[$v].DatastoreFullPath) -or ($_.Name -eq $vmName) })

                            # If there are none...
                            if($vmWithMatchingDatastoreFullPathOrName.Length -eq 0)
                            {
                                # Situation #1...
                                # There are no VMs using $vmxFiles[$v] as their config file or having name $vmName

                                Write-Host "`t`tno VM named $($vmName) or associated with VMX file: $($vmxFiles[$v].DatastoreFullPath) found..."
                                # Now select any existing VM with a matching name...

                                # Now, try to register the VM with vSphere
                                Write-Host "`t`tRegistering VM $($vmName) via VMX file: $($vmxFiles[$v].DatastoreFullPath)..."
                                New-VM -Server $vcDR -VMFilePath $vmxFiles[$v].DatastoreFullPath -ResourcePool $cluster | Out-Null

                                # Refresh the DR virtual machines list
                                Write-Host "`t`tRefreshing DR VM list to ensure $($vmName) was successfully registered..."
                                $drVMs = @(Get-VM -Location $drDatacenter -Server $vcDr)

                                # Try to get the newly registered VM from the list of VMs in DR
                                $drVM = @($drVMs | Where-Object { $_.Name -eq $vmName })
                                if(CheckForOneAndOnlyOne $drVM "drVM" "`t`tERROR: Too many VMs named $($vmName) found in DR VMs list." "`t`tFailed to register VM: $($vmName) using VMX file: $($vmxFiles[$v].DatastoreFullPath)!")
                                {
                                    $drVM = $drVM[0]
                                    $mapData.VMs[$vmIdx].VM = $drVM

                                    # Now relocate the registered VM to the proper folder...
                                    RelocateVM $mapData.VMs[$vmIdx]
                                }
                                else
                                {
                                    # Nothing, CheckForOneAndOnlyOne will display the error.
                                    $successful = $false
                                }
                            }
                            else
                            {
                                # Possible situations: 2, 3, and 4

                                # How many element match both name and datastore full path?
                                $vmWithMatchingDatastoreFullPathAndName = @($vmWithMatchingDatastoreFullPathOrName | Where-Object { ($_.DatastoreFullPath -eq $vmxFiles[$v].DatastoreFullPath) -and ($_.Name -eq $vmName) })

                                # If there are any elements in the array, then we have situation 4...
                                if($vmWithMatchingDatastoreFullPathAndName.Length -gt 0)
                                {
                                    # Situation 4...
                                    Write-Host "`t`tVM $($vmName) is already registered using VMX file: $($vmxFiles[$v].DatastoreFullPath)..."

                                    $drVM = @($drVMs | Where-Object { $_.Name -eq $vmName })
                                    if(CheckForOneAndOnlyOne $drVM "drVM" "`t`tERROR: Too many VMs named $($vmName) found in DR VMs list." "`t`tERROR: There doesn't seem to be a VM named $($vmName) in DR!!  Odd!")
                                    {
                                        $drVM = $drVM[0]
                                        $mapData.VMs[$vmIdx].VM = $drVM

                                        RelocateVM $mapData.VMs[$vmIdx]
                                    }
                                    else
                                    {
                                        # Nothing, CheckForOneAndOnlyOne will display the error.
                                        $successful = $false
                                    }
                                }
                                else
                                {
                                    # Otherwise we have Situation 2 or 3, both of which are not good.
                                    $successful = $false

                                    $vmWithMatchingName = @($vmWithMatchingDatastoreFullPathOrName | Where-Object { $_.Name -eq $vmName })

                                    # No elements with a matching name -- Situation #2
                                    if($vmWithMatchingName.Length -eq 0)
                                    {
                                        # Since there are no matching names in $vmWithMatchingDatastoreFullPathOrName, all the DatastoreFullPaths must match,
                                        #    So get a list of unique names...
                                        $tvmNames = @($vmWithMatchingDatastoreFullPathOrName | Select-Object -Unique -ExpandProperty Name)
                                        Write-Host -NoNewLine "`t`tERROR: VM"

                                        if($tvmNames.Length -gt 1)
                                        {
                                            Write-Host -NoNewLine "s"
                                        }
                                        Write-Host -NoNewLine " named: ($([String]::Join(",", $tvmNames))) "

                                        if($tvmNames.Length -gt 1)
                                        {
                                            Write-Host -NoNewLine "are "
                                        }
                                        else
                                        {
                                            Write-Host -NoNewLine "is "
                                        }
                                        Write-Host "registered using VMX file [$($vmxFiles[$v].DatastoreFullPath)]!"
                                    }
                                    else
                                    {
                                        # The only remaining situation is #3...
                                        Write-Host "`t`tERROR: A VM named $($vmName) is already registered with VMX file: $($vmWithMatchingDatastoreFullPathOrName[0].DatastoreFullPath)..."
                                    }
                                }
                            }
                        }
                        else
                        {
                            Write-Host "`t`tWARNING: Extra VM named $($vmName) located in VMX file: $($vmxFiles[$v].DatastoreFullPath).  Ignoring."
                        }
                    }
                    else
                    {
                        Write-Host "`tERROR: Null VM name read from [$($displayName[0])]!"
                        $successful = $false
                    }
                }
            }
            else
            {
                Write-Host "`tMissing DR cluster for VM registration."
            }
        }
        else
        {
            Write-Host "`tDatastore property specified in map data is not of type [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl] in Add_DR_DS_VMs_To_Inventory!"
        }
    }
    else
    {
        Write-Host "`tNull map data sent to Add_DR_DS_VMs_To_Inventory!"
    }

    return $successful
}

function AddDRVMsToInventory($map)
{
    # Flag for success
    $successful = $true

    # Array of DR Clusters
    $drClusters = $null

    # Before delving too deep into it, we need to make sure we have a cluster to use as a resource
    #   pool for registering VMs.  If there isn't one, then no need to proceed...

    # Get a list of DR Clusters
    Write-Host "`tLoading all clusters from $($vcDR.Name)\$($drDatacenter)..."
    if(($drClusters = @(Get-Cluster -Server $vcDR -Location $drDatacenter)).Length -gt 0)
    {
        # Get the first (and only cluster in the DR vSphere environment...)
        $cluster = $drClusters[0]

        # Array of all DR virtual machines
        $drVMs = @()

        # Get an array of all DR virtual machines
        Write-Host "`tLoading all VMs from $($vcDR.Name)\$($drDatacenter)..."
        $drVMs = @(Get-VM -Location $drDatacenter -Server $vcDr)

        for($v = 0; ($successful) -and ($v -lt $map.Length); $v++)
        {
            $successful = Add_DR_DS_VMs_To_Inventory $map[$v] $cluster $drVMs
        }
    }
    else
    {
        Write-Host "`tMissing DR cluster for VM registration."
        $successful = $false
    }

    return $successful
}

function FixDRVMNetworkAdapters($map)
{
    #
    #  Consider removing the NIC vs fixing it up.
    #

    # Flag for success
    $successful = $true

    if($map -is [Array])
    {
        for($i = 0; ($successful) -and ($i -lt $map.Length); $i++)
        {
            for($v = 0; ($successful) -and ($v -lt $map[$i].VMs.Length); $v++)
            {
                if($map[$i].VMs[$v].VM -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl])
                {
                    Write-Host "`tLoading network adapters for $($map[$i].VMs[$v].VM.Name)..."
                    $vmNetAdapters = @(Get-NetworkAdapter -VM $map[$i].VMs[$v].VM)

                    if($vmNetAdapters.Length -gt 0)
                    {
                        Write-Host "`t`tFound $($vmNetAdapters.Length) adapters..."
                        for($n = 0; ($successful) -and ($n -lt $map[$i].VMs[$v].NetAdapters.Length); $n++)
                        {
                            Write-Host "`t`tSearching for adapter with ID: $($map[$i].VMs[$v].NetAdapters[$n].ID)"
                            $netAdapter = $vmNetAdapters | Where-Object { $_.Id.EndsWith("/$($map[$i].VMs[$v].NetAdapters[$n].ID)") }

                            if($null -ne $netAdapter)
                            {
                                Write-Host "`t`t`tfound correct adapter..."

                                $portGroupName = $map[$i].VMs[$v].NetAdapters[$n].Name
                                if($useSIMSwitch)
                                {
                                    $portGroupName = "$($portGroupName) (sim)"
                                }

                                # Since the VM was recently added to the inventory, it's network adapter names will be all hosed up...
                                if($netAdapter.NetworkName -ne $portGroupName)
                                {
                                    Write-Host "`t`t`tChanging network adapter to $($portGroupName)/Start Connected: false [remember to change this before powering on...]"
                                    Set-NetworkAdapter -NetworkAdapter $netAdapter -Portgroup $portGroupName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                                    Set-NetworkAdapter -NetworkAdapter $netAdapter -Confirm:$false -StartConnected:$false -ErrorAction SilentlyContinue | Out-Null

                                    Start-Sleep -Seconds 5
                                    # Reload the network adapter to see if it was changed.
                                    $naID = $netAdapter.Id
                                    $netAdapter = Get-NetworkAdapter -Server $vcDR -VM $map[$i].VMs[$v].VM | Where-Object { $_.Id -eq $naID }

                                    # If the network adapter was not changed, throw an error...
                                    if(-not (($null -ne $netAdapter) -and ($netAdapter.NetworkName -eq $portGroupName)))
                                    {
                                        Write-Host "`t`tIt appears we failed to update the network adapter with ID: $($map[$i].VMs[$v].NetAdapters[$n].ID) on $($map[$i].VMs[$v].VM.Name)!"
                                        $successful = $false
                                    }
                                    else
                                    {
                                        # Nothing, the change was successful
                                    }
                                }
                                else
                                {
                                    # Nothing, network adapter is already correct.
                                }
                            }
                            elseif($vmNetAdapters.Length -gt 1)
                            {
                                Write-Host "s..."
                                Write-Host "`t`tToo many network adapters for VM: $($map[$i].VMs[$v].VM.Name) with ID: $($map[$i].VMs[$v].NetAdapters[$n].ID)!"
                            }
                            else
                            {
                                Write-Host "s..."
                                Write-Host "`t`tNo network adapters for VM: $($map[$i].VMs[$v].VM.Name) with ID: $($map[$i].VMs[$v].NetAdapters[$n].ID)!"
                            }
                        }
                    }
                    else
                    {
                        Write-Host "`tERROR: No network adapters found for $($map[$i].VMs[$v].VM.Name)..."
                    }
                }
                else
                {
                    # Nothing, the entry did not contain an actual VM Object.
                }
            }
        }
    }
    else
    {
        Write-Host "`tMap data passed to FixDRVMNetworkAdapters is not an array."
        $successful = $false
    }

    return $successful
}

function FinalReport($map)
{
}

function DoDR($map)
{
    # DR snapmirrors broken - pending
    # NetApp volumes mounted in the namespace - pending
    # Datastore create and relocated - pending
    # VM Folders created - pending
    # VMs added to inventory and relocated - pending

    if(BreakSnapmirrors $map)
    {
        # DR snapmirrors broken - check
        # NetApp volumes mounted in the namespace - pending
        # Datastore create and relocated - pending
        # VM Folders created - pending
        # VMs added to inventory and relocated - pending
        # Fix DR VM network adapters - pending

        # Attempt to mount the volumes in the NetApp Namespace...
        if(CheckAndMountDRVMWareVolumes $map)
        {
            # DR snapmirrors broken - check
            # NetApp volumes mounted in the namespace - check
            # Datastore create and relocated - pending
            # VM Folders created - pending
            # VMs added to inventory and relocated - pending
            # Fix DR VM network adapters - pending

            # Attempt add the datastore for the volume to all DR VM hosts
            if(AddDRDatastores $map)
            {
                # DR snapmirrors broken - check
                # NetApp volumes mounted in the namespace - check
                # Datastore create and relocated - check
                # VM Folders created - pending
                # VMs added to inventory and relocated - pending
                # Fix DR VM network adapters - pending

                # Attempt to create all VM folders required for the various DR VMs
                if(CreateAllVMFolders $map)
                {
                    # DR snapmirrors broken - check
                    # NetApp volumes mounted in the namespace - check
                    # Datastore create and relocated - check
                    # VM Folders created - check
                    # VMs added to inventory and relocated - pending
                    # Fix DR VM network adapters - pending

                    # Attempt to add all DR VMs to vSphere inventory...
                    if(AddDRVMsToInventory $map)
                    {
                        # DR snapmirrors broken - check
                        # NetApp volumes mounted in the namespace - check
                        # Datastore create and relocated - check
                        # VM Folders created - check
                        # VMs added to inventory and relocated - check
                        # Fix DR VM network adapters - pending

                        # Attempt to fix all DR VMs's network adapters...
                        if(FixDRVMNetworkAdapters $map)
                        {
                            # DR snapmirrors broken - check
                            # NetApp volumes mounted in the namespace - check
                            # Datastore create and relocated - check
                            # VM Folders created - check
                            # VMs added to inventory and relocated - check
                            # Fix DR VM network adapters - check

                            FinalReport $map
                        }
                        else
                        {
                            Write-Host "Failed to fix all DR VMs network adapters."
                        }
                    }
                    else
                    {
                        Write-Host "Failed to add DR VMs to vSphere inventory."
                    }
                }
                else
                {
                    Write-Host "Failed to check/create all required VM folders."
                }
            }
            else
            {
                Write-Host "Failed to add datastores to $($vcDr.Name)."
            }
        }
        else
        {
            Write-Host "Failed to mount VMWare volumes on $($cdot02.Name):$($drSVMName)!"
        }
    }
    else
    {
        Write-Host "Failed to break snapmirrors for VMware volumes."
    }
}

function Main($whichFunction, $configFile)
{
    if($useSIMSwitch)
    {
        $drVMDistributedSwitchName = "$($drVMDistributedSwitchBaseName) (sim)"
    }
    else
    {
        $drVMDistributedSwitchName = "$($drVMDistributedSwitchBaseName)"
    }
    if(![String]::IsNullOrEmpty($whichFunction))
    {
        if(HaveGlobals $whichFunction)
        {
            if(![String]::IsNullOrEmpty($configFile))
            {
                switch($whichFunction.ToUpper())
                {
                    "CREATEDRMAP"
                    {
                        $drMap = CreateDRMapFromProduction
                        if($drMap.Length -gt 0)
                        {
                            Write-Host "`r`nDR data map containing $($drMap.Length) records written to $($configFile)."
                            $drMap | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile
                        }
                        else
                        {
                            Write-Host "`r`nERROR: DR data map is empty.  Not written to $($configFile)."
                        }
                    }

                    "DODR"
                    {
                        $drMap = @(RehydrateDRMap $configFile)
                        if($drMap.Length -gt 0)
                        {
                            DoDR $drMap
                        }
                        else
                        {
                            Write-Host "Failed to rehydrate DR map from $($configFile)."
                        }
                    }
                }
            }
            else
            {
                Write-Host "Missing value for `$configFile in Main!"
            }
        }
        else
        {
            Usage $whichFunction
        }
    }
    else
    {
        Write-Host "Missing value for `$whichFunction in Main!"
    }
}
