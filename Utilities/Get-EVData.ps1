[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

# For Debugging
# $JSONArgsFile = "C:\Users\kbriney\KLB\PEI-IT-OPS\Utilities\VirtualInventory\invCfg.json"
# Set-Location -Path "C:\Users\kbriney\KLB\PEI-IT-OPS\Utilities\VirtualInventory"

<#

    This script collects virtual inventory data from various sources.

        1. Connect to Cisco Intersight to collect inventory data for UCS chasses, Fabric Interconnects, and servers.
        2. Connect to xClarity to collect inventory data for all Lenovo (IBM) servers.
        3. Connect to vCenter to update the operating system versions for Cisco and Lenovo ESXi servers and to add "unregistered" servers to 
           the export data.
        4. Export all Intersight data (it contains chasses, FIs, and servers)
        5. Export xClarity data, but only for active ESXi hosts.  Some servers are Microsoft Windows hosts and are covered via a SCCM export.
        6. Export "unregistered" ESXi servers.
        7. Connect to all the listed NetApp filers (Clustered Mode and 7-Mode) listed in the configuration data to collect inventory data
           from them.  Filers and intercluster switches are exported.
        8. Pull data from Statseeker via its API.  Currently, I'm only able to find Juniper and Riverbed data that is usable.

        The IPAM database is used to determine the location of a device.  This is completed by either looking up a devices name or IP address in
           the database (host table).
#>

<#
    Wrapper function for making an API call to Intersight.

    I found I was repeating the same steps over and over when calling most Intersight APIs, so I decided to wrap the calls in this function.
#>
function Query-Intersight
{
    [CmdletBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Position = 0, Mandatory = $true)]
        [Object]
        $invCfg,

        [Parameter(Position = 1, Mandatory = $true)]
        [String]
        $apiCallName,

        [Parameter(Position = 2, Mandatory = $false)]
        [Boolean]
        $count = $false,

        [Parameter(Position = 3, Mandatory = $false)]
        [String]
        $inlinecount = $null,

        [Parameter(Position = 4, Mandatory = $false)]
        [Int32]
        $top = $null,

        [Parameter(Position = 5, Mandatory = $false)]
        [Int32]
        $skip = $null,

        [Parameter(Position = 6, Mandatory = $false)]
        [String]
        $filter = $null,

        [Parameter(Position = 7, Mandatory = $false)]
        [String]
        $select = $null,

        [Parameter(Position = 8, Mandatory = $false)]
        [String]
        $orderby = $null,

        [Parameter(Position = 9, Mandatory = $false)]
        [String]
        $expand = $null
    )

    # The results of the API call to Intersight ... if any.
    $results = $null

    if(-not [String]::IsNullOrEmpty($apiCallName))
    {
        $apiCallFound = $false
        try { Get-ChildItem -Path Function:\$apiCallName -ErrorAction Stop | Out-Null; $apiCallFound = $true } catch { }
        if($apiCallFound)
        {
            [Log]::Trace("Cisco Intersight API call: {0}" -f @($apiCallName))
    
            # Make sure New-IntersightApiClient is not called multiple times.
            if(-not $Global:intersightClientCreated)
            {
                # First, create an Intersight API Client...
                [Log]::Info("API Key: {0}" -f @($invCfg.Intersight.APIKey))
                [Log]::Info("Private Key file: {0}" -f @($invCfg.Intersight.PrivateKeyFile))
                New-IntersightApiClient $invCfg.Intersight.URL $invCfg.Intersight.PrivateKeyFile $invCfg.Intersight.APIKey
                $Global:intersightClientCreated = $true
            }

            $retries = 0
            do
            {
                if($retries -gt 0)
                {
                    [Log]::Info("Intersight Query: {0}, Retry: {1}" -f @($apiCallName, $retries))
                }

                try
                {
                    $apiResponse = & $apiCallName $count $inlinecount $top $skip $filter $select $orderby $expand -ErrorAction Stop
                    $apiResponseStr = $apiResponse | ConvertTo-Json -Depth 10
                    [Log]::Trace($apiResponseStr)
                }
                catch
                {
                    $errorMessage = $_.Exception.Message
                    $failedItem = $_.Exception.ItemName
                    [Log]::Info("Failed Item: {0}`tError Message: {1}" -f @($failedItem, $errorMessage))
                    $retries++
                    Start-Sleep -Milliseconds 100
                }
            } while((($null -eq $apiResponse) -or ($null -eq $apiResponse.Results)) -and ($retries -lt 5))

            # Be sure we received a response back from Intersight
            if($null -ne $apiResponse)
            {
                # Default to returning the direct API response object, however...
                $results = $apiResponse

                # ... if there is a "Results" property, return it
                if($null -ne $apiResponse.Results)
                {
                    # Shortcut to the results
                    $results = $apiResponse.Results
                }
                else
                {
                    # Nothing, just return the API call response object
                }
            }
            else
            {
                [Log]::Error("No response from Cisco Intersight [{0}]." -f @($apiCallName))
            }
        }
        else
        {
            [Log]::Error("Unknown API call: {0}" -f @($apiCallName))
        }
    }
    else
    {
        [Log]::Error("Missing Intersight query API call name.")
    }

    return $results
}

<#
    Collect inventory data from Cisco Intersight.

    Return: [EVDataPoint][]

#>
function Collect-IntersightData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    [Log]::Info("Collecting Cisco Intersight data...")
    
    # Create an object to collect the data we need.
    $intersightData = $null

    # Not going to retest $invCfg because this function should not be reachable unless it's all good.

    # While debugging, make sure New-IntersightApiClient is not called multiple times.
    if($null -eq $Global:intersightClientCreated)
    {
        [Log]::Trace("Creating Cisco Intersight API Client.")
        [Log]::Trace("`tAPI Key: {0}" -f @($invCfg.Intersight.APIKey))
        [Log]::Trace("`tPrivate Key File: {0}" -f @($invCfg.Intersight.PrivateKeyFile))

        # First, create an Intersight API Client...
        New-IntersightApiClient $invCfg.Intersight.URL $invCfg.Intersight.PrivateKeyFile $invCfg.Intersight.APIKey
        $Global:intersightClientCreated = $true
    }

    <#
        Instead of trying to rely on Cisco Intersights API calls to function correctly when trying to filter the
        results, I've decided to just get ALL of each object type I need, then use PowerShell to filter down to
        the actual object I need.  I tried multiple times to use filtered requests, but kept getting unexplained
        errors mostly, "api_key_invalid" BS!!
    #>

    # Get a list of all the device registrations.
    $allDeviceRegistrations = Query-Intersight $invCfg "Invoke-AssetDeviceRegistrationApiAssetDeviceRegistrationsGet"
    if($null -eq $allDeviceRegistrations)
    {
        [Log]::Warning("No device registrations returned from Cisco Intersight.")
        return $intersightData
    }

    # Get a list of all compute physical summaries.
    $allComputePhysicalSummaries = Query-Intersight $invCfg "Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet"
    if($null -eq $allComputePhysicalSummaries)
    {
        [Log]::Warning("No compute physical summaries returned from Cisco Intersight.")
        return $intersightData
    }

    # Get a list of all equipment chasses...
    $allChassisSummaries = Query-Intersight $invCfg "Invoke-EquipmentChassisApiEquipmentChassesGet"
    if($null -eq $allChassisSummaries)
    {
        [Log]::Warning("No chassis summaries returned from Cisco Intersight.")
        return $intersightData
    }

    # Get a list of all network element summaries...
    $allNetworkElementSummaries = Query-Intersight $invCfg "Invoke-NetworkElementSummaryApiNetworkElementSummariesGet"
    if($null -eq $allNetworkElementSummaries)
    {
        [Log]::Warning("No network element summaries returned from Cisco Intersight.")
        return $intersightData
    }

    # Got all the data we need from Intersight, now setup an array to return the results we need.
    $intersightData = @()

    # Iterate through the devices...
    $d = 0
    while((-not $Global:isError) -and ($d -lt $allDeviceRegistrations.Count))
    {
        # Shortcut to a single device registration
        $device = $allDeviceRegistrations[$d]

        # Process the device based on the platform type.
        #  As of this version, we only have "UCSFI" and "IMCM5" device registrations.

        switch($device.PlatformType)
        {
            # Convert this to a function...
            "UCSFI"  # Fabric Interconnect
            {
                # Make sure there is host name for the device.
                if($device.DeviceHostname.Count -gt 0)
                {
                    # Let's pretend we don't have all the relevant data for the chassis...until we do.
                    $haveChassisData = $false

                    # Get the chassis summary for this device.
                    $chassisSummaries = @($allChassisSummaries | Where-Object { $_.DeviceMoId -eq $device.Moid })
                                
                    if($chassisSummaries.Length -eq 1)
                    {
                        $chassisSummary = $chassisSummaries[0]

                        # Create a new EasyVista datapoint for the chassis
                        $chassisDataPoint = [EVDataPoint]::new($device.DeviceHostname[0], $chassisSummary)

                        [Log]::Info("`t+Chassis: {0}, {1}, {2}" -f @($chassisDataPoint.Manufacturer, $chassisDataPoint.Model, $chassisDataPoint.SerialNumber))
                        $intersightData += $chassisDataPoint

                        # The chassis IP address is part of the "network elements".  The Ipv4Address property appears to be the management VIP, while the OutOfBandIpAddress property is the actual IP address
                        #    assigned to the FI.

                        # Flag to signal we can continue collecting FI and compute data for this chassis.
                        $haveChassisData = $true
                    }
                    elseif($chassisSummaries.Length -gt 1)
                    {
                        [Log]::Error("Too many chassis summaries returned ({0}) for DeviceMoid = {1}" -f @($chassisSummaries.Count, $device.Moid))
                    }
                    else
                    {
                        [Log]::Warning("No chassis summary with DeviceMoid = {0}" -f @($device.Moid))
                    }
                }
                else
                {
                    [Log]::Error("No host name for device with Moid = {0}." -f @($device.Moid))
                }

                # If we managed to collect the relevant data for the chassis, continue...

                if($haveChassisData)
                {
                    # Get a list of network elements (FIs) that belong to this device
                    $elementSummaries = @($allNetworkElementSummaries | Where-Object { $_.RegisteredDevice.Moid -eq $device.Moid })

                    # Be sure we received a response back from Intersight
                    if($null -ne $elementSummaries)
                    {
                        # Iterate the list of fabric interconnects.
                        $e = 0
                        while($e -lt $elementSummaries.Count)
                        {
                            # Shortcut to a single FI...
                            $elementSummary = $elementSummaries[$e]

                            # First, if we have not already set the IP address of the chassis, do so.
                            if([String]::IsNullOrEmpty($chassisDataPoint.IP))
                            {
                                # Make sure the element's IPv4Address property is set.
                                if(-not [String]::IsNullOrEmpty($elementSummary.Ipv4Address))
                                {
                                    $chassisDataPoint.SetIP($elementSummary.Ipv4Address)
                                }
                                else
                                {
                                    [Log]::Warning("No Ipv4Address found for FI with Moid = {0}" -f @($elementSummary.Moid))
                                }
                            }
                            else
                            {
                                # Nothing chassis IP address already set
                            }

                            # Create a new EasyVista datapoint for the FI
                            $elementDataPoint = [EVDataPoint]::new($elementSummary)

                            # Add the FI's data point to the list of intersight data...
                            $intersightData += $elementDataPoint
                            [Log]::Info("`t+FI: {0}, {1}, {2}" -f @($elementDataPoint.Manufacturer, $elementDataPoint.Model, $elementDataPoint.SerialNumber))

                            $e++
                        }
                    }
                    else
                    {
                        # Log warning, no FI information returned.
                        [Log]::Warning("No fabric interconnects found matching filter: {0}" -f @($filter))
                    }

                    # Get a list of compute devices that belong to this chassis
                    $chassisComputePhysicalSummaries = @($allComputePhysicalSummaries | Where-Object { $_.Owners.Contains($device.Moid) })

                    if($chassisComputePhysicalSummaries.Length -gt 0)
                    {
                        $c = 0
                        while($c -lt $chassisComputePhysicalSummaries.Count)
                        {
                            # Shortcut to the current compute physical summary
                            $computePhysicalSummary = $chassisComputePhysicalSummaries[$c]

                            # Create a new EasyVista datapoint for the server
                            $serverDataPoint = [EVDataPoint]::new()

                            $serverDataPoint.SetName($computePhysicalSummary.UserLabel)
                            $serverDataPoint.UpdateFromIPAMByName()

                            # If the IP address was not set via IPAM, then use the server's Ipv4Address
                            if([String]::IsNullOrEmpty($serverDataPoint.IP))
                            {
                                $serverDataPoint.SetIP($computePhysicalSummary.Ipv4Address)
                            }
                            else
                            {
                                # Nothing, IP was set
                            }

                            $serverDataPoint.SetManufacturer($computePhysicalSummary.Vendor)
                            $serverDataPoint.SerialNumber = $computePhysicalSummary.Serial
                            $serverDataPoint.Model = $computePhysicalSummary.Model
                            $serverDataPoint.CurrentVersion = $computePhysicalSummary.Firmware

                            [Log]::Info("`t+Server: {0}, {1}, {2}" -f @($serverDataPoint.Manufacturer, $serverDataPoint.Model, $serverDataPoint.SerialNumber))
                            $intersightData += $serverDataPoint

                            $c++
                        }
                    }
                    else
                    {
                        # Warning, no servers belong to this chassis
                    }
                }
                else
                {
                    # Nothing, already logged an error.
                }

                break
            }

            # Convert this to a function...
            "IMCM5"  # Stand-alone system
            {
                # Get the compute physical summary for this server.
                $physicalSummaries = @($allComputePhysicalSummaries | Where-Object { $_.DeviceMoid -eq $device.Moid })

                if($physicalSummaries.Length -eq 1)
                {
                    # Shortcut for the compute physical summary
                    $computePhysicalSummary = $physicalSummaries[0]

                    # Create a new EasyVista datapoint for the server
                    $serverDataPoint = [EVDataPoint]::new()

                    $serverDataPoint.SetName($computePhysicalSummary.UserLabel)
                    $serverDataPoint.UpdateFromIPAMByName()

                    # If the IP address was not set via IPAM, then use the server's Ipv4Address
                    if([String]::IsNullOrEmpty($serverDataPoint.IP))
                    {
                        $serverDataPoint.SetIP($computePhysicalSummary.Ipv4Address)
                    }

                    $serverDataPoint.SetManufacturer($computePhysicalSummary.Vendor)
                    $serverDataPoint.SerialNumber = $computePhysicalSummary.Serial
                    $serverDataPoint.Model = $computePhysicalSummary.Model
                    $serverDataPoint.CurrentVersion = $computePhysicalSummary.Firmware

                    $intersightData += $serverDataPoint
                    [Log]::Info("`t+Server: {0}, {1}, {2}, {3}." -f @($serverDataPoint.Name, $serverDataPoint.Manufacturer, $serverDataPoint.Model, $serverDataPoint.SerialNumber))
                }
                elseif($physicalSummaries.Length -eq 0)
                {
                    [Log]::Warning("No compute physical summary available for {0}." -f @($device.Moid))
                }
                else
                {
                    [Log]::Warning("Multiple compute physical summaries available for {0}." -f @($device.Moid))
                }
            }

            Default
            {
                [Log]::Warning("Unknown device platform type: {0}" -f @($device.PlatformType))
            }
        }

        $d++
    }

    return $intersightData
}

<#
    Collect inventory data from xClarity.

    Return: [EVDataPoint][]
#>
function Collect-xClarityData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    # Not going to retest $invCfg because this function should not be reachable unless it's all good.

    [Log]::Info("Collecting xClarity data...")

    # Create an object to collect the data we need.
    $xClarityData = @()

    #  Create a credential for connecting to xClarity
    $xClarityCredential = [System.Management.Automation.PsCredential]::new($invCfg.xClarity.UserName, ($invCfg.xClarity.Password | ConvertTo-SecureString))

    try
    {
        #  Try to connect to xClarity and pull an inventory...
        Connect-LXCA $invCfg.xClarity.Server -Credential $xClarityCredential -SkipCertificateCheck | Out-Null

        $xclaritySvrs = @(Get-LXCAServer)

        if ($xclaritySvrs.Length -gt 0)
        {
            # TRUE

            $l = 0
            while($l -lt $xclaritySvrs.Length)
            {
                # Shortcut to the server's data
                $xclaritySvr = $xclaritySvrs[$l]

                # Create a new EasyVista datapoint for the server
                $serverDataPoint = [EVDataPoint]::new()

                $serverDataPoint.SetName($xclaritySvr.Hostname)
                $serverDataPoint.SetIP($xclaritySvr.MgmtProcIPaddress)
                $serverDataPoint.SetManufacturer($xclaritySvr.Manufacturer)
                $serverDataPoint.SerialNumber = $xclaritySvr.SerialNumber
                $serverDataPoint.Model = $xclaritySvr.ProductName
                
                $xServerFW = @($xclaritySvr.Firmwares | Where-Object { $_.Name -eq "UEFI Firmware/BIOS"})
                if($xServerFW.Length -gt 0)
                {
                    $serverDataPoint.CurrentVersion = $xServerFW[0].Version
                }
                else
                {
                    $xServerFW = @($xclaritySvr.Firmwares | Where-Object { $_.Name -eq "UEFI" })
                    if($xServerFW.Length -gt 0)
                    {
                        $serverDataPoint.CurrentVersion = $xServerFW[0].Version
                    }
                    else
                    {
                        # Nothing I guess...
                    }
                }

                # "Correct" firmware version to match xClarity.
                #   Based on conversation with John Wilkerson, when the firmare looks like: VVE168DUS-3.10 or D7E172DUS-3.10, all
                #   they want is the 3.10.

                if (-not [String]::IsNullOrEmpty($serverDataPoint.CurrentVersion))
                {
                    # TRUE

                    if ($serverDataPoint.CurrentVersion -match "`-(\d+\.\d+)")
                    {
                        # TRUE

                        # Just use the part captured in the regular expression capture group (\d+\.\d+) as the firmware version
                        $serverDataPoint.CurrentVersion = $Matches[1]
                    }
                    else # NOT ($serverDataPoint.CurrentVersion -match "`-(\d+\.\d+)")
                    {
                        # FALSE

                        # Nothing, at this point, just leave the firmware as is.
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($serverDataPoint.CurrentVersion)
                {
                    # FALSE

                    # Nothing, no firmware version to "correct"
                }

                [Log]::Info("`t+Server: {0}, {1}, {2}, {3}" -f @($serverDataPoint.Name, $serverDataPoint.Manufacturer, $serverDataPoint.Model, $serverDataPoint.SerialNumber))
                $xClarityData += $serverDataPoint

                $l++
            }

            [Log]::Info("Successfully retrieved xClarity data.")
        }
        else # NOT ($xclaritySvrs.Length -gt 0)
        {
            # FALSE

            [Log]::Error("Unable to retrieve inventory from xClarity server: {0}" -f @($inventoryConfig.xClarity.Server))
        }
    }
    catch
    {
        [Log]::Error("Exception: Unable to connect to connect to xClarity server: {0}" -f @($inventoryConfig.xClarity.Server))
    }

    return $xClarityData
}

<#
    Update data collected from Cisco Intersight and xClarity as well as servers that are not registered with either.

    Return: [EVDataPoint][]
#>
function Collect-vCenterData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg,

        # Data collected from Cisco Intersight
        [Parameter(Mandatory=$true,Position=1)]
        [EVDataPoint[]]
        $intersightData,

        # xClarity data
        [Parameter(Mandatory=$true,Position=2)]
        [EVDataPoint[]]
        $xClarityData
    )

    [Log]::Info("Collecting vCenter data...")

    # Where we collect all EVDataPoints not already in $intersightData or $xClarityData
    $vCenterData = @()

    #  Create a credential for connecting to xClarity
    $vCenterCredential = [System.Management.Automation.PsCredential]::new($invCfg.vCenter.UserName, ($invCfg.vCenter.Password | ConvertTo-SecureString))

    try
    {
        $vc = Connect-VIServer -Server $invCfg.vCenter.Server -Credential $vCenterCredential -NotDefault
        if ($null -ne $vc)
        {
            # TRUE

            # Get all the ESXi hosts vCenter knows about.
            $vmHosts = Get-VMHost -Server $vc | Sort-Object Name

            # Loop through all the VM hosts, checking the UCS and xClarity data for more detailed information for the host.
            $a = 0
            while($a -lt $vmHosts.Length)
            {
                # Temp variable for the next VM Host to process...
                $vmH = $vmHosts[$a]

                # Reset $serialNumber and $server to $null so we can test to make sure we actually got new data.
                $serialNumber = $null
                $server = $null

                # Getting the serial number from ExtensionData.Hardware.SystemInfo.SerialNumber does not always work.
                #   Sometimes the service tag is the same as the serial number, however, that's not reliable either.
                #   For some of the B200M5 blades, the service tag/serial number vCenter returns is the serial
                #   number of the UCS chassis itself.  Same goes if I use Get-VMHostHardware.  However, using 
                #   Get-ESXCli works...

                # Connect to the ESXi hosts CLI interface...
                $esxCLI = Get-EsxCli -Server $vc -VMHost $vmH -V2

                if($null -ne $esxCLI)
                {
                    # Get the hardware platform for the ESXi host.
                    $hwPlatform = $esxCLI.hardware.platform.get.Invoke()
                    if($null -ne $hwPlatform)
                    {
                        # Now grab the serial number...
                        $serialNumber = $hwPlatform.SerialNumber
                    }
                    else
                    {
                        [Log]::Warning("Unable to get hardware platform object for {0}." -f @($vmH.Name))
                    }
                }
                else
                {
                    [Log]::Warning("Unable to establish ESXCLI connection to {0}." -f @($vmH.Name))
                }

                # Did we get a serial number for the host?
                if(-not [String]::IsNullOrEmpty($serialNumber))
                {
                    if($null -ne $intersightData)
                    {
                        # Is the server registered with Cisco Intersight?
                        $server = $intersightData | Where-Object { $_.SerialNumber -eq $serialNumber }
                    }
                    else
                    {
                        # Nothing, already logged a warning.
                    }

                    if(($null -eq $server) -and ($null -ne $xClarityData))
                    {
                        # Is the server registered with xClarity?
                        $server = $xClarityData | Where-Object { $_.SerialNumber -eq $serialNumber }
                    }
                    else
                    {
                        # Nothing, if $xClarityData -eq $null then we already logged a warning, otherwise, the server just isn't a Lenovo...
                    }

                    # If we did not find a "registered" server then create a new datapoint for it.
                    if($null -eq $server)
                    {
                        $server = [EVDataPoint]::new()
                        $server.SetName($vmH.Name)
                        $server.SetManufacturer($vmH.Manufacturer)
                        $server.Model = $vmH.Model
                        $server.CurrentVersion = ("{0} {1}.{2} [{3}]" -f @($vmH.ExtensionData.Hardware.BiosInfo.BiosVersion, $vmH.ExtensionData.Hardware.BiosInfo.MajorRelease, $vmH.ExtensionData.Hardware.BiosInfo.MinorRelease, $vmH.ExtensionData.Hardware.BiosInfo.ReleaseDate)).Replace(" . ", " ")
                        $server.SerialNumber = $serialNumber

                        # Get the location information for the host via the address assigned to the management vmk.
                        #   Get the vmkernel adapter for the management interface
                        $vmNA = @(Get-VMHostNetworkAdapter -Server $vc -VMHost $vmH -VMKernel | Where-Object { $_.ManagementTrafficEnabled })

                        if ($vmNA.Length -gt 0)
                        {
                            # TRUE

                            $server.SetIP($vmNA[0].IP)
                        }
                        else # NOT ($vmNA.Length -gt 0)
                        {
                            # FALSE

                            # Nothing...What?  No vmkernel adapter for management?
                            [Log]::Warning("No management vmkernel adapter found for VM Host: {0}" -f @($vmH.Name))
                        }

                        [Log]::Warning("{0} is not registered with Cisco Intersight, or xClarity." -f @($vmH.Name))

                        [Log]::Info("`t+ESXi Server: {0}, {1}, {2}, {3}" -f @($server.Name, $server.Manufacturer, $server.Model, $server.SerialNumber))
                        $vCenterData += $server
                    }
                    else
                    {
                        [Log]::Info("`tUpdating {0} ESXi Server: {1}, {2}, {3}." -f @($server.Manufacturer, $server.Name, $server.Model, $server.SerialNumber))
                    }
                }
                else
                {
                    [Log]::Warning("Unable to retrieve serial number from hardware information for {0}." -f @($vmH.Name))
                }

                # If $server is set, update the operating system for it and check various fields to ensure they are formatted correctly, etc...
                if($null -ne $server)
                {
                    $server.OperatingSystem = "VMware ESXi {0}" -f @($vmH.Version)
                }
                else
                {
                    [Log]::Warning("Script ended up where is should not be.  {0} is not a registered Cisco or Lenovo server, nor was a EVDataPoint created for it." -f @($vmH.Name))
                }

                $a++
            }
        }
        else # NOT ($null -ne $vc)
        {
            # FALSE

            [Log]::Error("Unable to connect to vCenter server: {0}" -f @($invCfg.vCenter.Server))
        }
    }
    catch
    {
        [Log]::Error("Exception: Failed to retrieve information from vCenter server: {0}" -f @($invCfg.vCenter.Server))
    }

    return @( , $vCenterData)   # Ensure even an empty array is returned.
}

<#
    Collect inventory data from NetApp Cluster controllers.

    Return: [EVDataPoint][]
#>
function Collect-CDOTData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    [Log]::Info("Collecting NetApp Cluster mode data..")

    # Where we collect all EVDataPoints not already in $intersightData or $xClarityData
    $cdotData = @()

    #  Create a credential for connecting to CDOT clusters
    $cdotCredential = [System.Management.Automation.PsCredential]::new($invCfg.Filers.CDOT.UserName, ($invCfg.Filers.CDOT.Password | ConvertTo-SecureString))

    $a = 0
    while($a -lt $invCfg.Filers.CDOT.Controllers.Length)
    {
        <#
            There are multiple CIs for NetApp clusters.
                The cluster itself: i.e. CDC-CDOTCLST01
                each node: CDC-NASA01, CDC-NASA02, etc...
                each disk shelf...
                each intercluster switch...
        #>

        # Make a transient connection to the cluster controller
        $cdotController = Connect-NcController -Name $invCfg.Filers.CDOT.Controllers[$a] -Credential $cdotCredential -Transient:$true

        if($null -eq $cdotController)
        {
            [Log]::Error("Failed to connect to CDOT controller {0}." -f @($invCfg.Filers.CDOT.Controllers[$a]))
            continue   # Skip to the next controller.
        }

        [Log]::Trace("`tProcessing {0}..." -f @($cdotController.Name))
        $clusterMgmtLIFS = @(Get-NCNetInterface -Controller $cdotController | Where-Object { $_.FirewallPolicy -eq "mgmt" })

        # CI for Cluster
        $cluster = Get-NCCluster -Controller $cdotController

        # Create an EVDataPoint for the cluster
        $clusterDP = [EVDataPoint]::new()
        $clusterDP.SetName($cdotController.Name)
        $clusterDP.Manufacturer = "NetApp"
        $clusterDP.OperatingSystem = $cdotController.Version
        $clusterDP.Model = "VSERVER"
        $clusterDP.SerialNumber = $cluster.ClusterSerialNumber

        $mgmtLIFs = @($clusterMgmtLIFS | Where-Object { ($_.Role -eq "cluster_mgmt") })
        if($mgmtLIFs.Length -gt 0)
        {
            $clusterDP.SetIP($mgmtLIFs[0].Address)
        }

        [Log]::Info("`t+Cluster: {0}, {1}, {2}" -f @($clusterDP.Name, $clusterDP.Model, $clusterDP.SerialNumber))
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
            $d.SerialNumber = $cn.NodeSerialNumber
            $d.OperatingSystem  = $cn.ProductVersion
            $d.Manufacturer = $cn.NodeVendor
            $d.Model = $cn.NodeModel
            $ncImage = @($clusterImages | Where-Object { $_.NodeId -eq $cn.Node })
            if($ncImage.Length -gt 0)
            {
                $d.CurrentVersion = $ncImage[0].CurrentVersion

                # Set the cluster CurrentVersion if it is not set.
                if([String]::IsNullOrEmpty($clusterDP.CurrentVersion))
                {
                    $clusterDP.CurrentVersion = $ncImage[0].CurrentVersion
                }
            }

            $nodeMgmtLIFs = @($clusterMgmtLIFS | Where-Object { ($_.Role -eq "node_mgmt") -and ($_.CurrentNode -eq $cn.Node) })
            if($nodeMgmtLIFs.Length -gt 0)
            {
                $d.SetIP($nodeMgmtLIFs[0].Address)
            }

            [Log]::Info("`t+Node: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
            $cdotData += $d

            $b++
        }

        # CIs for Cluster Switches

        [Log]::Trace("`tChecking for intercluster switches...")
        $clusterSwitches = @(Get-NCClusterSwitch -Controller $cdotController)

        $b = 0
        while($b -lt $clusterSwitches.Length)
        {
            $d = [EVDataPoint]::new($clusterSwitches[$b])

            [Log]::Info("`t+Switch: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
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

                        $d.SetName("{0}.SHELF.{1}" -f @($clusterDP.Name, $storageShelf.ShelfId))
                        $d.SerialNumber = $storageShelf.SerialNumber
                        $d.OperatingSystem  = "N/A"
                        $d.Manufacturer = $storageShelf.VendorName
                        $d.Model = $storageShelf.ShelfModel.ToUpper()
                        $d.CurrentVersion = $nodeShelves[$s].FirmwareRevA

                        # Since a shelf does not have an IP address, we'll set the shelf location to the same as the cluster.
                        $d.Location = $clusterDP.Location

                        [Log]::Info("`t+Shelf: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
                        $cdotData += $d
                    }
                    else
                    {
                        # Nothing, already inventoried this shelf.
                    }
                }
                else
                {
                    [Log]::Warning("Unable to locate shelf with UID: {0} in master storage shelf list for {1}." -f @($nodeShelves[$s].ShelfUid, $cdotController.Name))
                }

                $s++
            }

            $n++
        }

        $a++
    }

    return @( , $cdotData)   # Make sure an array is returned, even an empty one.
}

<#
    Collect inventory data from NetApp 7-Mode filers.

    Return: [EVDataPoint][]
#>
function Collect-SevenModeData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    [Log]::Info("Collecting NetApp 7-Mode data..")
    # Where we collect all EVDataPoints not already in $intersightData or $xClarityData
    $sevenModeData = @()

    #  Create a credential for connecting to CDOT clusters
    $sevenModeCredential = [System.Management.Automation.PsCredential]::new($invCfg.Filers.SM.UserName, ($invCfg.Filers.SM.Password | ConvertTo-SecureString))

    $a = 0
    while($a -lt $invCfg.Filers.SM.Nodes.Length)
    {
        [Log]::Trace("`tProcessing {0}..." -f @($invCfg.Filers.SM.Nodes[$a]))
        # Make a transient connection to the 7-Mode controller
        $smController = Connect-NaController -Name $invCfg.Filers.SM.Nodes[$a] -Credential $sevenModeCredential -Transient:$true -RPC

        if($null -eq $smController)
        {
            [Log]::Error("Failed to connect to 7-mode filer {0}." -f @($invCfg.Filers.SM.Nodes[$a]))
            continue   # Skip to the next controller.
        }

        $nodeInfo = Get-NASystemInfo -Controller $smController
        
        $d = [EVDataPoint]::new()
        $d.SetName($smController.Name)
        [Log]::Info("Processing {0}" -f @($d.Name))

        $d.SetIP($smController.Address)
        $d.SerialNumber = $nodeInfo.SystemSerialNumber
        if($smController.Version -match "\w+ \w+ ([^\s]+)")
        {
            $d.CurrentVersion = $Matches[1]
        }
        $d.OperatingSystem = $smController.Version
        $d.Manufacturer = $nodeInfo.VendorId
        $d.Model = $nodeInfo.SystemModel

<#
    
    NEED TO GET 7-Mode shelf information.  Currently, I don't see a way, using a Read-Only account, to get complete shelf information.
        Maybe v2.

#>
        [Log]::Info("`t+7-Mode node: {0}, {1}, {2}" -f @($d.Name, $d.Model, $d.SerialNumber))
        $sevenModeData += $d

        $a++
    }

    return @( , $sevenModeData)   # Make sure an array is returned, even an empty one.
}

<#
    The function pulls device and inventory data from Statseeker to avoid having to spider the network looking for hardware.

    As of 2020/11/03, the script is only able to gleen information about Juniper and Riverbed devices from Statseeker.
#>
function Collect-StatseekerData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    [Log]::Info("Collecting Statseeker data..")
    # Place to store [EVDataPoint]s collected from Statseeker.
    $statseekerData = @()

    # Create a new credential object for Statseeker access
    $statseekerCreds = [System.Management.Automation.PsCredential]::new($invCfg.Statseeker.UserName, ($invCfg.Statseeker.Password | ConvertTo-SecureString))

    # Since I have to create a base 64 encoded Basic Auth header for API access to Statseeker, I'll need the password in plaintext...
    $statseekerPwd = $statseekerCreds.GetNetworkCredential().Password

    # Create the plaintext username:password for Statseeker access
    $statseekerClearAuth = "{0}:{1}" -f @($statseekerCreds.UserName, $statseekerPwd)

    # Create a base 64 encoded string from the plaintext username:password
    $statseekerAuthBytes = [System.Text.Encoding]::Default.GetBytes($statseekerClearAuth)
    $statseekerb64Auth = [Convert]::ToBase64String($statseekerAuthBytes)

    # Create the complete Basic authentication header for Statseeker access
    $statseekerAuthKey = "Basic {0}" -f @($statseekerb64Auth)

    # Data from StatSeeker...
    $headers = [System.Collections.Generic.Dictionary[[String],[String]]]::new()

    # Add the authorization string to the header.
    $headers.Add("Authorization", $statseekerAuthKey)

    # String representing the Statseeker API URL
    $statseekerAPIURL = "{0}{1}" -f @($invCfg.Statseeker.URL, $invCfg.Statseeker.APIBase)

    # Have to use TLS 1.2...
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Get a list of devices from Statseeker
    [Log]::Trace("Getting devices from statseeker...")
    $deviceResponse = Invoke-RestMethod ("{0}/cdt_device?fields=deviceid,hostname,ipaddress,manual_name,name,sysDescr,sysLocation,sysName,vendor&limit=5000&offset=0" -f @($statseekerAPIURL)) -Method 'GET' -Headers $headers

    if($null -eq $deviceResponse)
    {
        [Log]::Error("No response from {0} when querying for devices." -f @($invCfg.Statseeker.URL))
        return $null
    }

    # Shortcut variable for returned devices.
    $devices = $deviceResponse.data.objects[0].data

    # Get an inventory list from Statseeker.
    [Log]::Trace("Getting inventory from statseeker...")
    $inventoryResponse = Invoke-RestMethod ("{0}/cdt_inventory/?fields=description,deviceid,firmwareRev,hardwareRev,id,idx,isFRU,model,name,serial,softwareRev,vendor&limit=5000&offset=0" -f @($statseekerAPIURL)) -Method 'GET' -Headers $headers
    if($null -eq $inventoryResponse)
    {
        [Log]::Error("No response from {0} when querying for inventory." -f @($invCfg.Statseeker.URL))
        return $null
    }

    # Shortcut variable for returned inventory
    $inventory = $inventoryResponse.data.objects[0].data

    $devNum = 0
    while($devNum -lt $devices.Count)
    {
        $device = $devices[$devNum]
        $d = [EVDataPoint]::new()
        $d.SetName($device.name)
        $d.SetManufacturer($device.vendor)

        # Only process Manufacturers we are interested in...
        if($d.Manufacturer -in @("Juniper Networks","Riverbed Technology"))
        {
            $devInv = @($inventory | Where-Object { $_.deviceid -eq $device.deviceid })

            $d.SetIP($device.ipaddress)

            $sn = @($devInv | Where-Object { (-not [String]::IsNullOrEmpty($_.serial)) -and ($_.serial -ne "N/A") -and ($_.serial -ne "NULL") })
            if($sn.Length -eq 1)
            {
                $d.SerialNumber = $sn[0].serial
            }
            elseif ($sn.Length -gt 1)
            {
                $sn = @($sn | Where-Object { $_.name -eq "Juniper 0" })
                if($sn.Length -eq 1)
                {
                    $d.SerialNumber = $sn[0].serial
                }
            }

            switch ($d.Manufacturer)
            {
                "Juniper Networks"
                {
                    if(-not [String]::IsNullOrEmpty($device.sysDescr))
                    {
                        $descr = $device.sysDescr.Replace($device.vendor,"").Trim()
                        $descrParts = $descr -split ","
                        if($descrParts.Length -gt 0)
                        {
                            $version = $descrParts -match "JUNOS (.*)$"
                            if($version.Length -eq 1)
                            {
                                if($version[0] -match "JUNOS (.*)$")
                                {
                                    $d.OperatingSystem = "JUNOS"
                                    $d.CurrentVersion = $Matches[1]
                                }
                            }

                            $d.Model = @($descrParts[0] -split " ")[0].ToUpper()
                        }
                    }

                    break   # It's a Juniper, no need to look at the rest.
                }

                "Riverbed Technology"
                {
                    $d.OperatingSystem = "LINUX"
                    if($devInv.Length -gt 0)
                    {
                        $devInv = @($devInv | Where-Object { $_.name -match "Riverbed" })
                        if($devInv.Length -eq 1)
                        {
                            if($devInv[0].model -match "\(([^)]+)")
                            {
                                $d.Model = $Matches[1]
                            }

                            $version = @($devInv[0].softwareRev -split " ")
                            if($version -gt 1)
                            {
                                $d.CurrentVersion = $version[1]
                            }
                        }
                    }
                    break   # It's a Riverbed, no need to look at the rest.
                }

                Default {}
            }

            if((-not [String]::IsNullOrEmpty($d.Name)) -and
               (-not [String]::IsNullOrEmpty($d.Model)) -and
               (-not [String]::IsNullOrEmpty($d.SerialNumber)))
            {
                [Log]::Info("`t+{0}: {1}, {2}, {3}" -f @($d.Manufacturer, $d.Name, $d.Model, $d.SerialNumber))
                $statseekerData += $d
            }
        }

        $devNum++
    }

    return @( , $statseekerData)     # Return an array, even if it's empty
}

# Source in the [Log] class

# NOTE: Uncomment the following line when ran in production.
. .\Log.ps1   # Once the [Log] class is loaded

# If the assignment statement below is executed outside a try-catch, it throws an error.  I like to catch it myself.
try
{
    $logClassFound = ($null -eq [Log])

    # For debugging...
    [Log]::Me().level = [LogLevel]::TRACE
}
catch
{
    Write-Error "Unable to locate the [Log] class, terminating script."
    return
}

# Do not initialize logging yet.  We still need the log file folder which will be available
#   after the script configuration is loaded later in this script.  For now, we'll just have
#   access to the [Log] functionality, but nothing will be written to storage until it is
#   actually initialized.

# Import the modules we need for access to various management systems

# Assume we have all the required modules until we learn otherwise.
$haveRequiredModules = $true

# The list of all modules required for this script.
$requiredModules = @(
    "LXCAPSTool",
    "VMWare.VimAutomation.Core",
    "DataONTAP",
    "Intersight"
)

[Log]::Trace("Checking for required modules...")
$availableModules = @(Get-Module -ListAvailable)
$a = 0
while($a -lt $requiredModules.Length)
{
    if(($availableModules | Where-Object { $_.Name -match $requiredModules[$a] }).Length -gt 0)
    {
        [Log]::Trace("Importing module " -f @($requiredModules[$a]))
        Import-Module -Name $requiredModules[$a]
    }
    else
    {
        [Log]::Error("Missing required module {0}" -f @($requiredModules[$a]))
        $haveRequiredModules = $false
    }

    $a++
}

# Do we have all the required modules?
if (-not $haveRequiredModules)
{
    # Oops... don't have all required modules, stop script.

    return
}


[Log]::Trace("Loading MySQL.Data assembly.")
#
#  The following lines must be executed before DBConnectionMYSQL.ps1 is sourced it.  I don't have any documentation to back up my thoughts,
#    but it seems PowerShell tries to define any types/classes in a file prior to running any other code.  When placing the 
#    following lines at the top of DBConnectionMYSQL.ps1, they do not seem to execute, but running them here seems to work fine.
#

if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
{
    [System.Reflection.Assembly]::LoadWithPartialName("MySQL.Data") | Out-Null

    if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
    {
        [Log]::Error("Unable to load MySQL.Data assembly, terminating script.")
        return
    }
    else
    {
        # Nothing
    }
}
else
{
    # Nothing
}

[Log]::Trace("Sourcing MySQLDBConnection class")
# Source in the MySQLDBConnection class
. .\DBConnectionMYSQL.ps1

try
{
    $mysqlDBClassFound = ($null -ne [MySQLDBConnection])
    [Log]::Info("MySQLDBConnection class loaded.")
}
catch
{
    [Log]::Error("Unable to locate the [MySQLDBConnection] class, terminating script.")
    return
}

[Log]::Trace("Sourcing EVDataPoint class")
# Source in the EVDataPoint class
. .\EVDatapoint.ps1

try
{
    $evDataPointClassFound = ($null -ne [EVDatapoint])
    [Log]::Info("EVDatapoint class loaded.")
}
catch
{
    [Log]::Error("Unable to locate the [EVDatapoint] class, terminating script.")
    return
}

[Log]::Trace("Sourcing LoadConfigurationData function")
# Source in LoadConfigurationData function.  This function is stored externally since it is used in other scripts.
. .\LoadConfigurationData.ps1

# Verify LoadConfigurationData was source into the script.
try
{
    Get-ChildItem -Path Function:\LoadConfigurationData -ErrorAction Stop | Out-Null
}
catch
{
    [Log]::Error("Unable to locate Function:\LoadConfigurationData, terminating script.")
    return
}

# At this point in the script all requirements (modules, class, and functions) should be available.

[Log]::Trace("Loading configuration data.")
# Load script initialization information.
$inventoryConfig = LoadConfigurationData $JSONArgsFile

if($null -eq $inventoryConfig)
{
     [Log]::Error("Failed to load virtual inventory configuration data from {0}, terminating script." -f @($JSONArgsFile))
    return
}

# Initialize logging.
[Log]::Init($inventoryConfig.LogPath, "VirtualInventory", 14, 1, [LogLevel]::INFO)
[Log]::Info("Initialized...")

# Verify connectivity to the IPAM database so we can use location data assigned to IP addresses.

[Log]::Trace("Testing access to IPAM database.")
# Connect to the IPAM database...
#  Create a credential object for the IPAMDB...
$ipamDBCredential = [System.Management.Automation.PsCredential]::new($inventoryConfig.IPAMDB.UserName, ($inventoryConfig.IPAMDB.Password | ConvertTo-SecureString))

#  Build a connection string from the configuration data and the credential
$dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};" -f @(
    $inventoryConfig.IPAMDB.Server,
    $inventoryConfig.IPAMDB.Port,
    $inventoryConfig.IPAMDB.Database,
    $ipamDBCredential.UserName,
    $ipamDBCredential.GetNetworkCredential().Password
)

#  Make a connection to the database
$Global:db = [MySQLDBConnection]::new($dbConnectionString)

#  Make sure we can query the database
$dt = $Global:db.GetDataTable("SELECT * FROM global_config;")

if(($null -eq $dt) -or ($dt.Rows.Count -eq 0))
{
    Write-Error ("Unable to connect to IPAM database {0} hosted at {1}:{2}, terminating script." -f @($inventoryConfig.IPAMDB.Database, $inventoryConfig.IPAMDB.Server, $inventoryConfig.IPAMDB.Port))
    return
}

[Log]::Info("Successfully connected to IPAM database.")

# Array of EVDataPoint objects to export for EV
$evData = @()

# Collect inventory data from Cisco Intersight
$intersightData = Collect-IntersightData $inventoryConfig
if ($null -eq $intersightData)
{
    Write-Error "Intersight data unavailable, terminating script."
    return
}

# Add all [EVDataPoint]s from Intersight to the $evData
$intersightData | ForEach-Object { $evData += $_ }

# Collect inventory data from xClarity
#  Don't add xClarity data to $evData.  After we collect vCenter data, we'll add xClarity data that is complete (has an Operating System assigned)
$xClarityData = Collect-xClarityData $inventoryConfig
if($null -eq $xClarityData)
{
    Write-Error "xClarity data unavailable, terminating script."
    return
}

# Connect to vCenter and collect VM host data, pass in $intersightData and $xClarityData so records for ESXi hosts can be updated.
$vCenterData = Collect-vCenterData $inventoryConfig $intersightData $xClarityData
if ($null -eq $vCenterData)
{
    Write-Error "vCenter data unavailable, terminating script."
    return
}

# Add servers not registered with xClarity or Cisco Intersight
$vCenterData | ForEach-Object { $evData += $_ }

# Add any xClarity DataPoints with an Operating System to $evData
$xClarityData | Where-Object { -not [String]::IsNullOrEmpty($_.OperatingSystem) } | ForEach-Object { $evData += $_ }

# Collect inventory data from each of the CDOT clusters listed in the configuration data.
$cdotData = Collect-CDOTData $inventoryConfig
if ($null -eq $cdotData)
{
    Write-Error "CDOT data unavailable, terminating script."
    return
}

# Add the CDOT Data to $evData
$cdotData | ForEach-Object { $evData += $_ }

# Collect inventory data from each of the 7-Mode filer listed in the configuration data.
$sevenModeData = Collect-SevenModeData $inventoryConfig
if ($null -eq $sevenModeData)
{
    Write-Error "7-Mode data unavailable, terminating script."
    return
}

# Add the 7-Mode Data to $evData
$sevenModeData | ForEach-Object { $evData += $_ }

# Collect inventory data from StatSeeker.
$statseekerData = Collect-StatseekerData $inventoryConfig
if ($null -eq $statseekerData)
{
    Write-Error "Statseeker data unavailable, terminating script."
    return
}

# Add the Statseeker Data to $evData
$statseekerData | ForEach-Object { $evData += $_ }

# Fail safe for any known field issues...
$evData | ForEach-Object { $_.FixUp() }

# Export EasyVista Data

$exportFileName = "{0}\{1}-VirtualInventory.csv" -f @($inventoryConfig.ExportPath, [DateTime]::Now.ToString("yyyyMMdd"))
[Log]::Info("Exporting EV Data to: {0}" -f @($exportFileName))
$exportData = @($evData | Sort-Object Name | ConvertTo-Csv -Delimiter "," -NoTypeInformation) -join "`r`n" | Set-Content -Path $exportFileName -Force
