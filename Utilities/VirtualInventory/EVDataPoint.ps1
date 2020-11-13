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

        [void] SetManufacturer([String] $manufacturer)
        {
            $this.Manufacturer = $manufacturer
            if(-not [String]::IsNullOrEmpty($this.Manufacturer))
            {
                $this.Manufacturer = $this.Manufacturer.Trim().Replace("(WIST)","").Replace(" Inc","").Trim(@('.',',',' '))
            }
        }

        # Initialize an [EVDataPoint] from an intercluter switch
        EVDataPoint([DataONTAP.C.Types.ClusterSwitch.ClusterSwitchInfo] $icsw)
        {
            $this.Name = $icsw.Device.ToUpper()
            $this.CurrentVersion = $icsw.SwVersion
            $this.SetIP($icsw.Address)
            $this.SerialNumber = $icsw.SerialNumber
            $this.Manufacturer = "NetApp"
            $this.Model = $icsw.Model.ToUpper()
            $this.OperatingSystem = "FASTPATH"
        }

        # Initialize an [EVDataPoint] from an intercluter switch
        EVDataPoint([intersight.Model.NetworkElementSummary] $netElement)
        {
            $this.SetIP($netElement.OutOfBandIpAddress)
            $this.SetManufacturer($netElement.Vendor)
            $this.CurrentVersion = $netElement.Version
            $this.SerialNumber = $netElement.Serial
            $this.Model = $netElement.Model
            $this.OperatingSystem = "NX-OS"
        }

        EVDataPoint([String] $name, [intersight.Model.EquipmentChassis] $chassis)
        {
            $this.SetName($name)
            $this.SerialNumber = $chassis.Serial
            $this.Model = $chassis.Model
            $this.SetManufacturer($chassis.Vendor)
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

        [void] UpdateFromIPAMByQuery($query)
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
                            # Default to "Not in IPAM" until we get confirmation back from the DB...
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
            # Sometimes data is not exactly correct.  This function is intended to be a last ditch effort to
            #   reformat, substitute, replace, etc any data that needs to be massaged.
            #
            # This function should be called prior to exporting the data for use with EV.

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

            # Make sure the Manufacturer name "NetApp" is always spell "NetApp"
            if(-not [String]::IsNullOrEmpty($this.Manufacturer))
            {
                if($this.Manufacturer -eq "NETAPP")    # Remember, in PS, string equality testing is case-insensitive unless we use -ceq
                {
                    $this.Manufacturer = "NetApp"   # Now, ensure it's always capital N, lower et, capital A, lower pp...
                }
            }
            else
            {
                # Nothing, no Manufacturer name...
            }
        }
    }
}
