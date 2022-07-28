function HostIsAlive
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, Position=0)]
        [string] $ipAddress
    )

    $maxRetries = 3
    $trys = 0
    $needToRetry = $true
    $isAlive = $false
    while(-not $isAlive -and $needToRetry)
    {
        $trys++
        $isAlive = (Test-Connection -ComputerName $ipAddress -Quiet)
        if (-not $isAlive)
        {
            # TRUE

            $needToRetry = ($trys -lt $maxRetries)
            if ($needToRetry)
            {
                # TRUE
                Start-Sleep -Seconds 5
            }
            else # NOT ($needToRetry)
            {
                # FALSE

                # Nothing.
            }
        }
        else # NOT (-not (Test-Connection -ComputerName $ipAddress -Quiet))
        {
            # FALSE

            # Nothing.
        }
    }

    return $isAlive
}

$vmHost = Get-VMHost -Server $vCenter -Name "ddc-esx-c1-b7.powereng.com"
$vSwitch0 = $vmHost | Get-VirtualSwitch -Standard -Name "vSwitch0"
$tmpMgmtPG = $vSwitch0 | New-VirtualPortGroup -Name "Temp Admin" -VLanId 5
$tmpVMK = New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $tmpMgmtPG -VirtualSwitch $vSwitch0 -IP 10.247.5.125 -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true

# Until a VMHost is added to the new distributed switch, the uplink ports will not be returned by Get-VDPort.





$ucsServer = Get-UCSServer -Ucs $ddcUCS | Where-Object { $_.UsrLbl -eq "DDC-ESX-C1-B6"}
$ucsServerNICs = Get-UCSAdaptorHostEthIf -Ucs $ddcUCS | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) }
$ucsServerNICVLans = Get-UcsAdaptorVlan -Ucs $ddcUCS | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) }
$ucsvNIC = Get-UcsVnic -Ucs $ddcUCS
$ucsvNICVLANs = Get-UcsVlan -Ucs $ddcUCS

$ucsUplinkNIC = $ucsServerNICs | Where-Object { $_.Name -eq $newSwitch.uplinks[0].nicName }
Get-VMHostNetworkAdapter -VMHost $vmHost -Physical | Where-Object { $_.Mac -eq $ucsUplinkNIC.Mac }

$vds = Get-VDSwitch -Server $vCenter -Name "DDC Internal vDS 01"

$uniqueVLANs = $ucsServerNICVLans | Select-Object -Unique Name, Id
$a = 0
while($a -lt $uniqueVLANs.Length)
{
    $vpg = New-VDPortgroup -VDSwitch $vds -Name $uniqueVLANs[$a].Name -VlanId $uniqueVLANs[$a].Id -PortBinding "Static"
    $a++
}

$a = 0
while($a -lt $uplinkData.Length)
{
    $uplinkNIC = $ucsServerNICs | Where-Object { $_.Name -eq $uplinkData[$a].nicName}
    $uplinkVLANs = $ucsServerNICVLans | Where-Object { $_.Dn.StartsWith($uplinkNIC.Dn) }

    $b = 0
    while($b -lt $uplinkVLANs.Length)
    {
        Write-Host ("Uplink: {0}, VLAN: {1}, VLAN Name: {2}, NIC Name: {3}, Port group name: {2} - {3}" -f @($uplinkData[$a].uplinkName, $uplinkVLANs[$b].Id, $uplinkVLANs[$b].Name, $uplinkNIC.Name, $ucsServerNICVLans[$b].Name))
        $b++
    }
    $a++
}
$uplinkNIC = $ucsServerNICs | Where-Object { $_.Name -eq $uplinkData[0].nicName}
$uplinkVLANs = $ucsServerNICVLans | Where-Object { $_.Dn.StartsWith($uplinkNIC.Dn) }


# https://docs.netapp.com/us-en/netapp-solutions/pdfs/sidebar/VMware_vSphere_with_ONTAP_Best_Practices.pdf
Get-AdvancedSetting -Entity $vmHost -Name "Net.TcpipHeapSize"        | Set-AdvancedSetting -Value 32   -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "Net.TcpipHeapMax"         | Set-AdvancedSetting -Value 1536 -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "NFS.MaxVolumes"           | Set-AdvancedSetting -Value 256  -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "NFS.MaxQueueDepth"        | Set-AdvancedSetting -Value 128  -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "NFS.HeartbeatMaxFailures" | Set-AdvancedSetting -Value 10   -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "NFS.HeartbeatFrequency"   | Set-AdvancedSetting -Value 12   -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "NFS.HeartbeatTimeout"     | Set-AdvancedSetting -Value 5    -Confirm:$false
Get-AdvancedSetting -Entity $vmHost -Name "SunRPC.MaxConnPerIP"      | Set-AdvancedSetting -Value 128  -Confirm:$false


Get-AdvancedSetting -Entity $vmHost -Name "NFS.MaxVolumes" | Set-AdvancedSetting -Value 256
Get-AdvancedSetting -Entity $vmHost -Name "NFS.MaxVolumes" | Set-AdvancedSetting -Value 256




$ucsServer = Get-UCSServer -Ucs $ddcUCS | Where-Object { $_.Serial -eq "FLM260109B4" }





$ucsServerNICs = Get-UCSAdaptorHostEthIf -Ucs $ddcUCS | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) }
$ucsServerNICVLans = Get-UcsAdaptorVlan -Ucs $ddcUCS | Where-Object { $_.Dn.StartsWith($ucsServer.Dn) }
$ucsvNIC = Get-UcsVnic -Ucs $ddcUCS
$ucsvNICVLANs = Get-UcsVlan -Ucs $ddcUCS

$ucsUplinkNIC = $ucsServerNICs | Where-Object { $_.Name -eq $newSwitch.uplinks[0].nicName }
Get-VMHostNetworkAdapter -VMHost $vmHost -Physical | Where-Object { $_.Mac -eq $ucsUplinkNIC.Mac }


$mgmtVMKs = @(Get-VMHostNetworkAdapter -Server $vCenter -VMHost $vmHost -VMKernel | Where-Object { $_.ManagementTrafficEnabled })
$mgmtPGs = @(Get-VirtualPortGroup -Server $vCenter -VMHost $vmHost -Name @($mgmtVMKs | Select-Object -Unique -ExpandProperty PortGroupName))
$mgmtVMNICs = @($mgmtPGs | Select-Object -ExpandProperty VirtualSwitch | Select-Object -Unique -ExpandProperty Nic)






$vds = $null
if ($null -ne $vCenter)
{
    # TRUE

    if ($vCenter.IsConnected)
    {
        # TRUE

        if ($null -ne $dsf)
        {
            # TRUE

            try
            {
                $vds = Get-VDSwitch -Server $vCenter -Name $dsf.switchName -ErrorAction SilentlyContinue
            }
            catch { } <# try-catch used to subdue error messages #>

            if ($null -ne $vds)
            {
                # TRUE


            }
            else # NOT ($null -ne $vds)
            {
                # FALSE

                ReportError ("Distributed switch `"{0}`" does not exist." -f @($dsf.switchName))
            }
        }
        else # NOT ($null -ne $dsf)
        {
            # FALSE

            ReportError ("Missing distributed switch definition in {0}." -f @($MyInvocation.MyCommand.Name))
        }
    }
    else # NOT ($vCenter.IsConnected)
    {
        # FALSE

        ReportError ("Not connected to `"{0}`" in `"{1}`"." -f @($vCenter.Name, $MyInvocation.MyCommand.Name))
    }
}
else # NOT ($null -ne $vCenter)
{
    # FALSE

    ReportError ("Missing vCenter in `"{0}`"." -f @($MyInvocation.MyCommand.Name))
}




<#
.SYNOPSIS

Adds a file name extension to a supplied name.

.DESCRIPTION

Adds a file name extension to a supplied name.
Takes any strings for the file name or extension.

.PARAMETER Name
Specifies the file name.

.PARAMETER Extension
Specifies the extension. "Txt" is the default.

.INPUTS

None. You cannot pipe objects to Add-Extension.

.OUTPUTS

System.String. Add-Extension returns a string with the extension
or file name.

.EXAMPLE

PS> extension -name "File"
File.txt

.EXAMPLE

PS> extension -name "File" -extension "doc"
File.doc

.EXAMPLE

PS> extension "File" "doc"
File.doc

.LINK

http://www.fabrikam.com/extension.html

.LINK

Set-Item
#>

$messages = @(
    @{Name = "UNKNOWN"; Level = "WARNING"; Message = "Unknown message {0}." },
    @{Name = "W0001";   Level = "WARNING"; Message = "This is a test warning message {0}." },
    @{Name = "N0001";   Level = "NOTICE";  Message = "This is a test notification message {0}." },
    @{Name = "S0001";   Level = "SUCCESS"; Message = "This is a test success message {0}." },
    @{Name = "E0001";   Level = "ERROR";   Message = "Poorly formatted message. Message: {0}, Args: {1}" }
    @{Name = "E0002";   Level = "ERROR";   Message = "This is a test error message {0} - {1}." }
)

function Report
{
    param(
        [Parameter(Mandatory=$True, Position = 0 )]
        [string] $msgName,

        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true, Position = 1)]
        [string[]] $messageArgs
    )

    $message = $messages | Where-Object { $_.Name -eq $msgName }
    $outputMessage = [String]::Empty
    if($null -ne $message)
    {
        if($message.Message -match "\{\d+\}")
        {
            try
            {
                if($null -eq $messageArgs)
                {
                    throw
                }
                $outputMessage = $message.Message -f $messageArgs
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Unable to format message `"{0}`" using @({1})." -f @($message.Message, ($messageArgs -join ", ")))
            }
        }
        else #
        {
            $outputMessage = $message.Message
        }

        switch($message.Level)
        {
            "NOTICE"  { $foreGroundColor = "White" }
            "SUCCESS" { $foreGroundColor = "Green" }
            "WARNING" { $foreGroundColor = "Yellow" }
            "ERROR"   { $foreGroundColor = "Red" }
            default   { $foreGroundColor = "White" }
        }

        Write-Host -ForegroundColor $foreGroundColor $outputMessage
    }
    else #
    {
        Report "UNKNOWN" $msgName
    }
}


Report "S0001" "because" "test" "buzzkill"
