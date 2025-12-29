function ReportError
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Red ("ERROR: {0}" -f @($message))
}

function ReportWarning
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Yellow ("WARNING: {0}" -f @($message))
}

function ReportNotice
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor White $message
}

function ReportSuccess
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [string] $message
    )

    Write-Host -ForegroundColor Green $message
}

function CreateVDS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $datacenterID,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $false
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                $uplinkNames = @($dsConfig.uplinkMappings | Select-Object -Unique -ExpandProperty uplinkName)

                if ($uplinkNames.Length -gt 0)
                {
                    # TRUE

                    # The following is sort of backwards, but the expected behavior is for Get-VDSwitch to throw an
                    #   exception if there in no distributed switch named $dsConfig.switchName -- which is what we want.
                    try
                    {
                        $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                        ReportError ("Distributed switch {0} already exists." -f @($dsConfig.name))
                        $vds = $null    # So we don't report the switch needs to be removed.
                    }
                    catch
                    {
                        try
                        {
                            # Get the datacenter where the new distributed switch will live
                            $vdsDatacenter = Get-Datacenter -Server $viServer -Id $datacenterID -ErrorAction Stop

                            # Create the new distributed switch
                            try
                            {
                                $vds = New-VDSwitch -Server $viServer -Name $dsConfig.name -Location $vdsDatacenter -NumUplinkPorts $dsConfig.uplinkMappings.Length -LinkDiscoveryProtocol "CDP" -LinkDiscoveryProtocolOperation "BOTH" -Mtu $dsConfig.mtu -Version $dsConfig.version -ErrorAction Stop

                                if ($doReportSuccess)
                                {
                                    # TRUE

                                    ReportSuccess ("Created distributed switch {0} under {1}." -f @($vds.Name, $vdsDatacenter.Name))
                                }
                                else # NOT ($doReportSuccess)
                                {
                                    # FALSE

                                    # Nothing.
                                }

                                # It is not imperative we rename the uplink port group, it's just cleaner to me.
                                try
                                {
                                    # Retrieve the uplinks port group on the new distributed switch
                                    $uplinkPortGroup = Get-VDPortGroup -VDSwitch $vds -ErrorAction Stop | Where-Object { $_.IsUplink }
                                    $uplinkName = "~{0} Uplinks" -f @($vds.Name)

                                    try
                                    {
                                        # Rename the uplinks port group on the new distributed switch
                                        $uplinkPortGroup | Set-VDPortgroup -Name $uplinkName -ErrorAction Stop

                                        if ($doReportSuccess)
                                        {
                                            # TRUE

                                            ReportNotice ("`tRenamed uplink port group to {0}." -f @($uplinkName))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # FALSE

                                            # Nothing.
                                        }
                                    }
                                    catch
                                    {
                                        ReportWarning ("Failed to rename uplink port group to {0}." -f @($uplinkName))
                                    }
                                }
                                catch
                                {
                                    ReportWarning ("Failed to retrieve default uplinks port group for {0}." -f @($vds.Name))
                                }

                                # Rename all the uplinks

                                try
                                {
                                    $vds = $null
                                    # Re-aquire the distributed switch so we have a valid ConfigVersion below
                                    $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                                    # Create a new spec to rename an uplink
                                    $spec = [VMware.Vim.DVSConfigSpec]::new()
                                    $spec.ConfigVersion = $vds.ExtensionData.Config.ConfigVersion
                                    $spec.UplinkPortPolicy = [VMware.Vim.DVSNameArrayUplinkPortPolicy]::new()

                                    # Add all the uplink names to the specification
                                    $dsConfig.uplinkMappings | ForEach-Object { $spec.UplinkPortPolicy.UplinkPortName += $_.uplinkName }

                                    try
                                    {
                                        # Submit the reconfigure DVS task to vCenter.
                                        $vds.ExtensionData.ReconfigureDvs($spec)

                                        if ($doReportSuccess)
                                        {
                                            # TRUE

                                            ReportSuccess ("`tRenamed uplinks to {0}." -f @(@((@($dsConfig.uplinkmappings | Select-Object -SkipLast 1 -ExpandProperty uplinkName) -join ", "), ($dsConfig.uplinkmappings | Select-Object -Last 1 -ExpandProperty uplinkName)) -join " and "))
                                        }
                                        else # NOT ($doReportSuccess)
                                        {
                                            # FALSE

                                            # Nothing.
                                        }

                                        try
                                        {
                                            # Enable Network I/O Control for the new distributed switch
                                            $vds.ExtensionData.EnableNetworkResourceManagement($true)

                                            $goodToGo = $true
                                            if ($doReportSuccess)
                                            {
                                                # TRUE

                                                ReportSuccess ("`tEnabled network I/O control on {0}." -f @($vds.Name))
                                            }
                                            else # NOT ($doReportSuccess)
                                            {
                                                # FALSE

                                                # Nothing.
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to enable network I/O control on {0}.  Check vCenter logs." -f @($vds.Name))
                                        }
                                    }
                                    catch
                                    {
                                        ReportError ("Failed to rename uplink {0}.  Check vCenter logs." -f @($uplinkNames[$a]))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to re-acquire distributed switch {0}." -f @($dsConfig.name))
                                }
                            }
                            catch
                            {
                                ReportError ("Failed to create distributed switch {0}.  Consult vCenter logs." -f @($dsConfig.name))
                            }
                        }
                        catch
                        {
                            ReportError ("Unable to locate datacenter {0} in vCenter." -f @($datacenterID))
                        }
                    }
                }
                else # NOT ($uplinkNames.Length -gt 0)
                {
                    # FALSE

                    ReportError "No uplink names found in distributed switch definition."
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }

    if (-not $goodToGo)
    {
        # TRUE

        if ($null -ne $vds)
        {
            # TRUE

            ReportWarning ("Please manually continue the creation of {0}, or correct the problem, remove the distributed switch if possible and retry to create it." -f @($dsConfig.name))
        }
        else # NOT ($null -ne $vds)
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT (-not $goodToGo)
    {
        # FALSE

        # Nothing.
    }

    return $vds
}

function CreatePortGroups
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Object] $dsConfig,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $DoIt,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $doReportSuccess
    )

    $goodToGo = $true
    $vds = $null
    if ($null -ne $viServer)
    {
        # TRUE

        if ($viServer.IsConnected)
        {
            # TRUE

            if ($null -ne $dsConfig)
            {
                # TRUE

                try
                {
                    $vds = Get-VDSwitch -Server $viServer -Name $dsConfig.name -ErrorAction Stop

                    $a = 0
                    while($goodToGo -and ($a -lt $dsConfig.portGroups.Length))
                    {
                        $vpg = $null
                        try
                        {
                            $vpg = Get-VDPortgroup -Server $viServer -VDSwitch $vds -Name $dsConfig.portGroups[$a].name -ErrorAction Stop

                            ReportWarning ("{0} already contains a distributed port group named {1}." -f @($vds.Name, $vpg.Name))
                        }
                        catch
                        {
                            # Set up the parameters to create a new port group
                            $newPortGroupParams = @{
                                VDSwitch = $vds
                                Name = $dsConfig.portGroups[$a].name
                                VlanId = $dsConfig.portGroups[$a].vlanID
                                PortBinding = $dsConfig.portGroups[$a].portBinding
                                ErrorAction = "Stop"
                            }

                            # Not all port groups are bound to a VLAN
                            if ($null -eq $dsConfig.portGroups[$a].vlanID)
                            {
                                # TRUE

                                $newPortGroupParams.Remove("VlanID")
                            }
                            else # NOT ($null -eq $dsConfig.portGroups[$a].vlanID)
                            {
                                # FALSE

                                # Nothing.
                            }

                            if ($doIt)
                            {
                                # TRUE

                                try
                                {
                                    $vpg = New-VDPortgroup @newPortGroupParams

                                    if ($doReportSuccess)
                                    {
                                        # TRUE

                                        ReportSuccess ("`tCreated port group {0} on {1}." -f @($vpg.Name, $vds.Name))
                                    }
                                    else # NOT ($doReportSuccess)
                                    {
                                        # FALSE

                                        # Nothing.
                                    }

                                    # Now set the teaming policy for the port group.

                                    $teamingPolicyParams = @{
                                        ActiveUplinkPort = $dsConfig.portGroups[$a].activeUplinkNames
                                        StandbyUplinkPort = $dsConfig.portGroups[$a].standbyUplinkNames
                                        UnusedUplinkPort = @(@($dsConfig.uplinkMappings | Select-Object -Unique -ExpandProperty uplinkName) | Where-Object { ($_ -notin $dsConfig.portGroups[$a].activeUplinkNames) -and ($_ -notin $dsConfig.portGroups[$a].standbyUplinkNames) })
                                    }

                                    # Remove any of the teaming policy parameters that are empty
                                    if($teamingPolicyParams.ActiveUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("ActiveUplinkPort")
                                    }
                                    if($teamingPolicyParams.StandbyUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("StandbyUplinkPort")
                                    }
                                    if($teamingPolicyParams.UnusedUplinkPort.Count -eq 0)
                                    {
                                        $teamingPolicyParams.Remove("UnusedUplinkPort")
                                    }

                                    if ($teamingPolicyParams.Count -gt 0)
                                    {
                                        # TRUE

                                        try
                                        {
                                            $teamingPolicy = $vpg | Get-VDUplinkTeamingPolicy -Server $viServer -ErrorAction Stop

                                            if ($null -ne $teamingPolicy)
                                            {
                                                # TRUE

                                                try
                                                {
                                                    [void] ($teamingPolicy | Set-VDUplinkTeamingPolicy @teamingPolicyParams -ErrorAction Stop)

                                                    if ($doReportSuccess)
                                                    {
                                                        # TRUE

                                                        ReportSuccess ("`tTeaming policy successfully set.")
                                                    }
                                                    else # NOT ($doReportSuccess)
                                                    {
                                                        # FALSE

                                                        # Nothing.
                                                    }
                                                }
                                                catch
                                                {
                                                    ReportError ("Failed to set teaming policy for {0}." -f @($vpg.Name))
                                                    $goodToGo = $false
                                                }
                                            }
                                            else # NOT ($null -ne $teamingPolicy)
                                            {
                                                # FALSE

                                                ReportError ("Failed to retrieve teaming policy for {0}." -f @($vpg.Name))
                                                $goodToGo = $false
                                            }
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to retrieve teaming policy for {0}." -f @($vpg.Name))
                                            $goodToGo = $false
                                        }
                                    }
                                    else # NOT ($teamingPolicyParams.Count -gt 0)
                                    {
                                        # FALSE

                                        ReportWarning ("{0} has no uplinks." -f @($vpg.Name))
                                    }
                                }
                                catch
                                {
                                    ReportError ("Failed to add distributed port group {0} to {1}." -f @($dsConfig.portGroups[$a].name, $vds.Name))
                                    $goodToGo = $false
                                }
                            }
                            else # NOT ($doIt)
                            {
                                # FALSE

                                ReportNotice ("Simulated creating port group {0} on {1}." -f @($dsConfig.portGroups[$a].name, $vds.Name))
                            }
                        }
                        $a++
                    }
                }
                catch
                {
                    ReportError ("Distributed switch {0} does not exist." -f @($dsConfig.name))
                    $goodToGo = $false
                }
            }
            else # NOT ($null -ne $dsConfig)
            {
                # FALSE

                ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
                $goodToGo = $false
            }
        }
        else # NOT ($viServer.IsConnected)
        {
            # FALSE

            ReportError ("Not connected to {0} in {1}." -f @($viServer.Name, $MyInvocation.MyCommand.Name))
            $goodToGo = $false
        }
    }
    else # NOT ($null -ne $viServer)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
        $goodToGo = $false
    }

    return $goodToGo
}

function CreateTopFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String[]] $topFolders
    )

    # Create top level folders
    $rootFolder = Get-Folder -Server $viServer -Type Datacenter

    $a = 0
    while($a -lt $topFolders.Length)
    {
        $fldr = New-Folder -Server $viServer -Name $topFolders[$a] -Location $rootFolder
        $a++
    }
}

function CreateClusters
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl] $location,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [String[]] $clusterNames
    )

    $a = 0
    while($a -lt $clusterNames.Length)
    {
        $newClusterParams = @{
            Server = $viServer
            Name = $clusterNames[$a]
            Location = $location
            HARestartPriority = [VMware.VimAutomation.ViCore.Types.V1.Cluster.HARestartPriority]::Medium
            HAIsolationResponse = [VMware.VimAutomation.ViCore.Types.V1.Cluster.HAIsolationResponse]::DoNothing
            VMSwapfilePolicy = [VMware.VimAutomation.ViCore.Types.V1.VMSwapfilePolicy]::WithVM
            HAFailoverLevel = 1
            DrsAutomationLevel = [VMware.VimAutomation.ViCore.Types.V1.Cluster.DrsAutomationLevel]::FullyAutomated
            EVCMode = "intel-skylake"
        }

        $newCluster = New-Cluster @newClusterParams
        Set-Cluster -Server $viServer -Cluster $newCluster -HAEnabled $false -DrsEnabled $false -VsanEnabled $false -Confirm:$false #-HAAdmissionControlEnabled $false
        $a++
    }
}

function CreateDatacentersAndClusters
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $viServer,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [String] $pFolderName,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl] $location,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [String[]] $dcNames,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [String[]] $clusterNames
    )

    # Create EDC Datacenters...
    # $fldrName = "EDC"
    # $fldrName = "OFFICE"
    # $fldrName = "RDC"

    $fldr = Get-Folder -Server $viServer -Name $pFolderName -Location $location

    # $dcNames = @("CH3", "DE2")
    # $dcNames = @("BOI")
    # $dcNames = @("AT4", "CH3", "DA11", "LAS04", "NY7", "SE4", "YYC01")

    $b = 0
    while($b -lt $dcNames.Length)
    {
        try
        {
            $dc = Get-Datacenter -Server $viServer -Name $dcNames[$b] -Location $fldr -ErrorAction Stop
        }
        catch
        {
            $dc = New-Datacenter -Server $viServer -Location $fldr -Name $dcNames[$b]
        }

        CreateClusters -viServer $viServer -location $dc -clusterNames $clusterNames
        $b++
    }
}

$foldersAndClusters = @(
    @{
        pFolderName = "EDC"
        dcNames = @("CH3", "DE2")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "OFFICE"
        dcNames = @("BOI")
        clusterNames = @("PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("AT4")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("CH3")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("DA11")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("LAS04")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("NY7")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("SE4")
        clusterNames = @("DMZ", "PROD")
    },
    @{
        pFolderName = "RDC"
        dcNames = @("YYC01")
        clusterNames = @("DMZ", "PROD")
    }
)

# Create top level folders
CreateTopFolders -viServer $vc01 -topFolders @("EDC","RDC","OFFICE")


# Create the bulk of the datacenters and clusters
$rootFolder = Get-Folder -Server $vc01 -Type Datacenter

$a = 0
while($a -lt $foldersAndClusters.Length)
{
    CreateDatacentersAndClusters -viServer $vc01 -pFolderName $foldersAndClusters[$a].pFolderName -location $rootFolder -dcNames $foldersAndClusters[$a].dcNames -clusterNames $foldersAndClusters[$a].clusterNames

    $a++
}

# Create CH3-EDC VCAD folders and clusters
$edcFolder = Get-Folder -Server $vc01 -Name "EDC" -Location $rootFolder
$ch3EDCDC = Get-Datacenter -Server $vc01 -Name "CH3" -Location $edcFolder
$ch3VCADFolder = New-Folder -Server $vc01 -Name "VCAD" -Location $ch3EDCDC
CreateClusters -viServer $viServer -location $ch3VCADFolder -clusterNames @("P6","T4","A16")

# Create DE2-EDC VCAD folders and clusters
$de2EDCDC = Get-Datacenter -Server $vc01 -Name "DE2" -Location $edcFolder
$de2VCADFolder = New-Folder -Server $vc01 -Name "VCAD" -Location $de2EDCDC
CreateClusters -viServer $viServer -location $de2VCADFolder -clusterNames @("P6","T4","A16")

# Create the various distributed switches
#  BOI will be created manually since it's different.
$vdsDefs = Get-ChildItem -Path "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\VMWare\MigratevCenter\vdsDefs" -Filter "*.json"
$a = 0
while($a -lt $vdsDefs.Length)
{
    $virtualizationDefinition = Get-Content -Path $vdsDefs[$a].FullName | ConvertFrom-Json
    $vds = CreateVDS -viServer $vc01 -datacenterID $virtualizationDefinition.datacenterID -dsConfig $virtualizationDefinition.switch -DoIt -doReportSuccess
    $null = CreatePortGroups -viServer $vc01 -dsConfig $virtualizationDefinition.switch  -DoIt -doReportSuccess

    $a++
}

$oldVCenterVMFolders = Get-Folder -Server $vCenter -Type VM
$oldRootFolder = $oldVCenterVMFolders | Where-Object { $null -eq $_.Parent }

$oldRootVMFolder = Get-Folder -Server $vCenter -NoRecursion

$a = 0
while($a -lt $oldRootVMFolder.ExtensionData.ChildEntity.Length)
{
    $e = $oldRootVMFolder.ExtensionData.ChildEntity[$a]

    while($null -ne $e)
    {
        $i = Get-Inventory -Server $vCenter -Id $e
    }

    $a++
}

$vms = @(Get-VM -Server $vCenter)
$folders = Get-Folder -Server $vCenter
$roles = Get-VIRole -Server $vCenter
$folderList = [System.Collections.Generic.List[String]]::new()
$folderPermissions = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[System.Object]]]]::new()
$sb = [System.Text.StringBuilder]::new()

$a = 0
while($a -lt $vms.Length)
{
    [void] $sb.Clear()
    $vm = $vms[$a]
    $vmFolder = $vm.Folder

    if(($null -ne $vmFolder) -and ($null -ne $vmFolder.ExtensionData.Permission) -and ($vmFolder.ExtensionData.Permission.Count -gt 0))
    {
        if(-not $folderPermissions.ContainsKey($vmFolder.Id.ToString()))
        {
            $folderPermissions.Add($vmFolder.Id.ToString(), [System.Collections.Generic.List[System.Object]]::new())
        }
        $b = 0
        while($b -lt $vmFolder.ExtensionData.Permission.Count)
        {
            $d = "" | Select-Object FolderID,RoleID, Principal
            $d.RoleID = $vmFolder.ExtensionData.Permission[$b].RoleId
            $d.Principal = $vmFolder.ExtensionData.Permission[$b].Principal

            $existingRolePerms = @($folderPermissions[$vmFolder.Id.ToString()] | Where-Object { ($_.RoleID -eq $d.RoleID) -and ($_.Principal -eq $d.Principal)})
            if($existingRolePerms.Length -eq 0)
            {
                $folderPermissions[$vmFolder.Id.ToString()].Add($d)
                $role = $roles | Where-Object { $_.Id -eq $d.RoleID }
                if($null -ne $role)
                {
                    $roleStr = $role.Name
                } `
                else
                {
                    $roleStr = "NF"
                }
                [void] $sb.AppendLine(("`tFolderID: {0}`t`tRoleID: {1} ({2})`t`tPrincipal: {3}" -f @($vmFolder.Id.ToString(), $d.RoleID, $roleStr, $d.Principal)))
            }
            $b++
        }
    }

    $folderList.Clear()
    while($null -ne $vmFolder.Parent)
    {
        $folderList.Add($vmFolder.Name)
        $vmFolder = $vmFolder.Parent
        if(($null -ne $vmFolder) -and ($null -ne $vmFolder.ExtensionData.Permission) -and ($vmFolder.ExtensionData.Permission.Count -gt 0))
        {
            if(-not $folderPermissions.ContainsKey($vmFolder.Id.ToString()))
            {
                $folderPermissions.Add($vmFolder.Id.ToString(), [System.Collections.Generic.List[System.Object]]::new())
            }
            $b = 0
            while($b -lt $vmFolder.ExtensionData.Permission.Count)
            {
                $d = "" | Select-Object FolderID,RoleID, Principal
                $d.RoleID = $vmFolder.ExtensionData.Permission[$b].RoleId
                $d.Principal = $vmFolder.ExtensionData.Permission[$b].Principal

                $existingRolePerms = @($folderPermissions[$vmFolder.Id.ToString()] | Where-Object { ($_.RoleID -eq $d.RoleID) -and ($_.Principal -eq $d.Principal)})
                if($existingRolePerms.Length -eq 0)
                {
                    $folderPermissions[$vmFolder.Id.ToString()].Add($d)
                    $role = $roles | Where-Object { $_.Id -eq $d.RoleID }
                    if($null -ne $role)
                    {
                        $roleStr = $role.Name
                    } `
                    else
                    {
                        $roleStr = "NF"
                    }
                    [void] $sb.AppendLine(("`tFolderID: {0}`t`tRoleID: {1} ({2})`t`tPrincipal: {3}" -f @($vmFolder.Id.ToString(), $d.RoleID, $roleStr, $d.Principal)))
                }
                $b++
            }
        }
    }
    $folderList.Add($vmFolder.Name)
<#
    while(-not $vmFolder.ParentId.StartsWith("Datacenter-datacenter"))
    {
        $folderList.Add($vmFolder.Name)
        $vmFolder = $folders | Where-Object { $_.Id -eq $vmFolder.ParentId }
    }
#>
    $folderList.Reverse()
    $folderList.Insert(0,$vm.Name)
    Write-Host ("{0}" -f @(($folderList -join "||")))
    if($sb.Length -gt 0)
    {
        Write-Host ("{0}" -f @($sb.ToString()))
    }

    $a++
}




$prodInventory = Get-Inventory -Server $vCenter
$permData = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $prodInventory.Length)
{
    try
    {
        $perms = @(Get-VIPermission -Server $vCenter -Entity $prodInventory[$a] -ErrorAction Stop)
        $b = 0
        while($b -lt $perms.Length)
        {
            $d = "" | Select-Object Name,ID,Principal,Role,Propagate
            $d.Name = $prodInventory[$a].Name
            $d.ID = $prodInventory[$a].Id
            $d.Principal = $perms[$b].Principal
            $d.Role = $perms[$b].Role
            $d.Propagate = $perms[$b].Propagate
            $permData.Add($d)
            if([Console]::KeyAvailable)
            {
                Write-Host ("{0}/{1}: {2}`t{3}`t{4}`t{5}`t{6}" -f @(($a+1), ($b+1), $prodInventory[$a].Name, $prodInventory[$a].Id, $perms[$b].Principal, $perms[$b].Role, $perms[$b].Propagate))
                $k = [Console]::ReadKey($false)
            }
            $b++
        }

    }
    catch
    {

    }
    $a++
}

$a = 0
$vms = Get-VM -Server $vCenter -ErrorAction Stop | Where-Object { $_.Name -notmatch "^vCLS\-" }
$folders = Get-Folder -Server $vc01
while($a -lt $vms.Length)
{
    $migrationRecords = @($vmMigrationData | Where-Object { $_.VMID -eq $vms[$a].Id })
    if($migrationRecords.Length -gt 0)
    {
        $b = 0
        while($b -lt $migrationRecords.Length)
        {
            $vmFolders = @($folders | Where-Object { $_.Id -eq $migrationRecords[$b].FolderID })
            if($vmFolders.Length -gt 0)
            {
                $c = 0
                while($c -lt $vmFolders.Length)
                {
                    Write-Host ("{0}: {1} --> {2}" -f @(($c + 1), $vms[$a].Name, $vmFolders[$c].Name))
                    $c++
                }
            }
            else
            {
                Write-Host ("Unable to locate folder for VM: {0}/{1}" -f @($vms[$a].Name, $vms[$a].Id))
            }

            $b++
        }
    }
    else
    {
        Write-Host ("Unable to locate migration record for VM: {0}/{1}" -f @($vms[$a].Name, $vms[$a].Id))
    }

    $a++
}

<#   Export Existing VM data prior to migration #>
$exportData = [System.Collections.Generic.List[System.Object]]::new()
$viServer = $vCenter
$vms = @(Get-VM -Server $viServer | Where-Object { $_.Name -notmatch "^vCLS\-" })
$a = 0
while($a -lt $vms.Length)
{
    try
    {
        $netAdapters = @($vms[$a] | Get-NetworkAdapter -Server $viServer -ErrorAction Stop)
        $b = 0
        while($b -lt $netAdapters.Length)
        {
            $d = "" | Select-Object Name,ID,Folder,FolderID,PersistentId,UUID,NAName,NAType,NName,MACAddress,AddressType

            $d.Name = $vms[$a].Name
            $d.ID = $vms[$a].Id
            $d.Folder = $vms[$a].Folder
            $d.FolderID = $vms[$a].FolderId
            $d.PersistentId = $vms[$a].PersistentId
            $d.UUID = $vms[$a].ExtensionData.Config.Uuid
            $d.NAName = $netAdapters[$b].Name
            $d.NAType = $netAdapters[$b].Type
            $d.NName = $netAdapters[$b].NetworkName
            $d.MACAddress = $netAdapters[$b].MacAddress
            $d.AddressType = $netAdapters[$b].ExtensionData.AddressType

            $exportData.Add($d)
            $b++
        }
    }
    catch
    {
        Write-Host -ForegroundColor Yellow ("No network adapters found for VM: {0}/{1}." -f @($vms[$a].Name, $vms[$a].Id))
    }
    $a++
}

$exportData | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
