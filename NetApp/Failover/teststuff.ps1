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

function NetworkContains
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [UInt32] $netAddress,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateRange(0,32)]
        [Int32] $netBits,

        [Parameter(Mandatory=$true, Position=2)]
        [UInt32] $ipAddress
    )

    $mask = INET_ATON "255.255.255.255"
    $hostMask = (1 -shl (32 - $netBits)) - 1
    $netMask = $mask -band (-bnot $hostMask)

    return ($netAddress -band $netMask) -eq ($ipAddress -band $netMask)
}
$allNFSDatastores = @(Get-Datastore -Server @($vCenterServers.Values) | Where-Object { $_.Type -eq "nfs" })

$volumeExportRules = @(Get-NcExportRule -Controller $vol.NcController -Vserver $vol.Vserver -Policy $vol.VolumeExportAttributes.Policy -Protocol "nfs" -ErrorAction Stop)

$a = 0
$found = $false
$matchingDatastore = $null
while(($null -eq $matchingDatastore) -and ($a -lt $allNFSDatastores.Length))
{
    $a++
}
$b = 0
while((-not $found) -and ($a -lt $ds[1].RemoteHost.Length))
{
    $remoteHostAddress = INET_ATON $ds[1].RemoteHost[$b]

    $c = 0
    while((-not $found) -and ($c -lt $volumeExportRules.Length))
    {
        $netBits = 32
        if($volumeExportRules[$c].ClientMatch -match "^([\.\d]+)[/]?(\d*)?")
        {
            $netIPStr = $Matches[1]
            if(-not [String]::IsNullOrEmpty($Matches[2]))
            {
                $netBits = [Int32] $Matches[2]
            }

            $found = NetworkContains -netAddress (INET_ATON $netIPStr) -netBits $netBits -ipAddress $remoteHostAddress
        }
        $c++
    }
    $b++
}

$allSourceVServerSnapmirrors = @(Get-NcSnapmirror -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { $_.SourceVserver -eq $SourceVServerName })

# Obviously, these will be set dynamically.
$oldSourceVServerUuid = "2a96bc80-75f2-11eb-99c2-d039ea238501"
$oldSourceVolume = "vol_SMB_REPLICATE_01"
$newSourceVServerUuid = "80452834-cb5f-11ee-9308-d039ea17955e"
$newSourceVolume = "SMDV_vol_LAB_SMB01_vol_SMB_REPLICATE_01"


$snapmirrorPolicyTranslationTable = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $allSourceVServerSnapmirrors.Length)
{
    $d = "" | Select-Object SourceVServerUuid, SourceVolume, DestinationVserverUuid, DestinationVolume, Policy
    $d.SourceVServerUuid = $allSourceVServerSnapmirrors[$a].SourceVServerUuid
    $d.SourceVolume = $allSourceVServerSnapmirrors[$a].SourceVolume
    $d.DestinationVserverUuid = $allSourceVServerSnapmirrors[$a].DestinationVserverUuid
    $d.DestinationVolume = $allSourceVServerSnapmirrors[$a].DestinationVolume
    $d.Policy = $allSourceVServerSnapmirrors[$a].Policy

    if(($allSourceVServerSnapmirrors[$a].SourceVServerUuid -eq $oldSourceVServerUuid) -and ($allSourceVServerSnapmirrors[$a].SourceVolume -eq $oldSourceVolume))
    {
        $d.SourceVServerUuid = $newSourceVServerUuid
        $d.SourceVolume = $newSourceVolume
    }
    else
    {
        # Nothing, already correctly set the source VServer and Volume.
    }

    if (($allSourceVServerSnapmirrors[$a].DestinationVserverUuid -eq $newSourceVServerUuid) -and ($allSourceVServerSnapmirrors[$a].DestinationVolume -eq $newSourceVolume))
    {
        $d.DestinationVserverUuid = $oldSourceVServerUuid
        $d.DestinationVolume = $oldSourceVolume
    }
    else
    {
        # Nothing, already correctly set the destination VServer and Volume.
    }

    $snapmirrorPolicyTranslationTable.Add($d)
    $a++
}

$svmPeersOk = $true
$allSnapmirrors = Get-NCSnapmirror -Controller @($cDot.Values)
$svmPeers = Get-NcVserverPeer -Controller @($cDot.Values)

$a = 0
while($a -lt $allSnapmirrors.Length)
{
    $reversePeer = $svmPeers | Where-Object { ($_.PeerVserverUuid -eq $allSnapmirrors[$a].SourceVserverUuid) -and ($_.VserverUuid -eq $allSnapmirrors[$a].DestinationVserverUuid) }
    if($null -eq $reversePeer)
    {
        $svmPeersOk = $false
        LogError ("Missing reverse SVM peering from {0} and {1}" -f @($allSnapmirrors[$a].DestinationVserver, $allSnapmirrors[$a].SourceVserver)) 0
    }
    $a++
}

if($svmPeersOk)
{
    LogInfo "GREAT NEWS!!!  All SVM reverse peerings appear to be in-place!!"
}
else
{
    LogError ("Please fix all reverse SVM peerings and retry!")
}


function GetSourceVServers()
{
    $snapmirrors = Get-NcSnapmirror -Controller @($cDot.Values)
    $srcVServers = @($snapmirrors | Select-Object -Unique -ExpandProperty SourceVServer)

    return $srcVServers
}

function GetDestinationVServersForSourceVServer($srcVServer)
{
    $destinationSMs = Get-NcSnapmirrorDestination -Controller @($cDot.Values) -SourceVserver $srcVServer
    $destinationVServers = @($destinationSMs | Select-Object -Unique -ExpandProperty DestinationVserver | Sort-Object)

    return $destinationVServers
}

function ta1
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [DataONTAP.C.Types.Volume.VolumeAttributes[]] $vols
    )

    Write-Host ("{0} volumes" -f @($vols.Length))
}

function ta2
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl] $ds
    )

    Write-Host ("{0}" -f @($ds.RemotePath))
}

$ds2VMHost = [System.Collections.Generic.SortedDictionary[System.String,System.Collections.Generic.List[System.Object]]]::new()
$a = 0
while($a -lt $data.NFSDatastores.Length)
{
    $dsID = $data.NFSDatastores[$a].Id.Replace("Datastore-","")
    $ds2VMHost.Add($dsID, [System.Collections.Generic.List[System.Object]]::new())

    ($vmHosts | Where-Object { (@($_.ExtensionData.Datastore | Where-Object { $_.Value -eq $dsId }).Length -gt 0) }) | ForEach-Object { $ds2VMHost[$dsID].Add($_) }

    $a++
}
