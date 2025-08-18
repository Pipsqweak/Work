function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # Using -match to parse out the octets.
        if($ipStr -match "^((\d+)\.(\d+)\.(\d+)\.(\d+))$")
        {
            $a = 0
            while($a -lt 4)
            {
                $octet = [Convert]::ToUInt32($Matches[$a + 2], 10)
                $ipAddr += ($octet -shl (24 - (8 * $a)))
                $a++
            }
        }
    } `
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

function IsInSubnet
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $ipStr,

        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $netIPStr,

        [Parameter(Mandatory=$true, Position=0)]
        [int]
        $bm
    )

    $ip = [int64] (INET_ATON $ipStr)
    $netIP = [int64] (INET_ATON $netIPStr)
    $mask = (($Global:baseBM -shr (32 - $bm)) -shl (32 - $bm))
    $maskedIP = $mask -band $ip
    $maskedNetIP = $mask -band $netIP

    return $maskedIP -eq $maskedNetIP
}

function IPAMSubnetsForAddress
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $ipStr
    )

    $ip = [int64] (INET_ATON $ipStr)

    return @($Global:ipamSubnets | Where-Object { ($_.Mask -band $ip) -eq $_.MaskedNetIPN })
}

function GetAddressFromPTR
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Object]
        $ptrRec
    )

    $addr = [String]::Empty

    if($null -ne $ptrRec)
    {
        try
        {
            $parts = @($ptrRec.DistinguishedName -split ',')
            $octets = @(($parts[0] -split '=')[1] -split '\.')[2..0]
            $octet1 = (($parts[1] -split '=')[1] -split '\.')[0]
            $addr = "{0}.{1}" -f @($octet1, ($octets -join '.'))
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to parse address from {0}." -f @($ptrRec.DistinguishedName))
        }
    }
    else
    {
        Write-Host -ForegroundColor Red "Record missing distinguished name."
    }

    return $addr
}

class DHCPRangeComparer:System.Collections.Generic.IComparer[System.Object]
{
    [int] Compare([System.Object] $rngObj1, [System.Object] $rngObj2)
    {
        $retVal = 0
        if(($null -eq $rngObj1) -and ($null -eq $rngObj2))
        {
            $retVal = 0
        } `
        elseif($null -eq $rngObj1)
        {
            $retVal = -1
        } `
        elseif($null -eq $rngObj2)
        {
            $retVal = 1
        } `
        else
        {
            if(($null -eq $rngObj1.Start) -and ($null -eq $rngObj2.Start))
            {
                $retVal = 0
            } `
            elseif($null -eq $rngObj1.Start)
            {
                $retVal = -1
            } `
            elseif($null -eq $rngObj2.Start)
            {
                $retVal = 1
            } `
            else
            {
                $retval = $rngObj1.Start.CompareTo($rngObj2.Start)
                if ($retVal -eq 0)
                {
                    if(($null -eq $rngObj1.End) -and ($null -eq $rngObj2.End))
                    {
                        $retVal = 0
                    } `
                    elseif($null -eq $rngObj1.End)
                    {
                        $retVal = -1
                    } `
                    elseif($null -eq $rngObj2.End)
                    {
                        $retVal = 1
                    } `
                    else
                    {
                        $retval = $rngObj1.End.CompareTo($rngObj2.End)
                    }
                } `
                else # NOT ($retVal -eq 0)
                {
                    # Nothing.
                }
            }
        }

        return $retval
    }
}

function AddDHCPRange
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $range
    )

    $i = $Global:dhcpRanges.BinarySearch($range, $Global:dhcpRangeComparer)
    if($i -lt 0)
    {
        # Learn how .BinarySearch works :P
        $i = -bnot $i
    } `
    else
    {
        # Nothing
    }

    # Write-Host ("Added {0} - {1}" -f @((INET_NTOA $range.Start), (INET_NTOA $range.End)))
    $Global:dhcpRanges.Insert($i, $range)
}

function AddGlobalAddressAssignment
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $addrStr,

        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $assignment
    )

    if (-not $Global:AddressAssignments.ContainsKey($addrStr))
    {
        $nl = [System.Collections.Generic.List[System.Object]]::new()
        $Global:AddressAssignments.Add($addrStr, $nl)
    } `
    else # NOT (-not $d.Leases.ContainsKey($_.))
    {
        # Nothing.
    }
    $Global:AddressAssignments[$addrStr].Add($assignment)
}

function AddAddressAssignment
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [AllowNull()]
        [System.Collections.Generic.SortedDictionary[System.String,System.Object]]
        $assignmentsDictionary,

        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $addrStr,

        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $assignment
    )

    if ($null -ne $assignmentsDictionary)
    {
        if (-not $assignmentsDictionary.ContainsKey($addrStr))
        {
            $assignmentsDictionary.Add($addrStr, $assignment)
        } `
        else # NOT (-not $assignmentsDictionary.ContainsKey($addrStr))
        {
            # Nothing.
        }

        AddGlobalAddressAssignment -addrStr $addrStr -assignment $assignment
    } `
    else # NOT ($null -ne $assignmentsDictionary)
    {
        # Nothing.
    }
}

function GetDHCPData
{
    $Global:DHCPDataAvailable = $false
    $Global:dhcpRanges = [System.Collections.Generic.List[System.Object]]::new()
    $Global:AddressAssignments = [System.Collections.Generic.SortedDictionary[System.String,System.Collections.Generic.List[System.Object]]]::new()
    $dhcpServers = @(Get-ADComputer -LDAPFilter "(&(objectClass=computer)(servicePrincipalName=*DHCP*))" -Property Name, DNSHostName | Sort-Object Name)

    if ($dhcpServers.Length -gt 0)
    {
        $a = 0
        while($a -lt $dhcpServers.Length)
        {
            Write-Host ("Loading DHCP Scopes from {0}..." -f @($dhcpServers[$a].Name))
            $scopes = @(Get-DhcpServerv4Scope -ComputerName $dhcpServers[$a].Name | Where-Object { $_.State -eq "Active" })
            Write-Host ("`tProcessing {0} scopes..." -f @($scopes.Length))
            $b = 0
            while($b -lt $scopes.Length)
            {
                Write-Host ("`tScope: {0}..." -f @($scopes[$b].ScopeId))
                $d = [PSCustomObject]@{
                    Start = INET_ATON $scopes[$b].StartRange.ToString()
                    End = INET_ATON $scopes[$b].EndRange.ToString()
                    Type = "DHCP"
                    Server = $dhcpServers[$a].Name
                    Scope = $scopes[$b]
                    Assignments = [System.Collections.Generic.SortedDictionary[System.String,System.Object]]::new()
                }

                $leases = @(Get-DhcpServerv4Lease -ComputerName $dhcpServers[$a].Name -ScopeId $scopes[$b].ScopeId)
                Write-Host ("`t`tLeases: {0}" -f @($leases.Length))
                $leases | ForEach-Object {
                    AddAddressAssignment -assignmentsDictionary $d.Assignments -addrStr $_.IPAddress.ToString() -assignment $_

                    <#
                    $addrStr = $_.IPAddress.ToString()
                    if (-not $d.Assignments.ContainsKey($addrStr))
                    {
                        $d.Assignments.Add($addrStr, $_)
                    } `
                    else # NOT (-not $d.Leases.ContainsKey($_.))
                    {
                        # Nothing.
                    }

                    AddGlobalAddressAssignment -addrStr $addrStr -assignment $_
                    #>
                }

                AddDHCPRange -range $d
                $b++
            }
            $a++
        }

        $Global:DHCPDataAvailable = $Global:dhcpRanges.Count -gt 0
    } `
    else # NOT ($dhcpServers.Length -gt 0)
    {
        Write-Host -ForegroundColor Red "No DHCP servers were located."
    }
}

function GetAOVPNData
{
    $Global:AOVPNDataAvailable = $false
#    $Global:dhcpRanges = [System.Collections.Generic.List[System.Object]]::new()
    $aovpnServers = @(Get-ADComputer -LDAPFilter "(&(objectClass=computer)(servicePrincipalName=*AOVPN*))" -Property Name, DNSHostName | Sort-Object Name)

    if ($aovpnServers.Length -gt 0)
    {
        $dhcpRangeCountAtStart = $Global:dhcpRanges.Count
        $a = 0
        while($a -lt $aovpnServers.Length)
        {
            Write-Host ("Loading IP address ranges from {0}..." -f @($aovpnServers[$a].Name))
            try
            {
                $ra = Get-RemoteAccess -ComputerName $aovpnServers[$a].Name -ErrorAction Stop
                $connections = @(Get-RemoteAccessConnectionStatistics -ComputerName $aovpnServers[$a].Name)

                $b = 0
                while($b -lt $ra.IPAddressRangeList.Count)
                {
                    if ($ra.IPAddressRangeList[$b] -match "(\d+\.\d+\.\d+\.\d+) - (\d+\.\d+\.\d+\.\d+)")
                    {
                        $d = [PSCustomObject]@{
                            Start = INET_ATON $Matches[1]
                            End = INET_ATON $Matches[2]
                            Type = "AOVPN"
                            Server = $aovpnServers[$a].Name
                            Scope = $null
                            Assignments = [System.Collections.Generic.SortedDictionary[System.String,System.Object]]::new()
                        }

                        $rangeConnections = @($connections | Where-Object { ($d.Start -le (INET_ATON $_.ClientIPv4Address)) -and ((INET_ATON $_.ClientIPv4Address) -le $d.End) } )
                        $rangeConnections | ForEach-Object {
                            AddAddressAssignment -assignmentsDictionary $d.Assignments -addrStr $_.ClientIPv4Address.ToString() -assignment $_

                            <#
                            $addrStr = $_.ClientIPv4Address.ToString()
                            if (-not $d.Assignments.ContainsKey($addrStr))
                            {
                                $d.Assignments.Add($addrStr, $_)
                            } `
                            else # NOT (-not $d.Leases.ContainsKey($_.))
                            {
                                # Nothing.
                            }

                            AddGlobalAddressAssignment -addrStr $addrStr -assignment $_
                            #>
                        }

                        AddDHCPRange -range $d
                    } `
                    else # NOT ($ra.IPAddressRangeList[$b] -match "(\d+\.\d+\.\d+\.\d+) - (\d+\.\d+\.\d+\.\d+)")
                    {
                        # Nothing.
                    }
                    $b++
                }
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to retrieve data from {0}" -f @($aovpnServers[$a].Name))
            }

            $a++
        }

        $Global:AOVPNDataAvailable = $Global:dhcpRanges.Count -gt $dhcpRangeCountAtStart
    } `
    else # NOT ($aovpnServers.Length -gt 0)
    {
        Write-Host -ForegroundColor Red "No AoVPN servers were located."
    }
}

function AddManualDHCPRanges
{
    $manualRanges = @(
        [PSCustomObject]@{ Start = INET_ATON "10.245.124.0";   End = INET_ATON "10.245.125.255"; Type = "NETSCALAR"; Server = "CDCZ-NSVPX02"; Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.247.124.0";   End = INET_ATON "10.247.125.255"; Type = "NETSCALAR"; Server = "DDCZ-NSVPX02"; Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.15.128.10";   End = INET_ATON "10.15.135.254";  Type = "AOVPN";     Server = "LABZ-AOVPN03"; Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.15.136.10";   End = INET_ATON "10.15.143.254";  Type = "AOVPN";     Server = "LABZ-AOVPN03"; Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.234.5.33";    End = INET_ATON "10.234.5.40";    Type = "UCSPOOL";   Server = "CH3-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.245.5.170";   End = INET_ATON "10.245.5.189";   Type = "UCSPOOL";   Server = "CDC-UCS02";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.245.5.190";   End = INET_ATON "10.245.5.199";   Type = "UCSPOOL";   Server = "CDC-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.245.5.200";   End = INET_ATON "10.245.5.216";   Type = "UCSPOOL";   Server = "CDC-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.245.5.217";   End = INET_ATON "10.245.5.240";   Type = "UCSPOOL";   Server = "CDC-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.15.5.33";     End = INET_ATON "10.15.5.40";     Type = "UCSPOOL";   Server = "LAB-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.232.5.33";    End = INET_ATON "10.232.5.40";    Type = "UCSPOOL";   Server = "LAS04-UCS01";  Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.247.106.182"; End = INET_ATON "10.247.106.240"; Type = "UCSPOOL";   Server = "DDC-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.233.5.33";    End = INET_ATON "10.233.5.40";    Type = "UCSPOOL";   Server = "DA11-UCS01";   Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.231.5.33";    End = INET_ATON "10.231.5.40";    Type = "UCSPOOL";   Server = "AT4-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.230.5.33";    End = INET_ATON "10.230.5.40";    Type = "UCSPOOL";   Server = "NY7-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.236.5.33";    End = INET_ATON "10.236.5.40";    Type = "UCSPOOL";   Server = "SE4-UCS01";    Scope = $null; Assignments = $null },
        [PSCustomObject]@{ Start = INET_ATON "10.241.5.33";    End = INET_ATON "10.241.5.40";    Type = "UCSPOOL";   Server = "YYC01-UCS01";  Scope = $null; Assignments = $null }
    )

    $a = 0
    while($a -lt $manualRanges.Length)
    {
        AddDHCPRange -range $manualRanges[$a]
        $a++
    }
}

function RefreshDHCPData
{
    GetDHCPData
    if ($Global:DHCPDataAvailable)
    {
        GetAOVPNData
        if ($Global:AOVPNDataAvailable)
        {
            AddManualDHCPRanges

            $addrKeys = @($Global:ipData.Keys)
            $a = 0
            while($a -lt $addrKeys.Length)
            {
                $addr = $addrKeys[$a]
                $Global:ipData[$addr].IsDHCPAddress = IsDHCPAddress -addr $Global:ipData[$addr].AddressN
                $a++
            }
        } `
        else # NOT ($Global:DNSDataAvailable)
        {
            Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required AoVPN data."
        }
    } `
    else # NOT ($Global:DHCPDataAvailable)
    {
        Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required DHCP data."
    }
}

function GetDHCPRangeIndexForAddress
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr
    )

    $i = [UInt32]::MaxValue
    if ($Global:DHCPDataAvailable)
    {
        # Create a new "fake" DHCP range with just $addr in it...
        $d = [PSCustomObject]@{
            Start = $addr
            End = $addr
        }

        # At what index would the new fake range be inserted?
        $i = $Global:dhcpRanges.BinarySearch($d, $Global:dhcpRangeComparer)

        # It would be HIGHLY unlikely we'd find a real DHCP address range with a single address, but it's possible.
        if ($i -lt 0)
        {
            # Point to the index where range:$addr..$addr would be inserted.
            $i = -bnot $i

            # Need to account for the possibility that $addr is the start of a DHCP range, and if so, it is a DHCP address.
            if ($Global:dhcpRanges[$i].Start -eq $addr)
            {
                # Nothing
            } `
            elseif ($i -gt 0) # NOT ($Global:dhcpRanges[$i].Start -eq $addr)
            {
                # $i now points to the DHCP range just after where range:$addr..$addr should live, so let's look at the range just before this.
                $i--
            } `
            else # NOT ($i -gt 0)
            {
                # Nothing
            }
        } `
        else # NOT ($i -gt 0)
        {
            # Nothing
        }
    } `
    else # NOT ($Global:DHCPDataAvailable)
    {
        # Nothing.
    }

    return $i
}

function GetAddressAssignmentsByHostname
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $hostname
    )

    $assignments = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $Global:dhcpRanges.Count)
    {
        $b = 0
        if ($null -ne $Global:dhcpRanges[$a].Assignments)
        {
            $assignmentKeys = @($Global:dhcpRanges[$a].Assignments.Keys)
            if($Global:dhcpRanges[$a].Type -eq "DHCP")
            {
                while($b -lt $assignmentKeys.Length)
                {
                    if ($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]].HostName -match $hostname)
                    {
                        $assignments.Add($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]])
                    } `
                    else # NOT ($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]].HostName -match $hostname)
                    {
                        # Nothing.
                    }
                    $b++
                }
            } `
            else
            {
                while($b -lt $assignmentKeys.Length)
                {
                    $c = 0
                    while($c -lt $Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]].UserName.Length)
                    {
                        if ($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]].UserName[$c] -match $hostname)
                        {
                            $assignments.Add($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]])
                        } `
                        else # NOT ($Global:dhcpRanges[$a].Assignments[$assignmentKeys[$b]].UserName[$c] -match $hostname)
                        {
                            # Nothing.
                        }
                        $c++
                    }

                    $b++
                }
            }
        } `
        else # NOT ($null -ne $Global:dhcpRanges[$a].Assignments)
        {
            # Nothing.
        }

        $a++
    }

    return @(, $assignments)
}

function GetAddressAssignmentByAddress
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr
    )

    $d = $null
    $i = GetDHCPRangeIndexForAddress -addr $addr
    if (($i -ge 0) -and ($i -lt $Global:dhcpRanges.Count))
    {
        $d = [PSCustomObject]@{
            Type = $Global:dhcpRanges[$i].Type
            Server = $Global:dhcpRanges[$i].Server
            Assignment = $null
        }
        $addrStr = INET_NTOA -ipAddress $addr
        if ($Global:dhcpRanges[$i].Assignments.ContainsKey($addrStr))
        {
            $d.Assignment = $Global:dhcpRanges[$i].Assignments[$addrStr]
        } `
        else # NOT ($Global:dhcpRanges[$i].Assignments.ContainsKey($addrStr))
        {
            # Nothing.
        }
    } `
    else # NOT (($i -ge 0) -and ($i -lt $Global:dhcpRanges.Count))
    {
        # Nothing
    }

    return $d
}

function GetHostnameFromAddressAssignment
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr
    )

    $hostname = [String]::Empty
    $assignment = GetAddressAssignmentByAddress -addr $addr
    if ($null -ne $assignment)
    {
        if ($null -ne ($assignment | Get-Member -Name "UserName"))
        {
            $hostName = $assignment.UserName[0]
        } `
        else # NOT ($null -ne ($assignment | Get-Member -Name "UserName"))
        {
            $hostname = $assignment.HostName
        }
    } `
    else # NOT ($null -ne $assignment)
    {
        # Nothing.
    }

    return $hostname
}

function IsDHCPAddress
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr
    )

    $isDHCP = $false
    if ($Global:DHCPDataAvailable)
    {
        # Create a new "fake" DHCP range with just $addr in it...
        $d = [PSCustomObject]@{
            Start = $addr
            End = $addr
        }

        # At what index would the new fake range be inserted?
        $i = $Global:dhcpRanges.BinarySearch($d, $Global:dhcpRangeComparer)

        # It would be HIGHLY unlikely we'd find a real DHCP address range with a single address, but it's possible.
        if ($i -lt 0)
        {
            # Point to the index where range:$addr..$addr would be inserted.
            $i = -bnot $i

            # Need to account for the possibility that $addr is the start of a DHCP range, and if so, it is a DHCP address.
            if ($Global:dhcpRanges[$i].Start -eq $addr)
            {
                $isDHCP = $true
            } `
            elseif ($i -gt 0) # NOT ($Global:dhcpRanges[$i].Start -eq $addr)
            {
                # $i now points to the DHCP range just after where range:$addr..$addr should live, so let's look at the range just before this.
                $i--

                $isDHCP = ($Global:dhcpRanges[$i].Start -le $addr) -and ($addr -le $Global:dhcpRanges[$i].End)
            } `
            else # NOT ($i -gt 0)
            {
                # $addr falls below the lowest DHCP range we know about, so it's not a DHCP address.
                $isDHCP = $false
            }
        } `
        else # NOT ($i -gt 0)
        {
            #  WOW!  found a range with a single address matching $addr... oh well, go with it...
            $isDHCP = $true
        }
    } `
    else # NOT ($Global:DHCPDataAvailable)
    {
        # Nothing.
    }

    return $isDHCP
}

function GetIPAMData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=0)]
        [Int32]
        $lastUpdate = -1
    )

    try
    {
        #  Make a connection to the database
        $Global:ipamDB = [MySQLDBConnection]::new($dbConnectionString)
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed to connect to IPAM database."
        $Global:ipamDB = $null
    }

    if ($null -ne $Global:ipamDB)
    {
        $lastUpdateClause = [String]::Empty
        if ($lastUpdate -ne -1)
        {
            $lastUpdateClause = "(last_update >= {0}) AND " -f @($lastUpdate)
        } `
        else # NOT ($lastUpdate -ne -1)
        {
            # Nothing.
        }

        $selectStatement = "SELECT h.id as id, h.hostname, INET_NTOA(h.ip) AS address, cnce2.entry AS aZone, cnce3.entry AS ptrZone, h.last_update FROM host h INNER JOIN net n ON h.red_num = n.red_num LEFT JOIN custom_net_column_entries cnce2 ON (n.red_num = cnce2.net_id) AND (cnce2.cc_id = 2) LEFT JOIN custom_net_column_entries cnce3 ON (n.red_num = cnce3.net_id) AND (cnce3.cc_id = 3) WHERE {0}(h.hostname <> '') ORDER BY h.ip;" -f @($lastUpdateClause)
        $ipamDT = $Global:ipamDB.GetDataTable($selectStatement)
        if ($null -ne $ipamDT)
        {
            $Global:ipamRecordsByAddress = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Data.DataRow]]]::new()
            $Global:ipamRecordsByName = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Data.DataRow]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $ipamDT.Rows | ForEach-Object {
                if (-not $Global:ipamRecordsByAddress.ContainsKey($_.address))
                {
                    $nl = [System.Collections.Generic.List[System.Data.DataRow]]::new()
                    $Global:ipamRecordsByAddress.Add($_.address, $nl)
                } `
                else # NOT (-not $Global:ipamRecordsByAddress.ContainsKey($_.address))
                {
                    # Nothing.
                }
                $Global:ipamRecordsByAddress[$_.address].Add($_)

                $hn = $_.hostname.ToLower()
                if (-not $Global:ipamRecordsByName.ContainsKey($hn))
                {
                    $nl = [System.Collections.Generic.List[System.Data.DataRow]]::new()
                    $Global:ipamRecordsByName.Add($hn, $nl)
                } `
                else # NOT (-not $Global:ipamRecordsByName.ContainsKey($_.hostname))
                {
                    # Nothing.
                }
                $Global:ipamRecordsByName[$hn].Add($_)
            }

            $ipamSubnetsDT = $Global:ipamDB.GetDataTable("SELECT * FROM net ORDER BY INET_ATON(red);")
            if ($null -ne $ipamSubnetsDT)
            {

                $Global:ipamSubnets = [System.Collections.Generic.List[System.Object]]::new()
                $a = 0
                while($a -lt $ipamSubnetsDT.Rows.Count)
                {
                    $d = [PSCustomObject]@{
                        Row = $ipamSubnetsDT.Rows[$a]
                        NetIPN = [int64] (INET_ATON $ipamSubnetsDT.Rows[$a].red)
                        Mask = (($Global:baseBM -shr (32 - $ipamSubnetsDT.Rows[$a].BM)) -shl (32 - $ipamSubnetsDT.Rows[$a].BM))
                        MaskedNetIPN = (($Global:baseBM -shr (32 - $ipamSubnetsDT.Rows[$a].BM)) -shl (32 - $ipamSubnetsDT.Rows[$a].BM)) -band ([int64] (INET_ATON $ipamSubnetsDT.Rows[$a].red))
                    }

                    $Global:ipamSubnets.Add($d)

                    $a++
                }

                $Global:IPAMDataAvailable = ($Global:ipamRecordsByAddress.Count -gt 0) -and ($Global:ipamRecordsByName.Count -gt 0) -and ($Global:ipamSubnets.Count -gt 0)
            } `
            else # NOT ($null -ne $ipamSubnetsDT)
            {
                # Nothing.
            }
        } `
        else # NOT ($null -ne $ipamDT)
        {
            # Nothing.
        }

        $dnsDT = $ipamDB.GetDataTable("SELECT * FROM dns_zone;")
        if ($null -ne $dnsDT)
        {
            $dnsDT.Rows | ForEach-Object {
                $Global:ipamDNSServers.Add($_)
            }
        } `
        else # NOT ($null -ne $dnsDT)
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $ipamDB)
    {
        # Nothing.
    }
}

function NewIPDataNode
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr,

        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyString()]
        [String]
        $hostname
    )

    $hn = [String]::Empty
    $isInIPAMByName = $false
    if (-not [String]::IsNullOrEmpty($hostname))
    {
        if ($hostname -match "^(.*?)\.powereng\.com\.$")
        {
            $hn = $Matches[1].ToLower()
        } `
        else # NOT ($hostname -match "\.powereng\.com\.$")
        {
            $hn = $hostname.ToLower()
        }
        $isInIPAMByName = $Global:ipamRecordsByName.ContainsKey($hn)
    } `
    else # NOT (-not [String]::IsNullOrEmpty($hostname))
    {
        # Nothing.
    }

    $addrStr = INET_NTOA $addr
    $isInIPAMByAddress = $Global:ipamRecordsByAddress.ContainsKey($addrStr)
    $ipamSubnets = @(IPAMSubnetsForAddress -ipStr $addrStr)

    $node = [PSCustomObject]@{
        HostName = $hn
        AddressN = [UInt32] $addr
        AddressStr = $addrStr
        PTRRecords = [System.Collections.Generic.List[System.Object]]::new()
        ARecords = [System.Collections.Generic.List[System.Object]]::new()
        IPAMRecords = [System.Collections.Generic.List[System.Object]]::new()
        IsInIPAMByAddress = $isInIPAMByAddress
        IsInIPAMByName = $isInIPAMByName
        IPAMSubnets = [System.Collections.Generic.List[System.Object]]::new()
        HasIPAMSubnet = $isInIPAMByAddress -or $isInIPAMByName -or ($ipamSubnets.Length -gt 0)
        IsDHCPAddress = $false
        Pingable = $false
    }

    $ipamSubnets.ForEach({ $node.IPAMSubnets.Add($_) })
    if ($isInIPAMByName)
    {
        $Global:ipamRecordsByName[$hn] | ForEach-Object {
            $id = $_.id
            if (@($node.IPAMRecords | Where-Object { $_.id -eq $id }).Length -eq 0)
            {
                $node.IPAMRecords.Add($_)
            } `
            else # NOT (@($node.IPAMRecords | Where-Object { $_.id -eq $id }).Length -eq 0)
            {
                # Nothing.
            }
        }
    } `
    else # NOT ($isInIPAMByName)
    {
        # Nothing.
    }
    if ($isInIPAMByAddress)
    {
        $Global:ipamRecordsByAddress[$addrStr] | ForEach-Object {
            $id = $_.id
            if (@($node.IPAMRecords | Where-Object { $_.id -eq $id }).Length -eq 0)
            {
                $node.IPAMRecords.Add($_)
            } `
            else # NOT (@($node.IPAMRecords | Where-Object { $_.id -eq $id }).Length -eq 0)
            {
                # Nothing.
            }
        }
    } `
    else # NOT ($isInIPAMByName)
    {
        # Nothing.
    }

    if (($null -ne $Global:dhcpRanges) -and ($Global:dhcpRanges.Count -gt 0))
    {
        $node.IsDHCPAddress = IsDHCPAddress -addr $node.AddressN
    } `
    else # NOT (($null -ne $Global:dhcpRanges) -and ($Global:dhcpRanges.Count -gt 0))
    {
        # Nothing.
    }

    return $node
}

function AddKeyAndObjectToDictList
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]
        $dict,

        [Parameter(Mandatory=$true, Position=1)]
        [System.Object]
        $newKey,

        [Parameter(Mandatory=$true, Position=2)]
        [System.Object]
        $newObj
    )

    if (-not $dict.ContainsKey($newKey))
    {
        $nl = [System.Collections.Generic.List[System.Object]]::new()
        $dict.Add($newKey, $nl)
    } `
    else # NOT (-not $dict.ContainsKey($newKey))
    {
        # Nothing.
    }
    $dict[$newKey].Add($newObj)
}

function GetDNSData
{
    $Global:DNSDataAvailable = $false
    $Global:aRecordsBy = "" | Select-Object Address,HostName
    $Global:aRecordsBy.Address = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()
    $Global:aRecordsBy.HostName = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()
    $Global:ptrRecordsBy = "" | Select-Object Address,HostName
    $Global:ptrRecordsBy.Address = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()
    $Global:ptrRecordsBy.HostName = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()

    $requiredDataAvailable = $Global:IPAMDataAvailable -and $Global:DHCPDataAvailable
    $Global:aRecords.Clear()
    $Global:ptrRecords.Clear()
    $aRecsLoadedSuccessfully = $false
    $ptrRecsLoadedSuccessfully = $false
    $aRecCount = 0
    $Global:ipData = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()

    if ($requiredDataAvailable)
    {
        try
        {
            $dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses.Length -gt 0 })  # { -not [String]::IsNullOrEmpty($_.ServerAddresses) })

            $a = 0
            while(($a -lt $dnsServers.Length) -and (-not $aRecsLoadedSuccessfully) -and (-not $ptrRecsLoadedSuccessfully))
            {
                $b = 0
                while(($b -lt $dnsServers[$a].ServerAddresses.Length) -and (-not $aRecsLoadedSuccessfully) -and (-not $ptrRecsLoadedSuccessfully))
                {
                    # Reset the follow each time to ensure we have A and PTR records from the same DNS server.
                    $Global:aRecords.Clear()
                    $Global:ptrRecords.Clear()
                    $aRecsLoadedSuccessfully = $false
                    $ptrRecsLoadedSuccessfully = $false
                    $aRecCount = 0
                    [Log]::Info("Retrieving DNS data from {0}" -f @($dnsServers[$a].ServerAddresses[$b]))

                    # Get information about the DNS server.
                    $dnsServer = $null
                    try
                    {
                        $dnsServer = Get-DNSServer -ComputerName $dnsServers[$a].ServerAddresses[$b] -ErrorAction Stop -WarningAction SilentlyContinue
                    }
                    catch
                    {
                        [Log]::Error("Unable to get DNS server information from {0}." -f @($dnsServers[$a].ServerAddresses[$b]))
                        $dnsServer = $null
                    }

                    if ($null -ne $dnsServer)
                    {
                        # Get all the primary/forward zones the server hosts.
                        $forwardZones = @($dnsServer.ServerZone | Where-Object { ($_.ZoneType -eq "Primary") -and (-not $_.IsReverseLookupZone) -and ($_.ZoneName -notmatch "^(_msdcs|TrustAnchors)")})

                        if ($forwardZones.Length -gt 0)
                        {
                            $c = 0
                            $zonesLoaded = 0
                            while($c -lt $forwardZones.Length)
                            {
                                try
                                {
                                    $aRecs = @(Get-DnsServerResourceRecord -ComputerName $dnsServers[$a].ServerAddresses[$b] -ZoneName $forwardZones[$c].ZoneName -RRType A -ErrorAction Stop)
                                    [Log]::Info("Loaded {0} A records from zone {1} on DNS server {2}." -f @($aRecs.Length, $forwardZones[$c].ZoneName, $dnsServers[$a].ServerAddresses[$b]))
                                    $zonesLoaded++
                                }
                                catch
                                {
                                    [Log]::Warning("Failed to load A records from zone {0} on DNS server {1}." -f @($forwardZones[$c].ZoneName, $dnsServers[$a].ServerAddresses[$b]))
                                }

                                $d = 0
                                while($d -lt $aRecs.Length)
                                {
                                    if (-not $Global:aRecords.ContainsKey($forwardZones[$c].ZoneName))
                                    {
                                        $aRecList = [System.Collections.Generic.List[System.Object]]::new()
                                        $Global:aRecords.Add($forwardZones[$c].ZoneName, $aRecList)
                                    } `
                                    else # NOT (-not $Global:aRecords.ContainsKey($forwardZones[$c].ZoneName))
                                    {
                                        # Nothing.
                                    }
                                    $Global:aRecords[$forwardZones[$c].ZoneName].Add($aRecs[$d])
                                    $aRecCount++
                                    $d++
                                }

                                $c++
                            }

                            $aRecsLoadedSuccessfully = ($zonesLoaded -eq $forwardZones.Length)

                            if ($aRecsLoadedSuccessfully)
                            {
                                [Log]::Info("Loaded {0} A records" -f @($aRecCount))
                                $ptrRecsLoadedSuccessfully = $true

                                <#
                                    NO more reverse zone.  It has been migrated to WSP.
                                try
                                {
                                    @(Get-DnsServerResourceRecord -ComputerName $dnsServers[$a].ServerAddresses[$b] -ZoneName "10.in-addr.arpa" -RRType Ptr -ErrorAction Stop) | ForEach-Object {
                                        $Global:ptrRecords.Add($_)
                                    }
                                    [Log]::Info("Loaded {0} PTR records" -f @($Global:ptrRecords.Count))
                                    $ptrRecsLoadedSuccessfully = $true
                                }
                                catch
                                {
                                    [Log]::Warning("Failed to load PTR records from zone 10.in-addr.arpa on DNS server {0}." -f @($dnsServers[$a].ServerAddresses[$b]))

                                    # Reset A records loaded flag...
                                    $aRecsLoadedSuccessfully = $false
                                }
                                #>
                            } `
                            else # NOT ($aRecsLoadedSuccessfully)
                            {
                                # Nothing.
                            }
                        } `
                        else # NOT ($forwardZones.Length -gt 0)
                        {
                            [log]::Warning("No forward zones found on DNS server: {0}" -f @($dnsServers[$a].ServerAddresses[$b]))
                        }
                    } `
                    else # NOT ($null -ne $dnsServer)
                    {
                        # Nothing.
                    }

                    $b++
                }

                $a++
            }
        }
        catch
        {
            [Log]::Warning("Failed to get local host DNS servers.")
        }

        if ($aRecsLoadedSuccessfully -and $ptrRecsLoadedSuccessfully)
        {
            $sw = [System.Diagnostics.Stopwatch]::new()
            $sw.Start()

            $a = 0
            $aRecsProcessed = 0
            $zoneKeys = @($Global:aRecords.Keys)
            while($a -lt $zoneKeys.Length)
            {
                $zoneName = $zoneKeys[$a]
                $b = 0
                while($b -lt $Global:aRecords[$zoneName].Count)
                {
                    $elapsedTicks = $sw.ElapsedTicks
                    $ticksPerItem = $elapsedTicks / ($aRecsProcessed + 1)
                    $totalETATicks = $ticksPerItem * $aRecCount
                    $remainingETATicks = $totalETATicks - $elapsedTicks
                    $etaTS = [TimeSpan]::new($remainingETATicks)
                    $etaDT = [DateTime]::Now.Add($etaTS)
                    $percentComplete = (($aRecsProcessed + 1)  / $aRecCount)
                    $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @(($aRecsProcessed + 1), $aRecCount, $percentComplete, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))
                    Write-Progress -Id 0 -Activity "Processing A records" -Status $status -PercentComplete ($percentComplete * 100.0)

                    if (-not $Global:dnsHostNameToIgnore.Contains($Global:aRecords[$zoneName][$b].HostName))
                    {
                        $addrN = INET_ATON $Global:aRecords[$zoneName][$b].RecordData.IPv4Address.IPAddressToString
                        $newNode = NewIPDataNode -addr $addrN -hostname $Global:aRecords[$zoneName][$b].HostName
                        if ($null -ne $newNode)
                        {
                            AddKeyAndObjectToDictList -dict $Global:aRecordsBy.HostName -newKey $newNode.HostName -newObj $Global:aRecords[$zoneName][$b]
                            AddKeyAndObjectToDictList -dict $Global:aRecordsBy.Address -newKey $newNode.AddressStr -newObj $Global:aRecords[$zoneName][$b]

                            if (-not $Global:ipData.ContainsKey($newNode.AddressStr))
                            {
                                $Global:ipData.Add($newNode.AddressStr, $newNode)
                            } `
                            else # NOT (-not $Global:ipData.ContainsKey($newNode.AddressStr))
                            {
                                $Global:ipData[$newNode.AddressStr].IsInIPAMByName = $Global:ipData[$newNode.AddressStr].IsInIPAMByName -or $newNode.IsInIPAMByName
                            }
                        } `
                        else # NOT ($null -ne $newNode)
                        {
                            [Log]::Error("Failed to create new ipData node from: {0}/{1}" -f @($Global:aRecords[$zoneName][$b].RecordData.IPv4Address.IPAddressToString, $Global:aRecords[$zoneName][$b].HostName))
                        }
                        $Global:ipData[$newNode.AddressStr].ARecords.Add($Global:aRecords[$zoneName][$b])
                    } `
                    else # NOT (-not $Global:dnsHostNameToIgnore.Contains($Global:aRecords[$b].HostName))
                    {
                        # Nothing.
                    }
                    $aRecsProcessed++
                    $b++
                }
                $a++
            }
            $sw.Stop()

            $sw.Reset()
            Write-Progress -Id 0 -Activity "Processing A records" -Status "Complete..." -PercentComplete 100 -Completed

            <#
                NO more reverse zone.  It has been migrated to WSP.
            $sw.Start()
            $a = 0
            while($a -lt $Global:ptrRecords.Count)
            {
                $elapsedTicks = $sw.ElapsedTicks
                $ticksPerItem = $elapsedTicks / ($a + 1)
                $totalETATicks = $ticksPerItem * $Global:ptrRecords.Count
                $remainingETATicks = $totalETATicks - $elapsedTicks
                $etaTS = [TimeSpan]::new($remainingETATicks)
                $etaDT = [DateTime]::Now.Add($etaTS)
                $percentComplete = (($a + 1)  / $Global:ptrRecords.Count)
                $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @(($a + 1), $Global:ptrRecords.Count, $percentComplete, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))

                Write-Progress -Id 1 -Activity "Processing PTR records" -Status $status -PercentComplete ($percentComplete * 100.0)

                $addr = GetAddressFromPTR $Global:ptrRecords[$a]

                if (-not [String]::IsNullOrEmpty($addr))
                {
                    $newNode = NewIPDataNode -addr (INET_ATON $addr) -hostname $Global:ptrRecords[$a].RecordData.PtrDomainName
                    if ($null -ne $newNode)
                    {
                        if (-not $Global:dnsHostNameToIgnore.Contains($newNode.HostName))
                        {
                            AddKeyAndObjectToDictList -dict $Global:ptrRecordsBy.HostName -newKey $newNode.HostName -newObj $Global:ptrRecords[$a]
                            AddKeyAndObjectToDictList -dict $Global:ptrRecordsBy.Address -newKey $newNode.AddressStr -newObj $Global:ptrRecords[$a]

                            if (-not $Global:ipData.ContainsKey($addr))
                            {
                                $Global:ipData.Add($newNode.AddressStr, $newNode)
                            } `
                            else # NOT (-not $Global:ipData.ContainsKey($addr))
                            {
                                $Global:ipData[$newNode.AddressStr].IsInIPAMByName = $Global:ipData[$newNode.AddressStr].IsInIPAMByName -or $newNode.IsInIPAMByName
                            }
                            $Global:ipData[$newNode.AddressStr].PTRRecords.Add($Global:ptrRecords[$a])
                        } `
                        else # NOT (-not $Global:dnsHostNameToIgnore.Contains($newNode.HostName))
                        {
                            # Nothing.
                        }
                    } `
                    else # NOT ($null -ne $newNode)
                    {
                        Write-Host -ForegroundColor Red ("Failed to create new ipData node from: {0}/{1}" -f @($addr, $Global:ptrRecords[$a].RecordData.PtrDomainName))
                    }
                } `
                else # NOT (-not [String]::IsNullOrEmpty($addr))
                {
                    # Nothing.
                }

                $a++
            }
            Write-Progress -Id 1 -Activity "Processing PTR records" -Status "Complete..." -PercentComplete 100 -Completed
            #>

            $Global:DNSDataAvailable = $Global:ipData.Count -gt 0
        } `
        else # NOT (($null -eq $Global:aRecords) -or ($null -eq $Global:ptrRecords))
        {
            $Global:aRecords.Clear()
            $Global:ptrRecords.Clear()
            [Log]::Error("Failed to retrieve required DNS data.")
        }
    } `
    else # NOT ($requiredDataAvailable)
    {
        if (-not $Global:IPAMDataAvailable)
        {
            Write-Host -ForegroundColor Red "Please load IPAM data before loading DNS data."
        } `
        else # NOT ($Global:IPAMDataAvailable)
        {
            # Nothing
        }

        if (-not $Global:DHCPDataAvailable)
        {
            Write-Host -ForegroundColor Red "Please load DHCP data before loading DNS data."
        } `
        else # NOT ($Global:DHCPDataAvailable)
        {
            # Nothing
        }
    }
}

function IsDHCPReservation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32]
        $addr
    )

    $isDHCPReservation = $false
    $ranges = @($Global:dhcpRanges | Where-Object { ($_.Start -le $addr) -and ($addr -le $_.End) })
    $a = 0
    while((-not $isDHCPReservation) -and ($a -lt $ranges.Length))
    {
        if ($ranges[$a].Type -eq "DHCP")
        {
            $addrStr = INET_NTOA $addr
            if ($ranges[$a].Assignments.ContainsKey($addrStr))
            {
                $isDHCPReservation = $isDHCPReservation -or ($ranges[$a].Assignments[$addrStr].AddressState -match "Reservation")
            } `
            else # NOT ($ranges[$a].Assignments.ContainsKey($addrStr))
            {
                # Nothing.
            }
        } `
        else # NOT ($ranges[$a].Type -eq "DHCP")
        {
            # Nothing.
        }
        $a++
    }

    return $isDHCPReservation
}

function AddMissingIPAMData
{
    $ipamAddrKeys = @($Global:ipamRecordsByAddress.Keys)
    $a = 0
    while($a -lt $ipamAddrKeys.Length)
    {
        if (-not $Global:ipData.ContainsKey($ipamAddrKeys[$a]))
        {
            $newNode = NewIPDataNode -addr (INET_ATON $ipamAddrKeys[$a]) -hostname $Global:ipamRecordsByAddress[$ipamAddrKeys[$a]].hostname
            if ($null -ne $newNode)
            {
                $Global:ipData.Add($newNode.AddressStr, $newNode)
            } `
            else # NOT ($null -ne $newNode)
            {
                Write-Host -ForegroundColor Red ("Failed to create new ipData node from: {0}/{1} in AddMissingIPAMData." -f @($ipamAddrKeys[$a], $Global:ipamRecordsByAddress[$ipamAddrKeys[$a]].hostname))
            }
        } `
        else # NOT (-not $Global:ipData.ContainsKey($ipamAddrKeys[$a]))
        {
            # Nothing.
        }
        $a++
    }
}

function GetData
{
    GetIPAMData

    if ($Global:IPAMDataAvailable)
    {
        GetDHCPData
        if ($Global:DHCPDataAvailable)
        {
            GetAOVPNData
            if ($Global:AOVPNDataAvailable)
            {
                AddManualDHCPRanges

                GetDNSData
                if ($Global:DNSDataAvailable)
                {
                    AddMissingIPAMData
                    Write-Host "Complete..."
                } `
                else # NOT ($Global:DNSDataAvailable)
                {
                    Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required DNS data."
                }
            } `
            else # NOT ($Global:DNSDataAvailable)
            {
                Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required AoVPN data."
            }

        } `
        else # NOT ($Global:DHCPDataAvailable)
        {
            Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required DHCP data."
        }
    } `
    else # NOT ($Global:IPAMDataAvailable)
    {
        Write-Host -ForegroundColor Red "ERROR: Failed to retrieve required IPAM data."
    }
}

function IPDataToCSV
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $node
    )

    $addrAssignment = $null
    $sb = [System.Text.StringBuilder]::new()
    if ($node.IsDHCPAddress)
    {
        $addrAssignment = GetAddressAssignmentByAddress -addr $node.AddressN
        if (-not [String]::IsNullOrEmpty($addrAssignment.Server))
        {
            $null = $sb.Append(("Server: {0}" -f @($addrAssignment.Server)))
        } `
        else # NOT (-not [String]::IsNullOrEmpty($addrAssignment.Server))
        {
            # Nothing.
        }
        if (($null -ne $addrAssignment) -and ($null -ne $addrAssignment.Assignment))
        {
            switch ($addrAssignment.Type)
            {
                "DHCP" {
                    if ($sb.Length -gt 0)
                    {
                        $null = $sb.Append(", ")
                    } `
                    else # NOT ($sb.Length -gt 0)
                    {
                        # Nothing.
                    }
                    $null = $sb.Append(("Address: {0}, ScopeID: {1}, ClientID: {2}, HostName: {3}, AddressState: {4}, LeaseExpiryTime: {5}" -f @($addrAssignment.Assignment.IPAddress, $addrAssignment.Assignment.ScopeId, $addrAssignment.Assignment.ClientID, $addrAssignment.Assignment.HostName, $addrAssignment.Assignment.AddressState, $addrAssignment.Assignment.LeaseExpiryTime)))
                    break
                }
                "AOVPN"
                {
                    if ($sb.Length -gt 0)
                    {
                        $null = $sb.Append(", ")
                    } `
                    else # NOT ($sb.Length -gt 0)
                    {
                        # Nothing.
                    }
                    $null = $sb.Append(("Address: {0}, UserName: {1}, ConnectDuration: {2}, ConnectionType: {3}" -f @($addrAssignment.Assignment.ClientIPAddress, ($addrAssignment.Assignment.UserName -join "|"), $addrAssignment.Assignment.ConnectionDuration, $addrAssignment.Assignment.ConnectionType)))
                }
                Default {}
            }
        } `
        else # NOT ($null -ne $addrAssignment) -and ($null -ne $addrAssignment.Assignment))
        {
            # Nothing.
        }
    } `
    else # NOT ($node.IsDHCPAddress)
    {
        $null = $sb.Append("N/A")
    }
    return $node | Select-Object `
        @{N = 'Address'; E= { $_.AddressStr }}, `
        HostName, `
        @{N = 'InDHCPRange'; E = { $_.IsDHCPAddress }}, `
        @{N = 'IsDHCPReservation'; E = { if($_.IsDHCPAddress) { (IsDHCPReservation -addr $_.AddressN) } else { "N/A" }}}, `
        @{N = 'A'; E = { @($_.ARecords | Where-Object { $_.RecordData.IPv4Address.ToString() -eq $node.AddressStr } | Foreach-Object { $isStatic = ""; if($null -eq $_.Timestamp) { $isStatic = "*" }; "{0}{1}/{2}" -f @( $isStatic, $_.RecordData.IPv4Address.ToString(), $_.HostName) }) -join ", " }}, `
        @{N = 'PTR'; E = { @($_.PTRRecords | Where-Object { (GetAddressFromPTR -ptrRec $_) -eq $node.AddressStr } | Foreach-Object { $isStatic = ""; if($null -eq $_.Timestamp) { $isStatic = "*" };  "{0}{1}/{2}" -f @( $isStatic, (GetAddressFromPTR -ptrRec $_) , $_.RecordData.PtrDomainName) }) -join ", " }}, `
        @{N = 'IPAM'; E = { @($_.IPAMRecords | Where-Object { $_.address -eq $node.AddressStr } | Foreach-Object { "{0}/{1}" -f @($_.address, $_.hostname) }) -join ", " }},
        @{N = 'Assignment Type'; E = { if($null -eq $addrAssignment) { "Static" } else { $addrAssignment.Type } }}, `
        @{N = 'Assignment Details'; E = { $sb.ToString() }}
}

function CheckARecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $addr,

        [Parameter(Mandatory=$true, Position=1)]
        [System.Object]
        $aRecord
    )

    $aRecordMatches = $true
    if ($Global:ipamRecordsByAddress[$addr].hostname -ne $aRecord.HostName)
    {
        $Global:addressesWhereIPAMHostnameDoesNotMatchARecord.Add($Global:ipData[$addr])
        $aRecordMatches = $false
    } `
    else # NOT ($Global:ipamRecordsByAddress[$addr].hostname -ne $aRecord.HostName)
    {
        # Nothing
    }

    if ($addr -ne $aRecord.RecordData.IPv4Address.IPAddressToString)
    {
        $Global:addressesWhereIPAMAddressDoesNotMatchARecord.Add($Global:ipData[$addr])
        $aRecordMatches = $false
    } `
    else # NOT ($addr -ne $aRecord.RecordData.IPv4Address.IPAddressToString)
    {
        # Nothing
    }

    if ($aRecordMatches)
    {
        if ($null -ne $aRecord.Timestamp)
        {
            $Global:aRecordsToMakeStatic.Add($aRecord)
        } `
        else # NOT ($null -ne $aRecord.Timestamp)
        {
            # Nothing.
        }
    } `
    else # NOT ($aRecordMatches)
    {
        # Nothing.
    }
}

function CheckPTRRecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $addr,

        [Parameter(Mandatory=$true, Position=1)]
        [System.Object]
        $ptrRecord
    )


    $ptrRecordMatches = $true
    if ($Global:ipamRecordsByAddress[$addr].hostname -ne $aRecord.HostName)
    {
        $Global:addressesWhereIPAMHostnameDoesNotMatchARecord.Add($Global:ipData[$addr])
        $ptrRecordMatches = $false
    } `
    else # NOT ($Global:ipamRecordsByAddress[$addr].hostname -ne $aRecord.HostName)
    {
        # Nothing
    }

    if ($addr -ne $aRecord.RecordData.IPv4Address.IPAddressToString)
    {
        $Global:addressesWhereIPAMAddressDoesNotMatchARecord.Add($Global:ipData[$addr])
        $ptrRecordMatches = $false
    } `
    else # NOT ($addr -ne $aRecord.RecordData.IPv4Address.IPAddressToString)
    {
        # Nothing
    }

    if ($ptrRecordMatches)
    {
        if ($null -ne $aRecord.Timestamp)
        {
            $Global:aRecordsToMakeStatic.Add($aRecord)
        } `
        else # NOT ($null -ne $aRecord.Timestamp)
        {
            # Nothing.
        }
    } `
    else # NOT ($ptrRecordMatches)
    {
        # Nothing.
    }
}

<#
    FixPTRRecordBasedOnIPAM should be ran after all relevant data has been loaded and $Global:ipData has been fully populated.

        GetIPAMData          - Get required data from the IPAM database
        GetDHCPData          - Load data about all DHCP scopes, leases, and reservations.
        GetAOVPNData         - Get IP address lists (pseudo DHCP ranges) and connections data
        AddManualDHCPRanges  - Add manual DHCP-like ranges to $Global:dhcpRanges.
        AddMissingIPAMData   - Create nodes in $Global:ipData for addresses which exist in IPAM, but don't appear anywhere else.
        GetDNSData           - Load all DNS records and constructs $Global:ipData
#>
function FixPTRRecordsBasedOnIPAM
{
    $Global:addressesMissingFromIPData = [System.Collections.Generic.List[System.Object]]::new()
    $Global:considerRemovingFromIPAM = [System.Collections.Generic.List[System.Object]]::new()
    $Global:dhcpPTRRecordsToRemove = [System.Collections.Generic.List[System.Object]]::new()
    $Global:dhcpARecordsToRemove = [System.Collections.Generic.List[System.Object]]::new()
    $Global:aRecordsToMakeStatic = [System.Collections.Generic.List[System.Object]]::new()
    $Global:ptrRecordsToMakeStatic = [System.Collections.Generic.List[System.Object]]::new()
    $Global:addressesWhereIPAMHostnameDoesNotMatchARecord = [System.Collections.Generic.List[System.Object]]::new()
    $Global:addressesWhereIPAMHostnameDoesNotMatchPTRRecord = [System.Collections.Generic.List[System.Object]]::new()
    $Global:addressesWhereIPAMAddressDoesNotMatchARecord = [System.Collections.Generic.List[System.Object]]::new()
    $Global:addressesWhereIPAMAddressDoesNotMatchPTRRecord = [System.Collections.Generic.List[System.Object]]::new()
    $Global:addressesToMakeStatic = [System.Collections.Generic.List[System.UInt32]]::new()


    # We are checking addresses which exist in IPAM...
    $ipamAddrKeys = @($Global:ipamRecordsByAddress.Keys)

    # $ipamAddrKeys = @($Global:ipData.Keys)

    $a = 0
    while($a -lt $ipamAddrKeys.Length)
    {
        $addr = $ipamAddrKeys[$a]

        # Only worry about 10 net addresses for now...
        if ($addr -match "^10\.\d+\.\d+\.\d+")
        {
            if ($Global:ipData.ContainsKey($addr))
            {
                # Consider removing the address from IPAM and removing DNS A and PTR records, but only if it is NOT a DHCP reservation
                if (($Global:ipData[$addr].IsDHCPAddress) -and (-not (IsDHCPReservation -addr $Global:ipData[$addr].AddressN)))
                {
                    $Global:considerRemovingFromIPAM.Add($Global:ipData[$addr])
                    $Global:ipData[$addr].ARecords | ForEach-Object {
                        $Global:dhcpARecordsToRemove.Add($_)
                    }
                    $Global:ipData[$addr].PTRRecords | ForEach-Object {
                        $Global:dhcpPTRRecordsToRemove.Add($_)
                    }
                } `
                else # NOT (($Global:ipData[$addr].IsDHCPAddress) -and (-not (IsDHCPReservation -addr $Global:ipData[$addr].AddressN)))
                {
                    # Check 'static' addresses and DHCP reservations.

                    # For now, we only care about PTR records

                    # Did we find a PTR address which does not match the $Global:ipData[$addr].AddressStr
                    $ptrAddressLogged = $false

                    # NOTE:  Remember, $addr here is based on $ipamAddrKeys = @($Global:ipamRecordsByAddress.Keys)
                    #        So, I'm only looking at records in $Global:ipData with have IPAM records.
                    $Global:ipData[$addr].PTRRecords | ForEach-Object {
                        $ptrAddr = GetAddressFromPTR -ptrRec $_
                        if ($addr -eq $ptrAddr)
                        {
                            if ($null -ne $_.Timestamp)
                            {
                                $Global:ptrRecordsToMakeStatic.Add($_)

                                $addrN = INET_ATON $ptrAddr
                                $i = $Global:addressesToMakeStatic.BinarySearch($addrN)
                                if ($i -lt 0)
                                {
                                    $Global:addressesToMakeStatic.Insert(-bnot $i, $addrN)
                                } `
                                else # NOT ($i -lt 0)
                                {
                                    # Nothing.
                                }
                            } `
                            else # NOT ($null -ne $_.Timestamp)
                            {
                                # Nothing.
                            }
                        } `
                        else # NOT ($addr -eq $ptrAddr)
                        {
                            if (-not $ptrAddressLogged)
                            {
                                $Global:addressesWhereIPAMAddressDoesNotMatchPTRRecord.Add($Global:ipData[$addr])
                                $ptrAddressLogged = $true
                            } `
                            else # NOT (-not $ptrAddressLogged)
                            {
                                # Nothing.
                            }
                        }

                        # $_.RecordData.PtrDomainName -notmatch ("^{0}" -f @($hn))
                    }


                    # Did we find an A record address which does not match the $Global:ipData[$addr].AddressStr
                    $aAddressLogged = $false

                    $Global:ipData[$addr].ARecords | ForEach-Object {
                        $aAddr = $_.RecordData.IPv4Address.ToString()
                        if ($addr -eq $aAddr)
                        {
                            if ($null -ne $_.Timestamp)
                            {
                                $Global:aRecordsToMakeStatic.Add($_)

                                $addrN = INET_ATON $aAddr
                                $i = $Global:addressesToMakeStatic.BinarySearch($addrN)
                                if ($i -lt 0)
                                {
                                    $Global:addressesToMakeStatic.Insert(-bnot $i, $addrN)
                                } `
                                else # NOT ($i -lt 0)
                                {
                                    # Nothing.
                                }
                            } `
                            else # NOT ($null -ne $_.Timestamp)
                            {
                                # Nothing.
                            }
                        } `
                        else # NOT ($addr -eq $aAddr)
                        {
                            if (-not $aAddressLogged)
                            {
                                $Global:addressesWhereIPAMAddressDoesNotMatchARecord.Add($Global:ipData[$addr])
                                $aAddressLogged = $true
                            } `
                            else # NOT (-not $ptrAddressLogged)
                            {
                                # Nothing.
                            }
                        }

                        # $_.RecordData.PtrDomainName -notmatch ("^{0}" -f @($hn))
                    }
                }
            } `
            else # NOT ($Global:ipData.ContainsKey($addr))
            {
                $Global:addressesMissingFromIPData.Add($addr)
            }
        } `
        else # NOT ($addr -match "^10\.\d+\.\d+\.\d+")
        {
            # Nothing.
        }

        $a++
    }
}

function SomeName
{
    $recordsToConvertToStatic = [System.Collections.Generic.List[System.Object]]::new()
    $ipamAddresses = @($Global:ipamRecordsByAddress.Keys)
    $a = 0
    while($a -lt $ipamAddresses.Length)
    {
        if ($Global:ipData.ContainsKey($ipamAddresses[$a]))
        {
            if ((-not $Global:ipData[$ipamAddresses[$a]].IsDHCPAddress) -or (IsDHCPReservation -addr $Global:ipData[$ipamAddresses[$a]].AddressN))
            {
                $b = 0
                while($b -lt $Global:ipData[$ipamAddresses[$a]].ARecords.Count)
                {
                    if ($null -ne $Global:ipData[$ipamAddresses[$a]].ARecords[$b].Timestamp)
                    {
                        $recordsToConvertToStatic.Add($Global:ipData[$ipamAddresses[$a]].ARecords[$b])
                    } `
                    else # NOT ($null -ne $Global:ipData[$ipamAddresses[$a]].ARecords[$b].Timestamp)
                    {
                        # Nothing.
                    }
                    $b++
                }

                $b = 0
                while($b -lt $Global:ipData[$ipamAddresses[$a]].PTRRecords.Count)
                {
                    if ($null -ne $Global:ipData[$ipamAddresses[$a]].PTRRecords[$b].Timestamp)
                    {
                        $recordsToConvertToStatic.Add($Global:ipData[$ipamAddresses[$a]].PTRRecords[$b])
                    } `
                    else # NOT ($null -ne $Global:ipData[$ipamAddresses[$a]].PTRRecords[$b].Timestamp)
                    {
                        # Nothing.
                    }
                    $b++
                }
            } `
            else # NOT (-not $Global:ipData[$ipamAddresses[$a]].IsDHCPAddress)
            {
                [Log]::Warning("Non-reservation DHCP Address in IPAM: {0}/{1}" -f @($Global:ipData[$ipamAddresses[$a]].HostName, $Global:ipData[$ipamAddresses[$a]].AddressStr))
            }
        } `
        else # NOT ($Global:ipData.ContainsKey($ipamAddresses[$a]))
        {
            [Log]::Warning("Address: {0} missing from ipData." -f @($ipamAddresses[$a]))
        }
        $a++
    }
}

function FixDynamicARecords
{
    $startDT = [DateTime]::Now.AddHours(-12)
    $past = [DateTime]::Parse("1970-01-01T00:00:00Z")
    $timestamp = [int32] [Math]::Floor(($startDT - $past).TotalSeconds)

    GetIPAMData -lastUpdate $timestamp
    $addresses = @($Global:ipamRecordsByAddress.Keys)

    # Only bother loading DNS records if there is a possibility we need to convert one to static...
    if ($addresses.Length -gt 0)
    {
        $dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses.Length -gt 0 })  # { -not [String]::IsNullOrEmpty($_.ServerAddresses) })

        $aRecs = @()
        $b = 0
        while(($b -lt $dnsServers.Length) -and ($aRecs.Length -eq 0))
        {
            $c = 0
            while(($c -lt $dnsServers[$b].ServerAddresses.Length) -and ($aRecs.Length -eq 0))
            {
                try
                {
                    # Filter the A records down to only the ones that are not static.
                    $aRecs = @(Get-DnsServerResourceRecord -ComputerName $dnsServers[$b].ServerAddresses[$c] -ZoneName "powereng.com" -RRType "A" -ErrorAction Stop | Where-Object { $null -ne $_.Timestamp })
                }
                catch
                {
                    $aRecs = @()
                }
                $c++
            }
            $b++
        }

        if ($aRecs.Length -gt 0)
        {
            $a = 0
            while($a -lt $addresses.Length)
            {
                # Already filtered $aRecs to only dynamic records, so no need to check .Timestamp
                $dynamicARec = $aRecs | Where-Object { $_.RecordData.IPv4Address.ToString()-eq $addresses[$a]}
                if ($null -ne $dynamicARec)
                {
                    if ((MakeDNSRecordStatic -dnsRec $dynamicARec))
                    {
                        [Log]::Info("Converted {0}/{1} to static record." -f @($addresses[$a], $dynamicARec.HostName))
                    } `
                    else # NOT ((MakeDNSRecordStatic -dnsRec $dynamicARec))
                    {
                        [Log]::Warning("Failed to convert {0}/{1} to static record." -f @($addresses[$a], $dynamicARec.HostName))
                    }
                } `
                else # NOT ($null -ne $dynamicARec)
                {
                    # Nothing.
                }
                $a++
            }
        } `
        else # NOT ($aRecs.Length -gt 0)
        {
            [Log]::Error("No DNS A records loaded.")
        }
    } `
    else # NOT ($addresses.Length -gt 0)
    {
        [Log]::Info("No IPAM records changed since {0}." -f @($startDT.ToString()))
    }
}


$Global:IPAMDataAvailable = $false
$Global:DHCPDataAvailable = $false
$Global:Good2Go = $true
$Global:baseBM = [int64] (INET_ATON -ipStr "255.255.255.255")
$Global:dhcpRangeComparer = [DHCPRangeComparer]::new()
$Global:dnsHostNameToIgnore = @(
    "@", "gc._msdcs", "DomainDnsZones", "ForestDnsZones"
)

$Global:aRecords = [System.Collections.Generic.SortedDictionary[System.String, [System.Collections.Generic.List[System.Object]]]]::new()
$Global:ptrRecords = [System.Collections.Generic.List[System.Object]]::new()

$Global:IPAMDataAvailable = $false
$Global:ipamDB = $null
$Global:ipamDNSServers = [System.Collections.Generic.List[System.Data.DataRow]]::new()

#  Build a connection string from the configuration data and the credential
$Global:dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};Default Command Timeout=600;" -f @(
    "ddc-ipam02.powereng.com",
    3306,
    "gestioip",
    "gestioip",
    "1n33dmCB!"
)

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\TempTest\Log.ps1

$logPath = "{0}\FixDNSPTR2.log" -f @($env:TEMP)
[Log]::Init($logPath, "FixDNS", 14, 1, [LogLevel]::INFO)
[Log]::Info("Logging initialized...")

#   vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
{
    [System.Reflection.Assembly]::LoadWithPartialName("MySQL.Data") | Out-Null

    if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
    {
        throw "Unable to load MySQL.Data assembly."
    } `
    else
    {
    }
}
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\TempTest\DBConnectionMYSQL.ps1


# Get the data for the DNS clean up spreadsheet.  Run after FixPTRRecordsBasedOnIPAM
$considerRemovingFromIPAM | ForEach-Object { IPDataToCSV -node $_ } | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard

$Global:addressesToMakeStatic | ForEach-Object {
    $addr = INET_NTOA $_
    if ($Global:ipData.ContainsKey($addr))
    {
        IPDataToCSV -node $Global:ipData[$addr]
    } `
    else # NOT ($Global:ipData.ContainsKey($ptrAddr))
    {
        Write-Host -ForegroundColor Red ("Missing node for address: {0}" -f @($ptrAddr))
    }
} | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard


# Code to remove IPAM/PTR/A records
$Global:dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Length -gt 0 })  # { -not [String]::IsNullOrEmpty($_.ServerAddresses) })

function RemoveDNSRecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $dnsRec
    )

    $removed = $false
    if ($null -ne $Global:dnsServers)
    {
        $Global:dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Length -gt 0 })  # { -not [String]::IsNullOrEmpty($_.ServerAddresses) })
    } `
    else # NOT ($null -ne $Global:dnsServers)
    {
        # Nothing
    }

    if (($null -ne $Global:dnsServers) -and ($Global:dnsServers.Length -gt 0))
    {
        $zoneName = [String]::Empty
        $message = [String]::Empty
        $rrType = $dnsRec.RecordType
        $recordData = [String]::Empty
        switch($rrType)
        {
            "A" {
                $zoneName = "powereng.com"
                $message = "A: {0}/{1}" -f @($dnsRec.HostName, $dnsRec.RecordData.IPv4Address.ToString())
                $recordData = $dnsRec.RecordData.IPv4Address.ToString()
            }
            "PTR" {
                $zoneName = "10.in-addr.arpa"
                $message = "PTR: {0}/{1}" -f @($dnsRec.RecordData.PtrDomainName, (GetAddressFromPTR -ptrRec $dnsRec))
                $recordData = $dnsRec.RecordData.PtrDomainName
            }
        }

        if (-not [String]::IsNullOrEmpty($zoneName))
        {
            $a = 0
            while((-not $removed) -and ($a -lt $Global:dnsServers.Length))
            {
                $b = 0
                while((-not $removed) -and ($b -lt $Global:dnsServers[$a].ServerAddresses.Length))
                {
                    try
                    {
                        Remove-DnsServerResourceRecord -ComputerName $Global:dnsServers[$a].ServerAddresses[$b] -ZoneName $zoneName -RRType $rrType -Name $dnsRec.HostName -Force -ErrorAction Stop
                        [Log]::Info("`tRemoved: {0}" -f @($message))
                        $removed = $true
                    }
                    catch
                    {
                        [Log]::Warning("Failed to remove: {0}" -f @($message))
                    }
                    $b++
                }
                $a++
            }

            if(-not $removed)
            {
                # Write-Host -ForegroundColor Red ("Failed to remove DNS record {0}" -f @($message))
            }
        } `
        else # NOT (-not [String]::IsNullOrEmpty($zoneName))
        {
            # Nothing.
        }
    } `
    else # NOT (($null -ne $Global:dnsServers) -and ($Global:dnsServers.Length -gt 0))
    {
        # Nothing.
    }

    return $removed
}

function RemoveIPAMRecord
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Int32]
        $id
    )

    $recordsDeleted = 0
    if ($null -eq $Global:ipamDB)
    {
        try
        {
            #  Make a connection to the database
            $Global:ipamDB = [MySQLDBConnection]::new($Global:dbConnectionString)
        }
        catch
        {
            [Log]::Warning("Failed to connect to IPAM database.")
            $Global:ipamDB = $null
        }
    } `
    else # NOT ($null -eq $Global:ipamDB)
    {
        # Nothing.
    }


    if ($null -ne $Global:ipamDB)
    {
        <#
        $dt = $Global:ipamDB.GetDataTable(("SELECT * FROM host WHERE id = {0};" -f @($id)))
        if ($null -ne $dt)
        {
            $a = 0
            while($a -lt $dt.Rows.Count)
            {
                [Log]::Info("`tFound IPAM record: {0}:{1}/{2}" -f @($dt.Rows[$a].id, $dt.Rows[$a].hostname, (INET_NTOA($dt.Rows[$a].ip))))
                $a++
            }
            $recordsDeleted = $dt.Rows.Count
        } `
        else # NOT ($null -ne $dt)
        {
            # Nothing.
        }
        #>

        $recordsDeleted = $Global:ipamDB.ExecuteNonQuery(("DELETE FROM host WHERE id = {0};" -f @($id)))
        if ($recordsDeleted -gt 0)
        {
            if ($recordsDeleted -gt 1)
            {
                [Log]::Info("`tRemoved {0} IPAM records" -f @($recordsDeleted))
            } `
            else # NOT ($recordsDeleted -gt 1)
            {
                [Log]::Info("`tRemoved {0} IPAM record" -f @($recordsDeleted))
            }
        } `
        else # NOT ($recordsDeleted -gt 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $Global:ipamDB)
    {
        # Nothing
    }

    return $recordsDeleted
}

function MakeDNSRecordStatic
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $dnsRec
    )

    $convertedToStatic = $false
    if ($null -ne $Global:dnsServers)
    {
        $Global:dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses.Length -gt 0 })  # { -not [String]::IsNullOrEmpty($_.ServerAddresses) })
    } `
    else # NOT ($null -ne $Global:dnsServers)
    {
        # Nothing
    }

    if (($null -ne $Global:dnsServers) -and ($Global:dnsServers.Length -gt 0))
    {
        $zoneName = $null
        try
        {
            $zoneName = @(@($dnsRec.DistinguishedName -split ",")[1] -split "=")[1]
        }
        catch
        {
            [Log]::Warning("Unable to get zone name from {0}" -f @($dnsRec.DistinguishedName))
        }

        if (-not [String]::IsNullOrEmpty($zoneName))
        {
            $message = [String]::Empty
            switch($dnsRec.RecordType)
            {
                "A" {
                    $message = "A: {0}/{1}" -f @($dnsRec.HostName, $dnsRec.RecordData.IPv4Address.ToString())
                }
                "PTR" {
                    $message = "PTR: {0}/{1}" -f @($dnsRec.RecordData.PtrDomainName, (GetAddressFromPTR -ptrRec $dnsRec))
                }

                Default {
                    $message = "Unexpected record type: [{0}]" -f @($dnsRec.RecordType)
                }
            }

            $a = 0
            while((-not $convertedToStatic) -and ($a -lt $Global:dnsServers.Length))
            {
                $b = 0
                while((-not $convertedToStatic) -and ($b -lt $Global:dnsServers[$a].ServerAddresses.Length))
                {
                    try
                    {
                        Set-DnsServerResourceRecord -ComputerName $Global:dnsServers[$a].ServerAddresses[$b] -ZoneName $zoneName -NewInputObject $dnsRec -OldInputObject $dnsRec | Out-Null
                        [Log]::Info("`tConverted to Static: {0}" -f @($message))
                        $convertedToStatic = $true
                    }
                    catch
                    {
                        # Nothing, handled below...
                    }
                    $b++
                }

                if (-not $convertedToStatic)
                {
                    [Log]::Warning("`tFailed to convert to Static: {0}" -f @($message))
                } `
                else # NOT (-not $convertedToStatic)
                {
                    # Nothing.
                }
                $a++
            }
        } `
        else # NOT (-not [String]::IsNullOrEmpty($zoneName))
        {
            # Nothing.
        }
    } `
    else # NOT (($null -ne $Global:dnsServers) -and ($Global:dnsServers.Length -gt 0))
    {
        # Nothing.
    }

    return $convertedToStatic
}

# Set-DnsServerResourceRecord -ComputerName 10.245.3.10 -NewInputObject $ipData["10.15.40.10"].ARecords[0] -OldInputObject $ipData["10.15.40.10"].ARecords[0] -ZoneName "powereng.com"

$staticConversions = 0
$considered = 0
$aRecordsRemoved = 0
$ptrRecordsRemoved = 0
$ipamRecordsRemoved = 0
$aRecordsConvertedToStatic = 0
$ptrRecordsConvertedToStatic = 0

$addressesToProcess = [System.Collections.Generic.List[System.UInt32]]::new()

$Global:addressesToMakeStatic | Foreach-Object { $addressesToProcess.Add($_) }
$addressesToProcess.Sort()

$Global:considerRemovingFromIPAM | Foreach-Object {
    $i = $addressesToProcess.BinarySearch($_.AddressN)
    if ($i -lt 0)
    {
        $addressesToProcess.Insert(-bnot $i, $_.AddressN)
    } `
    else # NOT ($i -lt 0)
    {
        # Nothing.
    }
}

$a = 0
while($a -lt $addressesToProcess.Count)
{
    $addr = INET_NTOA -ipAddress $addressesToProcess[$a]
    [Log]::Info("Processing IP Address: {0}" -f @($addr))

    $nodeToProcess = $Global:considerRemovingFromIPAM | Where-Object { $_.AddressN -eq $addressesToProcess[$a] }
    if ($null -ne $nodeToProcess)
    {
        $considered++
        # Remove A records...
        $b = 0
        while($b -lt $nodeToProcess.ARecords.Count)
        {
            if ($nodeToProcess.AddressStr -eq $nodeToProcess.ARecords[$b].RecordData.IPv4Address.ToString())
            {
                if ((RemoveDNSRecord -dnsRec $nodeToProcess.ARecords[$b]))
                {
                    $aRecordsRemoved++
                } `
                else # NOT ((RemoveDNSRecord -dnsRec $nodeToProcess.ARecords[$b]))
                {
                    # Nothing.
                }
            } `
            else # NOT($nodeToProcess.AddressStr -eq $nodeToProcess.ARecords[$b].RecordData.IPv4Address.ToString())
            {
                # Nothing.
            }
            $b++
        }

        # Remove all the PTR records with addresses matching $nodeToProcess.AddressStr
        $b = 0
        while($b -lt $nodeToProcess.PTRRecords.Count)
        {
            if ($nodeToProcess.AddressStr -eq (GetAddressFromPTR $nodeToProcess.PTRRecords[$b]))
            {
                if ((RemoveDNSRecord -dnsRec $nodeToProcess.PTRRecords[$b]))
                {
                    $ptrRecordsRemoved++
                } `
                else # NOT ((RemoveDNSRecord -dnsRec $nodeToProcess.PTRRecords[$b]))
                {
                    # Nothing.
                }
            } `
            else # NOT ($nodeToProcess.AddressStr -eq (GetAddressFromPTR $nodeToProcess.PTRRecords[$b]))
            {
                # Nothing.
            }
            $b++
        }

        # Remove IPAM records for DHCP like addresses...
        $b = 0
        while($b -lt $nodeToProcess.IPAMRecords.Count)
        {
            if ($nodeToProcess.AddressStr -eq $nodeToProcess.IPAMRecords[$b].address)
            {
                $ipamRecordsRemoved += (RemoveIPAMRecord -id $nodeToProcess.IPAMRecords[$b].id)
            } `
            else # NOT ($nodeToProcess.AddressStr -eq $nodeToProcess.IPAMRecords[$b].address)
            {
                # Nothing.
            }
            $b++
        }
    } `
    else # NOT ($null -ne $nodeToProcess)
    {
        # Nothing.
    }

    # See if we need to convert this address's A and/or PTR records to static...
    $i = $Global:addressesToMakeStatic.BinarySearch($addressesToProcess[$a])
    if ($i -ge 0)
    {
        $staticConversions++
        if ($Global:ipData.ContainsKey($addr))
        {
            $nodeToProcess = $Global:ipData[$addr]

            # Convert A records to static...
            $b = 0
            while($b -lt $nodeToProcess.ARecords.Count)
            {
                if ($null -ne $nodeToProcess.ARecords[$b].Timestamp)
                {
                    if ((MakeDNSRecordStatic -dnsRec $nodeToProcess.ARecords[$b]))
                    {
                        $aRecordsConvertedToStatic++
                    } `
                    else # NOT ((MakeDNSRecordStatic -dnsRec $nodeToProcess.ARecords[$b]))
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($null -ne $nodeToProcess.ARecords[$b].Timestamp)
                {
                    # Nothing.
                }
                $b++
            }

            # Convert PTR records to static...
            $b = 0
            while($b -lt $nodeToProcess.PTRRecords.Count)
            {
                if ($null -ne $nodeToProcess.PTRRecords[$b].Timestamp)
                {
                    if ((MakeDNSRecordStatic -dnsRec $nodeToProcess.PTRRecords[$b]))
                    {
                        $ptrRecordsConvertedToStatic++
                    } `
                    else # NOT ((MakeDNSRecordStatic -dnsRec $nodeToProcess.PTRRecords[$b]))
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($null -ne $nodeToProcess.PTRRecords[$b].Timestamp)
                {
                    # Nothing.
                }
                $b++
            }
        } `
        else # NOT ($Global:ipData.ContainsKey($addr))
        {
            [Log]::Warning("{0} not found in ipData!" -f @($addr))
        }
    } `
    else # NOT ($i -ge 0)
    {
        # Nothing.
    }
    $a++
}
[Log]::Info("Removed {0} A Records" -f @($aRecordsRemoved))
[Log]::Info("Removed {0} PTR Records" -f @($ptrRecordsRemoved))
[Log]::Info("Removed {0} IPAM Records" -f @($ipamRecordsRemoved))
[Log]::Info("Converted {0} A Records to static" -f @($aRecordsConvertedToStatic))
[Log]::Info("Converted {0} PTR Records to static" -f @($ptrRecordsConvertedToStatic))
[Log]::Info("Considered: {0}" -f @($considered))
[Log]::Info("Static conversions: {0}" -f @($staticConversions))





while($a -lt $Global:considerRemovingFromIPAM.Count)
{
    [Log]::Info("Removing records for: {0}" -f @($Global:considerRemovingFromIPAM[$a].AddressStr))
    # Remove all the A records with addresses matching $Global:considerRemovingFromIPAM[$a].AddressStr
    $b = 0
    while($b -lt $Global:considerRemovingFromIPAM[$a].ARecords.Count)
    {
        if ($Global:considerRemovingFromIPAM[$a].AddressStr -eq $Global:considerRemovingFromIPAM[$a].ARecords[$b].RecordData.IPv4Address.ToString())
        {
            if ((RemoveDNSRecord -dnsRec $Global:considerRemovingFromIPAM[$a].ARecords[$b]))
            {
                $dnsRecordsRemoved++
            } `
            else # NOT ((RemoveDNSRecord -dnsRec $Global:considerRemovingFromIPAM[$a].ARecords[$b]))
            {
                # Nothing.
            }
        } `
        else # NOT ($Global:considerRemovingFromIPAM[$a].AddressStr -eq $Global:considerRemovingFromIPAM[$a].ARecords[$b].RecordData.IPv4Address.ToString())
        {
            # Nothing.
        }
        $b++
    }

    # Remove all the PTR records with addresses matching $Global:considerRemovingFromIPAM[$a].AddressStr
    $b = 0
    while($b -lt $Global:considerRemovingFromIPAM[$a].PTRRecords.Count)
    {
        if ($Global:considerRemovingFromIPAM[$a].AddressStr -eq (GetAddressFromPTR $Global:considerRemovingFromIPAM[$a].PTRRecords[$b]))
        {
            if ((RemoveDNSRecord -dnsRec $Global:considerRemovingFromIPAM[$a].PTRRecords[$b]))
            {
                $dnsRecordsRemoved++
            } `
            else # NOT ((RemoveDNSRecord -dnsRec $Global:considerRemovingFromIPAM[$a].PTRRecords[$b]))
            {
                # Nothing.
            }
        } `
        else # NOT ($Global:considerRemovingFromIPAM[$a].AddressStr -eq (GetAddressFromPTR $Global:considerRemovingFromIPAM[$a].PTRRecords[$b]))
        {
            # Nothing.
        }
        $b++
    }

    $b = 0
    while($b -lt $Global:considerRemovingFromIPAM[$a].IPAMRecords.Count)
    {
        if ($Global:considerRemovingFromIPAM[$a].AddressStr -eq $Global:considerRemovingFromIPAM[$a].IPAMRecords[$b].address)
        {
            if ((RemoveIPAMRecord -id $Global:considerRemovingFromIPAM[$a].IPAMRecords[$b].id))
            {
                $ipamRecordsRemoved++
            } `
            else # NOT ((RemoveIPAMRecord -id $Global:considerRemovingFromIPAM[$a].IPAMRecords[$b].id))
            {
                # Nothing.
            }
        } `
        else # NOT ($Global:considerRemovingFromIPAM[$a].AddressStr -eq $Global:considerRemovingFromIPAM[$a].IPAMRecords[$b].address)
        {
            # Nothing.
        }
        $b++
    }
    $a++
}

$a = 0
$dnsRecordsConvertedToStatic = 0
while($a -lt $Global:addressesToMakeStatic.Count)
{
    $addr = INET_NTOA -ipAddress $Global:addressesToMakeStatic[$a]
    if ($Global:ipData.ContainsKey($addr))
    {
        $b = 0
        while($b -lt $Global:ipData[$addr].ARecords.Count)
        {
            if ($null -ne $Global:ipData[$addr].ARecords[$b].Timestamp)
            {
                if ((MakeDNSRecordStatic -dnsRec $Global:ipData[$addr].ARecords[$b]))
                {
                    $dnsRecordsConvertedToStatic++
                } `
                else # NOT ((MakeDNSRecordStatic -dnsRec $Global:ipData[$addr].ARecords[$b]))
                {
                    # Nothing.
                }
            } `
            else # NOT ($null -ne $Global:ipData[$addr].ARecords[$b].Timestamp)
            {
                # Nothing.
            }
            $b++
        }

        $b = 0
        while($b -lt $Global:ipData[$addr].PTRRecords.Count)
        {
            if ($null -ne $Global:ipData[$addr].PTRRecords[$b].Timestamp)
            {
                if ((MakeDNSRecordStatic -dnsRec $Global:ipData[$addr].PTRRecords[$b]))
                {
                    $dnsRecordsConvertedToStatic++
                } `
                else # NOT ((MakeDNSRecordStatic -dnsRec $Global:ipData[$addr].PTRRecords[$b]))
                {
                    # Nothing.
                }
            } `
            else # NOT ($null -ne $Global:ipData[$addr].PTRRecords[$b].Timestamp)
            {
                # Nothing.
            }
            $b++
        }
    } `
    else # NOT ($Global:ipData.ContainsKey($addr))
    {
        # Nothing.
    }
    $a++
}



$addrKeys = @($ipData.Keys)

$a = 0
while($a -lt $addrKeys.Length)
{
    $addr = $addrKeys[$a]
    # First, is this a DHCP address?
    if ($ipData[$addr].IsDHCPAddress)
    {
        # Yes...

        $ranges = @($dhcpRanges | Where-Object { ($_.Start -le $ipData[$addr].AddressN) -and ($ipData[$addr].AddressN -le $_.End) })
        $b = 0
        $isDHCPReservation = $false
        while($b -lt $ranges.Length)
        {
            if ($ranges[$b].Type -eq "DHCP")
            {
                if ($ranges[$b].Assignments.ContainsKey($addr))
                {
                    $addrAssignment = $ranges[$b].Assignments[$addr]
                    $isDHCPReservation = $isDHCPReservation -or ($addrAssignment.AddressState -match "Reservation")
                } `
                else # NOT ($ranges[$b].Assignments.ContainsKey($addr))
                {
                    # Nothing.
                }
            } `
            else # NOT ($ranges[$b].Type -eq "DHCP")
            {
                # Nothing.
            }
            $b++
        }



        # Ok, is it a lease, or a reservation?
        if ($Global:AddressAssignments.ContainsKey($addr))
        {
            $addrAssignments = $Global:AddressAssignments[$addr]

        } `
        else # NOT ($Global:AddressAssignments.ContainsKey($addr))
        {
            # Nothing.
        }
    } `
    else # NOT ($ipData[$addr].IsDHCPAddress)
    {
        # Nothing.
    }
}

$addressesWithMismatchedARecords = [System.Collections.Generic.List[System.Object]]::new()
$addressesWithMismatchedPTRRecords = [System.Collections.Generic.List[System.Object]]::new()
$addressesWithMismatchedIPAMRecords = [System.Collections.Generic.List[System.Object]]::new()
$addressesMissingPTRRecord = [System.Collections.Generic.List[System.Object]]::new()
$addressesMissingARecord = [System.Collections.Generic.List[System.Object]]::new()
$addressesMissingIPAMRecord = [System.Collections.Generic.List[System.Object]]::new()
$addressesWhereIPAMRecordDoesNotMatchPTR = [System.Collections.Generic.List[System.Object]]::new()
$cleanAddresses = [System.Collections.Generic.List[System.Object]]::new()
$dirtyAddresses = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $addrKeys.Length)
{
    $aRecordMismatch = $false
    $ptrRecordMismatch = $false
    $ipamRecordMismatch = $false

    if ($ipData[$addrKeys[$a]].ARecords.Count -gt 0)
    {
        if (@($ipData[$addrKeys[$a]].ARecords | Where-Object { $_.RecordData.IPv4Address.ToString() -ne $addrKeys[$a]}).Length -gt 0)
        {
            $addressesWithMismatchedARecords.Add($ipData[$addrKeys[$a]])
            $aRecordMismatch = $true
        } `
        else # NOT (@($ipData[$addrKeys[$a]].ARecords | Where-Object { $_.RecordData.IPv4Address.ToString() -ne $addrKeys[$a]}).Length -gt 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($ipData[$addrKeys[$a]].ARecords.Count -gt 0)
    {
        $addressesMissingARecord.Add($ipData[$addrKeys[$a]])
    }

    if ($ipData[$addrKeys[$a]].PTRRecords.Count -gt 0)
    {
        if (@($ipData[$addrKeys[$a]].PTRRecords | Where-Object { (GetAddressFromPTR $_) -ne $addrKeys[$a]}).Length -gt 0)
        {
            $addressesWithMismatchedPTRRecords.Add($ipData[$addrKeys[$a]])
            $ptrRecordMismatch = $true
        } `
        else # NOT (@($ipData[$addrKeys[$a]].ARecords | Where-Object { $_.RecordData.IPv4Address.ToString() -ne $addrKeys[$a]}).Length -gt 0)
        {
            # Nothing.
        }

        $b = 0
        while($b -lt $ipData[$addrKeys[$a]].PTRRecords.Count)
        {
            $addr = GetAddressFromPTR $ipData[$addrKeys[$a]].PTRRecords[$b]
            if (@($ipData[$addrKeys[$a]].IPAMRecords | Where-Object { $_.address -ne $addr }).Length -gt 0)
            {
                $addressesWhereIPAMRecordDoesNotMatchPTR.Add($ipData[$addrKeys[$a]])
                break
            } `
            else # NOT (@($ipData[$addrKeys[$a]].IPAMRecords | Where-Object { $_.address -ne $addr }).Length -gt 0)
            {
                # Nothing.
            }
            $b++
        }
    } `
    else # NOT ($ipData[$addrKeys[$a]].PTRRecords.Count -gt 0)
    {
        $addressesMissingPTRRecord.Add($ipData[$addrKeys[$a]])
    }

    if ($ipData[$addrKeys[$a]].IPAMRecords.Count -gt 0)
    {
        if (@($ipData[$addrKeys[$a]].IPAMRecords | Where-Object { $_.address -ne $addrKeys[$a] }).Length -gt 0)
        {
            $addressesWithMismatchedIPAMRecords.Add($ipData[$addrKeys[$a]])
            $ipamRecordMismatch = $true
        } `
        else # NOT (@($ipData[$addrKeys[$a]].ARecords | Where-Object { $_.RecordData.IPv4Address.ToString() -ne $addrKeys[$a]}).Length -gt 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($ipData[$addrKeys[$a]].PTRRecords.Count -gt 0)
    {
        $addressesMissingIPAMRecord.Add($ipData[$addrKeys[$a]])
    }

    if ($aRecordMismatch -or $ptrRecordMismatch -or $ipamRecordMismatch)
    {
        $dirtyAddresses.Add($ipData[$addrKeys[$a]])
    } `
    else # NOT (-not ($aRecordMismatch -or $ptrRecordMismatch -or $ipamRecordMismatch))
    {
        $cleanAddresses.Add($ipData[$addrKeys[$a]])
    }

    $a++
}
Write-Host ("Addresses with mismatched A Records: {0}" -f @($addressesWithMismatchedARecords.Count))
Write-Host ("Addresses with mismatched PTR Records: {0}" -f @($addressesWithMismatchedPTRRecords.Count))
Write-Host ("Addresses with mismatched IPAM Records: {0}" -f @($addressesWithMismatchedIPAMRecords.Count))
Write-Host ("Addresses missing A Record: {0}" -f @($addressesMissingARecord.Count))
Write-Host ("Addresses missing PTR Record: {0}" -f @($addressesMissingPTRRecord.Count))
Write-Host ("Addresses missing IPAM Record: {0}" -f @($addressesMissingIPAMRecord.Count))
Write-Host ("Addresses where PTR and IPAM differ: {0}" -f @($addressesWhereIPAMRecordDoesNotMatchPTR.Count))
Write-Host ("Clean addresses: {0}" -f @($cleanAddresses.Count))
Write-Host ("Dirty addresses: {0}" -f @($dirtyAddresses.Count))






$aovpnAssignments = [System.Collections.Generic.List[System.Object]]::new()
$dhcpAssignments = [System.Collections.Generic.List[System.Object]]::new()
$dhcpRanges | ForEach-Object {
    if ($_.Type -eq "AOVPN")
    {
        @($_.Assignments.Values) | Foreach-Object {
            $aovpnAssignments.Add($_)
        }
    } `
    else # NOT ($_.Type -eq "AOVPN")
    {
        @($_.Assignments.Values) | Foreach-Object {
            $dhcpAssignments.Add($_)
        }
    }
}

$dhcpAddresses = @(
    @($Global:ipData.Values) | Where-Object { $_.IsDHCPAddress }
)

$dhcpLeases = [System.Collections.Generic.List[System.Object]]::new()
$dhcpReservations = [System.Collections.Generic.List[System.Object]]::new()
$dhcpAddressesInIPAM = [System.Collections.Generic.List[System.Object]]::new()
$dhcpReservationsInIPAM = [System.Collections.Generic.List[System.Object]]::new()
$dhcpAddresses | ForEach-Object {
    if(IsDHCPReservation -addr $_.AddressN)
    {
        $dhcpReservations.Add($_)
        if ($_.IsInIPAMByAddress -or $_.IsInIPAMByName)
        {
            $dhcpReservationsInIPAM.Add($_)
        } `
        else # NOT ($_.IsInIPAMByAddress -or $_.IsInIPAMByName)
        {
            # Nothing.
        }
    } `
    else
    {
        $dhcpLeases.Add($_)
    }

    if ($_.IsInIPAMByAddress -or $_.IsInIPAMByName)
    {
        $dhcpAddressesInIPAM.Add($_)
    } `
    else # NOT ($_.IsInIPAMByAddress -or $_.IsInIPAMByName)
    {
        # Nothing.
    }
}

$addressesInIPAM = @(
    @($ipData.Values) | Where-Object { ($_.IPAMRecords.Count -gt 0) }
)

$aRecordsToDelete = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $addressesInIPAM.Length)
{
    $b = 0
    $aRecToDeleteCount = 0
    while($b -lt $addressesInIPAM[$a].ARecords.Count)
    {
        if ($addressesInIPAM[$a].ARecords[$b].HostName -cne $addressesInIPAM[$a].IPAMRecords)
        {

        } `
        else # NOT ($addressesInIPAM[$a].ARecords[$b].HostName -cne $addressesInIPAM[$a].IPAMRecords)
        {
            # Nothing.
        }
    }
    $a++
}

$nonStaticAddressesInIPAM = @(
    $addressesInIPAM | Where-Object { (($_.PTRRecords | Where-Object { $null -ne $_.Timestamp }).Length -gt 0) -or (($_.ARecords | Where-Object { $null -ne $_.Timestamp }).Length -gt 0) }
)

$nonStaticAddressesInIPAM | ForEach-Object {
    $hn = $_.HostName
    # $_.ARecords | Where-Object { $_.HostName -notmatch $_.HostName }
    $_.PTRRecords | Where-Object { $_.RecordData.PtrDomainName -notmatch ("^{0}" -f @($hn)) }
}


$cleanAddresses = @(
    @($ipData.Values) | Where-Object { (-not $_.IsDHCPAddress) -and ($_.ARecords.Count -eq 1) -and (@($_.ARecords | Where-Object { $null -ne $_.Timestamp }).Length -eq 0) -and ($_.PTRRecords.Count -eq 1) -and (@($_.PTRRecords | Where-Object { $null -ne $_.Timestamp }).Length -eq 0) }
)


$ipsInIPAMNoARecord = @(
    @($Global:ipData.Values) | Where-Object { ($_.IsInIPAMByAddress -or $_.IsInIPAMByName) -and ($_.ARecords.Count -eq 0) }
)

$dhcpLeasesWithStaticDNSRecords = @(
    $dhcpLeases | Where-Object { (@($_.PTRRecords | Where-Object { $null -eq $_.Timestamp }).Length -gt 0) -or (@($_.ARecords | Where-Object { $null -eq $_.Timestamp }).Length -gt 0) }
#    @($ipData.Values) | Where-Object { $_.PTRRecords | Where-Object { $null -eq $_.Timestamp } }
)


$dhcpLeasesInIPAM = @(
    $dhcpLeases | Where-Object { $_.IsInIPAMByAddress -or $_.IsInIPAMByName }
)

@($recordsWithPTRAndNoA | Where-Object { $_.HasIPAMSubnet }).Length

@($recordsWithPTRAndNoA | Where-Object { $_.IsInIPAMByAddress }).Length

@($recordsWithPTRAndNoA | Where-Object { $_.IsInIPAMByAddress })[0]

$node = @($recordsWithPTRAndNoA | Where-Object { $_.IsInIPAMByAddress })[0]

$nodeAssignments = @(
    if ($node.IsDHCPAddress)
    {
        $ranges = @($dhcpRanges | Where-Object { ($_.Start -le $node.AddressN) -and ($node.AddressN -le $_.End) })

        $ranges | ForEach-Object {
            if ($_.Assignments.ContainsKey($node.AddressStr))
            {
                $_.Assignments[$node.AddressStr]
            } `
            else # NOT ($_.Assignments.ContainsKey($node.AddressStr))
            {
                # Nothing.
            }
        }
    } `
    else # NOT ($node.IsDHCPAddress)
    {
        # Nothing.
    }
)

$testAddressCount = 10
$testAddresses = @($addrKeys | Select-Object -Skip (Get-Random -Minimum 0 -Maximum $testAddressCount) -First $testAddressCount)

$deadAddresses = @(@($ipData.Values) | Where-Object { ($_.AddressStr -match "(^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)") -and $_.HasIPAMSubnet -and (-not $_.Pingable) } | Sort-Object AddressN | Select-Object -ExpandProperty AddressStr)

$deadAddresses | Foreach-Object -ThrottleLimit 50 -Parallel {
    $ipD = $using:ipData

    if(-not $ipD[$_].Pingable)
    {
        if(Test-Connection -ComputerName $_ -Quiet)
        {
            Write-Host -ForegroundColor Green ("{0}:{1} is alive" -f ($ipD[$_].HostName, $_))
            $ipD[$_].Pingable = $true
        } `
        else
        {
            Write-Host -ForegroundColor Red ("{0} is dead" -f ($_))
        }
    }
}



$Global:ipData = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()


$notInIPAMByAddress = @(@($Global:ipData.Values | Where-Object { (-not $_.IsInIPAMByAddress) -and (-not $_.IsDHCPAddress)}))
$dhcpAddresses = @(@($Global:ipData.Values | Where-Object { $_.IsDHCPAddress }))

$notInIPAMByAddress.ForEach({  $p = (ping -n 1 $($_.AddressStr)) -match "Sent ="; Write-Host ("{0,15} {1}" -f @($_.AddressStr, $p[0])) })

$addrKeys = @($Global:ipData.Keys)
$a = 0
while($a -lt $addrKeys.Length)
{
    $percentComplete = (($a + 1)  / $addrKeys.Length)
    $status = "{0} of {1} | {2,7:P2} Complete..." -f @(($a + 1), $addrKeys.Length, $percentComplete)
    Write-Progress -Id 2 -Activity "Checking for IPAM subnets" -Status $status -PercentComplete ($percentComplete * 100.0)

    $Global:ipData[$addrKeys[$a]].HasIPAMSubnet = (IPAMSubnetsForAddress -ipStr $Global:ipData[$addrKeys[$a]].AddressStr).Length -gt 0
    $a++
}
Write-Progress -Id 2 -Activity "Checking for IPAM subnets" -Status "Complete..." -PercentComplete 100.0


IsInIPAM = $ipamRecordsByAddress.ContainsKey($addr)
ARecords = [System.Collections.Generic.List[System.Object]]::new()
IsStaticRecord = ($null -eq $ptrRecordsByAddress[$addr][$b].Timestamp)





$ipamRecordsByAddress = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()
$a = 0
while($a -lt $ipamRecords.Count)
{
    if($ipamRecords[$a].address -match "^10\.")
    {
        if (-not $ipamRecordsByAddress.ContainsKey($ipamRecords[$a].address))
        {
            $ipamRecordsByAddress.Add($ipamRecords[$a].address, $ipamRecords[$a])
        } `
        else # NOT (-not $ipamRecordsByAddress.ContainsKey($ipamRecords[$a].address))
        {
            Write-Host -ForegroundColor Red ("Duplicate address: {0}" -f @($ipamRecords[$a].address))
        }
    }
    $a++
}

$reportData = [System.Collections.Generic.List[System.Object]]::new()

$reportNode = [PSCustomObject]@{
    PTRRecord = $null
    Address = "10.0.0.0"
    HasIPAMSubnet = $true
    ARecords = [System.Collections.Generic.List[System.Object]]::new()
    IsStaticRecord = $false
}

$sbIPAMMissing = [System.Text.StringBuilder]::new()
$sbARecDups = [System.Text.StringBuilder]::new()
$sbARecNonNullTS = [System.Text.StringBuilder]::new()
$addressesWithNoIPAMSubnet = [System.Collections.Generic.List[System.String]]::new()
$addrKeys = @($aRecordsByAddress.Keys)
$a = 0
while($a -lt $addrKeys.Length)
{
    if (($a % 100) -eq 0)
    {
        $x = [Console]::CursorLeft
        Write-Host -NoNewline ("{0}." -f @($a))
        [Console]::CursorLeft = $x + 1
    } `
    else # NOT (($a % 100) -eq 0)
    {
        # Nothing.
    }
    $addr = $addrKeys[$a]

    if (@(IPAMSubnetsForAddress -ipStr $addr).Length -eq 0)
    {
        $i = $addressesWithNoIPAMSubnet.BinarySearch($addr)
        if ($i -lt 0)
        {
            $addressesWithNoIPAMSubnet.Insert(-bnot $i, $addr)
        } `
        else # NOT ($i -lt 0)
        {
            # Nothing.
        }
    } `
    else # NOT (@(IPAMSubnetsForAddress -ipStr $addr).Length -eq 0)
    {
        # Nothing.
    }

    if($aRecordsByAddress[$addr].Count -gt 1)
    {
        $null = $sbARecDups.AppendLine("{0}:" -f @($addr))
        @($aRecordsByAddress[$addr]).ForEach({
            $null = $sbARecDups.AppendLine("`t{0}" -f @($_.HostName))
        })
    }

    if ($ipamRecordsByAddress.ContainsKey($addr))
    {
        # A records should be static ($null -eq .Timestamp) if there is a record in IPAM.
        $b = 0
        while($b -lt $aRecordsByAddress[$addr].Count)
        {
            if ($null -ne $aRecordsByAddress[$addr][$b].Timestamp)
            {
                $null = $sbARecNonNullTS.AppendLine("A Record for {0}:{1} needs null timestamp" -f @($aRecordsByAddress[$addr][$b].HostName, $addr))
            } `
            else # NOT ($null -ne $aRecordsByAddress[$addr][$b].Timestamp)
            {
                # Nothing.
            }
            $b++
        }
    } `
    else # NOT ($ipamRecordsByAddress.ContainsKey($addr))
    {
        $null = $sbIPAMMissing.AppendLine($addr)
    }

    $a++
}

$reportData = [System.Collections.Generic.List[System.Object]]::new()

$sbPTRDups = [System.Text.StringBuilder]::new()
$sbPTRNonNullTS = [System.Text.StringBuilder]::new()
$addrKeys = @($ptrRecordsByAddress.Keys)
$a = 0
while($a -lt $addrKeys.Length)
{
    $addr = $addrKeys[$a]
    $b = 0
    while($b -lt $ptrRecordsByAddress[$addr].Count)
    {
        if ($b -eq 1)
        {
            $null = $sbPTRDups.AppendLine("{0}:" -f @($addr))
        } `
        else # NOT ($b -eq 1)
        {
            # Nothing.
        }

        if ($b -ge 1)
        {
            $null = $sbPTRDups.AppendLine("`t{0}" -f @($ptrRecordsByAddress[$addr][$b].RecordData.PtrDomainName))
        } `
        else # NOT ($b -ge 1)
        {
            # Nothing.
        }

        $reportNode = [PSCustomObject]@{
            PTRRecord = $ptrRecordsByAddress[$addr][$b]
            Address = $addr
            HasIPAMSubnet = (IPAMSubnetsForAddress -ipStr $addr).Length -gt 0
            IsInIPAM = $ipamRecordsByAddress.ContainsKey($addr)
            ARecords = [System.Collections.Generic.List[System.Object]]::new()
            IsStaticRecord = ($null -eq $ptrRecordsByAddress[$addr][$b].Timestamp)
        }

        if ($aRecordsByAddress.ContainsKey($addr))
        {
            $aRecordsByAddress[$addr] | ForEach-Object {
                $reportNode.ARecords.Add($_)
            }
        } `
        else # NOT ($aRecordsByAddress.ContainsKey($addr))
        {
            # Nothing.
        }

        $reportData.Add($reportNode)

        if ((-not $reportData.IsStaticRecord) -and ($reportData.IsInIPAM))
        {
            $null = $sbPTRNonNullTS.AppendLine("PTR for {0}:{1} needs null timestamp" -f @($ptrRecordsByAddress[$addr][$b].RecordData.PtrDomainName, $addr))
        } `
        else # NOT ((-not $reportData.IsStaticRecord) -and ($reportData.IsInIPAM))
        {
            # Nothing.
        }

        $b++
    }

    $a++
}

if ($sbPTRDups.Length -gt 0)
{
    Write-Host $sbPTRDups.ToString()
} `
else # NOT ($sbPTRDups.Length -gt 0)
{
    # Nothing.
}

$a = 0
while($a -lt $ptrRecords.Length)
{
    $addr = GetAddressFromPTR -ptrRec $ptrRecords[$a]
    if (-not [String]::IsNullOrEmpty($addr))
    {
        if ($ipamRecordsByAddress.ContainsKey($addr))
        {

        } `
        else # NOT ($ipamRecordsByAddress.ContainsKey($addr))
        {
            Write-Host -ForegroundColor Yellow ("Missing IPAM record for address: {0}" -f @($addr))
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($addr))
    {
        # Nothing.
    }
    $a++
}


$dnsServer = Get-DNSServer -ComputerName CDC-DC01
$forwardZones = @($dnsServer.ServerZone | WHere-Object { ($_.ZoneType -eq "Primary") -and (-not $_.IsReverseLookupZone) -and ($_.ZoneName -notmatch "^(_msdcs|TrustAnchors)")})
