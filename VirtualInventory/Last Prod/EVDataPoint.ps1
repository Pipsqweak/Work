# The following code tests to see if the EVDataPoint class has already been defined.

$found = $false
try { $found = ($null -ne [EVDataPoint]) } catch { }

# If the EVDataPoint class has not been defined, define it.
if(-not $found)
{
    <#
        Class:
            EVDataPoint

        Description:
            Internal class used by the Log class to provide buffered logging
    #>

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

        # Initialize an [EVDataPoint] from a NetworkElementSummary
        EVDataPoint([intersight.Model.NetworkElementSummary] $netElement)
        {
            $this.SetIP($netElement.OutOfBandIpAddress)
            $this.SetManufacturer($netElement.Vendor)
            $this.SetCurrentVersion($netElement.Version)
            $this.SetSerialNumber($netElement.Serial)
            $this.SetModel($netElement.Model)
            $this.SetOperatingSystem("NX-OS")
        }

        # Initialize an [EVDataPoint] from a UCS compute physical summary
        EVDataPoint([intersight.Model.ComputePhysicalSummary] $computePhysicalSummary)
        {
            if (-not [String]::IsNullOrEmpty($computePhysicalSummary.UserLabel))
            {
                $this.SetName($computePhysicalSummary.UserLabel)
            } `
            else # NOT (-not [String]::IsNullOrEmpty($computePhysicalSummary.UserLabel))
            {
                # Guess we go with the name...
                $this.SetName($computePhysicalSummary.Name)
            }
            $this.SetManufacturer($computePhysicalSummary.Vendor)
            $this.SetCurrentVersion($computePhysicalSummary.Firmware)
            $this.SetSerialNumber($computePhysicalSummary.Serial)
            $this.SetModel($computePhysicalSummary.Model)
        }

        # Initialize an [EVDataPoint] from an EquipmentChassis
        EVDataPoint([intersight.Model.EquipmentChassis] $chassis)
        {
            $this.SetName($chassis.Name)
            $this.SerialNumber = $chassis.Serial
            $this.SetModel($chassis.Model)
            $this.SetManufacturer($chassis.Vendor)
        }

        # Initialize an [EVDataPoint] from an intersight device registration -- ONLY UCSFI devices
        EVDataPoint([intersight.Model.AssetDeviceRegistration] $deviceRegistration)
        {
            if ($deviceRegistration.PlatformType -eq "UCSFI")
            {
                $this.SetName($deviceRegistration.DeviceHostName[0])
                $this.SetCurrentVersion($deviceRegistration.SwVersion)
                if ([String]::IsNullOrEmpty($this.IP) -and ($deviceRegistration.DeviceIPAddress.Length -gt 0))
                {
                    $this.SetIP($deviceRegistration.DeviceIPAddress[$deviceRegistration.DeviceIPAddress.Length - 1])
                } `
                else # NOT ([String]::IsNullOrEmpty($this.IP) -and ($deviceRegistration.DeviceIPAddress.Length -gt 0))
                {
                    # Nothing.
                }
                $this.SetSerialNumber($this.Name)
                $this.SetManufacturer($deviceRegistration.Vendor)
                $this.SetModel("virtual")
            } `
            else # NOT ($deviceRegistration.PlatformType == "UCSFI")
            {
                # Nothing.
            }
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
                $this.UpdateFromIPAMByName()
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

            if($isIP)
            {
                $this.UpdateFromIPAMByIP()
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

        [void] UpdateFromIPAMByQuery($query)
        {

            # Only query the database if $this.Location or $this.IP or $this.Name is blank/empty
            if([String]::IsNullOrEmpty($this.Location) -or [String]::IsNullOrEmpty($this.IP))
            {
                # Get the data from the database...
                $dt = $Global:db.GetDataTable($query)
                if($null -ne $dt)
                {
                    if($null -ne $dt.Rows)
                    {
                        if($dt.Rows.Count -gt 0)
                        {
                            if(([String]::IsNullOrEmpty($this.Location)) -and (-not [String]::IsNullOrEmpty($dt.Rows[0].loc)))
                            {
                                $this.Location = $dt.Rows[0].loc
                            }

                            if(([String]::IsNullOrEmpty($this.IP)) -and (-not [String]::IsNullOrEmpty($dt.Rows[0].ipaddress)))
                            {
                                $this.IP = $dt.Rows[0].ipaddress
                            }

                            if(([String]::IsNullOrEmpty($this.Name)) -and (-not [String]::IsNullOrEmpty($dt.Rows[0].hostname)))
                            {
                                $this.SetName($dt.Rows[0].hostname)
                            }
                        }
                    }
                }
            }
        }

        [void] UpdateFromIPAMByIP()
        {
            if(-not [String]::IsNullOrEmpty($this.IP))
            {
                # Create a query to get the IP's location and host name from IPAM.
                $query = "SELECT locations.loc,host.hostname,INET_NTOA(host.ip) as ipaddress FROM locations INNER JOIN host ON locations.id = host.loc WHERE (host.ip = INET_ATON('{0}'));" -f @($this.IP)

                $this.UpdateFromIPAMByQuery($query)
            }
            else
            {
                # Warning: Attempt to update datapoint by IP with no IP.
            }
        }

        [void] UpdateFromIPAMByName()
        {
            if(-not [String]::IsNullOrEmpty($this.Name))
            {
                # Make sure there is no ".powereng.com" on the end of the name.
                $this.Name = $this.Name.ToUpper().Replace(".POWERENG.COM","")

                # Create a query to get the IP's location and host name from IPAM.
                $query = "SELECT locations.loc,host.hostname,INET_NTOA(host.ip) as ipaddress FROM locations INNER JOIN host ON locations.id = host.loc WHERE (host.hostname = '{0}');" -f @($this.Name)

                $this.UpdateFromIPAMByQuery($query)
            }
            else
            {
                # Warning: Attempt up update datapoint by name with no name.
            }
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
}
