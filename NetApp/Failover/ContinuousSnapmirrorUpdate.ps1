[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)]
    [String[]]
    $SourceVServerNames,

    [Parameter(Mandatory=$false,Position=1)]
    [Int32]
    $SecondsToPause = 60,

    [Parameter(Mandatory=$false,Position=2)]
    [Switch]
    $Simulated = $false
)

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
    Write-Host -NoNewline -ForegroundColor Green ("`t`tWaiting for snapmirror to be {0}/{1} (CTRL-C to abort script)." -f @($status2WaitFor, $mirrorState2WaitFor, $simulatedMsg))
    do
    {
        try
        {
            # Refresh the snapmirror info to see if its idle...
            $snapmirror = Get-NCSnapmirror -Controller $snapmirror.NcController -DestinationVserver $snapmirror.Vserver -DestinationVolume $snapmirror.DestinationVolume -ErrorAction Stop
            if($null -ne $snapmirror)
            {
                if((-not $Simulated) -and (($snapmirror.Status -ne $status2WaitFor) -or ($snapmirror.MirrorState -ne $mirrorState2WaitFor)))
                {
                    Write-Host -NoNewline -ForegroundColor Green "."
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
                Write-Host -ForegroundColor Red ("`r`n{0}" -f @($FailureMsg))
                $good2Go = $false
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red ("`r`nException: {0}" -f @($FailureMsg))
            $good2Go = $false
        }
    } until($Simulated -or (-not $good2Go) -or (($snapmirror.Status -eq $status2WaitFor) -and ($snapmirror.MirrorState -eq $mirrorState2WaitFor)))
    Write-Host ""

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
    Write-Host -ForegroundColor Green ("`t`tRefresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}..." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
    try
    {
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
                    Write-Host -ForegroundColor Red ("`t`t`tSnapmirror between {0}:{1} and {2}:{3}:{4} has status {5}.  Expected: {6}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $snapmirror.MirrorState, $desiredStatus))
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("`t`t`tSnapmirror between {0}:{1} and {2}:{3}:{4} has mirror state {5}.  Expected: {6}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $snapmirror.MirrorState, $desiredMirrorState))
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("`t`t`tFailed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}.  (`$null returned)" -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
            $good2Go = $false
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("`t`tException: Failed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
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
                Write-Host -ForegroundColor Green ("`t`tUpdating snapmirror {0}:{1}:{2}.{3}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $simulatedMsg))
                if(-not $Simulated)
                {
                    $null = Invoke-NcSnapmirrorUpdate -Controller $snapmirror.NcController -DestinationVserver $snapmirror.Vserver -DestinationVolume $snapmirror.DestinationVolume -ErrorAction Stop
                }

                # Now, wait until the snapmirror is idle...
                $good2Go = WaitForSnapmirrorAction -snapmirror $snapmirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg ("`r`nFailed to retrieve snapmirror status after invoking an update between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Exception: Failed to update snapmirror between {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
                $good2Go = $false
            }
        }
        else
        {
            Write-Host -ForegroundColor Red ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
        }
    }
    else
    {
        # Nothing, an error would have already been displayed
    }

    return $good2Go
}

$periods = @("day(s)","hour(s)","minute(s)","second(s)")
$pauseDuration = [TimeSpan]::new(0,0,$SecondsToPause)
$durationString = ""
$periodValues = @($pauseDuration.ToString("d\:hh\:mm\:ss") -split ":")
$a = 0
while($a -lt $periodValues.Length)
{
    $pv = $periodValues[$a].TrimStart("0")
    if(-not [String]::IsNullOrEmpty($pv))
    {
        $durationString = ("{0}, {1} {2}" -f @($durationString, $pv, $periods[$a])).TrimStart(@(' ',','))
    }
    $a++
}

Write-Host -ForegroundColor Green ("Connecting to all ONTAP clusters...")

ConnectTo cDot
# Will need to change this to work for anyone...

$simulatedMsg = " (simulated)"
if(-not $Simulated)
{
    $simulatedMsg = ""
}

# Keep track of run status...
$good2Go = $true   #If this changes to $false, the script should terminate...

Write-Host -ForegroundColor Green ("Keeping all snapmirror destinations up to date from volumes (with snapmirror destinations) hosted on vServer: {0}...[CTRL-C] to break..." -f @(($SourceVServerNames -join ", ")))

do
{
    # Get all volumes hosted on all ONTAP clusters.  Seems overkill, but this way, we have all the volumes for later use.
    Write-Host -ForegroundColor Green "Retrieving all ONTAP volumes from all clusters..."
    try
    {
        $allONTAPVolumes = @(Get-NCVol -Controller @($cDot.Values) -ErrorAction Stop)
        if($allONTAPVolumes.Length -gt 0)
        {
            # Capture all volumes hosted any vserver in $SourceVServerNames...
            Write-Host -ForegroundColor Green ("`t{0} volumes found." -f @($allONTAPVolumes.Length))
            $sourceVolumes = @($allONTAPVolumes | Where-Object { $_.VServer -in $SourceVServerNames })
            if($sourceVolumes.Length -gt 0)
            {
                Write-Host -ForegroundColor Green ("`t{0} volumes found." -f @($sourceVolumes.Length))
                $sourceVolumes | ForEach-Object {
                    Write-Host -ForegroundColor Green ("`t`t{0}:{1}:{2}" -f @($_.NCController.Name, $_.VServer, $_.Name))
                }

                try
                {
                    # Get all snapmirrors hosted on all ONTAP clusters where the source VServer = $SourceVServerName
                    Write-Host -ForegroundColor Green ("Retrieving all ONTAP snapmirrors from all clusters where source VServer in {0}..." -f @(($SourceVServerNames -join ", ")))
                    $allSourceVServerSnapmirrors = @(Get-NcSnapmirror -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { $_.SourceVserver -in $SourceVServerNames })
                    if($allSourceVServerSnapmirrors.Length -gt 0)
                    {
                        Write-Host -ForegroundColor Green ("`t{0} snapmirrors found." -f @($allSourceVServerSnapmirrors.Length))

                        # Get all the source volumes which have snapmirror destinations.
                        $sourceVolumesWithSnapmirrorDestinations = @($sourceVolumes | Where-Object { @($allSourceVServerSnapmirrors | Select-Object -Unique -ExpandProperty SourceVolume) -contains $_.Name })
                        if($sourceVolumesWithSnapmirrorDestinations.Length -gt 0)
                        {
                            Write-Host -ForegroundColor Green ("`t{0} source volumes have snapmirror destinations." -f @($sourceVolumesWithSnapmirrorDestinations.Length))
                            $sourceVolumesWithSnapmirrorDestinations | ForEach-Object {
                                Write-Host -ForegroundColor Green ("`t`t{0}:{1}:{2}" -f @($_.NCController.Name, $_.VServer, $_.Name))
                            }

                            # On to the snapmirrors...
                            $srcVolIdx = 0
                            while($good2Go -and ($srcVolIdx -lt $sourceVolumesWithSnapmirrorDestinations.Length))
                            {
                                $sourceVolume = $sourceVolumesWithSnapmirrorDestinations[$srcVolIdx]
                                Write-Host -ForegroundColor Green ("`r`nProcessing source volume: {0}:{1}:{2}..." -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name))

                                $sourceVolumeSnapmirrors = @($allSourceVServerSnapmirrors | Where-Object { ($_.SourcevServer -eq $sourceVolume.VServer) -and ($_.SourceVolume -eq $sourceVolume.Name) })
                                $snapmirrorIdx = 0
                                while($good2Go -and ($snapmirrorIdx -lt $sourceVolumeSnapmirrors.Length))
                                {
                                    $snapmirror = $sourceVolumeSnapmirrors[$snapmirrorIdx]
                                    Write-Host -ForegroundColor Green ("`tSnapmirror destination: {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume))
                                    $snapmirrorDestinationVolume = $allONTAPVolumes | Where-Object { ($_.NCController.Name -eq $snapmirror.NcController.Name) -and ($_.VServer -eq $snapmirror.DestinationvServer) -and ($_.Name -eq $snapmirror.DestinationVolume)}
                                    if($null -ne $snapmirrorDestinationVolume)
                                    {
                                        $good2Go = UpdateSnapmirror -snapmirror $snapmirror
                                    }
                                    else
                                    {
                                        Write-Host -ForegroundColor Red ("`tFailed to retrieve volume object for {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume))
                                        $good2Go = $false
                                    }
                                    $snapmirrorIdx++
                                }

                                $srcVolIdx++
                            }
                        }
                        else
                        {
                            Write-Host -ForegroundColor Yellow "`tNo source volumes have snapmirror destinations."
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red "`tNo snapmirrors where retrieve from any ONTAP clusters."
                        $good2Go = $false
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red "`tException: Failed to retrieve all snapmirrors from all ONTAP clusters."
                    $good2Go = $false
                }
            }
            else
            {
                Write-Host -ForegroundColor Yellow ("`tNo volumes found where VServer = {0}." -f @($SourceVServerName))
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "`tNo volumes retrieved from any ONTAP cluster."
            $good2Go = $false
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red "`tException: Failed to retrieve all volumes from all ONTAP clusters."
        $good2Go = $false
    }

    if($good2Go)
    {
        Write-Host ("`r`nPausing for {0}, [CTRL-C] to break..." -f @($durationString))
        Start-Sleep -Milliseconds $pauseDuration.TotalMilliseconds
    }
} while($good2Go)
