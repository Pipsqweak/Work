[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $SourceVServerName,

    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $DRVServerName,

    [Parameter(Mandatory=$false,Position=2)]
    [Switch]
    $Simulated = $false
)

<#
    NOTES:  Need to update this block....

    Consider changing this from a CIFS server thing to a VServer thing.  That way we migrate all snapmirror volumes to the destination...
        Failover-VServer -SourceVServerName LAB-SMB01 -DRVServerName LABDR-SMB02

        -- Possible issues:
            What if there are volumes on SourceVServer that are snapmirrored to a different VServer than DRVServerName
            - This shouldn't matter since the point of this script is to failover volumes from the source to the specified destination.


    1. Get all volumes hosted on SourceVServerName that have snapmirror destinations on DRVServerName.

    2. For each volume found:
        a. Add the source volume to the list of new snapmirror destination volumes ($newSnapmirrorDestinationVolumes)
        b. Get all snapmirrors (across all ONTAP clusters) where the snapmirror source = source VServer/volume
            1) For each snapmirror:
                a) Capture the destination volume for the snapmirror
                    A. If the snapmirror destination volume is hosted on DRVServerName
                        then: capture it as $newSnapmirrorSourceVolume
                        else: add the volume to the list of new snapmirror destination volumes ($newSnapmirrorDestinationVolumes)
                a) Sync from source to destination.
                b) Break snapmirror
            2) For each $newSnapmirrorDestinationVolumes
                a) Create a new snapmirror between $newSnapmirrorSourceVolume and $newSnapmirrorDestinationVolumes[x]
                b) (Re)sync the snapmirror between $newSnapmirrorSourceVolume and $newSnapmirrorDestinationVolumes[x]
        c. Capture if there are any CIFS shares hosted on the source volume.  ($sourceHasCIFSShares)
        d. Update the snapshot policy on the new snapmirror source volume. ($newSnapmirrorSourceVolume)
            1) Use the same snapshot policy that is used on the source volume.

    4. If the source VServer hosted any CIFS shares ($sourceHasCIFSShares)
        then:
            a. Migrate service principal names from the source AD computer object to the destination AD computer object
            b. Update the "FS1" CNAME record in DNS.

#>

function LogOutput
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Int32]
        $IndentLevel,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.ConsoleColor]
        $Color,

        [Parameter(Mandatory = $false, Position = 2)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 4)]
        [Switch]
        $NewLine
    )

    if($null -eq $Script:sbMessageLog)
    {
        $Script:sbMessageLog = [System.Text.StringBuilder]::new()
    }

    if($NewLine)
    {
        Write-Host ""
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.AppendLine("")
        }
    }

    $indent = [String]::new(' ', ($IndentLevel * 3))
    if($NoNewLine)
    {
        Write-Host -ForegroundColor $Color -NoNewline ("{0}{1}" -f @($indent, $message))
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.Append(("{0}{1}" -f @($indent, $message)))
        }
    }
    else
    {
        Write-Host -ForegroundColor $color ("{0}{1}" -f @($indent, $message))
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.AppendLine(("{0}{1}" -f @($indent, $message)))
        }
    }
}

function LogInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Green -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogWarning
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Yellow -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function LogError
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Red -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogException
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Red -Message ("Exception: {0}" -f @($Message)) -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function VolumeToString
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume
    )

    return "{0}:{1}:{2}" -f @($volume.NcController.Name, $volume.Vserver, $volume.Name)
}

function StartCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer
    )

    $good2Go = $true

    try
    {
        $Error.Clear()
        LogInfo ("Starting CIFS services on: {0}:{1}{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $Global:simulatedMsg)) 1
        if(-not $Simulated)
        {
            Start-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -Confirm:$false -ErrorAction Stop | Out-Null
        }

        # Wait for the CIFS service to be down...
        LogInfo ("Waiting for CIFS server {0}:{1} to be on-line.{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $Global:simulatedMsg)) 2 -NoNewLine
        do
        {
            try
            {
                $Error.Clear()
                $cifsServer = Get-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -ErrorAction Stop
                if($null -ne $cifsServer)
                {
                    if((-not $Simulated) -and ($cifsServer.AdministrativeStatus -ne "up"))
                    {
                        LogInfo "." -NoNewLine
                        # Pause a moment for station identification...
                        Start-Sleep -Seconds 5
                    }
                }
                else
                {
                    LogError ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
                    $good2Go = $false
                }
            }
            catch
            {
                LogException ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 2
                $errStr = $Error[0] | Out-String
                LogError ("{0}" -f @($errStr))
                $good2Go = $false
            }
        } until (($Simulated) -or (-not $good2Go) -or ($cifsServer.AdministrativeStatus -eq "up"))
        if($cifsServer.AdministrativeStatus -eq "up")
        {
            LogInfo
        }
    }
    catch
    {
        LogException ("Failed to start CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
        $good2Go = $false
    }

    if(-not $good2Go)
    {
        LogWarning ("Please remember to check CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
    }
}

function ShutdownCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer
    )

    $good2Go = $true

    try
    {
        LogInfo ("Stopping CIFS services on: {0}:{1}{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $Global:simulatedMsg)) 1
        if(-not $Simulated)
        {
            $Error.Clear()
            Stop-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -Confirm:$false -ErrorAction Stop | Out-Null
        }

        # Wait for the CIFS service to be down...
        LogInfo ("Waiting for CIFS server {0}:{1} to be off-line.{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $Global:simulatedMsg)) 1 -NoNewLine
        do
        {
            try
            {
                $Error.Clear()
                $cifsServer = Get-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -ErrorAction Stop
                if($null -ne $cifsServer)
                {
                    if((-not $Simulated) -and ($cifsServer.AdministrativeStatus -ne "down"))
                    {
                        LogInfo "." -NoNewLine
                        # Pause a moment for station identification...
                        Start-Sleep -Seconds 5
                    }
                }
                else
                {
                    LogError ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
                    $good2Go = $false
                }
            }
            catch
            {
                LogException ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
                $errStr = $Error[0] | Out-String
                LogError ("{0}" -f @($errStr))
                $good2Go = $false
            }
        } until (($Simulated) -or (-not $good2Go) -or ($cifsServer.AdministrativeStatus -eq "down"))
        LogInfo ""
    }
    catch
    {
        LogException ("Failed to stop CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
        $good2Go = $false
    }

    return $good2Go
}

function WaitForSnapmirrorAction
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $status2WaitFor,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $mirrorState2WaitFor,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FailureMsg
    )

    $good2Go = $true

    # Now, wait until the snapmirror is $status2WaitFor...
    LogInfo ("Waiting for snapmirror to be {0}/{1} (CTRL-C to abort script)." -f @($status2WaitFor, $mirrorState2WaitFor, $Global:simulatedMsg)) 2 -NoNewLine
    do
    {
        try
        {
            $Error.Clear()
            # Refresh the snapmirror info to see if its idle...
            $snapmirror = Get-NCSnapmirror -Controller $snapmirror.NcController -DestinationVserver $snapmirror.Vserver -DestinationVolume $snapmirror.DestinationVolume -ErrorAction Stop
            if($null -ne $snapmirror)
            {
                if((-not $Simulated) -and (($snapmirror.Status -ne $status2WaitFor) -or ($snapmirror.MirrorState -ne $mirrorState2WaitFor)))
                {
                    LogInfo "." -NoNewLine
                    # Pause a moment for station identification...
                    Start-Sleep -Seconds 5
                }
                else
                {
                    # Nothing, snapmirror is good to go...
                }
            }
            else
            {
                LogError $FailureMsg 2 -NewLine
                $good2Go = $false
            }
        }
        catch
        {
            LogException $FailureMsg 2 -NewLine
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr))
            $good2Go = $false
        }
    } until($Simulated -or (-not $good2Go) -or (($snapmirror.Status -eq $status2WaitFor) -and ($snapmirror.MirrorState -eq $mirrorState2WaitFor)))
    LogInfo ""

    return $good2Go
}

function IsSnapmirrorReady
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$false, Position=1)]
        [System.String]
        $desiredMirrorState = "snapmirrored",

        [Parameter(Mandatory=$false, Position=2)]
        [System.String]
        $desiredStatus = "idle"
    )

    $good2Go = $true    # Set to false if an error occurs.
    # Assume the snapmirror is not ready until we determine it is...
    $snapmirrorReady = $false
    LogInfo ("Refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}..." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
    try
    {
        $Error.Clear()
        $snapmirror = Get-NcSnapmirror -Controller $snapmirror.NcController -VserverContext $snapmirror.Vserver -SourceVserver $snapmirror.SourceVserver -SourceVolume $snapmirror.SourceVolume -ErrorAction Stop
        if($null -ne $snapmirror)
        {
            # Make sure the snapmirror is in the desired state
            if($snapmirror.MirrorState -eq $desiredMirrorState)
            {
                # Further, make sure the snapmirror status is $desiredStatus
                if($snapmirror.Status -eq $desiredStatus)
                {
                    $snapmirrorReady = $true
                }
                else
                {
                    LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} has status {5}.  Expected: {6}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $snapmirror.MirrorState, $desiredStatus)) 1
                }
            }
            else
            {
                LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} has mirror state {5}.  Expected: {6}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $snapmirror.MirrorState, $desiredMirrorState)) 1
            }
        }
        else
        {
            LogError ("Failed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}.  (`$null returned)" -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
            $good2Go = $false
        }
    }
    catch
    {
        LogException ("Failed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
        $good2Go = $false
    }

    return @($good2Go, $snapmirrorReady)
}

function UpdateSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror
    if($good2Go)
    {
        if($snapmirrorReady)
        {
            try
            {
                LogInfo ("Updating snapmirror {0}:{1}:{2}.{3}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $Global:simulatedMsg)) 2
                if(-not $Simulated)
                {
                    $Error.Clear()
                    $null = Invoke-NcSnapmirrorUpdate -Controller $snapmirror.NcController -DestinationVserver $snapmirror.Vserver -DestinationVolume $snapmirror.DestinationVolume -ErrorAction Stop
                }

                # Now, wait until the snapmirror is idle...
                $good2Go = WaitForSnapmirrorAction -snapmirror $snapmirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg ("Failed to retrieve snapmirror status after invoking an update between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
            }
            catch
            {
                LogException ("Failed to update snapmirror between {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
                $errStr = $Error[0] | Out-String
                LogError ("{0}" -f @($errStr))
                $good2Go = $false
            }
        }
        else
        {
            LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
        }
    }
    else
    {
        # Nothing, an error would have already been displayed
    }

    return $good2Go
}

function BreakSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror
    if($good2Go)
    {
        if($snapmirrorReady)
        {
            $maxRetries = 3
            $retries = 0
            $brokenOff = $false
            while((-not $brokenOff) -and ($retries -lt 3))
            {
                $retries++
                try
                {
                    LogInfo ("Breaking snapmirror {0}:{1}:{2} - try {3} of {4}.{5}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $retries, $maxRetries, $Global:simulatedMsg)) 2
                    if(-not $Simulated)
                    {
                        $Error.Clear()
                        $null = Invoke-NcSnapmirrorBreak -Controller $snapmirror.NcController -DestinationVserver $snapmirror.Vserver -DestinationVolume $snapmirror.DestinationVolume -Confirm:$false -ErrorAction Stop
                        $brokenOff = $true

                        # Now, wait until the snapmirror is idle...
                        $good2Go = WaitForSnapmirrorAction -snapmirror $snapmirror -status2WaitFor "idle" -mirrorState2WaitFor "broken-off" -FailureMsg ("Failed to retrieve snapmirror status after invoking snapmirror break between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
                    }
                    else
                    {
                        # Nothing, just simulated.
                    }
                }
                catch
                {
                    if($retries -lt $maxRetries)
                    {
                        LogException ("Failed to break snapmirror between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
                        $errStr = $Error[0] | Out-String
                        LogError ("{0}" -f @($errStr))
                        $good2Go = $false
                    }
                    else
                    {
                        LogWarning "Pausing 10 seconds before retry..."
                        Start-Sleep -Seconds 10
                    }
                }
                $retries++
            }
        }
        else
        {
            LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
            $good2Go = $false
        }
    }
    else
    {
        # Nothing, an error would already have been displayed.
    }

    return $good2Go
}

function DeleteSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = $true
    $snapmirrorReady = $true

    $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus "idle"

    if($snapmirrorReady)
    {
        try
        {
            LogInfo ("Removing snapmirror {0}:{1}:{2}.{3}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $Global:simulatedMsg)) 2
            if(-not $Simulated)
            {
                $Error.Clear()
                Remove-NcSnapmirror -Controller $snapmirror.NcController -DestinationVolume $snapmirror.DestinationVolume -DestinationVserver $snapmirror.DestinationVserver -Confirm:$false -ErrorAction Stop | Out-Null
            }
        }
        catch
        {
            LogException ("Failed to remove snapmirror relationship between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr))
            $good2Go = $false
        }
    }
    else
    {
        LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
    }

    return $good2Go
}

function ReleaseSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = $false
    $snapmirrorReady = $true
    # $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus = "idle"

    if($snapmirrorReady)
    {
        try
        {
            LogInfo ("Releasing snapmirror {0}:{1}:{2} -> {3}:{4}:{5}.{6}" -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $Global:simulatedMsg)) 2
            if(-not $Simulated)
            {
                $Error.Clear()
                Invoke-NcSnapmirrorRelease -Controller $sourceVolume.NcController -SourceVserver $sourceVolume.Vserver -SourceVolume $sourceVolume.Name -DestinationVolume $snapmirror.DestinationVolume -DestinationVserver $snapmirror.DestinationVserver -RelationshipId $snapmirror.RelationshipId -Confirm:$false -ErrorAction Stop  | Out-Null
            }
            $good2Go = $true
        }
        catch
        {
            LogException ("Failed to release snapmirror relationship between: {0}:{1}:{2} -> {3}:{4}:{5}." -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr))
        }
    }
    else
    {
        LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
    }

    return $good2Go
}

function CreateSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $dstVolume,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $snapmirrorPolicyName
    )

    $good2Go = $false

    LogInfo ("Verifying existence of snapmirror policy {0} on {1}" -f @($snapmirrorPolicyName, $dstVolume.NcController.Name)) 2
    try
    {
        $Error.Clear()
        $snapmirrorPolicies = @(Get-NcSnapmirrorPolicy -Controller $dstVolume.NcController -Name $snapmirrorPolicyName -ErrorAction Stop)
        if($snapmirrorPolicies.Length -gt 0)
        {
            try
            {
                LogInfo ("Creating snapmirror source: {0}:{1}:{2} destination: {3}:{4}:{5}.{6}" -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name, $Global:simulatedMsg)) 2
                if(-not $Simulated)
                {
                    <#  NOTE new mirror is broken-off! #>
                    $Error.Clear()
                    $newSnapmirror = New-NcSnapmirror -DestinationVolume $dstVolume.Name -DestinationVserver $dstVolume.VServer -SourceVolume $srcVolume.Name -SourceVserver $srcVolume.VServer -Controller $dstVolume.NCController -Policy $snapmirrorPolicyName -ErrorAction Stop
                }

                $good2Go = $Simulated -or ($null -ne $newSnapmirror)
            }
            catch
            {
                LogException ("Failed to create snapmirror source: {0}:{1}:{2} destination: {3}:{4}:{5}." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
                $errStr = $Error[0] | Out-String
                LogError ("{0}" -f @($errStr))
            }
        }
        else
        {
            LogError ("Failed to acquire snapmirror policy {0} from {1}." -f @($snapmirrorPolicyName, $dstVolume.NcController.Name))
        }
    }
    catch
    {
        LogException ("Failed to acquire snapmirror policy {0} from {1}." -f @($snapmirrorPolicyName, $dstVolume.NcController.Name)) 2
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
    }

    return $good2Go
}

function ResyncSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $dstVolume
    )

    $good2Go = $false
    $snapmirrorReady = $true
    # $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus = "idle"

    if($snapmirrorReady)
    {
        try
        {
            LogInfo ("Resyncing snapmirror {0}:{1}:{2} -> {3}:{4}:{5}.{6}" -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name, $Global:simulatedMsg)) 2
            if(-not $Simulated)
            {
                $Error.Clear()
                <# NOTE:  Need to disable ransomware stuff on the destination volume. #>
                $result = Invoke-NcSnapmirrorResync -Controller $dstVolume.NcController -DestinationVserver $dstVolume.Vserver -DestinationVolume $dstVolume.Name -ErrorAction Stop

                <#
                    NcController      : LAB-NTAP01
                    ResultOperationId : 30fc8f26-d10e-11ee-9cb9-d039ea238501
                    ErrorCode         :
                    ErrorMessage      :
                    JobId             :
                    JobVserver        :
                    Status            : succeeded
                #>
            }

            $good2Go = $Simulated -or (($null -ne $result) -and ($result.Status -eq "succeeded"))
        }
        catch
        {
            LogException ("Failed to resync snapmirror {0}:{1}:{2} -> {3}:{4}:{5}." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr))
        }
    }
    else
    {
        LogError ("Snapmirror between {0}:{1}:{2} and {3}:{4}:{5} is not idle/snapmirrored." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
    }

    return $good2Go
}

function UpdateServicePrincipalName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADComputer]
        $adComp,

        [Parameter(Mandatory=$false,Position=1)]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc = $null
    )

    $good2Go = $true

    # This is what the values should be before we update the AD object
    $servicePrincipalNamesStringBefore = (($adComp.servicePrincipalName | Sort-Object) -join "|").ToLower()

    LogInfo ("Updating {0}...{1}" -f @($adComp.Name, $Global:simulatedMsg)) 3
    $setADCompParams = @{
        Instance = $adComp
        ErrorAction = [System.Management.Automation.ActionPreference]::Stop
    }

    # If a domain controller was given, add it to the parameter hash table
    if($null -ne $dc)
    {
        $setADCompParams.Add("Server", $dc.Name)
    }


    try
    {
        if(-not $Simulated)
        {
            $Error.Clear()
            Set-ADComputer @setADCompParams | Out-Null
        }

        # If a domain controller was given, then the updates were made on a specific DC, so we should be able to verify the change happened.
        if($null -ne $dc)
        {
            LogInfo ("Verifying service principal name was updated for {0}" -f @($adComp.Name)) 3 -NoNewline
            $getADCompParams = @{
                Identity = $adComp.Name
                Properties = @("servicePrincipalName")
                ErrorAction = [System.Management.Automation.ActionPreference]::Stop
                Server = $dc.Name
            }

            $tries = 0
            $verified = $false
            $maxRetries = 3
            while(($tries -lt $maxRetries) -and (-not $verified))
            {
                LogInfo "." -NoNewline
                $tries++
                try
                {
                    $Error.Clear()
                    $adVerifyComp = Get-ADComputer @getADCompParams

                    # This is what the service principal names are after updating the AD computer object...
                    $servicePrincipalNamesStringAfter = (($adVerifyComp.servicePrincipalName | Sort-Object) -join "|").ToLower()

                    $verified = (-not $Simulated) -and ($servicePrincipalNamesStringBefore -eq $servicePrincipalNamesStringAfter)

                    # Don't display an error until we've tried $maxRetries times to verify the settings took.
                    if((-not $verified) -and ($tries -eq $maxRetries))
                    {
                        LogError "Failed"
                        LogWarning ("Service principal names for {0} do not appear to have been updated!" -f @($adComp.Name)) 4
                    }
                }
                catch
                {
                    LogException ("Failed to reacquire AD computer object for: {0}" -f @($adComp.Name)) 4 -NewLine
                    $errStr = $Error[0] | Out-String
                    LogError ("{0}" -f @($errStr))
                }

                if (-not $verified)
                {
                    Start-Sleep -Seconds 5
                } `
                else # NOT (-not $verified)
                {
                    # Nothing.
                }
            }

            # An error/warning would have completed the line if -not $verified
            if($verified)
            {
                LogInfo "Success"
            }
        }
        else
        {
            # Nothing, since we can't guarantee we'll get the AD computer object back from the same DC we updated it on, we'll just have to roll with it.
        }
    }
    catch
    {
        LogException ("Failed to update AD computer object for: {0}" -f @($adComp.Name)) 4
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
        $good2Go = $false
    }

    return $good2Go
}

function MigrateFS1CName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADComputer]
        $newFS1ADComputer,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc
    )

    $good2Go = $true
#    LogInfo "Migrating FS1 alias..." 1
    LogInfo "Migrating file server aliases..." 1
    try
    {
        $Error.Clear()
        $adDomain = Get-ADDomain -ErrorAction Stop
        if($null -ne $adDomain)
        {
            LogInfo ("Acquired AD Domain: {0}" -f @($adDomain.DNSRoot)) 1

            # Find the HOST/FS1 alias service principal name we need to register as a CNAME...
#            $hostSPN = $newFS1ADComputer.servicePrincipalName | Where-Object { ($_ -notmatch $newFS1ADComputer.Name) -and ($_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($adDomain.DNSRoot)))) } | Select-Object -First 1
            $hostSPNs = @($newFS1ADComputer.servicePrincipalName | Where-Object { ($_ -notmatch $newFS1ADComputer.Name) -and ($_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($adDomain.DNSRoot)))) })
            if($hostSPNs.Length -gt 0)
            {
                $a = 0
                while($good2Go -and ($a -lt $hostSPNs.Length))
                {
                    $hostSPN = $hostSPNs[$a]

                    if((-not [String]::IsNullOrEmpty($hostSPN)) -and ($hostSPN -match "^HOST/([^.]+)\."))
                    {
                        $fs1Alias = $Matches[1]
        #                LogInfo ("FS1 Alias: {0}" -f @($fs1Alias)) 1
                        # LogInfo ("Migrating Alias: {0}" -f @($fs1Alias)) 1

        #                LogInfo ("Registering FS1 alias CNAME for {0}.{1}" -f @($newFS1ADComputer.Name, $Global:simulatedMsg)) 2
                        LogInfo ("Registering CNAME {0} alias for {1}.{2}" -f @($fs1Alias, $newFS1ADComputer.Name, $Global:simulatedMsg)) 2
                        $newHostNameAlias = "{0}.{1}" -f @($newFS1ADComputer.Name, $adDomain.DNSRoot)

                        try
                        {
                            $Error.Clear()
                            Add-DnsServerResourceRecordCName -Name $fs1Alias -HostNameAlias $newHostNameAlias -ZoneName $adDomain.DNSRoot -ComputerName $dc.Name -ErrorAction Stop | Out-Null
                        }
                        catch
                        {
                            LogWarning ("Failed to move {0} CNAME record to {1}.  DNS CNAME records not updated." -f @($fs1Alias, $newHostNameAlias)) 3
                            $errStr = $Error[0] | Out-String
                            LogError ("{0}" -f @($errStr))
                        }
                    }
                    else
                    {
                        LogWarning ("Failed to determine FS1 alias from {0} service principal names.  DNS CNAME records not updated." -f @($newFS1ADComputer.Name)) 3
                        $newFS1ADComputer.servicePrincipalName.ForEach({
                            LogWarning ("{0}" -f @($_)) 4
                        })
                    }

                    $a++
                }
            }
            else
            {
                # Nothing, no aliases to migrate...
            }
        }
        else
        {
            LogWarning "Failed to acquire a AD domain data.  DNS CNAME records not updated." 3
        }
    }
    catch
    {
        LogWarning "Failed to acquire a AD domain data.  DNS CNAME records not updated." 3
        $errStr = $Error[0] | Out-String
        LogWarning ("{0}" -f @($errStr))
    }

    return $good2Go
}

function GetADComputer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $computerName,

        [Parameter(Mandatory=$false, Position=1)]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc = $null
    )

    $adComputer = $null

    # Use a hash table for parameters to Get-ADComputer so I can optionally add the -Server parameter if a domain controller was located.
    $getADComputerParams = @{
        Identity = $computerName
        Properties = @("servicePrincipalName")
        ErrorAction = [System.Management.Automation.ActionPreference]::Stop
    }
    if($null -ne $domainController)
    {
        $getADComputerParams.Add("Server", $domainController.Name)
    }

    try
    {
        $Error.Clear()
        $adComputer = Get-ADComputer @getADComputerParams
    }
    catch
    {
        LogException ("Failed to acquire AD computer object for: {0}" -f @($computerName)) 2
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
    }

    return $adComputer
}

function UpdateServicePrincipalNames
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourceCIFSServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DRCIFSServerName
    )

    $good2Go = $true

    LogInfo "Transferring 'FS' service principal names..." 2

    $domainController = $null
    LogInfo "Acquiring domain controller..." 3
    try
    {
        $Error.Clear()
        $domainController = Get-ADDomainController -ErrorAction Stop
        LogInfo ("Got: {0}" -f @($domainController.HostName)) 4
    }
    catch
    {
        LogWarning "Exception: Failed to acquire a domain controller.  AD computer object updates will not be verified." 4
        $errStr = $Error[0] | Out-String
        LogWarning ("{0}" -f @($errStr))
    }

    LogInfo ("Getting computer object for {0} from AD." -f @($SourceCIFSServerName)) 3
    $sourceCIFSServerADComputer = GetADComputer -computerName $SourceCIFSServerName -dc $domainController

    if($null -ne $sourceCIFSServerADComputer)
    {
        LogInfo ("Received: {0}" -f @($sourceCIFSServerADComputer.DistinguishedName)) 4

        LogInfo ("Getting computer object for {0} from AD." -f @($DRCIFSServerName)) 3
        $destCIFSServerADComputer = GetADComputer -computerName $DRCIFSServerName -dc $domainController

        if($null -ne $destCIFSServerADComputer)
        {
            LogInfo ("Received: {0}" -f @($destCIFSServerADComputer.DistinguishedName)) 4

            # Capture the service principal names which need to be removed from the source AD computer object and added to the
            #    destination computer object
            $spnsToMove = @($sourceCIFSServerADComputer.servicePrincipalName | Where-Object { $_ -notmatch $sourceCIFSServerADComputer.Name })
            if($spnsToMove.Length -gt 0)
            {
                LogInfo "Processing the following service principal names:" 3
                $spnsToMove.ForEach({
                    LogInfo ("{0}:" -f @($_)) 4
                    if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogInfo ("-{0}" -f @($sourceCIFSServerADComputer.Name)) 5
                        $sourceCIFSServerADComputer.servicePrincipalName.Remove($_) | Out-Null
                    }

                    if(-not $destCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogInfo ("+{0}" -f @($destCIFSServerADComputer.Name)) 5
                        $destCIFSServerADComputer.servicePrincipalName.Add($_) | Out-Null
                    }

                    if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogError ("Failed to remove {0} from {1} computer object." -f @($_, $sourceCIFSServerADComputer.Name)) 4
                        $good2Go = $false
                    }

                    if(-not $destCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogError ("Failed to add {0} to {1} computer object." -f @($_, $destCIFSServerADComputer.Name)) 4
                        $good2Go = $false
                    }

                    if(-not $good2Go)
                    {
                        break
                    }
                })

                if($good2Go)
                {
                    LogInfo "Pushing the following changes to AD:" 3
                    LogInfo ("{0}:" -f @($sourceCIFSServerADComputer.DistinguishedName)) 4
                    $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                        LogInfo $_ 5
                    })

                    LogInfo ("{0}:" -f @($destCIFSServerADComputer.DistinguishedName)) 4
                    $destCIFSServerADComputer.servicePrincipalName.ForEach({
                        LogInfo $_ 5
                    })

                    # Send the changes back to AD...
                    $good2Go = UpdateServicePrincipalName -adComp $sourceCIFSServerADComputer -dc $domainController
                    if($good2Go)
                    {
                        $good2Go = UpdateServicePrincipalName -adComp $destCIFSServerADComputer -dc $domainController

                        if($good2Go)
                        {
                            if($null -ne $domainController)
                            {
                                $good2Go = MigrateFS1CName -newFS1ADComputer $destCIFSServerADComputer -dc $domainController
                            }
                            else
                            {
                                LogWarning "'FS1' CNAME record(s) not updated.  Please update manually." 3
                            }
                        }
                        else
                        {
                            # Nothing, already reported an error.
                        }
                    }
                    else
                    {
                        # Nothing error was already displayed
                    }
                }
            }
            else
            {
                LogWarning ("{0}'s AD computer object's service principal name list does not appear to have any 'FS1' entries!" -f @($SourceCIFSServerName))
                $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                    LogWarning $_ 1
                })
                LogWarning "Service principal names not updated!"
            }
        }
        else
        {
            LogError ("Failed to acquire AD computer object for: {0}" -f @($DRCIFSServerName)) 2
            $good2Go = $false
        }
    }
    else
    {
        LogException ("Failed to acquire AD computer object for: {0}" -f @($SourceCIFSServerName)) 2
        $good2Go = $false
    }

    return $good2Go
}

function UpdateSnapshotPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $destinationVolume
    )

    $good2Go = $true
    <# Step 4 make sure the snapshot policy is correct on the destination volume.
        #Update snapshot policy on new source
        # NOTE: EDC snapshot policies are pre-pended with clst_  Check this.
        vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
    #>

    LogInfo "Updating snapshot policy..." 2
    # Is there a snapshot policy set on the source volume?
    $sourceVolumeSnapshotPolicyName = $sourceVolume.VolumeSnapshotAttributes.SnapshotPolicy
    if(-not [String]::IsNullOrEmpty($sourceVolumeSnapshotPolicyName))
    {
        # Is the source volume hosted in an EDC?
        if($sourceVolumeSnapshotPolicyName -match "^clst_(.*)$")
        {
            LogInfo "Detected EDC snapshot policy..." 3
            # Yes...remove clst_ from the front of the policy name...
            $sourceVolumeSnapshotPolicyName = $Matches[1]
        }
        else
        {
            # Nothing, leave the policy name as it is.
        }

        # Is the snapshot policy on the destination volume "different" than the policy on the source?
        if($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy -notmatch ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))
        {
            # Yes, different policy...
            LogInfo ("Snapshot policies are different...") 3
            LogInfo ("Source volume snapshot policy: {0}" -f @($sourceVolumeSnapshotPolicyName)) 4
            LogInfo ("Destination volume snapshot policy: {0}" -f @($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 4

            LogInfo "Getting snapshot policies that match the source from the destination cluster" 3
            # Get any snapshot policy from the destination cluster with a name that matches the source volume's snapshot policy name...
            $destinationSnapshotPolicies = @(Get-NcSnapshotPolicy -Controller $destinationVolume.NcController -ErrorAction Stop | Where-Object { $_.Policy -match $sourceVolumeSnapshotPolicyName })

            # Did we find a single match?
            if($destinationSnapshotPolicies.Length -eq 1)
            {
                # Yes, use it for the snapshot policy on the destination volume.
                $destinationSnapshotPolicyName = $destinationSnapshotPolicies[0].Policy
                LogInfo ("Using destination snapshot policy: {0}" -f @($destinationSnapshotPolicyName)) 4

                # Set up a query object to ensure we update the correct destination volume.
                $queryObj = Get-NCVol -Controller $destinationVolume.NcController -Template
                Initialize-NcObjectProperty -Object $queryObj -Name VolumeIdAttributes
                $queryObj.VolumeIdAttributes.Uuid = $destinationVolume.VolumeIdAttributes.Uuid

                # Set up an update query object to set the snapshot policy
                $updateObj = Get-NCVol -Controller $destinationVolume.NcController -Template
                Initialize-NcObjectProperty -Object $updateObj -Name VolumeSnapshotAttributes
                $updateObj.VolumeSnapshotAttributes.SnapshotPolicy = $destinationSnapshotPolicyName

                try
                {
                    LogInfo ("Sending volume update command to update snapshot policy...") 3
                    $Error.Clear()
                    $result = Update-NcVol -Controller $destinationVolume.NcController -Query $queryObj -Attributes $updateObj -ErrorAction Stop
                    if($null -ne $result)
                    {
                        if($result.SuccessList.Length -gt 0)
                        {
                            LogInfo "Updated snapshot policy on:" 3
                            $result.SuccessList.Foreach({
                                LogInfo ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                            })
                        }
                        else
                        {
                            # Shouldn't have to do anything here... the next block should cover it...BUT... just to make sure, we'll set $good2Go = $false since there weren't any successes.
                            $good2Go = $false
                        }

                        if($result.FailureList.Length -gt 0)
                        {
                            LogError "Failed to update snapshot policy on:" 3
                            $result.FailureList.Foreach({
                                LogError ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                            })
                            $good2Go = $false
                        }
                        else
                        {
                            # Nothing... all might be good depending on the SuccessList.
                        }
                    }
                    else
                    {
                        LogWarning "No result object returned when updating snaphot policy." 3
                    }
                }
                catch
                {
                    LogException ("Failed to set snapshot policy to {0} on {0}:{1}:{2}." -f @($destinationSnapshotPolicyName, $snapmirrorDestinationVolume.NcController.Name, $snapmirrorDestinationVolume.VServer, $snapmirrorDestinationVolume.Name)) 3
                    $errStr = $Error[0] | Out-String
                    LogError ("{0}" -f @($errStr))
                    $good2Go = $false
                }
            }
            elseif ($destinationSnapshotPolicies.Length -gt 1)
            {
                LogWarning ("{0} snapshot policies found which match: {1}." -f @($destinationSnapshotPolicies.Length, ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))) 3
                $destinationSnapshotPolicies.ForEach({
                    LogWarning ("{0}" -f @($_)) 4
                })
            }
            else  # there was no matching snapshot policy found on the destination
            {
                LogError ("No snapshot policies found which match: {0} on {1}." -f @(("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $snapmirrorDestinationVolume.NcController.Name)) 3
            }
        }
        else
        {
            LogInfo ("Source volume snapshot policy: {0} seems to match {1}.  No changes needed." -f @($sourceVolumeSnapshotPolicyName, $snapmirrorDestinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 3
        }
    }
    else
    {
        LogWarning ("No snapshot policy found on source volume: {0}:{1}:{2}" -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) 2
        LogWarning "Ensure you check snapshot policies." 2
    }

    return $good2Go
}

function SetVolumeEfficiencySettings
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume
    )

    $good2Go = $true
    try
    {
        <# Step 5a: Update volume efficiency settings on the destination volume.
            #Enable/update storage efficiency on new source
            --> vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
        #>

        LogInfo ("Checking status of storage efficiency for: {0}:{1}:{2}..." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name)) 2
        $Error.Clear()
        $volSIS = Get-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop
        if($null -ne $volSIS)
        {
            if($volSIS.State -ne "enabled")
            {
                LogInfo ("Storage efficiency not enabled.  Enabling it.") 3
                try
                {
                    $Error.Clear()
                    # Not enabled, so let's enable it...
                    $result = Enable-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop

                    try
                    {
                        LogInfo "Verifying storage efficiency was enabled..." 3 -NoNewline
                        $Error.Clear()
                        $volSIS = Get-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop
                        if($volSIS.State -eq "enabled")
                        {
                            LogInfo "Success"
                        }
                        else
                        {
                            LogError "Failed"
                            LogWarning "Manually update storage efficiencies as required." 3
                        }
                    }
                    catch
                    {
                        LogException ("Failed to verify if storage efficiency was enabled on: {0}:{1}:{2}.  Please check manually." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name)) -NewLine
                        $errStr = $Error[0] | Out-String
                        LogError ("{0}" -f @($errStr))
                    }
                }
                catch
                {
                    LogException ("Failed to enable storage efficiency on: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
                    $errStr = $Error[0] | Out-String
                    LogError ("{0}" -f @($errStr))
                    $good2Go = $false
                }
            }
            else
            {
                # Nothing, storage efficiency is already enabled for the volume.
            }

            # Need to recheck $volSIS.State since we may have enabled it above.
            if($volSIS.State -eq "enabled")
            {
                try
                {
                    <# Step 5b: Update volume efficiency settings on the destination volume.
                        #Enable/update storage efficiency on new source
                            vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                        --> vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                    #>
                    $Error.Clear()
                    $result = Set-NcSis -Name $volume.Name -Compression $true -Controller $volume.NcController -InlineCompression $true -Policy "default" -VserverContext $volume.VServer -ErrorAction Stop
                }
                catch
                {
                    LogException ("Failed to set storage efficiency settings on: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
                    $errStr = $Error[0] | Out-String
                    LogError ("{0}" -f @($errStr))
                    $good2Go = $false
                }
            }
            else
            {
                # Nothing, would have already alerted user.
            }
        }
        else
        {
            LogError ("Failed to get storage efficiency setting for: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
            $good2Go = $false
        }
    }
    catch
    {
        LogException ("Failed to get storage efficiency setting for: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
        $good2Go = $false
    }
}

$defaultSnapmirrorPolicyName = "smvp_180_nightly_01"

$Global:simulatedMsg = " (simulated)"
if(-not $Simulated)
{
    $Global:simulatedMsg = ""
}
else
{
    LogInfo "No changes will be made.  Running in simulation mode."
}

LogInfo "Connecting to all ONTAP clusters..."

ConnectTo cDot
# Will need to change this to work for anyone...

LogInfo "Connected to:"
$cDot.Values.ForEach({
    LogInfo $_.Name 1
})

# Keep track of run status...
$good2Go = @($cDot.Values).Length -gt 0   #If this changes to $false, the script should terminate...
if($good2Go)
{
    # Initialize some variables
    $destinationCIFSServer = $null
    $sourceCIFSServer = $null

    $svmPeersOk = $true
    try
    {
        LogInfo "Checking SVM peering..."
        $Error.Clear()
        $allSnapmirrors = @(Get-NCSnapmirror -Controller @($cDot.Values) -ErrorAction Stop)

        if($allSnapmirrors.Length -gt 0)
        {
            try
            {
                $Error.Clear()
                $svmPeers = @(Get-NcVserverPeer -Controller @($cDot.Values) -ErrorAction Stop)

                if($svmPeers.Length -gt 0)
                {
                    $a = 0
                    while($a -lt $allSnapmirrors.Length)
                    {
                        # $reversePeer = $svmPeers | Where-Object { ($_.PeerVserverUuid -eq $allSnapmirrors[$a].SourceVserverUuid) -and ($_.VserverUuid -eq $allSnapmirrors[$a].DestinationVserverUuid) -and ($_.Applications -contains "snapmirror") }
                        $reversePeer = $svmPeers | Where-Object { ($_.PeerVserverUuid -eq $allSnapmirrors[$a].DestinationVserverUuid) -and ($_.VserverUuid -eq $allSnapmirrors[$a].SourceVserverUuid) -and ($_.Applications -contains "snapmirror") }
                        if($null -eq $reversePeer)
                        {
                            $svmPeersOk = $false
                            LogError ("Missing reverse SVM peering from {0} and {1}" -f @($allSnapmirrors[$a].DestinationVserver, $allSnapmirrors[$a].SourceVserver)) 0
                            # Write-Host ("Missing reverse SVM peering from {0} and {1}" -f @($allSnapmirrors[$a].DestinationVserver, $allSnapmirrors[$a].SourceVserver))
                        }
                        $a++
                    }
                }
                else
                {
                    $svmPeersOk = $false
                    LogError ("Even though {0} snapmirrors were retrieved, I was unable to get SVM peer relationships from any ONTAP cluster." -f @($allSnapmirrors.Length))
                }
            }
            catch
            {
                $svmPeersOk = $false
                LogError "Unable to retrieve all SVM peer relationships."
                $errStr = $Error[0] | Out-String
                LogError ("{0}" -f @($errStr))
            }
        }
        else
        {
            $svmPeersOk = $false
            LogWarning "No snapmirrors returned from any connected ONTAP clusters."
        }
    }
    catch
    {
        $svmPeersOk = $false
        LogError "Unable to retrieve all snapmirrors."
        $errStr = $Error[0] | Out-String
        LogError ("{0}" -f @($errStr))
    }

    if($svmPeersOk)
    {
        LogInfo "CONGRATULATIONS CAPT'N DIPSHIT!  All SVM reverse peerings appear to be in-place!!" 1

        # Get all volumes hosted on all ONTAP clusters.  Seems overkill, but this way, we have all the volumes for later use.
        LogInfo "Retrieving all NON-SNAPLOCK volumes from all clusters..."
        try
        {
            $Error.Clear()
            # Create a query template to retrieve all volumes that are "non_snaplock"
            $nonSnaplockVolumesQuery = Get-NCVol -Controller @($cDot.Values)[0] -Template
            Initialize-NcObjectProperty -Object $nonSnaplockVolumesQuery -Name VolumeSnaplockAttributes
            $nonSnaplockVolumesQuery.VolumeSnaplockAttributes.SnaplockType = "non_snaplock"

            # Additionally, filter out JP_ and ROOT_ volumes
            $allNonSnaplockVolumes = Get-NCVol -Controller @($cDot.Values) -Query $nonSnaplockVolumesQuery -ErrorAction Stop | Where-Object { $_.Name -notmatch "^(JP)|(ROOT)_" }

            # Old: $allONTAPVolumes = @(Get-NCVol -Controller @($cDot.Values) -ErrorAction Stop)

            # Reusing an old variable, but $allONTAPVolumes now excludes all SNAPLOCK volumes.
            $allONTAPVolumes = $allNonSnaplockVolumes
            if($allONTAPVolumes.Length -gt 0)
            {
                # Capture all volumes hosted on $SourceVServerName...
                LogInfo ("{0} volumes found." -f @($allONTAPVolumes.Length)) 1

                $sourceVolumes = @($allONTAPVolumes | Where-Object { $_.VServer -eq $SourceVServerName })
                if($sourceVolumes.Length -gt 0)
                {
                    LogInfo ("{0} source volumes found." -f @($sourceVolumes.Length)) 1

                    try
                    {
                        $Error.Clear()
                        # Get all snapmirrors hosted on all ONTAP clusters where the source VServer = $SourceVServerName
                        LogInfo ("Retrieving all ONTAP snapmirrors from all clusters where source VServer = {0}..." -f @($SourceVServerName))
                        $allSourceVServerSnapmirrors = @($allSnapmirrors | Where-Object { $_.SourceVserver -eq $SourceVServerName })

                        if($allSourceVServerSnapmirrors.Length -gt 0)
                        {
                            LogInfo ("`t{0} snapmirrors found." -f @($allSourceVServerSnapmirrors.Length)) 1

                            $snapmirrorsToDRVServer = @($allSourceVServerSnapmirrors | Where-Object { $_.DestinationVserver -eq $DRVServerName })
                            if($snapmirrorsToDRVServer.Length -gt 0)
                            {
                                # Get all the source volumes which have snapmirror destinations.
                                $sourceVolumesWithSnapmirrorDestinations = @($sourceVolumes | Where-Object { @($allSourceVServerSnapmirrors | Select-Object -Unique -ExpandProperty SourceVolume) -contains $_.Name } | Sort-Object @{E = { $_.NCController.Name }; Descending = $true }, VServer, Name)
                                if($sourceVolumesWithSnapmirrorDestinations.Length -gt 0)
                                {
                                    LogInfo ("{0} source volumes have snapmirror destinations." -f @($sourceVolumesWithSnapmirrorDestinations.Length)) 1
                                    $sourceVolumesWithSnapmirrorDestinations.ForEach({
                                        LogInfo ("{0}:{1}:{2}" -f @($_.NCController.Name, $_.VServer, $_.Name)) 2
                                    })

                                    # Get any CIFS shares hosted on $SourceVServerName
                                    $sourceCIFSSharesWithSnapmirrorDestinations = @(Get-NcCifsShare -Controller $sourceVolumesWithSnapmirrorDestinations[0].NCController -VserverContext $sourceVolumesWithSnapmirrorDestinations[0].Vserver -ErrorAction Stop | Where-Object {  @($sourceVolumesWithSnapmirrorDestinations | Select-Object -Unique -ExpandProperty Name) -contains $_.Volume  })
                                    $sourceHasCIFSShares = $sourceCIFSSharesWithSnapmirrorDestinations.Length -gt 0
                                    if($sourceHasCIFSShares)
                                    {
                                        LogInfo ("{0} CIFS shares were located on these volumes." -f @($sourceCIFSSharesWithSnapmirrorDestinations.Length)) 1
                                        $sourceCIFSSharesWithSnapmirrorDestinations.Foreach({
                                            LogInfo ("{0} -> {1}" -f @($_.ShareName, $_.Volume)) 2
                                        })

                                        # Get the CIFS server for the source VServer
                                        try
                                        {
                                            $Error.Clear()
                                            LogInfo ("Getting CIFS server on {0}:{1}." -f @($sourceCIFSSharesWithSnapmirrorDestinations[0].NcController, $sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                                            $sourceCIFSServer = Get-NcCifsServer -Controller $sourceCIFSSharesWithSnapmirrorDestinations[0].NcController -VserverContext $sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver -ErrorAction Stop

                                            if($null -ne $sourceCIFSServer)
                                            {
                                                # Stop the CIFS Server

                                                # If the source CIFS server is not down, make it down...
                                                if($sourceCIFSServer.AdministrativeStatus -ne "down")
                                                {
                                                    <# Step 1: Stop CIFS services on the source VServer.  This is to ensure the snapmirror update process send all the latest changes to the destination volume.
                                                        #Stop SMB service at current source
                                                        vserver cifs stop -vserver LAB-SMB02
                                                    #>
                                                    $good2Go = ShutdownCIFSServer -cifsServer $sourceCIFSServer
                                                }
                                                else
                                                {
                                                    # Nothing, the CIFS server is already shutdown.
                                                }
                                            }
                                            else
                                            {
                                                LogError ("Failed to retrieve CIFS server for: {0}:{1}." -f @($sourceCIFSSharesWithSnapmirrorDestinations[0].NcController.Name, $sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                                                $good2Go = $false
                                            }
                                        }
                                        catch
                                        {
                                            LogException ("Failed to retrieve CIFS server for: {0}:{1}." -f @($sourceCIFSSharesWithSnapmirrorDestinations[0].NcController.Name, $sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                                            $errStr = $Error[0] | Out-String
                                            LogError ("{0}" -f @($errStr))
                                            $good2Go = $false
                                        }
                                    }
                                    else
                                    {
                                        # Nothing, no CIFS shares to worry about...
                                    }

                                    # On to the snapmirrors...
                                    $srcVolIdx = 0
                                    while($good2Go -and ($srcVolIdx -lt $sourceVolumesWithSnapmirrorDestinations.Length))
                                    {

                                        <#
                                            For each source volume, create a data structure to track the new snapmirror relationships that need to be created after the old snapmirrors are processed.

                                            .SourceVolume  = The new source volume.  This will be the volume hosted on $DRVServerName
                                            .Relationships = A list of destination volumes and policies to use.  At a minimum will include the original volume hosted on $SourceVServerName
                                                [0].DestinationVolume  = The snapmirror destination volume.
                                                [0].Policy             = The policy to use when creating the new snapmirrors.  Since the policy must reside at the destination, always keep the destination volume and policy
                                                                            together.  EVEN when reversing the snapmirror between the original source and original destination (which technically changes the destination)
                                                                            -- use the same policy as the original relationship
                                        #>

                                        $newSnapmirrors = "" | Select-Object SourceVolume, Relationships
                                        $newSnapmirrors.SourceVolume = $null
                                        $newSnapmirrors.Relationships = [System.Collections.Generic.List[System.Object]]::new()


                                        # Reset the new snapmirror source volume...
                                        $newSnapmirrorSourceVolume = $null

                                        $sourceVolume = $sourceVolumesWithSnapmirrorDestinations[$srcVolIdx]
                                        LogInfo ("Processing source volume: {0}:{1}:{2}..." -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) -NewLine

                                        # Capture all the volumes which will be snapmirror destinations for the new source volume (The volume on $DRVServerName where $sourceVolume is snapmirrored to).
                                        $newSnapmirrorDestinationVolumes = [System.Collections.Generic.List[System.Object]]::new()

                                        # $sourceVolume will end up being a snapmirror destination to the DR volume we are bringing online.
                                        LogInfo "Added to new snapmirror destination volume list." 1
                                        $newSnapmirrorDestinationVolumes.Add($sourceVolume)

                                        if($sourceHasCIFSShares)
                                        {
                                            LogInfo "CIFS Shares:" 1
                                            $sourceCIFSSharesWithSnapmirrorDestinations | Where-Object { ($_.VServer -eq $sourceVolume.Vserver) -and ($_.Volume -eq $sourceVolume.Name) } | ForEach-Object {
                                                LogInfo ("\\{0}\{1}" -f @($_.CifsServer, $_.ShareName)) 2
                                            }
                                        }

                                        # $allSourceVServerSnapmirrors is populated with data from the perspective of the DESTINATION VSERVER.
                                        #     Therefore, ($_.VServer -notmatch "SNAPLOCK") will be (not)matching the snapmirror destination VServer’s name to "SNAPLOCK", not the source VServer’s name.
                                        #     Therefore, $sourceVolumeSnapmirrors will never contain a snapmirror destination hosted on a SNAPLOCK VServer
                                        # No snapmirror destination hosted on a SNAPLOCK VServer will be processed... no updates, no breakage, nothing...
                                        $sourceVolumeSnapmirrors = @($allSourceVServerSnapmirrors | Where-Object { ($_.VServer -notmatch "SNAPLOCK") -and ($_.SourcevServer -eq $sourceVolume.VServer) -and ($_.SourceVolume -eq $sourceVolume.Name)})
                                        $snapmirrorIdx = 0
                                        while($good2Go -and ($snapmirrorIdx -lt $sourceVolumeSnapmirrors.Length))
                                        {
                                            $snapmirror = $sourceVolumeSnapmirrors[$snapmirrorIdx]
                                            LogInfo ("Snapmirror destination: {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume)) 2
                                            $snapmirrorDestinationVolume = $allONTAPVolumes | Where-Object { ($_.NCController.Name -eq $snapmirror.NcController.Name) -and ($_.VServer -eq $snapmirror.DestinationvServer) -and ($_.Name -eq $snapmirror.DestinationVolume)}
                                            if($null -ne $snapmirrorDestinationVolume)
                                            {
                                                # Since the original list of volumes did not include any SNAPLOCK volumes, we no longer have to worry about $snapmirrorDestinationVolume being a SNAPLOCK volume.

                                                # If this snapmirror destination volume is hosted on the requested DR VServer, then capture it as the new snapmirror source volume.
                                                if($snapmirrorDestinationVolume.Vserver -eq $DRVServerName)
                                                {
                                                    LogInfo "Will become the new snapmirror source volume." 2
                                                    $newSnapmirrorSourceVolume = $snapmirrorDestinationVolume
                                                    $newSnapmirrors.SourceVolume = $snapmirrorDestinationVolume

                                                    # Add a new relationship to $newSnapmirrors for the original source volume --- using the snapmirror policy currently assigned to the orginial destination volume
                                                    $newRelationship = "" | Select-Object DestinationVolume, Policy
                                                    $newRelationship.DestinationVolume = $sourceVolume
                                                    $newRelationship.Policy = $snapmirror.Policy
                                                    $newSnapmirrors.Relationships.Add($newRelationship)

                                                    # Ok, we have the destination volume, so let's collect the CIFS server information about it.
                                                    LogInfo ("Collecting CIFS server details from: {0}:{1}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver)) 2
                                                    try
                                                    {
                                                        $Error.Clear()
                                                        $destinationCIFSServer = Get-NcCifsServer -Controller $snapmirror.NcController -VserverContext $snapmirror.Vserver -ErrorAction Stop
                                                        if($null -ne $destinationCIFSServer)
                                                        {
                                                            LogInfo ("Found: {0}" -f @($destinationCIFSServer.CifsServer)) 3

                                                            # It's not critical if the destination CIFS server is not started.  There will be a warning if it was not started.
                                                            StartCIFSServer -cifsServer $destinationCIFSServer
                                                        }
                                                        else
                                                        {
                                                            LogWarning ("Failed to retrieve CIFS server from {0}:{1}." -f @($snapmirror.NcController.Name, $snapmirror.Vserver)) 3
                                                            LogWarning "SPNs and CNAME records will need to be manually updated." 3
                                                        }
                                                    }
                                                    catch
                                                    {
                                                        LogWarning ("Exception: Failed to retrieve CIFS server from {0}:{1}." -f @($snapmirror.NcController.Name, $snapmirror.Vserver)) 3
                                                        LogWarning "SPNs and CNAME records will need to be manually updated." 3
                                                        $errStr = $Error[0] | Out-String
                                                        LogWarning ("{0}" -f @($errStr))
                                                    }
                                                }
                                                else
                                                {
                                                    # Add the snapmirror destination volume to the list of new snapmirror destination volumes.... but only add it once.
                                                    #if($newSnapmirrorDestinationVolumes.IndexOf($snapmirrorDestinationVolume) -eq -1)

                                                    # If we haven't already created a new relationship for this snapmirror destination, then create it using the snapmirror policy assigned to it.
                                                    if($newSnapmirrors.Relationships.IndexOf($snapmirrorDestinationVolume) -eq -1)
                                                    {
                                                        LogInfo "Added to new snapmirror destination volume list." 2
                                                        $newSnapmirrorDestinationVolumes.Add($snapmirrorDestinationVolume)

                                                        $newRelationship = "" | Select-Object DestinationVolume, Policy
                                                        $newRelationship.DestinationVolume = $snapmirrorDestinationVolume
                                                        $newRelationship.Policy = $snapmirror.Policy
                                                        $newSnapmirrors.Relationships.Add($newRelationship)
                                                    }
                                                    else
                                                    {
                                                        # Nothing, only adding the volume once.
                                                    }
                                                }

                                                <# Step 2: Update the snapmirrors...
                                                    #Update applicable snapmirrors
                                                    snapmirror update -destination-path LABDR-SMB02:*
                                                #>
                                                $good2Go = UpdateSnapmirror -snapmirror $snapmirror

                                                if($good2Go)
                                                {
                                                    # Step 3: Now break the snapmirror...
                                                    <#
                                                        #Break existing relationships
                                                        snapmirror break -destination-path LABDR-SMB02:*
                                                    #>
                                                    $good2Go = BreakSnapmirror -snapmirror $snapmirror

                                                    if($good2Go)
                                                    {
                                                        <# Step 4 make sure the snapshot policy is correct on the destination volume.
                                                            #Update snapshot policy on new source
                                                            # NOTE: EDC snapshot policies are pre-pended with clst_  Check this.
                                                            vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                                        #>
                                                        $good2Go = UpdateSnapshotPolicy -sourceVolume $sourceVolume -destinationVolume $snapmirrorDestinationVolume

                                                        if($good2Go)
                                                        {
                                                            <# Step 5: Update volume efficiency settings on the destination volume.
                                                                #Enable/update storage efficiency on new source
                                                                vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                                                vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                                                            #>

                                                            # No return value here, it's not vital if we fail to set storage efficiency.  A visual warning is enough.
                                                            SetVolumeEfficiencySettings -volume $snapmirrorDestinationVolume

                                                            if($good2Go)
                                                            {
                                                                # Step 7a: Now delete the snapmirror relationship...
                                                                <#
                                                                    #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                                                    --> snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                                                        snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                                                #>
                                                                $good2Go = DeleteSnapmirror -snapmirror $snapmirror

                                                                if($good2Go)
                                                                {
                                                                    # Step 7b: Now release the snapmirror relationship...
                                                                    <#
                                                                        #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                                                            snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                                                        --> snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                                                    #>
                                                                    $good2Go = ReleaseSnapmirror -sourceVolume $sourceVolume -snapmirror $snapmirror
                                                                }
                                                                else
                                                                {
                                                                    # Nothing, an error would have been displayed already.
                                                                }
                                                            }
                                                            else
                                                            {
                                                                # Nothing, an error would have been displayed already.
                                                            }
                                                        }
                                                        else
                                                        {
                                                            # Nothing, an error would have been displayed already.
                                                        }
                                                    }
                                                    else
                                                    {
                                                        # Nothing, an error should have already been displayed
                                                    }
                                                }
                                                else
                                                {
                                                    # Nothing, an error would have been displayed already.
                                                }
                                            }
                                            else
                                            {
                                                LogError ("Failed to retrieve volume object for {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume)) 1
                                                $good2Go = $false
                                            }
                                            $snapmirrorIdx++
                                        }

                                        <#
                                            Now that:
                                                all snapmirrors are updated/broken/deleted/released
                                                destination snapshot policies are updated
                                                destination volume efficiencies are set

                                            Recreate reverse snapmirror relationships
                                        #>
                                        if($good2Go)
                                        {
                                            # Once all the snapmirrors have been sync'd and broken-off, time to rebuild them, but with a new source...
                                            if($null -ne $newSnapmirrors.SourceVolume)
                                            #if($null -ne $newSnapmirrorSourceVolume)
                                            {
                                                $snapmirrorIdx = 0
                                                while($good2Go -and ($snapmirrorIdx -lt $newSnapmirrors.Relationships.Count))
                                                #while($good2Go -and ($snapmirrorIdx -lt $newSnapmirrorDestinationVolumes.Count))
                                                {
                                                    if($null -ne $newSnapmirrors.Relationships[$snapmirrorIdx].DestinationVolume)
                                                    {
                                                        if([String]::IsNullOrEmpty($newSnapmirrors.Relationships[$snapmirrorIdx].Policy))
                                                        {
                                                            LogWarning ("Missing snapmirror policy between {0} ==> {1}.  Defaulting to {2}." -f @((VolumeToString $newSnapmirrors.SourceVolume), (VolumeToString $newSnapmirrors.Relationships[$snapmirrorIdx].DestinationVolume), $defaultSnapmirrorPolicyName)) 1
                                                        }
                                                        else
                                                        {
                                                            # Nothing, already have the policy
                                                        }

                                                        # Step 8a: Now create the new snapmirror...
                                                        <#
                                                            #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                                            --> snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                                            --> snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                                        #>

                                                        #$good2Go = CreateSnapmirror -srcVolume $newSnapmirrorSourceVolume -dstVolume $newSnapmirrorDestinationVolumes[$snapmirrorIdx] -snapmirrorPolicyName "INSERT NAME HERE" # $snapmirror.Policy
                                                        $good2Go = CreateSnapmirror -srcVolume $newSnapmirrors.SourceVolume -dstVolume $newSnapmirrors.Relationships[$snapmirrorIdx].DestinationVolume -snapmirrorPolicyName $newSnapmirrors.Relationships[$snapmirrorIdx].Policy

                                                        if($good2Go)
                                                        {
                                                            # Step 8b: Finally, resync the new new snapmirror...
                                                            <#
                                                                #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                                                    snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                                                --> snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                                            #>
                                                            #$good2Go = ResyncSnapmirror -srcVolume $newSnapmirrorSourceVolume -dstVolume $newSnapmirrorDestinationVolumes[$snapmirrorIdx]
                                                            $good2Go = ResyncSnapmirror -srcVolume $newSnapmirrors.SourceVolume -dstVolume $newSnapmirrors.Relationships[$snapmirrorIdx].DestinationVolume
                                                        }
                                                    }
                                                    else
                                                    {
                                                        LogWarning "Missing destination volume when recreating snapmirrors.  Snapmirror not created." 1
                                                    }

                                                    $snapmirrorIdx++
                                                }
                                            }
                                            else
                                            {
                                                LogError "Failed to identify a new snapmirror source volume." 1
                                                $good2Go = $false
                                            }
                                        }
                                        else
                                        {
                                            # Nothing, an error would have been displayed already.
                                        }

                                        $srcVolIdx++
                                    }

                                    if($good2Go)
                                    {
                                        if(($null -ne $sourceCIFSServer) -and ($null -ne $destinationCIFSServer))
                                        {
                                            <# Step 6: Update service principal names and FS1 aliases...
                                                #Migrate SPN's to new source AD object
                                                #Update FS1 CNAME record in DNS
                                            #>
                                            $good2Go = UpdateServicePrincipalNames -SourceCIFSServerName $sourceCIFSServer.CifsServer -DRCIFSServerName $destinationCIFSServer.CifsServer
                                        }
                                        else
                                        {
                                            # Nothing, warnings were already displayed
                                        }
                                    }
                                    else
                                    {
                                        # Nothing
                                    }
                                }
                                else
                                {
                                    LogWarning "No source volumes have snapmirror destinations." 1
                                }
                            }
                            else
                            {
                                LogWarning ("No snapmirrors detected between {0} and {1}." -f ($SourceVServerName, $DRVServerName)) 1
                            }
                        }
                        else
                        {
                            LogError "No snapmirrors where retrieve from any ONTAP clusters." 1
                            $good2Go = $false
                        }
                    }
                    catch
                    {
                        LogException "Failed to retrieve all snapmirrors from all ONTAP clusters." 1
                        $errStr = $Error[0] | Out-String
                        LogError ("{0}" -f @($errStr))
                        $good2Go = $false
                    }
                }
                else
                {
                    LogWarning ("No volumes found where VServer = {0}." -f @($SourceVServerName)) 1
                }
            }
            else
            {
                LogError "No volumes retrieved from any ONTAP cluster." 1
                $good2Go = $false
            }
        }
        catch
        {
            LogException "Failed to retrieve all volumes from all ONTAP clusters." 1
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr))
            $good2Go = $false
        }
    }
    else
    {
        LogError "Please fix all reverse SVM peerings and retry!" 1
    }
}
else
{
    LogError "Failed to connect to any ONTAP clusters."
}

if($null -ne $Script:sbMessageLog)
{
    $Script:sbMessageLog.ToString() | Set-Clipboard
    Write-Host "`r`n`r`nScript output copied to clipboard!!`r`n`r`n"
}
