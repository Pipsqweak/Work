
if($theone -ne $null)
{
}

$data = Import-Csv "C:\Users\........Production.csv" -Delimiter "`t"
# $msOnlineCredential = Get-Credential -Message "Enter credentials for Azure AD/MS Teams"
$powerAzureADTenantID = "f07fff05-bf71-4ed8-b274-173ea27956dc"
$Global:CallQueueApplicationInstanceID = "11cd3e2e-fccb-42ad-ad00-878b93575e07"  # https://docs.microsoft.com/en-us/powershell/module/skype/new-csonlineapplicationinstance?view=skype-ps
$Global:maximumRetries = 5
$Global:retryDelayTime = 1000   # in milliseconds

$Global:VerboseOutput = $VerbosePreference -eq "Continue"
$Global:LastTestedServiceConnectivity = $null

<#
Hi Ken,
The accounts for testing have been created as follows”
RA Test (Resource Account) – number assigned 602-892-0089
RA Test Backup (Resource Account)

RA Test Call Queue
RA Test Backup Call Queue

Feel free to do whatever you need to these accounts.

#>

# $msOnlineCreds = Get-Credential -Message "O365/Teams/Azure AD credentials"

Connect-AzureAD
Connect-MicrosoftTeams -TenantId $powerAzureADTenantID

# Connect-MsolService


if(-not [String]::IsNullOrEmpty($Global:phoneSystemVirtualUserSkuId))
{
    # Test Item
    $item = "" | Select-Object UPN,DisplayName,PhoneNumber,Country,CQName
    $item.UPN = "ratestklb@powereng0.onmicrosoft.com"
    $item.DisplayName = "RA Test Account KLB"
    $item.PhoneNumber = "+16025625530"
    $item.Country = "US"
    $item.CQName = "CQ Test Account KLB"

    foreach ($item in $data)
    {
        $forwardCallForParams = @{
            UserPrincipalName = $item.UPN
            DisplayName = $item.DisplayName
            PhoneNumber = $item.PhoneNumber
            Country = $item.Country
            CallQueueName = $item.CQName
            VerboseOutput = $Global:VerboseOutput
        }

        Set-CallForwardingFor @forwardCallForParams
    }
}
else
{
    # Nothing, can't create call queues without the PHONESYSTEM_VIRTUALUSER account SKU
}


$UserPrincipalName = $item.UPN
$DisplayName = $item.DisplayName
$PhoneNumber = $item.PhoneNumber
$Country = $item.Country
$CallQueueName = $item.CQName
$VerboseOutput = $Global:VerboseOutput
$maxRetries = $Global:maximumRetries
$retryDelay = $Global:retryDelayTime

function INET_ATON   # Yes -- just like in MySQL server :)
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [String] $ipStr
    )

    [uint32] $ipAddr = 0
    $tempIP = [System.Net.IPAddress]::new(0)
    if ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # TRUE

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
    }
    else # NOT ([System.Net.IPAddress]::TryParse($ipStr, [ref] $tempIP))
    {
        # FALSE

        # Nothing -- just return 0 for the converted IP address to signal an error
    }

    return $ipAddr
}

function INET_NTOA
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [UInt32] $ipAddress
    )

    $octets = @(0,0,0,0)

    for($o = 3; $o -ge 0; $o--)
    {
        $octets[$o] = ($ipAddress -shr (24 - ($o * 8))) -band 255
    }

    return ($octets -join ".")
}

<#
    NOTE: Need to walk nfsPath looking for export policies

    /VMware/cdc_DMZ_SATA_01
  |     |        `----> exp_vmware_dmz_nfs_01
  |     `---> exp_cdc_vmware_all_nfs_01
  `---> exp_default  (This is the export policy assigned to the SVM's root volume -- everything must have at least read-only permissions to get any further down the path.)
#>



#
#   /
$dsVol = Get-NCVol  -Controller $cdcNC | Where-Object { $_.JunctionPath -eq $datastoreDefs[0].nfsPath }
if($null -ne $dsVol)
{
    $exportPolicyRules = @(Get-NcExportRule -Controller $dsVol.NcController -Vserver $dsVol.Vserver -Policy $dsVol.VolumeExportAttributes.Policy)
}

# For /VMWare
$newExportRuleParams = @{
    ClientMatch = "10.245.68.18"
    Policy = "exp_cdc_vmware_all_nfs_01"
    ReadOnlySecurityFlavor = "sys"
    ReadWriteSecurityFlavor = "sys"
#    Anon = ""
    ChownMode = "restricted"
    DisableDev = $false
    DisableSetUid = $false
    EnableDev = $true
    EnableSetUid = $true
    Index = 14
    NtfsUnixSecurityOps = "fail"
    Protocol = "nfs"
    SuperUserSecurityFlavor = "any"
    VserverContext = $dsVol.Vserver
    NcController = $dsVol.NcController
}

# For /VMWare/cdc_DMZ_SATA_01
$newExportRuleParams = @{
    ClientMatch = "10.245.68.17"
    Policy = "exp_vmware_dmz_nfs_01"
    ReadOnlySecurityFlavor = "sys"
    ReadWriteSecurityFlavor = "sys"
#    Anon = ""
    ChownMode = "restricted"
    DisableDev = $false
    DisableSetUid = $false
    EnableDev = $true
    EnableSetUid = $true
    Index = 15
    NtfsUnixSecurityOps = "fail"
    Protocol = "nfs"
    SuperUserSecurityFlavor = "any"
    VserverContext = $dsVol.Vserver
    NcController = $dsVol.NcController
}

# For SVM root volume
$svmRoot = Get-NCVol -Controller $dsVol.NcController -Vserver $dsVol.Vserver | Where-Object { ($_.VolumeStateAttributes.IsVserverRoot) -and (-not $_.VolumeMirrorAttributes.IsLoadSharingMirror) }
$exportPolicyRules = @(Get-NcExportRule -NcController $svmRoot.NcController -Vserver $svmRoot.Vserver -Policy $svmRoot.VolumeExportAttributes.Policy)
$newExportRuleParams = @{
    ClientMatch = "10.245.68.17"
    Policy = $exportPolicyRules[0].PolicyName
    ReadOnlySecurityFlavor = "none"
    ReadWriteSecurityFlavor = "none"
#    Anon = ""
    ChownMode = "restricted"
    DisableDev = $false
    DisableSetUid = $false
    EnableDev = $true
    EnableSetUid = $true
    Index = $exportPolicyRules.Length + 1
    NtfsUnixSecurityOps = "fail"
    Protocol = "nfs"
    SuperUserSecurityFlavor = "any"
    VserverContext = $exportPolicyRules[0].Vserver
    NcController = $exportPolicyRules[0].NcController
}



$clientIPAddr = INET_ATON "10.245.11.30"


Backup-Ucs -Ucs $cdcUCS -Type config-logical -PathPattern '${ucs}-${yyyy}${MM}${dd}-${HH}${mm}-config-logical.xml'

$vmkData = @(
    $a = 0
    while($a -lt $vmHosts.Length)
    {
        $vmks = @(Get-VMHostNetworkAdapter -VMHost $vmHosts[$a] -VMKernel)

        $b = 0
        while($b -lt $vmks.Length)
        {
            $d = "" | Select-Object Host, VMK, IP

            $d.Host = $vmHosts[$a].Name
            $d.VMK = $vmks[$b].DeviceName
            $d.IP = $vmks[$b].IP

            $d
            $b++
        }
        $a++
    }
)


$ucsHosts = @(
    "cdc-esx-c1-b1", "cdc-esx-c1-b2", "cdc-esx-c1-b3", "cdc-esx-c1-b4", "cdc-esxvcad01",
    "cdc-esxvcad02", "cdcz-esx-c1-b5", "cdcz-esx-c1-b6", "ddc-esx-c1-b1", "ddc-esx-c1-b2",
    "ddc-esx-c1-b3", "ddc-esx-c1-b4", "ddc-esx-c1-b5", "ddc-esx-c1-b6", "ddc-esx-c1-b7",
    "ddc-esx-c1-b8", "ddc-esx-c2-b1", "ddc-esx-c2-b2", "ddc-esx-c2-b3", "ddc-esx-c2-b4",
    "ddc-esx-c2-b5", "ddc-esx-c2-b6", "ddc-esx-c2-b7", "ddc-esx-c2-b8", "ddc-esx-c3-b1",
    "ddc-esx-c3-b2", "ddc-esx-c3-b3", "ddc-esx-c3-b4", "ddc-esxvcad01", "ddc-esxvcad02",
    "ddc-esxvcad03", "ddc-esxvcad04", "ddc-esxvcad05"
)

$a = 0
while($a -lt $ucsHosts.Length)
{
    CaptureVMHostVMs -vCenter $vcenter -vmHostName $ucsHosts[$a]
    $a++
}

# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esx-c1-b1"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esx-c1-b2"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esx-c1-b3"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esx-c1-b4"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esxvcad01"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdc-esxvcad02"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdcz-esx-c1-b5"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "cdcz-esx-c1-b6"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b1"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b2"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b3"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b4"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b5"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b6"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b7"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c1-b8"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b1"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b2"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b3"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b4"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b5"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b6"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b7"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c2-b8"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c3-b1"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c3-b2"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c3-b3"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esx-c3-b4"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esxvcad01"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esxvcad02"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esxvcad03"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esxvcad04"
# RemoveVMHostDatastores -vCenter $vCenter -vmHostName "ddc-esxvcad05"


# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esx-c1-b1"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esx-c1-b2"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esx-c1-b3"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esx-c1-b4"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esxvcad01"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdc-esxvcad02"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdcz-esx-c1-b5"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "cdcz-esx-c1-b6"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b1"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b2"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b3"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b4"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b5"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b6"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b7"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c1-b8"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b1"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b2"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b3"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b4"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b5"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b6"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b7"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c2-b8"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c3-b1"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c3-b2"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c3-b3"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esx-c3-b4"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esxvcad01"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esxvcad02"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esxvcad03"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esxvcad04"
# RestoreVMHostVMs -vCenter $vcenter -vmHostName "ddc-esxvcad05"

# cdc-esx-c1-b1
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esx-c1-b1"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdc-esx-c1-b2
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esx-c1-b2"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdc-esx-c1-b3
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esx-c1-b3"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdc-esx-c1-b4
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esx-c1-b4"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdc-esxvcad01
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esxvcad01"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdc-esxvcad02
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdc-esxvcad02"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdcz-esx-c1-b5
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcDMZv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdcz-esx-c1-b5"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# cdcz-esx-c1-b6
$virtualizationDefinition = Get-Content -Path ".\VMWare\cdcDMZv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "cdcz-esx-c1-b6"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $cdcUCS -vdsName "CDC DMZ vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b1
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b1"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b2
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b2"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b3
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b3"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b4
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b4"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b5
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b5"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b6
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b6"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b7
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b7"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c1-b8
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c1-b8"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b1
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b1"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b2
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b2"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b3
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b3"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b4
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b4"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b5
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b5"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b6
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b6"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b7
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b7"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c2-b8
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c2-b8"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c3-b1
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c3-b1"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c3-b2
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c3-b2"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c3-b3
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c3-b3"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esx-c3-b4
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddcInternalv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esx-c3-b4"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC Internal vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC Internal vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esxvcad01
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esxvcad01"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esxvcad02
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esxvcad02"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esxvcad03
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esxvcad03"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esxvcad04
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esxvcad04"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

# ddc-esxvcad05
$virtualizationDefinition = Get-Content -Path ".\VMWare\ddc-vdivcadv2.json" | ConvertFrom-Json
$hostDef = GetHostDefinition -virtualizationDefinition $virtualizationDefinition -hostName "ddc-esxvcad05"
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -ExcludevmNIC0 -DoIt -doReportSuccess
MigrateHostVMKsToVDS -vCenter $vCenter -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -DoIt -doReportSuccess
MigrateHostVMNICsToVDS -vCenter $vCenter -ucsManager $ddcUCS -vdsName "DDC VCAD/VDI vDS 01" -hostDef $hostDef -OnlyvmNIC0 -DoIt -doReportSuccess
MountDatastoresToHost -vCenter $vCenter -datastores $virtualizationDefinition.datastores -hostDef $hostDef -cDot $cDot -doReportSuccess

$a = 0
$result = @()
while($a -lt $vmHosts.Length)
{
    $vmHost = $vmHosts[$a]
    $esxcli = Get-EsxCli -V2 -VMHost $vmHost
    $d = $esxcli.storage.core.device.list.invoke() | Where-Object {$_.IsBootDevice -match "true"} | Select-Object @{N="VMhost";E={$vmHost.Name}}, Vendor, Model, IsBootDevice, IsLocal, IsSAS, IsSSD, IsUSB, Device
    $d
    $result += $d
    $a++
}
