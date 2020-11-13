<#
    Wrapper function for making an API call to Intersight.

    I found I was repeating the same steps over and over when calling most Intersight APIs, so I decided to wrap the calls in this function.
#>
function IntersightQuery
{
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0, Mandatory = $true)]
        [String]
        $apiCallName,

        [Parameter(Position = 1, Mandatory = $false)]
        [Boolean]
        $count = $false,

        [Parameter(Position = 2, Mandatory = $false)]
        [String]
        $inlinecount = $null,

        [Parameter(Position = 3, Mandatory = $false)]
        [Int32]
        $top = $null,

        [Parameter(Position = 4, Mandatory = $false)]
        [Int32]
        $skip = $null,

        [Parameter(Position = 5, Mandatory = $false)]
        [String]
        $filter = $null,

        [Parameter(Position = 6, Mandatory = $false)]
        [String]
        $select = $null,

        [Parameter(Position = 7, Mandatory = $false)]
        [String]
        $orderby = $null,

        [Parameter(Position = 8, Mandatory = $false)]
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
            $apiResponse = & $apiCallName $count $inlinecount $top $skip $filter $select $orderby $expand
            # $apiResponse = & $apiCallName $false $null $null $null $filter

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
                # Log error, no response from Intersight
            }
        }
        else
        {
            # Log error, unknown Intersight API call...
        }
    }
    else
    {
        # Log error, invalid IntersightQuery
    }

    return $results
}

<#
    Collect inventory data from Cisco Intersight.

    As with most things, this could have been completed many different ways, the following is just how I did it.
#>

function CollectIntersightData
{
    [CmdLetBinding()]
    Param(
        # Virtual inventory configuration data structure.
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $invCfg
    )

    # Create an object to collect the data we need.
    $intersightData = @()

    # Not going to retest $invCfg because this function should not be reachable unless it's all good.

<#
    $intersightURL = "https://intersight.com/api/v1"
    $private_key_path = "C:\Users\kbriney\KLB\PEI-IT-OPS\intersight.pem"
    $api_key_id = "5b51f81e6a636d6d34958477/5e0f6d207564612d301d07b7/5f7b68017564612d33de8075"
#>
    try
    {
        # First, create an Intersight API Client...
        New-IntersightApiClient $invCfg.Intersight.URL $invCfg.Intersight.PrivateKeyFile $invCfg.Intersight.APIKey

        # Get a list of all the device registrations.
        $deviceRegistrations = IntersightQuery "Invoke-AssetDeviceRegistrationApiAssetDeviceRegistrationsGet"

        # Get a list of all compute physical summaries.
        #    I tried to get these one chassis at a time, but could not make the API call work correctly, so I decided to 
        #    get them all at once and filter them via powershell.
        $computePhysicalSummaries = IntersightQuery "Invoke-ComputePhysicalSummaryApiComputePhysicalSummariesGet"

        # Be sure we received a response back from Intersight
        if ($null -ne $deviceRegistrations)
        {
            # TRUE

            # Iterate through the devices...
            $d = 0
            while((-not $Global:isError) -and ($d -lt $deviceRegistrations.Count))
            {
                # Shortcut to a single device registration
                $device = $deviceRegistrations[$d]

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

                            # Create a new EasyVista datapoint for the chassis
                            $chassisDataPoint = [EVDataPoint]::new()

                            $chassisDataPoint.SetName($device.DeviceHostname[0])

                            # Now, let's collect some more details about the UCS chassis: SerialNumber, Model, and Vendor
                            $filter = "DeviceMoId eq '{0}'" -f @($device.Moid)
                            $chassisSummaries = IntersightQuery "Invoke-EquipmentChassisApiEquipmentChassesGet" -filter $filter
                            
                            # Be sure we received a response back from Intersight
                            if($null -ne $chassisSummaries)
                            {
                                # Create shortcut...
                                if($chassisSummaries.Count -eq 1)
                                {
                                    $chassisSummary = $chassisSummaries[0]

                                    $chassisDataPoint.SerialNumber = $chassisSummary.Serial
                                    $chassisDataPoint.Model = $chassisSummary.Model
                                    $chassisDataPoint.SetManufacturer($chassisSummary.Vendor)

                                    $intersightData += $chassisDataPoint

                                    # The chassis IP address is part of the "network elements".  The Ipv4Address property appears to be the management VIP, while the OutOfBandIpAddress property is the actual IP address
                                    #    assigned to the FI.

                                    # Flag to signal we can continue collecting FI and compute data for this chassis.
                                    $haveChassisData = $true
                                }
                                else
                                {
                                    [Log]::Error("Too many chassis summaries returned ({0}) for DeviceMoid = {1}" -f @($chassisSummaries.Count, $device.Moid))
                                }
                            }
                            else
                            {
                                [Log]::Error("No response from Intersight when querying for equipment chassis {0}" -f @($filter))
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
                            $filter = "RegisteredDevice.Moid eq '{0}'" -f @($device.Moid)
                            $elementSummaries = IntersightQuery "Invoke-NetworkElementSummaryApiNetworkElementSummariesGet" -filter $filter

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
                                    $elementDataPoint = [EVDataPoint]::new()

                                    # Set the FI's IP address, name and location based on data from IPAM...
                                    $elementDataPoint.SetIP($elementSummary.OutOfBandIpAddress)

                                    # Set the other properties for the FI.
                                    $elementDataPoint.SetManufacturer($elementSummary.Vendor)
                                    $elementDataPoint.CurrentVersion = $elementSummary.Version
                                    $elementDataPoint.SerialNumber = $elementSummary.Serial
                                    $elementDataPoint.Model = $elementSummary.Model

                                    # All FIs run NX-OS for an operating system
                                    $elementDataPoint.OperatingSystem = "NX-OS"

                                    # Add the FI's data point to the list of intersight data...
                                    $intersightData += $elementDataPoint

                                    $e++
                                }
                            }
                            else
                            {
                                # Log warning, no FI information returned.
                                [Log]::Warning("No fabric interconnects found matching filter: {0}" -f @($filter))
                            }

                            # Get a list of compute devices that belong to this chassis
                            $chassisComputePhysicalSummaries = @($computePhysicalSummaries | Where-Object { $_.Owners.Contains($device.Moid) })

                            if($chassisComputePhysicalSummaries.Length -gt 0)
                            {
                                $c = 0
                                while($c -lt $chassisComputePhysicalSummaries.Count)
                                {
                                    # Shortcut to the currect compute physical summary
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
                        $physicalSummaries = @($computePhysicalSummaries | Where-Object { $_.DeviceMoid -eq $device.Moid })

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
        }
        else # NOT ($null -ne $deviceRegistrations)
        {
            # FALSE

            [Log]::Error("No device registrations returned from Intersight.")
        }
    }
    catch
    {
        [Log]::Error("Failed to query Cisco Intersight for UCS platform data.")
    }

    return $intersightData
}
