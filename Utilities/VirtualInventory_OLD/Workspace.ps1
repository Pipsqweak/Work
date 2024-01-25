# Old CollectvCenterData code

        # Each data point is collected in an [EVDataPoint] structure...See comments on the class for details.
        $d = [EVDataPoint]::new()
        $d.SetName($vmH.Name)
        $d.SetManufacturer($vmH.Manufacturer)
        $d.OperatingSystem = "VMware ESXi {0}" -f @($vmH.Version)
        $d.Model = $vmH.Model

        [Log]::Info("Processing {0}..." -f @($d.Name))

        # Get the location information for the host via the address assigned to the management vmk.
        #   Get the vmkernel adapter for the management interface
        $vmNA = @(Get-VMHostNetworkAdapter -Server $vcenter -VMHost $vmH -VMKernel | Where-Object { $_.ManagementTrafficEnabled })

        if ($vmNA.Length -gt 0)
        {
            # TRUE

            $d.SetIP($vmNA[0].IP)
        }
        else # NOT ($vmNA.Length -gt 0)
        {
            # FALSE

            # Nothing...What?  No vmkernel adapter for management?
            [Log]::Warning("No management vmkernel adapter found for VM Host: {0}" -f @($d.Name))
        }

        # Below here, we see if we can get better information for the VM host by seeing if there is Intersight or xClarity data available for the server.
        #    I don't like using the VM host's name as the key, but at the time, I didn't see a "better" way to go about this.

        # See if the host is a UCS blade/server...
        #    Get ALL blades/servers that match the name....should be only 1, but get an array anyway, we can adjust...
        $ciscoServer = @($intersightData | Where-Object { $_.UserLabel -match ($vcad[5].name -replace '.powereng.com','') })
        if ($ucsServer.Length -eq 1)
        {
            # TRUE - Only one server that matches, so convert the array to a single object.

            $ucsServer = $ucsServer[0]
            $d.SetManufacturer($ucsServer.Vendor)
            $d.Model = $ucsServer.Model
            $d.SerialNumber = $ucsServer.Serial

            # Get ALL the server firmware entries in an array and adjust...  (I don't like relying on what I get back if there is no match...)
            $ucsServerFW = @($ucsData.Firmware | Where-Object { ($_.Ucs -eq $ucsServer.Ucs) -and ($_.Dn -match $ucsServer.Dn) -and ($_.Deployment -eq "boot-loader") -and ($_.Type -eq "blade-bios") } | Sort-Object Dn | Select-Object -Unique Deployment, PackageVersion, Type, Version )

            if ($ucsServerFW.Length -gt 0)
            {
                # TRUE

                # Convert the array to a single object
                $ucsServerFW = $ucsServerFW[0]

                # Is there a Package version for the Firmware?
                if (-not [String]::IsNullOrEmpty($ucsServerFW.PackageVersion))
                {
                    # TRUE -- There is a PackageVersion for the UCS server.

                    # Sometimes the firmware version includes a date on the end.  This results in the field being too long for EV,
                    #   so we have to trim it a bit, so let's remove any date info on the end.
                    #
                    #   Example: C240M5.4.0.4d.0.0506190827 5.14 [5/6/2019 12:00:00 AM]
                    #
                    # Split the string on '['   The delimiter is a regex so need to escape the '[' character.
                    $k = $ucsServerFW.PackageVersion -split '\['

                    # Use was is let, except, let's remove any trailing spaces
                    $d.CurrentVersion = $k[0].Trim()
                }
                else # NOT (-not [String]::IsNullOrEmpty($ucsServerFW.PackageVersion))
                {
                    # FALSE

                    # Nothing.
                }
            }
            else # NOT ($ucsServerFW.Length -gt 0)
            {
                # FALSE

                # Nothing.
            }
        }
        else # NOT ($ucsServer.Length -eq 1)
        {
            # FALSE, not a UCS server...

            # See if the host is a Lenovo server...
            $xServer = @($xClarityServers | Where-Object { $_.Name -eq $d.Name })

            if ($xServer.Length -eq 1)
            {
                # TRUE

                $xServer = $xServer[0]
                $d.SetManufacturer($xServer.Manufacturer)
                $d.Model = $xServer.ProductName
                $d.SerialNumber = $xServer.SerialNumber
                $xServerFW = @($xServer.Firmwares | Where-Object { $_.Name -eq "UEFI Firmware/BIOS"})
                if($xServerFW.Length -gt 0)
                {
                    $d.CurrentVersion = $xServerFW[0].Version
                }
                else
                {
                    $xServerFW = @($xServer.Firmwares | Where-Object { $_.Name -eq "UEFI" })
                    if($xServerFW.Length -gt 0)
                    {
                        $d.CurrentVersion = $xServerFW[0].Version
                    }
                    else
                    {
                        # Nothing I guess...
                    }
                }

                # "Correct" firmware version to match xClarity.
                #   Based on conversation with John Wilkerson, when the firmare looks like: VVE168DUS-3.10 or D7E172DUS-3.10, all
                #   they want is the 3.10.

                if (-not [String]::IsNullOrEmpty($d.CurrentVersion))
                {
                    # TRUE

                    if ($d.CurrentVersion -match "`-(\d+\.\d+)")
                    {
                        # TRUE

                        # Just use the part captured in the regular expression capture group (\d+\.\d+) as the firmware version
                        $d.CurrentVersion = $Matches[1]
                    }
                    else # NOT ($d.CurrentVersion -match "`-(\d+\.\d+)")
                    {
                        # FALSE

                        # Nothing, at this point, just leave the firmware as is.
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($d.CurrentVersion)
                {
                    # FALSE

                    # Nothing, no firmware version to "correct"
                }
            }
            else # NOT ($xServer.Length -eq 1)
            {
                # FALSE

                $serviceTag = @($vmH.ExtensionData.Summary.Hardware.OtherIdentifyingInfo | Where-Object { $_.IdentifierType.Label -eq "Service Tag" } )

                if($serviceTag.Length -gt 0)
                {
                    $d.SerialNumber = $serviceTag[0].IdentifierValue
                    $d.CurrentVersion = ("{0} {1}.{2} [{3}]" -f @($vmH.ExtensionData.Hardware.BiosInfo.BiosVersion, $vmH.ExtensionData.Hardware.BiosInfo.MajorRelease, $vmH.ExtensionData.Hardware.BiosInfo.MinorRelease, $vmH.ExtensionData.Hardware.BiosInfo.ReleaseDate)).Replace(" . ", " ")
                }

                [Log]::Warning("{0} is not in UCS or xClarity." -f @($d.Name))
            }
        }

        # Fail safe for any known field issues...

        # CurrentVersion field in EV is limited to 50 characters, so let's make sure it's 50 or less characters long.
        if ((-not [String]::IsNullOrEmpty($d.CurrentVersion) -and ($d.CurrentVersion.Length -gt 50)))
        {
            # TRUE

            # Sorry, we can only use the first 50 characters...
            $d.CurrentVersion = $d.CurrentVersion.Substring(0, 50)
        }
        else # NOT ((-not [String]::IsNullOrEmpty($d.CurrentVersion) -and ($d.CurrentVersion.Length -gt 50)))
        {
            # FALSE

            # Nothing.
        }

        $vCenterData += $d
        $a++
    }

    return $vCenterData
}
