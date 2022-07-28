$Global:settingsToCheck = @(
    @{Name = "Net.TcpipHeapSize";                               RecommendedValue = 32 },
    @{Name = "Net.TcpipHeapMax";                                RecommendedValue = 1536 },
    @{Name = "NFS.MaxVolumes";                                  RecommendedValue = 256 },
    @{Name = "NFS.MaxQueueDepth";                               RecommendedValue = 128 },
    @{Name = "NFS.HeartbeatMaxFailures";                        RecommendedValue = 10 },
    @{Name = "NFS.HeartbeatFrequency";                          RecommendedValue = 12 },
    @{Name = "NFS.HeartbeatTimeout";                            RecommendedValue = 5 },
    @{Name = "SunRPC.MaxConnPerIP";                             RecommendedValue = 128 },
    @{Name = "UserVars.SuppressCoredumpWarning";                RecommendedValue = 1 }
    @{Name = "Config.HostAgent.plugins.hostsvc.esxAdminsGroup"; RecommendedValue = "pgVCenterAdmin" }
)

$Global:ntpServers = @(
    "ntp1.powereng.com",
    "ntp2.powereng.com"
)

function SetAdvancedSettingForVMHost($vmHost, $setting, $value)
{
    try
    {
        $advSetting = Get-AdvancedSetting -Server $vCenter -Entity $vmHost -Name $setting -ErrorAction Stop

        if($advSetting.Value -ne $value)
        {
            try
            {
                $newAdvSetting = $advSetting | Set-AdvancedSetting -Value $value -Confirm:$false -ErrorAction Stop
                Write-Host -ForegroundColor Green ("{0,-30}{1,-50}{2,25}{3,25} (Updated)" -f @($vmHost.Name, $advSetting.Name, $advSetting.Value, $newAdvSetting.Value))
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to set {0} to {1} on {2}." -f @($setting, $value, $vmHost.Name))
            }
        }
        else
        {
            Write-Host -ForegroundColor White ("{0,-30}{1,-50}{2,25}{3,25}" -f @($vmHost.Name, $advSetting.Name, $advSetting.Value, $value))
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to retrieve advanced setting {0} from {1}." -f @($setting, $vmHost.Name))
    }
}

function SetAdvancedSettingsForVMhost($vmHost)
{
    $b = 0
    while($b -lt $settingsToCheck.Length)
    {
        SetAdvancedSettingForVMHost $vmHost $Global:settingsToCheck[$b].Name $Global:settingsToCheck[$b].RecommendedValue
        $b++
    }
}

function JoinESXiToDomain
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter,

        [Parameter(Mandatory=$false, Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl] $vmHost,

        [Parameter(Mandatory=$false, Position=2)]
        [String] $ouToJoin,

        [Parameter(Mandatory=$false, Position=3)]
        [PSCredential] $adCredentials
    )

    if ($null -ne $vCenter)
    {
        # TRUE

        if ($null -ne $vmHost)
        {
            # TRUE

            if (-not [String]::IsNullOrEmpty($ouToJoin))
            {
                # TRUE

                if ($null -ne $adCredentials)
                {
                    # TRUE

                    try
                    {
                        $adDomain = Get-ADDomain -ErrorAction SilentlyContinue
                    }
                    catch { }

                    if ($null -ne $adDomain)
                    {
                        # TRUE

                        try
                        {
                            $adOU = Get-ADOrganizationalUnit -Identity $ouToJoin -Properties "CanonicalName" -ErrorAction SilentlyContinue
                        }
                        catch {}

                        if ($null -ne $adOU)
                        {
                            # TRUE

                            if (-not [String]::IsNullOrEmpty($adOU.CanonicalName))
                            {
                                # TRUE

                                try
                                {
                                    $vmHostAuthentication = Get-VMHostAuthentication -Server $vCenter -VMHost $vmHost -ErrorAction SilentlyContinue
                                }
                                catch { }

                                if ($null -ne $vmHostAuthentication)
                                {
                                    # TRUE

                                    if ($vmHostAuthentication.Domain -ne $adDomain.DNSRoot)
                                    {
                                        # TRUE

                                        try
                                        {
                                            $newVMHostAuthentication = $vmHostAuthentication | Set-VMHostAuthentication -Domain $adOU.CanonicalName -JoinDomain -Credential $adCredentials -Confirm:$false -ErrorAction SilentlyContinue
                                        }
                                        catch
                                        {
                                            ReportError ("Failed to join {0} to {1}." -f @($vmHost.Name, $adOU.CanonicalName))
                                        }
                                    }
                                    else # NOT ($vmHostAuthentication.Domain -ne $adDomain.DNSRoot)
                                    {
                                        # FALSE

                                        # Nothing.
                                    }
                                }
                                else # NOT ($null -ne $vmHostAuthentication)
                                {
                                    # FALSE

                                    ReportError ("Failed to retrieve VM host authentication for `"{0}`"." -f @($vmHost.Name))
                                }
                            }
                            else # NOT (-not [String]::IsNullOrEmpty($adOU.CanonicalName))
                            {
                                # FALSE

                                ReportError ("CanonicalName for `"{0}`" not returned from Active Directory." -f @($ouToJoin))
                            }
                        }
                        else # NOT ($null -ne $adOU)
                        {
                            # FALSE

                            ReportError ("Unable to retrieve Active Directory OU matching `"{0}`"." -f @($ouToJoin))
                        }
                    }
                    else # NOT ($null -ne $adDomain)
                    {
                        # FALSE

                        ReportError "Failed to retrieve Active Directory domain information."
                    }
                }
                else # NOT ($null -ne $adCredentials)
                {
                    # FALSE

                    ReportError ("Missing credential used to join {0} to domain in {1}." -f @($vmHost.Name, $MyInvocation.MyCommand.Name))
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($ouToJoin))
            {
                # FALSE

                ReportError ("Missing OU where {0} should be joined in {1}." -f @($vmHost.Name, $MyInvocation.MyCommand.Name))
            }

        }
        else # NOT ($null -ne $vmHost)
        {
            # FALSE

            ReportError ("Missing vmHost in {0}." -f @($MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($null -ne $vCenter)
    {
        # FALSE

        ReportError ("Missing vCenter in {0}." -f @($MyInvocation.MyCommand.Name))
    }
}

function RenameLocalDatastores($vCenter, $vmHost)
{
    $localDataStores = @(Get-Datastore -Server $vCenter -RelatedObject $vmHost | Where-Object { $_.Type -eq "VMFS" })

    $a = 0
    while($a -lt $localDataStores.Length)
    {
        $newDSName = "~{0} local storage" -f @(($vmHost.Name.ToUpper().Replace(".POWERENG.COM", "")))

        if($localDataStores[$a].Name -ne $newDSName)
        {
            Write-Host -ForegroundColor Green ("Renaming {0}:{1} to {2}." -f @($vmHost.Name, $localDataStores[$a].Name, $newDSName))
            try
            {
                [void] (Set-Datastore -Server $vCenter -Datastore $localDataStores[$a] -Name $newDSName -ErrorAction Stop)
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to rename {0}:{1} to {2}." -f @($vmHost.Name, $localDataStores[$a].Name, $newDSName))
            }
        }
        $a++
    }
}

$adCreds = Get-Credential -Message "Provide credentials to join ESXi host(s) to domain in the form: user@domain.name.net."

foreach($location in @( <# "CDCTEST", "DDCTEST", #> "CDCDMZTEST"))
{
    $vmHosts = Get-VMHost -Server $vCenter -Location $location
    # Write-Host ("`r`n{0,-30}{1,-26}{2,13}{3,17}" -f @("VMHost", "Setting", "CurrentValue", "RecommendedValue"))

    $a = 0
    while($a -lt $vmHosts.Length)
    {

        $vmHostNTPServers = Get-VMHostNtpServer -Server $vCenter -VMHost $vmHosts[$a]
        $b = 0
        while($b -lt $vmHostNTPServers.Length)
        {
            if ($ntpServers -notcontains $vmHostNTPServers[$b])
            {
                # TRUE

                Write-Host ("Removing NTP server: {0} from {1}" -f @($vmHostNTPServers[$b], $vmHosts[$a].Name))
                Remove-VMHostNtpServer -Server $vCenter -VMHost $vmHosts[$a] -NtpServer $vmHostNTPServers[$b]
            }
            else # NOT ($ntpServers -notcontains $vmHostNTPServers[$b)
            {
                # FALSE


                # Nothing.
            }

            $b++
        }

        $vmHostNTPServers = Get-VMHostNtpServer -Server $vCenter -VMHost $vmHosts[$a]
        $b = 0
        while($b -lt $ntpServers.Length)
        {
            if ($vmHostNTPServers -notcontains $ntpServers[$b])
            {
                # TRUE

                Write-Host ("Adding NTP server: {0} to {1}" -f @($ntpServers[$b], $vmHosts[$a].Name))
                Add-VMHostNtpServer -Server $vCenter -VMHost $vmHosts[$a] -NtpServer $ntpServers[$b]
            }
            else # NOT ($vmHostNTPServers -notcontains $ntpServers[$b])
            {
                # FALSE


                # Nothing.
            }

            $b++
        }

        $ntpService = Get-VMHostService -Server $vCenter -VMHost $vmHosts[$a] | Where-Object { $_.Key -eq "ntpd" }
        if ($null -ne $ntpService)
        {
            # TRUE

            if ($ntpService.Policy -ne "automatic")
            {
                # TRUE

                Write-Host ("Setting {0} {1} service policy to automatic." -f @($vmHosts[$a].Name, $ntpService.Label))
                Set-VMHostService -HostService $ntpService -Policy "Automatic"
            }
            else # NOT ($ntpService.Policy -ne "automatic")
            {
                # FALSE

                # Nothing.
            }

            if (-not $ntpService.Running)
            {
                # TRUE

                Write-Host ("Starting {0} {1} service." -f @($vmHosts[$a].Name, $ntpService.Label))
                Start-VMHostService $ntpService
            }
            else # NOT (-not $ntpService.Running)
            {
                # FALSE

                # Nothing.
            }
        }
        else # NOT ($null -ne $ntpService)
        {
            # FALSE

            # Nothing.
        }

        JoinESXiToDomain -vCenter $vCenter -vmHost $vmHosts[$a] -ouToJoin "OU=VMware,OU=Servers,OU=PEI,DC=powereng,DC=com" -adCredentials $adCreds

        # Must happen after the ESXi host is joined to the domain.  -- well sort of ... or the admin group makes sense.
        SetAdvancedSettingsForVMhost $vmHosts[$a]

        # Rename the local datastores
        RenameLocalDatastores $vCenter $vmHosts[$a]
        $a++
    }
}
