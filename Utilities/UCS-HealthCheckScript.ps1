
#pick debugging
$ErrorActionPreference = "SilentlyContinue"
#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = "Continue"
#$ErrorActionPreference = "Inquire"

#Verify PowerShell Version for script support
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
if ($PSMinimum -lt "3")
{
    Write-Host -ForegroundColor Red "This script requires PowerShell version 3 or above"
    Write-Host -ForegroundColor Red "Please update your system and try again."
    Write-Host -ForegroundColor Red "You can download PowerShell updates here:"
    Write-Host -ForegroundColor Red "   http://search.microsoft.com/en-us/DownloadResults.aspx?rf=sp&q=powershell+4.0+download"
    Write-Host -ForegroundColor Red "If you are running a version of Windows before 7 or Server 2008R2 you need to update to be supported"
    Write-Host -ForegroundColor Red "      Exiting..."
    Disconnect-Ucs
    exit
}

Import-Module Cisco.UCS.Core
Import-Module Cisco.UCSManager

set-executionpolicy remoteSigned

# form: ucs-powereng.com\kbriney-adm
$cred = Get-Credential -Message "Enter credentials to connect to UCS..."
$UCSname = "PEI"

$handle1 = Connect-Ucs cdc-ucs01.powereng.com -NotDefault -Credential $cred
$handle2 = Connect-Ucs ddc-ucs01.powereng.com -NotDefault -Credential $cred

$handleArray = $handle1,$handle2

# Create the HTML file #

$ReportFile = "C:\TMP\UCSReport\UCS-HealthCheck-$UCSname.html"

# Define the HTML #
$sbHTML = [System.Text.StringBuilder]::new()

#region HTML Lead...
[void] $sbHTML.AppendLine(
@"
<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.0 Strict//EN'  'http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd'>
<html xmlns='http://www.w3.org/1999/xhtml'>
<head>
   <meta http-equiv='Content-Type' content='text/html; charset=utf-8' />
   <title>UCS Health Check Report for $UCSname</title>
   <style type='text/css'>
      div.content {
          border: #48f solid 3px;
          clear: left;
          padding: 1em;
          font-family: Tahoma;
      }

      div.content.inactive {
         display: none;
      }

      ol#toc {
          height: 2em;
          list-style: none;
          margin: 0;
          padding: 0;
      }

      ol#toc a {
          background: #bdf url(tabs.gif);
          color: #008;
          display: block;
          float: left;
          height: 2em;
          padding-left: 10px;
          text-decoration: none;
      }

      ol#toc a:hover {
          background-color: #3af;
          background-position: 0 -120px;
      }

      ol#toc a:hover span {
          background-position: 100% -120px;
      }

      ol#toc li {
          float: left;
          margin: 0 1px 0 0;
      }

      ol#toc li a.active {
          background-color: #48f;
          background-position: 0 -60px;
          color: #fff;
          font-weight: bold;
          font-family: Tahoma;
      }

      ol#toc li a.active span {
          background-position: 100% -60px;
      }

      ol#toc span {
          background: url(tabs.gif) 100% 0;
          display: block;
          line-height: 2em;
          padding-right: 10px;
      }

      body {
         background-color:#99ccff;
         font-family:Tahoma;
      }

      table {
         font-family: Tahoma;
         border-width: 2px;
         border-style: solid;
         border-color: black;
         border-collapse: collapse;
      }

      th {
         border-width: 2px;
         padding: 2px;
         border-style: solid;
         border-color: black;
         background-color:LightGray;
      }

      td {
         border-width: 2px;
         padding: 2px;
         border-style: solid;
         border-color: black;
         background-color:white;
      }
   </style>
</head>
<body>
   <h1>UCS Health Check Report for $UCSname</h1>

   <!-- Define HTML Tabs -->
   <ol id='toc'>
      <li><a href='#page-1'><span>Configuration Summary</span></a></li>
      <li><a href='#page-2'><span>Service Profiles</span></a></li>
      <li><a href='#page-3'><span>Firmware</span></a></li>
      <li><a href='#page-4'><span>Hardware Inventory</span></a></li>
      <li><a href='#page-5'><span>Environmental Statistics</span></a></li>
      <li><a href='#page-6'><span>Ethernet Statistics</span></a></li>
      <li><a href='#page-7'><span>SAN FC Statistics</span></a></li>
      <li><a href='#page-8'><span>Fault Report</span></a></li>
   </ol>
"@)
#endregion

#region Tab 1: UCS Configuration
[void] $sbHTML.AppendLine("   <div class='content' id='page-1'>")

Write-Host "Getting Cluster Configuration and State..."
[void] $sbHTML.AppendLine("      <H2>Cluster Configuration</H2>")
Get-UcsStatus -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.Name}}, @{Name="Cluster IP";Expression={$_.VirtualIpv4Address}}, @{Name="HA State";Expression={$_.HaConfiguration}}, @{Name="HA Ready";Expression={$_.HaReady}}, @{Name="FI-A Role";Expression={$_.FiALeadership}}, @{Name="FI-A IP";Expression={$_.FiAOobIpv4Address}}, @{Name="FI-B Role";Expression={$_.FiBLeadership}}, @{Name="FI-B IP";Expression={$_.FiBOobIpv4Address}} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting IP CIMC MGMT Pool..."
[void] $sbHTML.AppendLine("      <H2>CIMC IP Pool</H2>")
Get-UcsIpPoolBlock -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,From,To,Subnet,@{Name="Gateway";Expression={$_.DefGw}} | Where-Object {$_.Dn -like "*ext-mgmt*"}  | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting IP CIMC MGMT Pool Assignments..."
[void] $sbHTML.AppendLine("      <H2>CIMC IP Pool Assignments free IP addresses: $ipfree </H2>")
$ucsIPPoolAddr = Get-UcsIpPoolAddr -Ucs $handleArray
$ipfree = @($ucsIPPoolAddr | Select-Object assigned | where-object {$_.assigned -ne "no"}).Count
$ucsIPPoolAddr | Sort-Object -Property UCS,AssignedToDn | Where-Object {$_.Assigned -eq "yes"} | Select-Object @{Name="POD";Expression={$_.UCS}},@{Name="Blade";Expression={$_.AssignedToDn}},@{Name="IP";Expression={$_.Id}} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting DNS Domain..."
[void] $sbHTML.AppendLine("      <H2>DNS Domain</H2>")
Get-UcsDns -Ucs $handleArray | Sort-Object -Property UCS | Select-Object -Unique @{Name="POD";Expression={$_.UCS}},Domain | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting DNS Servers..."
[void] $sbHTML.AppendLine("      <H2>DNS Servers</H2>")
Get-UcsDnsServer -Ucs $handleArray | Sort-Object -Property UCS | Select-Object -Unique @{Name="POD";Expression={$_.UCS}},Name | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting NTP Servers..."
[void] $sbHTML.AppendLine("      <H2>NTP Servers</H2>")
Get-UcsNtpServer -Ucs $handleArray | Sort-Object -Property UCS,Name | Select-Object -Unique @{Name="POD";Expression={$_.UCS}},Name | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Timezone..."
[void] $sbHTML.AppendLine("      <H2>Timezone</H2>")
Get-UcsTimezone -Ucs $handleArray | Sort-Object -Property UCS | Select-Object -Unique @{Name="POD";Expression={$_.UCS}},Timezone | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Global chassis discovery policy..."
[void] $sbHTML.AppendLine("      <H2>Chassis Discovery Policy</H2>")
Get-UcsChassisDiscoveryPolicy -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,Action | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Global chassis power redundancy policy..."
[void] $sbHTML.AppendLine("      <H2>Chassis Power Redundancy Policy</H2>")
Get-UcsPowerControlPolicy -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,Redundancy | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Organizations..."
[void] $sbHTML.AppendLine("      <H2>Organizations</H2>")
Get-UcsOrg -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Dn | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LAN Switching Mode..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Ethernet Switching Mode</H2>")
Get-UcsLanCloud -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,Mode | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting SAN Switching Mode..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Fibre Channel Switching Mode</H2>")
Get-UcsSanCloud -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,Mode | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Fabric Interconnect Ethernet port usage and role info..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Ethernet Port Configuration</H2>")
Get-UcsFabricPort -Ucs $handleArray | Sort-Object -Property UCS,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,IfRole,LicState,Mode,OperState,OperSpeed,XcvrType | Where-Object {$_.OperState -eq "up"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Fabric Interconnect to Chassis port mapping..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Chassis IOM Mappings</H2>")
Get-UcsEtherSwitchIntFIo -Ucs $handleArray | Sort-Object -Property UCS,SwitchId,SlotId,PortId | Select-Object @{Name="POD";Expression={$_.UCS}},ChassisId,Discovery,Model,OperState,SwitchId,PeerSlotId,PeerPortId,SlotId,PortId,XcvrType | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Fabric Interconnect FC Uplink Ports..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect FC Uplink Ports</H2>")
Get-UcsFiFcPort -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},EpDn,SwitchId,SlotId,PortId,LicState,Mode,OperSpeed,OperState | where-object {$_.OperState -ne "sfp-not-present"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting SAN Fiber Channel Uplink Port Channel info..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect FC Uplink Port Channels</H2>")
Get-UcsFcUplinkPortChannel -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Name,OperSpeed,OperState,Transport | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Ethernet LAN Uplink Port Channel info..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Ethernet Uplink Port Channels</H2>")
Get-UcsUplinkPortChannel -Ucs $handleArray | Sort-Object -Property Ucs,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Name,OperSpeed,OperState,Transport | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Ethernet LAN Uplink Port Channel port membership info..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Ethernet Uplink Port Channel Members</H2>")
Get-UcsUplinkPortChannelMember -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Membership | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Native Authentication Source..."
[void] $sbHTML.AppendLine("      <H2>Native Authentication</H2>")
Get-UcsNativeAuth -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,DefLogin,ConLogin | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LDAP server info..."
[void] $sbHTML.AppendLine("      <H2>LDAP Providers</H2>")
Get-UcsLdapProvider -Ucs $handleArray | Sort-Object -Property UCS,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Rootdn,Basedn,Attribute | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LDAP group mappings..."
[void] $sbHTML.AppendLine("      <H2>LDAP Group Mappings</H2>")
Get-UcsLdapGroupMap -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Name | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting user and LDAP group roles..."
[void] $sbHTML.AppendLine("      <H2>User Roles</H2>")
Get-UcsUserRole -Ucs $handleArray | Sort-Object -Property UCS,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Dn | Where-Object {$_.Dn -like "sys/ldap-ext*"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Call Home config..."
[void] $sbHTML.AppendLine("      <H2>Call Home Configuration</H2>")
Get-UcsCallhome -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},AdminState | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Call Home SMTP Server..."
[void] $sbHTML.AppendLine("      <H2>Call Home SMTP Server</H2>")
Get-UcsCallhomeSmtp -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},Host | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Call Home Recipients..."
[void] $sbHTML.AppendLine("      <H2>Call Home Recipients</H2>")
Get-UcsCallhomeRecipient -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Email | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting SNMP Configuration..."
[void] $sbHTML.AppendLine("      <H2>SNMP Configuration</H2>")
Get-UcsSnmp -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},AdminState,Community,SysContact,SysLocation | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting UUID Suffix Pools..."
[void] $sbHTML.AppendLine("      <H2>UUID Pools</H2>")
Get-UcsUuidSuffixPool -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Prefix,Size,Assigned | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting UUID Suffix Pool Blocks..."
[void] $sbHTML.AppendLine("      <H2>UUID Pool Blocks</H2>")
Get-UcsUuidSuffixBlock -Ucs $handleArray | Sort-Object -Property Ucs | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,From,To | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting UUID UUID Pool Assignments..."
[void] $sbHTML.AppendLine("      <H2>UUID Pool Assignments</H2>")
Get-UcsUuidpoolAddr -Ucs $handleArray | Where-Object {$_.Assigned -ne "no"} | Sort-Object -Property UCS | select-object @{Name="POD";Expression={$_.UCS}},AssignedToDn,Id | sort-object -property Ucs,AssignedToDn | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting MAC Address Pools..."
[void] $sbHTML.AppendLine("      <H2>MAC Address Pools</H2>")
Get-UcsMacPool -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}}, Name,Size,Assigned | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting MAC Address Pool Blocks..."
[void] $sbHTML.AppendLine("      <H2>MAC Address Pool Blocks</H2>")
Get-UcsMacMemberBlock -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,From,To | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting MAC Pool Assignments..."

[void] $sbHTML.AppendLine("      <H2>MAC Address Pool Assignments</H2>")
Get-UcsVnic -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,IdentPoolName,Addr | where {$_.Addr -ne "derived"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting WWNN Pools..."
[void] $sbHTML.AppendLine("      <H2>WWN Pools</H2>")
Get-UcsWwnPool -Ucs $handleArray | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Purpose,Size,Assigned | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting WWNN/WWPN Pool Assignments..."
[void] $sbHTML.AppendLine("      <H2>WWN Pool Assignments</H2>")
Get-UcsVhba -Ucs $handleArray | Sort-Object -Property Ucs,Addr | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,IdentPoolName,NodeAddr,Addr | where {$_.NodeAddr -ne "vnic-derived"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting WWNN/WWPN vHBA and adaptor Assignments..."
[void] $sbHTML.AppendLine("      <H2>vHBA Details</H2>")
Get-UcsAdaptorHostFcIf -Ucs $handleArray | sort-object -Property Ucs,VnicDn -Descending | Select-Object @{Name="POD";Expression={$_.UCS}},VnicDn,Vendor,Model,LinkState,SwitchId,NodeWwn,Wwn | Where-Object {$_.NodeWwn -ne "00:00:00:00:00:00:00:00"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Server Pools..."
[void] $sbHTML.AppendLine("      <H2>Server Pools</H2>")
Get-UcsServerPool -Ucs $handleArray | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Assigned | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Server Pool Assignments..."
[void] $sbHTML.AppendLine("      <H2>Server Pool Assignments</H2>")
Get-UcsServerPoolAssignment -Ucs $handleArray | Select-Object @{Name="POD";Expression={$_.UCS}},Name,AssignedToDn | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting QoS Class Configuration..."
[void] $sbHTML.AppendLine("      <H2>QoS System Class Configuration</H2>")
Get-UcsQosClass -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Priority,AdminState,Cos,Weight,Drop,Mtu | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting QoS Policies..."
[void] $sbHTML.AppendLine("      <H2>QoS Policies</H2>")
Get-UcsQosPolicy -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Name | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Network Control Policies..."
[void] $sbHTML.AppendLine("      <H2>Network Control Policies</H2>")
Get-UcsNetworkControlPolicy -Ucs $handleArray | Sort-Object -Property UCS,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Cdp,UplinkFailAction | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting vNIC Templates..."
[void] $sbHTML.AppendLine("      <H2>vNIC Templates</H2>")
Get-UcsVnicTemplate -Ucs $handleArray | Sort-Object -Property UCS,Name| Select-Object @{Name="POD";Expression={$_.UCS}},Name,Descr,SwitchId,TemplType,IdentPoolName,Mtu,NwCtrlPolicyName,QosPolicyName | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting vHBA Templates..."
[void] $sbHTML.AppendLine("      <H2>vHBA Templates</H2>")
Get-UcsVhbaTemplate -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Descr,SwitchId,TemplType,QosPolicyName | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting vHBA to VSAN Mappings..."
[void] $sbHTML.AppendLine("      <H2>vHBA to VSAN Mappings</H2>")
Get-UcsVhbaInterface -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,OperVnetName,Initiator | Where-Object {$_.Initiator -ne "00:00:00:00:00:00:00:00"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Service Profile Templates..."
[void] $sbHTML.AppendLine("      <H2>Service Profile Templates</H2>")
Get-UcsServiceProfile -Ucs $handleArray | Where-object {$_.UuidSuffix -eq "0000-000000000000"}  | Sort-object -Property Ucs,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Name,BiosProfileName,BootPolicyName,HostFwPolicyName,LocalDiskPolicyName,MaintPolicyName,MgmtFwPolicyName,VconProfileName | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Service Profiles..."
[void] $sbHTML.AppendLine("      <H2>Service Profiles</H2>")
Get-UcsServiceProfile -Ucs $handleArray | Where-object {$_.UuidSuffix -ne "0000-000000000000"}  | Sort-object -Property Ucs,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Name,AssocState,PnDn,BiosProfileName,IdentPoolName,Uuid,BootPolicyName,HostFwPolicyName,LocalDiskPolicyName,MaintPolicyName,MgmtFwPolicyName,VconProfileName,OperState | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Ethernet VLANs..."
[void] $sbHTML.AppendLine("      <H2>Ethernet VLANs</H2>")
Get-UcsVlan -Ucs $handleArray | Where-Object {$_.IfRole -eq "network"} | Sort-Object -Property Ucs,Id | Select-Object @{Name="POD";Expression={$_.UCS}},Id,Name,SwitchId | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Ethernet VLAN to vNIC Mappings..."
[void] $sbHTML.AppendLine("      <H2>Ethernet VLAN to vNIC Mappings</H2>")
Get-UcsAdaptorVlan -Ucs $handleArray | sort-object Ucs,Id,SwitchId | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Name,Id,SwitchId | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting FC VSAN info..."
[void] $sbHTML.AppendLine("      <H2>FC VSANs</H2>")
Get-UcsVsan -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Id,FcoeVlan,DefaultZoning | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting FC Port Channel VSAN Mapping..."
[void] $sbHTML.AppendLine("      <H2>FC VSAN to FC Port Mappings</H2>")
Get-UcsVsanMemberFcPortChannel -Ucs $handleArray | Sort-Object -Property UCS | Select-Object @{Name="POD";Expression={$_.UCS}},EpDn,IfType | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 2: UCS Service Profiles
Write-Host "Getting Service Profiles..."
[void] $sbHTML.AppendLine("   <div class='content' id='page-2'>")
[void] $sbHTML.AppendLine("      <H2>Service Profiles</H2>")
Get-UcsServiceProfile -Ucs $handleArray | Sort-Object -Property UCS,Name | Select-Object @{Name="POD";Expression={$_.UCS}},@{Name="Profile Name";Expression={$_.Name}},AssocState,@{Name="Blade Location";Expression={$_.PnDN}} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 3: UCS Firmware
[void] $sbHTML.AppendLine("   <div class='content' id='page-3'>")

Write-Host "Getting running firmware version from all components..."
[void] $sbHTML.AppendLine("      <H2>Firmware Versions</H2>")
Get-UcsFirmwareRunning -Ucs $handleArray | Sort-Object -Property UCS,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Type,Version | Where-Object -FilterScript {$_.Type -notlike "unspecified"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 4: UCS Hardware Inventory
[void] $sbHTML.AppendLine("   <div class='content' id='page-4'>")

Write-Host "Getting Fabric Interconnects..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnects</H2>")
Get-UcsNetworkElement -Ucs $handleArray | Sort-Object -Property UCS,RN | Select-Object @{Name="POD";Expression={$_.UCS}},@{Name="ROLE";Expression={$_.RN}},@{Name="IP Address";Expression={$_.OobIfIp}},@{Name="Mask";Expression={$_.OobIfMask}},@{Name="Gateway";Expression={$_.OobIfGw}},Operability,Model,Serial | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Fabric Interconnect inventory..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect Modules</H2>")
Get-UcsFiModule -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},@{Name="Slot Location";Expression={$_.Dn}},Model,@{Name="Description";Expression={$_.Descr}},@{Name="Operability";Expression={$_.OperState}},State,Serial | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting License usage..."
[void] $sbHTML.AppendLine("      <H2>Fabric Interconnect License Usage</H2>")
Get-UcsLicense -Ucs $handleArray | Sort-Object -Property Ucs,Scope | Select-Object @{Name="POD";Expression={$_.UCS}},@{Name="FI";Expression={$_.Scope}},@{Name="Total";Expression={$_.AbsQuant}},@{Name="Used";Expression={$_.UsedQuant}},PeerStatus,OperState | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Chassis info..."
[void] $sbHTML.AppendLine("      <H2>Chassis Inventory</H2>")
Get-UcsChassis -Ucs $handleArray | Sort-Object -Property Ucs,Rn | Select-Object @{Name="POD";Expression={$_.UCS}},Rn,Model,OperState,Thermal,Serial | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting chassis IOM (FEX) info..."
[void] $sbHTML.AppendLine("      <H2>IOM (FEX) Inventory</H2>")
Get-UcsIom -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},ChassisId,Rn,Model,OperState,Side,Thermal,Serial | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Get all UCS servers and server info..."
[void] $sbHTML.AppendLine("      <H2>Server Inventory</H2>")
Get-UcsServer -Ucs $handleArray | Sort-Object -Property Ucs,ChassisID,SlotID,Name | Select-Object @{Name="POD";Expression={$_.UCS}},Name,ChassisId,SlotId,Model,AvailableMemory,AssignedToDn,OperState,Operability,OperPower,Serial | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting server adaptor (mezzanine card) info..."
[void] $sbHTML.AppendLine("      <H2>Server Adaptor Inventory</H2>")
Get-UcsAdaptorUnit -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},ChassisId,BladeId,Model | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting server processor info..."
[void] $sbHTML.AppendLine("      <H2>Server CPU Inventory</H2>")
Get-UcsProcessorUnit -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,SocketDesignation,Cores,CoresEnabled,Threads,Speed,OperState,Thermal,Model | Where-Object {$_.OperState -ne "removed"} | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting server memory info..."
[void] $sbHTML.AppendLine("      <H2>Server Memory Inventory</H2>")
Get-UcsMemoryUnit -Ucs $handleArray | Sort-Object -Property Ucs,Dn,Location | where {$_.Capacity -ne "unspecified"} | Select-Object -Property @{Name="POD";Expression={$_.UCS}},Dn,Location,Capacity,Clock,OperState,Model | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 5: UCS Environmental Statistics
[void] $sbHTML.AppendLine("   <div class='content' id='page-5'>")

Write-Host "Getting chassis power usage stats..."
[void] $sbHTML.AppendLine("      <H2>Chassis Power Stats</H2>")
Get-UcsChassisStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,InputPower,InputPowerAvg,InputPowerMax,InputPowerMin,OutputPower,OutputPowerAvg,OutputPowerMax,OutputPowerMin,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting chassis and FI PSU status..."
[void] $sbHTML.AppendLine("      <H2>Chassis and Fabric Interconnect Power Supply Status</H2>")
Get-UcsPsu -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,OperState,Perf,Power,Thermal,Voltage | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting chassis PSU stats..."
[void] $sbHTML.AppendLine("      <H2>Chassis Power Supply Stats</H2>")
Get-UcsPsuStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,AmbientTemp,AmbientTempAvg,Input210v,Input210vAvg,Output12v,Output12vAvg,OutputCurrentAvg,OutputPowerAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting chassis and FI fan stats..."
[void] $sbHTML.AppendLine("      <H2>Chassis and Fabric Interconnect Fan Stats</H2>")
Get-UcsFan -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Module,Id,Perf,Power,OperState,Thermal | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting chassis IO Module (fex) temp stats..."
[void] $sbHTML.AppendLine("      <H2>Chassis IO Module (FEX) Temperature Stats</H2>")
Get-UcsEquipmentIOCardStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,AmbientTemp,AmbientTempAvg,Temp,TempAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting blade power usage stats..."
[void] $sbHTML.AppendLine("      <H2>Server Power Stats</H2>")
Get-UcsComputeMbPowerStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,ConsumedPower,ConsumedPowerAvg,ConsumedPowerMax,InputCurrent,InputCurrentAvg,InputVoltage,InputVoltageAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting blade temprature stats..."
[void] $sbHTML.AppendLine("      <H2>Server Temperature Stats (in Celcius)</H2>")
Get-UcsComputeMbTempStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,FmTempSenIo,FmTempSenIoAvg,FmTempSenIoMax,FmTempSenRear,FmTempSenRearAvg,FmTempSenRearMax,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting Memory temprature stats..."
[void] $sbHTML.AppendLine("      <H2>Cisco Memory Temperature Stats (in Celcius)</H2>")
Get-UcsMemoryUnitEnvStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,Temperature,TemperatureAvg,TemperatureMax,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting CPU Power and temprature stats..."
[void] $sbHTML.AppendLine("      <H2>Cisco CPU Power and Temperature Stats (in Celcius)</H2>")
Get-UcsProcessorEnvStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn |Select-Object @{Name="POD";Expression={$_.UCS}},Dn,InputCurrent,InputCurrentAvg,InputCurrentMax,Temperature,TemperatureAvg,TemperatureMax,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 6: UCS Ethernet Statistics
[void] $sbHTML.AppendLine("   <div class='content' id='page-6'>")

Write-Host "Getting LAN Uplink Port Channels..."
[void] $sbHTML.AppendLine("      <H2>Cisco LAN Uplink Port Channels</H2>")
Get-UcsUplinkPortChannel -Ucs $handleArray| Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Name,Dn,Rn,Status,AdminSpeed,AdminState,AutoNegotiate,Bandwidth,Descr,FlowCtrlPolicy,IfRole,IfType,LacpPolicyName,Locale,OperLacpPolicyName,OperSpeed,OperState,OverlappingVlans,PeerDn,PortId,Sacl,StateQual,SwitchId,Transport,Type,VlanStatus,Warnings | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LAN Uplink Port Channel Loss Stats..."
[void] $sbHTML.AppendLine("      <H2>Cisco LAN Uplink Port Channel Loss Stats</H2>")
Get-UcsEtherLossStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,ExcessCollision,ExcessCollisionDeltaAvg,LateCollision,LateCollisionDeltaAvg,MultiCollision,MultiCollisionDeltaAvg,SingleCollision,SingleCollisionDeltaAvg | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LAN Uplink Port Channel Receive Stats..."
[void] $sbHTML.AppendLine("      <H2>Cisco LAN Uplink Port Channel Receive Stats</H2>")
Get-UcsEtherRxStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,BroadcastPackets,BroadcastPacketsDeltaAvg,JumboPackets,JumboPacketsDeltaAvg,MulticastPackets,MulticastPacketsDeltaAvg,TotalBytes,TotalBytesDeltaAvg,TotalPackets,TotalPacketsDeltaAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting LAN Uplink Port Channel Transmit Stats..."
[void] $sbHTML.AppendLine("      <H2>Cisco LAN Uplink Port Channel Transmit Stats</H2>")
Get-UcsEtherTxStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,BroadcastPackets,BroadcastPacketsDeltaAvg,JumboPackets,JumboPacketsDeltaAvg,MulticastPackets,MulticastPacketsDeltaAvg,TotalBytes,TotalBytesDeltaAvg,TotalPackets,TotalPacketsDeltaAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

Write-Host "Getting vNIC Stats..."
[void] $sbHTML.AppendLine("      <H2>vNIC Stats</H2>")
Get-UcsAdaptorVnicStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,BytesRx,BytesRxDeltaAvg,BytesTx,BytesTxDeltaAvg,PacketsRx,PacketsRxDeltaAvg,PacketsTx,PacketsTxDeltaAvg,DroppedRx,DroppedRxDeltaAvg,DroppedTx,DroppedTxDeltaAvg,ErrorsTx,ErrorsTxDeltaAvg,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 7: UCS FC Statistics
[void] $sbHTML.AppendLine("   <div class='content' id='page-7'>")

Write-Host "Getting LAN Uplink Port Channel Loss Stats..."
[void] $sbHTML.AppendLine("      <H2>FC Uplink Port Stats</H2>")
Get-UcsFcErrStats -Ucs $handleArray | Sort-Object -Property Ucs,Dn | Select-Object @{Name="POD";Expression={$_.UCS}},Dn,CrcRx,CrcRxDeltaAvg,DiscardRx,DiscardRxDeltaAvg,DiscardTx,DiscardTxDeltaAvg,LinkFailures,SignalLosses,Suspect | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

#region Tab 8: UCS Fault Report
[void] $sbHTML.AppendLine("   <div class='content' id='page-8'>")

Write-Host "Getting all UCS Faults sorted by severity..."
[void] $sbHTML.AppendLine("      <H2>Faults</H2>")
Get-UcsFault -Ucs $handleArray | Sort-Object -Property Ucs,Severity | Select-Object @{Name="POD";Expression={$_.UCS}},Severity,Created,Descr,dn | ConvertTo-Html -Fragment | ForEach-Object { [void] $sbHTML.AppendLine($_) }

[void] $sbHTML.AppendLine("   </div>")
#endregion

[void] $sbHTML.AppendLine("</body>")

#region Javascript to Activate the Tabs
[void] $sbHTML.AppendLine(
@"
   <script type='text/javascript'>
        // Wrapped in a function so as to not pollute the global scope.
        var activatables = (function ()
        {
            // The CSS classes to use for active/inactive elements.
            var activeClass = 'active';
            var inactiveClass = 'inactive';

            var anchors = {},
                activates = {};
            var regex = /#([A-Za-z][A-Za-z0-9:._-]*)$/;

            // Find all anchors (<a href='#something'>.)
            var temp = document.getElementsByTagName('a');
            for (var i = 0; i < temp.length; i++)
            {
                var a = temp[i];

                // Make sure the anchor isn't linking to another page.
                if ((a.pathname != location.pathname &&
                        '/' + a.pathname != location.pathname) ||
                    a.search != location.search) continue;

                // Make sure the anchor has a hash part.
                var match = regex.exec(a.href);
                if (!match) continue;
                var id = match[1];

                // Add the anchor to a lookup table.
                if (id in anchors)
                    anchors[id].push(a);
                else
                    anchors[id] = [a];
            }

            // Adds/removes the active/inactive CSS classes depending on whether the
            // element is active or not.
            function setClass(elem, active)
            {
                var classes = elem.className.split(/\s+/);
                var cls = active ? activeClass : inactiveClass,
                    found = false;
                for (var i = 0; i < classes.length; i++)
                {
                    if (classes[i] == activeClass || classes[i] == inactiveClass)
                    {
                        if (!found)
                        {
                            classes[i] = cls;
                            found = true;
                        }
                        else
                        {
                            delete classes[i--];
                        }
                    }
                }

                if (!found) classes.push(cls);
                elem.className = classes.join(' ');
            }

            // Functions for managing the hash.
            function getParams()
            {
                var hash = location.hash || '#';
                var parts = hash.substring(1).split('&');

                var params = {};
                for (var i = 0; i < parts.length; i++)
                {
                    var nv = parts[i].split('=');
                    if (!nv[0]) continue;
                    params[nv[0]] = nv[1] || null;
                }

                return params;
            }

            function setParams(params)
            {
                var parts = [];
                for (var name in params)
                {
                    // One of the following two lines of code must be commented out. Use the
                    // first to keep empty values in the hash query string; use the second
                    // to remove them.
                    //parts.push(params[name] ? name + '=' + params[name] : name);
                    if (params[name]) parts.push(name + '=' + params[name]);
                }

                location.hash = knownHash = '#' + parts.join('&');
            }

            // Looks for changes to the hash.
            var knownHash = location.hash;

            function pollHash()
            {
                var hash = location.hash;
                if (hash != knownHash)
                {
                    var params = getParams();
                    for (var name in params)
                    {
                        if (!(name in activates)) continue;
                        activates[name](params[name]);
                    }
                    knownHash = hash;
                }
            }
            setInterval(pollHash, 250);

            function getParam(name)
            {
                var params = getParams();
                return params[name];
            }

            function setParam(name, value)
            {
                var params = getParams();
                params[name] = value;
                setParams(params);
            }

            // If the hash is currently set to something that looks like a single id,
            // automatically activate any elements with that id.
            var initialId = null;
            var match = regex.exec(knownHash);
            if (match)
            {
                initialId = match[1];
            }

            // Takes an array of either element IDs or a hash with the element ID as the key
            // and an array of sub-element IDs as the value.
            // When activating these sub-elements, all parent elements will also be
            // activated in the process.
            function makeActivatable(paramName, activatables)
            {
                var all = {},
                    first = initialId;

                // Activates all elements for a specific id (and inactivates the others.)
                function activate(id)
                {
                    if (!(id in all)) return false;

                    for (var cur in all)
                    {
                        if (cur == id) continue;
                        for (var i = 0; i < all[cur].length; i++)
                        {
                            setClass(all[cur][i], false);
                        }
                    }

                    for (var i = 0; i < all[id].length; i++)
                    {
                        setClass(all[id][i], true);
                    }

                    setParam(paramName, id);

                    return true;
                }

                activates[paramName] = activate;

                function attach(item, basePath)
                {
                    if (item instanceof Array)
                    {
                        for (var i = 0; i < item.length; i++)
                        {
                            attach(item[i], basePath);
                        }
                    }
                    else if (typeof item == 'object')
                    {
                        for (var p in item)
                        {
                            var path = attach(p, basePath);
                            attach(item[p], path);
                        }
                    }
                    else if (typeof item == 'string')
                    {
                        var path = basePath ? basePath.slice(0) : [];
                        var e = document.getElementById(item);
                        if (e)
                            path.push(e);
                        else
                            return;

                        if (!first) first = item;

                        // Store the elements in a lookup table.
                        all[item] = path;

                        // Attach a function that will activate the appropriate element
                        // to all anchors.
                        if (item in anchors)
                        {
                            // Create a function that will call the 'activate' function with
                            // the proper parameters. It will be used as the event callback.
                            var func = (function (id)
                            {
                                return function (e)
                                {
                                    activate(id);

                                    if (!e) e = window.event;
                                    if (e.preventDefault) e.preventDefault();
                                    e.returnValue = false;
                                    return false;
                                };
                            })(item);

                            for (var i = 0; i < anchors[item].length; i++)
                            {
                                var a = anchors[item][i];

                                if (a.addEventListener)
                                {
                                    a.addEventListener('click', func, false);
                                }
                                else if (a.attachEvent)
                                {
                                    a.attachEvent('onclick', func);
                                }
                                else
                                {
                                    throw 'Unsupported event model.';
                                }

                                all[item].push(a);
                            }
                        }

                        return path;
                    }
                    else
                    {
                        throw 'Unexpected type.';
                    }

                    return basePath;
                }

                attach(activatables);

                // Activate an element.
                if (first) activate(getParam(paramName)) || activate(first);
            }

            return makeActivatable;
        })();

        activatables('page', ['page-1', 'page-2', 'page-3', 'page-4', 'page-5', 'page-6', 'page-7', 'page-8']);
   </script>
"@)
#endregion

[void] $sbHTML.AppendLine("</html>")

$sbHTML.ToString() | Out-File -FilePath $ReportFile -Force

######################
# E-mail HTML output #
######################
if ($enablemail -match "yes")
{
    $msg = new-object Net.Mail.MailMessage
    $att = new-object Net.Mail.Attachment($ReportFile)
    $smtp = new-object Net.Mail.SmtpClient($smtpServer)
    $msg.From = $mailfrom
    $msg.To.Add($mailto)
    $msg.Subject = “Cisco UCS Health Check”
    $msg.Body = “Cisco UCS Health Check, open the attached HTML file to view the report.”
    $msg.Attachments.Add($att)
    $smtp.Send($msg)
}
