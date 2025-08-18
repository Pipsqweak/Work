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
    $TakeAction,

    [Parameter(Mandatory=$false,Position=3)]
    [String[]]
    $VolumesToInclude<#,

    [Parameter(Mandatory=$false,Position=4)]
    [Switch]
    $Retry
#>
)
<#

    NOTES:

        You'll see several instances and variations of the following in this script, or any script I write.  I do this as a way to let myself know, if/when I look at the code again,
            that I have considered the "else" result of the if comparison and not just forgotten to add the else.  It can be confusing to go back to code you wrote in the past and
            wonder, "Why didn't I handle the else?"  Was the else irrelevant?  Did I forget to flesh it out? etc...  So to avoid the confusion, I try to always add the else, even if it's # Nothing.

        if(...some comparison...)
        {
            SomeAction...
        } `
        else
        {
            # Nothing
        }

    Layout of $data:

        .Good2Go                   - While no errors are encountered, this will remain $true
        .FirstPass                 - $true if the script is running through the processing section the first time to create .ActionSequence (not yet implemented)
        .ActionSequence            - The actions which need to be preformed on the second pass of the processing section (not yet implemented)
        .AllVolumes                - All volumes from all ONTAP clusters where the volume name does not match $Script:volumesToIgnoreRegex
        .AllVServers               - All VServers (SVMs) from all ONTAP clusters
        .RelatedControllers        - Once all snapmirror destinations are know, this will be the controllers we need to query for information instead of relying on $Global:cDot
        .Snapmirrors               - All the currently established snapmirrors related to this failover.  (From the perspective of the destination cluster -- Get-NCSnapmirror)
        .SnapmirrorDestinations    - All the snapmirror destinations related to theis failover.  (From the perspective of the source VServer -- Get-NCSnapmirrorDestination)
        .NFSDatastores             - vSphere NFS datastores related to this failover.
        .DatastoreToVMHosts        - Dictionary of datastore IDs to list of VMHosts connected to the datastore
        .ServicePrincipalNames     - Service principal names to transfer from the source AD computer to the destination computer object
        .CNAMERecords              - CNAME records to transfer from the current CIFS server to the destination CIFS server
        .Source|.Destination       - These store the following information for the source and destination
            .VServer               - The source or destination VServer
            .CIFServer             - The CIFS server returned by Get-NCCifsServer for the associated .VServer
            .CIFSShares            - A list of all the CIFS shares hosted on .VServer which do not match $Script:sharesToIgnore
            .IsNFSHost             - $true/$false
            .NetworkInterfaces     - If .IsNFSHost then a list of Get-NcNetInterface where NFS exports are served from
        .NewSnapmirrors            - A list representing the new snapmirrors which need to be created to affect the failover.
            .OriginalSourceVolume  - The original volume hosted on .Source.VServer which this .NewSnapmirror is based on.
            .SourceVolume          - When the new snapmirrors are created, this will be the snapmirror source volume for all related destinations
            .Datastores            - A list of datastores related to .SourceVolume
            .Relationships         - A list of destinations for the snapmirror
                .DestinationVolume - The destination volume for the new snapmirror
                .Snapmirror        - The snapmirror object from $data.Snapmirrors this relationship is based on.
                .Datastores        - The datastores related to .DestinationVolume

    As of now (4/24/2024) the NFS part of the fail over is not complete.  The script can be used to process the snapmirrors related the the NFS volumes, but the vSphere integration is not yet complete.

    As of now (4/24/2024) the action sequence is also not implemented.  The idea is, during the first pass, I generate an action sequence representing the actions which need to happen to complete
        the failover.  The action sequence is then saved to a .JSON file which can be used as the basis of the -Retry switch on the script (commented out).  After the action sequence is saved,
        it is used as the basis for completing the failover.  See below.

        Once real changes begin to take place as a result of the script, it will likely not be possible to rely on Initialize to collect the needed information to recreate the action sequence.  Snapmirrors
        maybe broken off, some might be delete, others even released and new mirrors created but not sync'd.  So I have to have a reliable means to represent each atomic action independent of all others.

        Meaning, when .ActionSequence is fleshed out, the actual change processing will be as simple as (or something very similar):

            $good2Go = $true
            $a = 0
            while($good2Go -and ($a -lt $actionSequence.Count))
            {
                if(-not $actionSequence[$a].Complete)
                {
                    $good2Go = PerformAction $actionSequence[$a]
                    if($good2Go)
                    {
                        # Only update the action sequence file while $good2Go
                        UpdateActionSequenceJSON $actionSequence
                    } `
                    else
                    {
                        # Nothing, when .ActionSequence was initially created, all actions are flagged not complete so no
                        #   need to update the file to change .Complete to false since it's already false :)
                    }
                } `
                else
                {
                    # Nothing, this action was already completed.
                }
                $a++
            }

        There won't be any:
            if snapmirror updated then break the snapmirror
            if snapmirror broken then delete snapmirror
            etc...
        Just continue performing actions until something fails then stop.

        I imagine the completed script will look significantly different than it does now.  Such is the nature of coding...

#>

# Make sure $Script:VolumesToInclude is an array before proceeding.
if($null -eq $Script:VolumesToInclude)
{
    $Script:VolumesToInclude = @()
} `
else
{
    if($Script:VolumesToInclude -isnot [Array])
    {
        $Script:VolumesToInclude = @($Script:VolumesToInclude)
    } `
    else
    {
        # Nothing
    }
}

# Define some script wide variables
$Script:sharesToIgnore = @("c`$","ipc`$", "Shares`$", "admin`$")
$Script:volumesToIgnoreRegex = "^(JP_)|(ROOT_)|(vol0)"
$Script:defaultSnapmirrorPolicyName = "smvp_180_nightly_01"
$Script:maxOperationRetries = 3
$Script:actionRetriesWaitSeconds = 5

# Set the simulation message based on $Script:TakeAction
$Script:simulatedMsg = " (simulated)"
if($Script:TakeAction)
{
    $Script:simulatedMsg = [String]::Empty
} `
else
{
    # Nothing
}

$Script:domainController = $null

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

    if([String]::IsNullOrEmpty($Script:LogFileName))
    {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        $Script:LogFileName = "{0}\FO-{1}" -f @(([System.IO.Path]::GetDirectoryName($tmpFile)), ([System.IO.Path]::GetFileName($tmpFile)))
    }
    else `
    {
        # Nothing
    }

    if($NewLine)
    {
        $leadingCRLFs = "`r`n"
    } `
    else
    {
        $leadingCRLFs = [String]::Empty
    }

    $Message = $Message.Replace("~SIMULATED~", $Script:simulatedMsg)
    while(-not [String]::IsNullOrEmpty($Message) -and $Message.StartsWith("`r`n"))
    {
        $leadingCRLFs += "`r`n"
        $Message = $Message.Substring(2, $Message.Length - 2)
    }
    $indent = [String]::new(' ', ($IndentLevel * 3))
    if([Console]::CursorLeft -eq 0)
    {
        $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff: ")
    } `
    else
    {
        $ts = [String]::Empty
    }
    $logMsg = "{0}{1}{2}{3}" -f @($leadingCRLFs, $ts, $indent, $Message)
    $logParams = @{
        Path = $Script:LogFileName
        Value = $logMsg
    }

    if($NoNewLine)
    {
        Write-Host -ForegroundColor $Color -NoNewline ("{0}{1}{2}" -f @($leadingCRLFs, $indent, $Message))
        $logParams.Add("NoNewLine", $true)
    } `
    else
    {
        Write-Host -ForegroundColor $Color ("{0}{1}{2}" -f @($leadingCRLFs, $indent, $Message))
    }

    if(-not [String]::IsNullOrEmpty($Script:LogFileName))
    {
        Add-Content @logParams -ErrorAction SilentlyContinue
    } `
    else
    {
        # Nothing
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

function AddTypeExtensions
{
    $typeData = Get-TypeData -TypeName "NetApp.Ontapi.Filer.C.NcController"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "NetApp.Ontapi.Filer.C.NcController" -MemberType ScriptProperty -MemberName "Identity" -Value { $this.Name }
    }

    $typeData = Get-TypeData -TypeName "DataONTAP.C.Types.Vserver.VserverInfo"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "DataONTAP.C.Types.Vserver.VserverInfo" -MemberType ScriptProperty -MemberName "Identity" -Value { "{0}:{1}" -f @($this.NCController.Identity, $this.VServerName) }
    }

    $typeData = Get-TypeData -TypeName "DataONTAP.C.Types.Volume.VolumeAttributes"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "DataONTAP.C.Types.Volume.VolumeAttributes" -MemberType ScriptProperty -MemberName "Identity" -Value { "{0}:{1}:{2}" -f @($this.NCController.Identity, $this.VServer, $this.Name) }
    }

    $typeData = Get-TypeData -TypeName "DataONTAP.C.Types.Cifs.CifsServerConfig"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "DataONTAP.C.Types.Cifs.CifsServerConfig" -MemberType ScriptProperty -MemberName "Identity" -Value { "{0}:{1}:{2}" -f @($this.NCController.Identity, $this.VServer, $this.CifsServer) }
    }

    $typeData = Get-TypeData -TypeName "DataONTAP.C.Types.Snapmirror.SnapmirrorInfo"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "DataONTAP.C.Types.Snapmirror.SnapmirrorInfo" -MemberType ScriptProperty -MemberName "Identity" -Value { "{0} --> {1}" -f @($this.SourceLocation, $this.DestinationLocation) }
    }

    $typeData = Get-TypeData -TypeName "VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl"
    if($null -eq (@($typeData.Members.Keys) | Where-Object { $_ -eq "Identity" }))
    {
        Update-TypeData -TypeName "VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl" -MemberType ScriptProperty -MemberName "Identity" -Value { $this.Id.Replace("Datastore-","") }
    }
}

function CatchActionException
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false, Position=0)]
        [Int32]
        $tries = 1,

        [Parameter(Mandatory=$false, Position=1)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $IgnoreException = $false
    )

    $good2Go = $true
    if($tries -lt $maxTries)
    {
        if(($tries -eq 1) -and (-not $IgnoreException))
        {
            LogWarning "Operation failed."
            if($maxTries -gt 1)
            {
                LogWarning ("Pausing {0} seconds before retrying (max {1} attempts)" -f @($secondsToPause, $maxTries))
            } `
            else
            {
                # Nothing only show the message if we are going to retry.
            }
        } `
        else
        {
            # Nothing, only want to display a message once.
        }
        Start-Sleep -Seconds $secondsToPause
    } `
    else
    {
        $good2Go = $false

        if(-not $IgnoreException)
        {
            LogError "Operation failed" -NewLine -NoNewLine
            if($tries -gt 1)
            {
                LogError (" after {0} tries." -f @($tries)) -NoNewLine
            } `
            else
            {
                # Nothing
            }
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr)) -NewLine
        } `
        else
        {
            # Nothing, do as we are told...ignore the error.
        }
    }

    return $good2Go
}

function ReTryCatch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $callee,

        [Parameter(Mandatory=$false, Position=1)]
        [HashTable]
        $funcParameters,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch]
        $IgnoreException
    )

    if($null -eq $funcParameters)
    {
        $funcParameters = @{
            ErrorAction = [System.Management.Automation.ActionPreference]::Stop
        }
    } `
    else
    {
        # Nothing, we were provided function parameters for $callee
    }

    if(-not $funcParameters.ContainsKey("ErrorAction"))
    {
        $funcParameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop)
    } `
    else
    {
        # Nothing, ErrorAction already specified.
    }

    # Capture vital information is $result which is returned to the caller.
    $result = "" | Select-Object ActionComplete, Good2Go, ReturnValue, Tries, Error
    $result.Good2Go = $true              # .Good2Go does NOT imply the result of & $callee was successful, just that & $callee was successfully called.  It's up to the caller to check .ReturnValue
    $result.ReturnValue = $null          # ALWAYS an array of the results of calling $callee
    $result.ActionComplete = $false      # Did $callee complete without an exception?
    $result.Error = $null                # $Error[0].ErrorRecord if the call failed
    $result.Tries = 0                    # How many times was $callee called?

    $calleeIsValid = $false
    $Error.Clear()
    try
    {
        $calleeIsValid = ($null -ne (Get-Command -Name $callee -ErrorAction Stop)) -or ($null -ne (Get-Item -Path ("Function:\{0}" -f @($callee)) -ErrorAction Stop))
    }
    catch
    {
        LogError ("No cmdlet or function named {0} found." -f @($callee))
        $result.Good2Go = $false
    }

    if($calleeIsValid)
    {
        do
        {
            $result.Tries++
            $Error.Clear()

            try
            {
                # To ensure consistency, I'll always return an array...
                $result.ReturnValue = @(& $callee @funcParameters)
                $result.ActionComplete = $true
            }
            catch
            {
                $result.Error = $Error[0]
                $result.Good2Go = CatchActionException -tries $result.Tries -maxTries $maxTries -secondsToPause $secondsToPause -IgnoreException:$IgnoreException.IsPresent
            }
        } while($result.Good2Go -and (-not $result.ActionComplete) -and ($result.Tries -lt $maxTries))
    } `
    else
    {
        # Nothing already display a message
    }

    return $result
}

function GetVServerData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String] $SourceVServerName,

        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.String] $DRVServerName
    )

    if($data.Good2Go)
    {
        LogInfo "Collecting VServers..."
        # Get all VServer objects ...

        $funcParams = @{
            Controller = @($cDot.Values)
        }

        $result = ReTryCatch -callee "Get-NCVserver" -funcParameters $funcParams

        if($result.Good2Go)
        {
            $data.AllVServers = $result.ReturnValue

            # Get enough VServers?
            if($data.AllVServers.Length -ge 2)
            {
                LogInfo ("Located {0} VServer(s)." -f @($data.AllVServers.Length)) 1
                $sourceVServers = @($data.AllVServers | Where-Object { $_.VServerName -eq $SourceVServerName })
                if($sourceVServers.Length -eq 1)
                {
                    # Unique source VServer was found...
                    $data.Source.VServer = $sourceVServers[0]
                    LogInfo ("Source VServer: {0}" -f @($data.Source.VServer.Identity)) 1

                    $destinationVServers = @($data.AllVServers | Where-Object { $_.VServerName -eq $DRVServerName })
                    if($destinationVServers.Length -eq 1)
                    {
                        # Unique destination VServer was found...
                        $data.Destination.VServer = $destinationVServers[0]
                        LogInfo ("Destination VServer: {0}" -f @($data.Destination.VServer.Identity)) 1
                    } `
                    elseif($destinationVServers.Length -eq 0)
                    {
                        # No VServer was found...
                        LogError  ("Failed to retrieve vServer object for {0}." -f @($DRVServerName))
                        $data.Good2Go = $false
                    } `
                    else
                    {
                        # Multiple VSerers were found.
                        LogError ("Multiple VServers found for {0}." -f @($DRVServerName))
                        $destinationVServers.ForEach({
                            LogError ("{0}" -f @($_.Identity)) 1
                        })
                        $data.Good2Go = $false
                    }
                } `
                elseif($sourceVServers.Length -eq 0)
                {
                    # No VServer was found...
                    LogError  ("Failed to retrieve vServer object for {0}." -f @($SourceVServerName))
                    $data.Good2Go = $false
                } `
                else
                {
                    # Multiple VServers were found.
                    LogError ("Multiple VServers found for {0}." -f @($SourceVServerName))
                    $sourceVServers.ForEach({
                        LogError ("{0}" -f @($_.Identity)) 1
                    })
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Failed to retrieve VServer data from ONTAP clusters."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Failed to retrieve VServer data from ONTAP clusters."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function FixVolumesToInclude
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$false,Position=1)]
        [String[]]
        $VolumesToInclude
    )

    $tmpList = [System.Collections.Generic.List[System.String]]::new()
    if($data.Good2Go)
    {
        LogInfo "Parsing volumes to include..."
        if($null -ne $data.Source.VServer)
        {
            $a = 0
            while($a -lt $VolumesToInclude.Length)
            {
                $volName = $VolumesToInclude[$a]
                if(-not [String]::IsNullOrEmpty($volName))
                {
                    if($volName -match "(.+):(.+)")
                    {
                        $svmName = $Matches[1]
                        if($svmName -ne $data.Source.VServer.VserverName)
                        {
                            LogError ("{0} is not hosted on {1}." -f @($volName, $data.Source.VServer.VServerName))
                            $data.Good2Go = $false
                            $volName = [String]::Empty
                        } `
                        else
                        {
                            # Nothing
                        }
                    } `
                    else
                    {
                        $volName = "{0}:{1}" -f @($data.Source.VServer.VServerName, $volName)
                    }

                    if(-not [String]::IsNullOrEmpty($volName))
                    {
                        $idx = $tmpList.BinarySearch($volName)
                        if($idx -lt 0)
                        {
                            $tmpList.Insert(-bnot $idx, $volName)
                        } `
                        else
                        {
                            # Nothing don't need or want duplicates.
                        }
                    } `
                    else
                    {
                        # Nothing, skip erroneous volume name
                    }
                } `
                else
                {
                    # Nothing, skip empty volume names.
                }
                $a++
            }
        } `
        else
        {
            # Nothing, already displayed an error.
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    return $tmpList.ToArray()
}

function GetVolumesData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$false,Position=1)]
        [String[]]
        $VolumesToInclude
    )

    if($data.Good2Go)
    {
        # Collect volumes we might care about.  Exclude JP_, ROOT_
        LogInfo "Collecting volumes..."

        $funcParams = @{
            Controller = @($cDot.Values)
        }
        $result = ReTryCatch -callee "Get-NCVol" -funcParameters $funcParams
        if($result.Good2Go)
        {
            $data.AllVolumes = @($result.ReturnValue | Where-Object { $_.Name -notmatch $Script:volumesToIgnoreRegex })
            if($data.AllVolumes.Length -gt 0)
            {
                LogInfo ("{0} volumes collected." -f @($data.AllVolumes.Length)) 1

                # Check to make sure the volumes in the list of volumes to include are valid.
                if($VolumesToInclude.Length -gt 0)
                {
                    $invalidIncludedVolumes = [System.Collections.Generic.List[System.String]]::new()
                    $a = 0
                    while($a -lt $VolumesToInclude.Length)
                    {
                        if($null -eq ($data.AllVolumes | Where-Object { ("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $VolumesToInclude[$a] }))
                        {
                            $idx = $invalidIncludedVolumes.BinarySearch($VolumesToInclude[$a])
                            if($idx -lt 0)
                            {
                                $invalidIncludedVolumes.Insert(-bnot $idx, $VolumesToInclude[$a])
                            } `
                            else
                            {
                                # Nothing only add the included volume once.
                            }
                        }
                        $a++
                    }

                    if($invalidIncludedVolumes.Count -gt 0)
                    {
                        $data.Good2Go = $false
                        LogError "Invalid volume(s) found in list of volumes to include:"
                        @($invalidIncludedVolumes).ForEach({
                            LogError ("{0}" -f @($_)) 1
                        })
                    } `
                    else
                    {
                        # Nothing
                    }
                } `
                else
                {
                    # Nothing, no volumes explicitly included so nothing to check.
                }
            } `
            else
            {
                LogError "Failed to get volume objects from ONTAP."
                $data.Good2Go = $false
            }
        } `
        else
        {
            $data.Good2Go = $false
            LogError "Failed to get volume objects from ONTAP."
        }
    } `
    else
    {
        # Nothing, already reported an error.
    }
}

function GetSnapmirrorDestinations
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$false,Position=1)]
        [String[]]
        $VolumesToInclude
    )
    <#
        GetSnapmirrorDestinations builds a list of snapmirror destinations relevant to the failover operation.  It also validates the existance of the source and destination volumes.
            Therefore, for any function following GetSnapmirrorDestinations, testing if a volume is a source or destination in $data.SnapmirrorDestinations implicitly validates the existance
            of said volume.  Additionally testing a volume against $data.SnapmirrorDestinations.SourceVolume will verify if a volume is to be included.
    #>

    <#
        Build $data.SnapmirrorDestinations to include only snapmirrors whose source volumes are to be included.  However, do NOT include
            any SNAPLOCK volumes -- whether they be sources or destinations, just ignore any snapmirror relationship which includes a SNAPLOCK volume. PERIOD
    #>

    if($data.Good2Go)
    {
        if($null -ne $data.Source.VServer)
        {
            if(($null -ne $data.AllVolumes) -and ($data.AllVolumes.Length -gt 0))
            {
                LogInfo "Collecting snapmirror destinations from the source VServer..."

                # Get all the snapmirror destinations from the requested source VServer.
                #   Include all snapmirrors if $Script:VolumesToInclude is empty, otherwise only include snapmirrors where SourceLocation is contained in $Script:VolumesToInclude
                $funcParams = @{
                    Controller = $data.Source.VServer.NcController
                    SourceVServer = $data.Source.VServer.VServerName
                }
                $result = ReTryCatch -callee "Get-NcSnapmirrorDestination" -funcParameters $funcParams

                if($result.Good2Go)
                {
                    $allSourceSnapmirrorDestinations = $result.ReturnValue
                    $data.SnapmirrorDestinations = [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorDestinationInfo]]::new()

                    if($allSourceSnapmirrorDestinations.Length -gt 0)
                    {
                        LogInfo ("Found {0} snapmirror destinations." -f @($allSourceSnapmirrorDestinations.Length)) 1

                        # Now fill out $data.SnapmirrorDestinations with the appropriate snapmirror destinations.
                        $a = 0
                        while($a -lt $allSourceSnapmirrorDestinations.Length)
                        {
                            # Filter out snapmirrors where the source location is not included in $VolumesToInclude (remember, if $VolumesToInclude.Length -eq 0, include all snapmirrors)
                            if(($VolumesToInclude.Length -eq 0) -or ($VolumesToInclude -contains $allSourceSnapmirrorDestinations[$a].SourceLocation))
                            {
                                # Verify there is a source volume for $allSourceSnapmirrorDestinations[$a]...
#                                $snapmirrorSourceVolumes = @($data.AllVolumes | Where-Object { ($_.VServer -eq $allSourceSnapmirrorDestinations[$a].SourceVserver) -and ($_.Name -eq $allSourceSnapmirrorDestinations[$a].SourceVolume) })
                                $snapmirrorSourceVolumes = @($data.AllVolumes | Where-Object { ("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $allSourceSnapmirrorDestinations[$a].SourceLocation })
                                if($snapmirrorSourceVolumes.Length -eq 1)
                                {
                                    $snapmirrorSourceVolume = $snapmirrorSourceVolumes[0]

                                    # Filter out SNAPLOCK source volumes...(if that's even possible)
                                    if($snapmirrorSourceVolume.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock")
                                    {
                                        # Verify there is a destination volume for $allSourceSnapmirrorDestinations[$a]...
#                                        $snapmirrorDestinationVolumes = @($data.AllVolumes | Where-Object { ($_.VServer -eq $allSourceSnapmirrorDestinations[$a].DestinationVserver) -and ($_.Name -eq $allSourceSnapmirrorDestinations[$a].DestinationVolume) })
                                        $snapmirrorDestinationVolumes = @($data.AllVolumes | Where-Object { ("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $allSourceSnapmirrorDestinations[$a].DestinationLocation })
                                        if($snapmirrorDestinationVolumes.Length -eq 1)
                                        {
                                            $snapmirrorDestinationVolume = $snapmirrorDestinationVolumes[0]

                                            # Also filter out all SNAPLOCK destination volumes...
                                            if($snapmirrorDestinationVolume.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock")
                                            {
                                                # Found a keeper...
                                                $data.SnapmirrorDestinations.Add($allSourceSnapmirrorDestinations[$a])
                                            } `
                                            else
                                            {
                                                LogWarning ("Snapmirror destination volume {0} is a snaplock volume.  Ignoring snapmirror." -f @($snapmirrorDestinationVolume.Identity))
                                            }
                                        } `
                                        elseif ($snapmirrorDestinationVolumes.Length -eq 0)
                                        {
                                            LogError ("No volume found for snapmirror destination: {0}." -f @($allSourceSnapmirrorDestinations[$a].DestinationLocation))
                                            $data.Good2Go = $false
                                        } `
                                        else
                                        {
                                            LogError ("Multiple volumes found for snapmirror destination: {0}" -f @($allSourceSnapmirrorDestinations[$a].DestinationLocation))
                                            $snapmirrorDestinationVolumes.ForEach({
                                                LogError ("{0}" -f @($_.Identity)) 1
                                            })
                                            $data.Good2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        LogWarning ("Snapmirror source volume {0} is a snaplock volume.  Ignoring snapmirror." -f @($snapmirrorSourceVolume.Identity))
                                    }
                                } `
                                elseif ($snapmirrorSourceVolumes.Length -eq 0)
                                {
                                    LogError ("No volume found for snapmirror source: {0}." -f @($allSourceSnapmirrorDestinations[$a].SourceLocation))
                                    $data.Good2Go = $false
                                } `
                                else
                                {
                                    LogError ("Multiple volumes found for snapmirror source: {0}" -f @($allSourceSnapmirrorDestinations[$a].SourceLocation))
                                    $snapmirrorSourceVolumes.ForEach({
                                        LogError ("{0}" -f @($_.Identity)) 1
                                    })
                                    $data.Good2Go = $false
                                }
                            }
                            else
                            {
                                # Keep track that we are not migrating all volumes.
                                $data.MigrateAllVolumes = $false
                            }
                            $a++
                        }
                    } `
                    else
                    {
                        LogError ("No snapmirror destinations found for {0}." -f @($data.Source.VServer.Identity))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to retrieve snapirror destinations from {0}." -f @($data.Source.VServer.Identity))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "No volumes data available.  Volumes data must be collected prior to collecting snapmirror destinations data."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer is not available.  Collect VServer data prior to collecting snapmirror destinations."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function GetRelatedControllers
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    $data.RelatedControllers = [System.Collections.Generic.List[System.Object]]::new()
    if($data.Good2Go)
    {
        LogInfo "Collecting related controllers data."
        if($null -ne $data.Source.VServer)
        {
            if(($null -ne $data.SnapmirrorDestinations) -and ($data.SnapmirrorDestinations.Count -gt 0))
            {
                # Build the list of controllers involved with all the snapmirrors
                #    Seed the list with the source controller
                # 2024-08-29:  Discovered an issue where the NCController object from $data.Souce.VServer.NcController also specified the VServer, which I do not want,
                #   so, I'll use the name of the controller from $data.Source.VServer.NcController to find the corresponding object in $Global:cDot.
                $controller = $Global:cDot.Values | Where-Object { ($_.Name -eq $data.Source.VServer.NcController.Name) -and (($_.Address -eq $data.Source.VServer.NcController.Address)) }
                if($null -ne $controller)
                {
                    $data.RelatedControllers.Add($controller)
                    $a = 0
                    while($a -lt $data.SnapmirrorDestinations.Count)
                    {
                        $snapmirrorDestinationVServersByName = @($data.AllVServers | Where-Object { $_.VServerName -eq $data.SnapmirrorDestinations[$a].DestinationVserver })
                        if($snapmirrorDestinationVServersByName.Length -eq 1)
                        {
                            $existingController = $data.RelatedControllers | Where-Object { $_.Name -eq $snapmirrorDestinationVServersByName[0].NcController.Name }
                            if($null -eq $existingController)
                            {
                                $controller = $Global:cDot.Values | Where-Object { ($_.Name -eq $snapmirrorDestinationVServersByName[0].NCController.Name) -and (($_.Address -eq $snapmirrorDestinationVServersByName[0].NcController.Address)) }
                                if($null -ne $controller)
                                {
                                    $data.RelatedControllers.Add($controller)
                                } `
                                else
                                {
                                    LogError ("No NetApp controller located for snapmirror destination VServer: {0}." -f @($snapmirrorDestinationVServersByName[0].Identity))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, only add the controller once.
                            }
                        } `
                        elseif ($snapmirrorDestinationVServersByName.Length -eq 0)
                        {
                            LogError ("No NetApp controller located for snapmirror destination VServer: {0}." -f @($data.SnapmirrorDestinations[$a].DestinationVserver))
                            $data.Good2Go = $false
                        }
                        $a++
                    }
                    LogInfo ("{0} connected controllers." -f @($data.RelatedControllers.Count))
                } `
                else
                {
                    LogError ("No NetApp controller located for source vServer: {0}." -f @($data.Source.VServer.Identity))
                    $data.Good2Go = $false
                }

            } `
            else
            {
                LogError "Snapmirror destinations not available.  Collect snapmirror destination data prior to collecting related controllers data."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer not available.  Collect VServer data prior to collecting related controllers data."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function GetSnapmirrors
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    $data.Snapmirrors = [System.Collections.Generic.List[DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]]::new()
    if($data.Good2Go)
    {
        LogInfo "Collecting snapmirror relationships."
        if($null -ne $data.Source.VServer)
        {
            if(($null -ne $data.SnapmirrorDestinations) -and ($data.SnapmirrorDestinations.Count -gt 0))
            {
                # Before we can check the other VServer peerings, we need to get all the snapmirrors related to the source VServer
                $funcParams = @{
                    Controller = $data.Source.VServer.NcController
                    Template = $true
                }
                $result = ReTryCatch -callee "Get-NCSnapmirror" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $snapmirrorQueryTemplate = $result.ReturnValue[0]  # Remember, $result.ReturnValue is always an array
                    if($null -ne $snapmirrorQueryTemplate)
                    {
                        $snapmirrorQueryTemplate.SourceVserverUuid = $data.Source.VServer.Uuid

                        try
                        {
                            LogInfo ("Collecting snapmirrors where {0} is the source..." -f @($data.Source.VServer.Identity))
                            # Have to send the query to all peered controllers since we have no idea which ones have snapmirror destinations for the source VServer -- one might assume they all do... but we know what happens when you assume...
                            #    Maybe could have used Get-NcSnapmirrorDestination here, but I chose not to.
                            $funcParams = @{
                                Controller = $data.RelatedControllers
                                Query = $snapmirrorQueryTemplate
                            }
                            $result = ReTryCatch -callee "Get-NCSnapmirror" -funcParameters $funcParams

                            if($result.Good2Go)
                            {
                                $allSourceSnapmirrors = $result.ReturnValue

                                if($allSourceSnapmirrors.Length -gt 0)
                                {
                                    $a = 0
                                    while($a -lt $allSourceSnapmirrors.Length)
                                    {
                                        # Make sure $allSourceSnapmirrors[$a] is for a volume we are interested in.
                                        if($null -ne ($data.SnapmirrorDestinations | Where-Object { $_.RelationshipId -eq $allSourceSnapmirrors[$a].RelationshipId }))
                                        {
                                            # We are interested in this snapmirror...

                                            # Have we already collected this snapmirror?
                                            if($null -eq ($data.Snapmirrors | Where-Object { $_.RelationshipId -eq $allSourceSnapmirrors[$a].RelationshipId }))
                                            {
                                                # Nope...
                                                $data.Snapmirrors.Add($allSourceSnapmirrors[$a])
                                            } `
                                            else
                                            {
                                                # Nothing, only need to capture the snapmirror relationship once.
                                            }
                                        }
                                        $a++
                                    }

                                    # Make sure there are snapmirror destinations on the requested VServer.
                                    if($null -ne ($data.Snapmirrors | Where-Object { $_.DestinationVserverUuid -eq $data.Destination.VServer.Uuid }))
                                    {
                                        LogInfo ("Snapmirrors: {0}" -f @($data.Snapmirrors.Count))
                                    } `
                                    else
                                    {
                                        LogError ("No snapmirror destinations found for requested VServer: {0}.  Failover not possible." -f @($data.Destination.VServer.Identity))
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    LogError ("No snapmirrors found for {0}.  Failover not possible." -f @($data.Source.VServer.Identity))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed an error.
                            }
                        }
                        catch
                        {
                            LogException ("Failed to retrieve snapmirror objects from source VServer {0}." -f @($data.Source.VServer.Identity))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Null snapmirror query template returned from {0}" -f @($data.Source.VServer.NcController.Identity))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to create snapmirror query template from {0}." -f @($data.Source.VServer.Identity))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Snapmirror destinations not available.  Collect snapmirror destination data prior to collecting related controllers data."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer not available.  Collect VServer data prior to collecting related controllers data."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function GetCIFSData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        if($null -ne $data.Source.VServer)
        {
            if($null -ne $data.Destination.VServer)
            {
                if($null -ne $data.SnapmirrorDestinations)
                {
                    # Get the CIFS server associated with the source VServer, if there is one.
                    LogInfo "Collecting source CIFS data..."
                    $funcParams = @{
                        Controller = $data.Source.VServer.NcController
                        VserverContext = $data.Source.VServer.VserverName
                    }
                    $result = ReTryCatch -callee "Get-NCCifsServer" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $data.Source.CifsServer = $result.ReturnValue[0]
                        LogInfo ("Is CIFS Server: {0}" -f @(($null -ne $data.Source.CIFSServer))) 1

                        if($null -ne $data.Source.CIFSServer)
                        {
                            # Get the CIFS shares for the CIFS Server which are included in $data.SnapmirrorDestination
                            $funcParams = @{
                                Controller = $data.Source.VServer.NcController
                                VserverContext = $data.Source.VServer.VserverName
                            }
                            $result = ReTryCatch -callee "Get-NcCifsShare" -funcParameters $funcParams
                            if($result.Good2Go)
                            {
                                $data.Source.CIFSShares = @(($result.ReturnValue | Where-Object { ($_.ShareName -notin $Script:sharesToIgnore) }).ForEach({
                                    $cifsShareVolume = "{0}:{1}" -f @($_.Vserver, $_.Volume)
                                    if(($data.SnapmirrorDestinations | Where-Object { $_.SourceLocation -eq $cifsShareVolume }).Length -gt 0) { $_ }
                                }))
                                LogInfo ("Shares: {0}" -f @($data.Source.CIFSShares.Length)) 1
                            } `
                            else
                            {
                                LogError ("Failed to retrieve CIFS shares from {0}." -f @($data.Source.VServer.Identity))
                                $data.Good2Go = $false
                            }

                            LogInfo "Collecting destination CIFS data..."
                            # Get the CIFS server associated with the destination VServer, if there is one.
                            $funcParams = @{
                                Controller = $data.Destination.VServer.NcController
                                VserverContext = $data.Destination.VServer.VserverName
                            }
                            $result = ReTryCatch -callee "Get-NCCifsServer" -funcParameters $funcParams
                            if($result.Good2Go)
                            {
                                $data.Destination.CIFSServer = $result.ReturnValue[0]
                                LogInfo ("Is CIFS Server: {0}" -f @(($null -ne $data.Destination.CIFSServer))) 1

                                if($null -ne $data.Destination.CIFSServer)
                                {
                                    # Get the CIFS shares for the CIFS Server
                                    $funcParams = @{
                                        Controller = $data.Destination.VServer.NcController
                                        VserverContext = $data.Destination.VServer.VserverName
                                    }
                                    $result = ReTryCatch -callee "Get-NcCifsShare" -funcParameters $funcParams
                                    if($result.Good2Go)
                                    {
                                        # Again, only collect shares related to the snapmirror destinations.
                                        $data.Destination.CIFSShares = @(($result.ReturnValue | Where-Object { ($_.ShareName -notin $Script:sharesToIgnore) }).ForEach({
                                            $cifsShareVolume = "{0}:{1}" -f @($_.Vserver, $_.Volume)
                                            if(($data.SnapmirrorDestinations | Where-Object { $_.DestinationLocation -eq $cifsShareVolume}).Length -gt 0) { $_ }
                                        }))
                                        LogInfo ("Shares: {0}" -f @($data.Destination.CIFSShares.Length)) 1
                                    } `
                                    else
                                    {
                                        LogError ("Failed to retrieve CIFS shares from {0}." -f @($data.Destination.VServer.Identity))
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    LogError ("Destination VServer {0} does not have a CIFS server defined." -f @($data.Source.VServer.Identity))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                LogError ("Failed to retrieve CIFS server data from {0}." -f @($data.Destination.VServer.Identity))
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            # Nothing.  If $data.Source.CIFSServer is null, that's fine, just means there isn't a CIFS server configured for the VServer.  Hence we won't get the non-existant shares.
                        }
                    } `
                    else
                    {
                        LogError ("Failed to retrieve CIFS server data from {0}." -f @($data.Source.VServer.Identity))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError "Snapmirror destinations are not available.  Please collect snapmirror destination data prior to collecting CIFS data."
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Destination VServer is not available.  Please collect VServer data prior to collecting CIFS data."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer is not available.  Please collect VServer data prior to collecting CIFS data."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function GetADData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    $data.CNAMERecords = [System.Collections.Generic.List[Microsoft.Management.Infrastructure.CimInstance]]::new()

    if($data.Good2Go)
    {
        GetDomainController
        if($null -ne $data.Source.CIFSServer)
        {
            if($null -ne $data.Destination.CIFSServer)
            {
                LogInfo "Collecting AD data..."

                $funcParams = @{
                    Identity = $data.Source.CIFSServer.CifsServer
                    Properties = @("servicePrincipalName")
                }
                $result = ReTryCatch -callee "Get-ADComputer" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $sourceCIFSServerADComputer = $result.ReturnValue[0]

                    if($null -ne $sourceCIFSServerADComputer)
                    {
                        $data.ServicePrincipalNames = @($sourceCIFSServerADComputer.servicePrincipalName | Where-Object { $_ -notmatch $sourceCIFSServerADComputer.Name })

                        if($null -ne $Script:domainController)
                        {
                            if($data.ServicePrincipalNames.Length -gt 0)
                            {
                                # Get DNS CNAME records for the source AD computer
                                $funcParams = @{}
                                $result = ReTryCatch -callee "Get-ADDomain" -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    $adDomain = $result.ReturnValue[0]
                                    if($null -ne $adDomain)
                                    {
                                        # Find the HOST/FQDN alias service principal names we need to transfer...
                                        $hostFQDNSPNs = @($data.ServicePrincipalNames | Where-Object { $_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($adDomain.DNSRoot))) })
                                        if($hostFQDNSPNs.Length -gt 0)
                                        {
                                            $a = 0
                                            while($a -lt $hostFQDNSPNs.Length)
                                            {
                                                $hostFQDNSPN = $hostFQDNSPNs[$a]

                                                if((-not [String]::IsNullOrEmpty($hostFQDNSPN)) -and ($hostFQDNSPN -match "^HOST/([^.]+)\."))
                                                {
                                                    $alias = $Matches[1]
                                                    if(-not [String]::IsNullOrEmpty($alias))
                                                    {
                                                        $funcParams = @{
                                                            Name = $alias
                                                            ZoneName = $adDomain.DNSRoot
                                                            ComputerName = $Script:domainController.Name
                                                            RRType = "CName"
                                                        }
                                                        $result = ReTryCatch -callee "Get-DnsServerResourceRecord" -funcParameters $funcParams -IgnoreException
                                                        if($result.Good2Go)
                                                        {
                                                            if($null -ne $result.ReturnValue)
                                                            {
                                                                $result.ReturnValue.ForEach({ $data.CNAMERecords.Add($_) })
                                                            } `
                                                            else
                                                            {
                                                                LogWarning ("No CNAME record found for {0}." -f @($alias))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            LogWarning ("No CNAME record found for {0}." -f @($alias))
                                                        }
                                                    }
                                                } `
                                                else
                                                {
                                                    LogWarning ("Unable to determine alias from service principal name: {0}" -f @($alias)) 3
                                                }

                                                $a++
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, no aliases to migrate...
                                        }
                                    } `
                                    else
                                    {
                                        LogError "Failed to acquire AD domain data."
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    LogError "Failed to acquire AD domain data."
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, no service principal names that don't match the computer name.
                            }
                        } `
                        else
                        {
                            LogWarning "No domain controller available.  Unable to report on or transfer CNAME records at this time."
                        }
                    } `
                    else
                    {
                        LogError ("Failed to acquire AD computer object for: {0}" -f @($data.Source.CIFSServer.CifsServer)) 2
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to acquire AD computer object for: {0}" -f @($data.Source.CIFSServer.CifsServer)) 2
                    $data.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, no destination CIFS server to transfer to.
            }
        } `
        else
        {
            # Nothing, no source CIFS server to transfer from.
        }
    } `
    else
    {
        # Nothing already displayed a message
    }
}

function GetNFSData  <# Needs a tune-up -- it's long!  288 lines #>
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        if($null -ne $data.Source.VServer)
        {
            if($null -ne $data.Destination.VServer)
            {
                if($null -ne $data.SnapmirrorDestinations)
                {
                    # Collecting NFS data requires $data.AllVolumes[x].JunctionPath to check the .RemotePath property.
                    if(($null -ne $data.AllVolumes) -and ($data.AllVolumes.Length -gt 0))
                    {

                        LogInfo ("Checking for NFS services on {0}." -f @($data.Source.VServer.Identity))
                        $funcParams = @{
                            Controller = $data.Source.VServer.NcController
                            VserverContext = $data.Source.VServer.VserverName
                        }
                        $result = ReTryCatch -callee "Get-NcNfsService" -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            $nfsService = $result.ReturnValue[0]
                            $data.Source.IsNFSHost = ($null -ne $nfsService)
                            LogInfo ("NFS Server: {0}" -f @($data.Source.IsNFSHost)) 1

                            if($data.Source.IsNFSHost)
                            {
                                # Need the network interfaces on the VServer to mount datastores...

                                LogInfo "Collecting source NFS network interfaces..."
                                $funcParams = @{
                                    Controller = $data.Source.VServer.NcController
                                    Vserver = $data.Source.VServer.VserverName
                                }
                                $result = ReTryCatch -callee "Get-NcNetInterface" -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    $data.Source.NetworkInterfaces = @($result.ReturnValue | Where-Object { $_.DataProtocols -contains "nfs" })
                                    if($data.Source.NetworkInterfaces.Length -ne 0)
                                    {
                                        LogInfo ("{0} NFS network interfaces" -f @($data.Source.NetworkInterfaces.Length)) 1

                                        if(($null -eq $Global:vCenterServers) -or ($Global:vCenterServers.Count -eq 0))
                                        {
                                            LogInfo "Connecting to vCenter..."
                                            ConnectTo vCenter
                                        } `
                                        else
                                        {
                                            # Nothing, already connected to vCenters
                                        }

                                        $data.Good2Go = ($null -ne $Global:vCenterServers) -and ($Global:vCenterServers.Count -gt 0)
                                        if($data.Good2Go)
                                        {
                                            LogInfo ("Connected to {0} vCenter server(s)..." -f @($Global:vCenterServers.Count))
                                            LogInfo "Collecting vSphere NFS datastores..."
                                            $funcParams = @{
                                                Server = @($Global:vCenterServers.Values)
                                            }
                                            $result = ReTryCatch -callee "Get-Datastore" -funcParameters $funcParams
                                            if($result.Good2Go)
                                            {
                                                $allNFSDatastores = @($result.ReturnValue | Where-Object { $_.Type -eq "NFS" })

                                                $data.NFSDatastores = [System.Collections.Generic.List[VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl]]::new()
                                                $a = 0
                                                while($a -lt $allNFSDatastores.Length)
                                                {
                                                    $netInterface = $null
                                                    $b = 0
                                                    while(($null -eq $netInterface) -and ($b -lt $allNFSDatastores[$a].RemoteHost.Length))
                                                    {
                                                        $netInterface = $data.Source.NetworkInterfaces | Where-Object { $_.Address -eq $allNFSDatastores[$a].RemoteHost[$b] }
                                                        $b++
                                                    }

                                                    if($null -ne $netInterface)
                                                    {
                                                        $datastoreVolumes = @($data.AllVolumes | Where-Object { ($_.VServer -eq $netInterface.Vserver) -and ($_.JunctionPath -eq $allNFSDatastores[$a].RemotePath) })

                                                        if($datastoreVolumes.Length -eq 1)
                                                        {
                                                            $datastoreVolume = $datastoreVolumes[0]
                                                            # Found a network interface on the source VServer for the datastore, even found a volume for it, but is it one of the volumes to include??

                                                            $volumeLocation = "{0}:{1}" -f @($datastoreVolume.Vserver, $datastoreVolume.Name)
                                                            $snapmirrorSource = $data.SnapmirrorDestinations | Where-Object { $_.SourceLocation -eq $volumeLocation }
                                                            if($null -ne $snapmirrorSource)
                                                            {
                                                                # Network Interface, Volume, and now, an included snapmirror source to match the datastore...BINGO
                                                                $existingDatastore = $data.NFSDatastores | Where-Object { ($_.DatacenterId -eq $allNFSDatastores[$a].DatacenterId) -and ($_.Id -eq $allNFSDatastores[$a].Id) }
                                                                if($null -eq $existingDatastore)
                                                                {
                                                                    $data.NFSDatastores.Add($allNFSDatastores[$a])
                                                                } `
                                                                else
                                                                {
                                                                    # Nothing, don't track duplicate datastores.
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, $datastoreVolume is not a DR'd datastore
                                                            }
                                                        } `
                                                        elseif($datastoreVolumes.Length -gt 1)
                                                        {
                                                            LogError ("Multiple volumes found which match {0}:{1}" -f @($netInterface.Address, $allNFSDatastores[$a].RemotePath))
                                                            $datastoreVolumes.ForEach({
                                                                LogError ("{0}" -f @($_.Identity)) 1
                                                            })
                                                        } `
                                                        else
                                                        {
                                                            # Nothing, found an interface that would service this datastore, but not a volume, so skip it.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        # Nothing, didn't find a network interface on the source vserver for this datastore...
                                                    }
                                                    $a++
                                                }

                                                if($data.NFSDatastores.Count -ne 0)
                                                {
                                                    LogInfo ("Located {0} relevant NFS datastores." -f @($data.NFSDatastores.Count)) 1

                                                    LogInfo "Collecting vSphere hosts..."
                                                    $funcParams = @{
                                                        Server = @($Global:vCenterServers.Values)
                                                    }
                                                    $result = ReTryCatch -callee "Get-VMHost" -funcParameters $funcParams
                                                    if($result.Good2Go)
                                                    {
                                                        $vmHosts = $result.ReturnValue
                                                        if($vmHosts.Length -gt 0)
                                                        {
                                                            LogInfo ("Located {0} VMHosts." -f @($vmHosts.Length)) 1

                                                            LogInfo "Building dictionary of datastores to vmHosts..."
                                                            # Build a dictionary of DatastoreIDs to list of connected vmhosts
                                                            $data.DatastoreToVMHosts = [System.Collections.Generic.SortedDictionary[System.String,System.Collections.Generic.List[System.Object]]]::new()
                                                            $a = 0
                                                            while($a -lt $data.NFSDatastores.Count)
                                                            {
                                                                $data.DatastoreToVMHosts.Add($data.NFSDatastores[$a].Identity, [System.Collections.Generic.List[System.Object]]::new())

                                                                ($vmHosts | Where-Object { (@($_.ExtensionData.Datastore | Where-Object { $_.Value -eq $data.NFSDatastores[$a].Identity }).Length -gt 0) }) | ForEach-Object { $data.DatastoreToVMHosts[$data.NFSDatastores[$a].Identity].Add($_) }
                                                                $a++
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            LogWarning ("No VMHosts retrieved.  vSphere datastore failover will not be available.")
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        LogError "Failed to get VMHost objects.  vSphere datastore failover will not be available."
                                                    }
                                                } `
                                                else
                                                {
                                                    LogWarning ("No NFS datastore objects retrieved from vCenter.  vSphere datastore failover will not be available.")
                                                }
                                            } `
                                            else
                                            {
                                                LogError "Failed to retrieve datastores from vCenter."
                                                $data.Good2Go = $false
                                            }

                                            <#

                                            NOTE: Need to flesh out the destination NFS data store stuff later once I add the VMware stuff to the script...

                                            #>

                                            LogInfo ("Checking for NFS servics on {0}." -f @($data.Destination.VServer.Identity))
                                            $funcParams = @{
                                                Controller = $data.Destination.VServer.NcController
                                                VserverContext = $data.Destination.VServer.VserverName
                                            }
                                            $result = ReTryCatch -callee "Get-NcNfsService" -funcParameters $funcParams
                                            if($result.Good2Go)
                                            {
                                                $nfsService = $result.ReturnValue[0]
                                                $data.Destination.IsNFSHost = ($null -ne $nfsService)
                                                LogInfo ("NFS Server: {0}" -f @($data.Destination.IsNFSHost)) 1
                                            } `
                                            else
                                            {
                                                LogError ("Failed to retrieve NFS Service status from {0}." -f @($data.Destination.VServer.Identity))
                                            }

                                            $funcParams = @{
                                                Controller = $data.Destination.VServer.NcController
                                                Vserver = $data.Destination.VServer.VserverName
                                            }
                                            $result = ReTryCatch -callee "Get-NcNetInterface" -funcParameters $funcParams
                                            if($result.Good2Go)
                                            {
                                                $data.Destination.NetworkInterfaces = @($result.ReturnValue | Where-Object { $_.DataProtocols -contains "nfs" })
                                                if($data.Destination.NetworkInterfaces.Length -ne 0)
                                                {
                                                    LogInfo ("{0} NFS network interfaces" -f @($data.Destination.NetworkInterfaces.Length)) 1
                                                } `
                                                else
                                                {
                                                    LogWarning ("No NFS network interfaces retrieved from {0}." -f @($data.Destination.VServer.Identity)) 1
                                                    LogWarning ("Will not be able to mount datastore DR volumes to ESXi hosts and failover VMs.") 1
                                                }
                                            } `
                                            else
                                            {
                                                LogWarning ("Failed to retrieve network interface definitions from {0}." -f @($data.Destination.VServer.Identity))
                                                LogWarning ("Will not be able to mount datastore DR volumes to ESXi hosts to failover VMs.") 1
                                            }
                                        } `
                                        else
                                        {
                                            LogWarning "Unable to establish connection to vCenter."
                                            LogWarning ("Will not be able to mount datastore DR volumes to ESXi hosts to failover VMs.") 1
                                        }
                                    } `
                                    else
                                    {
                                        LogError ("No NFS network interfaces retrieved from {0}." -f @($data.Source.VServer.Identity)) 1
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to retrieve network interfaces from {0}." -f @($data.Source.VServer.Identity))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, if the source VServer is not an NFS host, then there will be no vSphere anything to worry about...
                                # NOTE: What about NFS mounts for non ESXi hosts...
                            }
                        } `
                        else
                        {
                            LogError ("Failed to retrieve NFS Service status from {0}." -f @($data.Source.VServer.Identity))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError "No volumes data available.  Volumes data must be collected prior to collecting NFS data."
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError "Snapmirror destinations are not available.  Please collect snapmirror destination data prior to collecting NFS data."
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Destination VServer is not available.  Please collect VServer data prior to collecting NFS data."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer is not available.  Please collect VServer data prior to collecting NFS data."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function NewSnapmirrorObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$false,Position=1)]
        [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]]
        $datastores
    )

    <#
        OriginalSourceVolume:
            The source volume from the VServer we are failing away from.  This will not change after the new snapmirrors are fixed up.
            This is used later as the source volume when snapshot policies are updated.
        SourceVolume:
            Will represent the volume from which snapmirrors are taken.  After the new snapmirrors have been fixed up,
            this will be the volume hosted on the requested DR VServer
        Relationships:
            A list of relationship objects: destination volume, snapmirror policy, and any datastores associated with the destination volume
        Datastores:
            An array of datastores associated with the source volume
    #>

    $d = "" | Select-Object OriginalSourceVolume, SourceVolume, Relationships, Datastores
    $d.OriginalSourceVolume = $srcVolume
    $d.SourceVolume = $srcVolume
    $d.Datastores = $datastores
    $d.Relationships = [System.Collections.Generic.List[System.Object]]::new()

    return $d
}

function NewSnapmirrorRelationship
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$false,Position=2)]
        [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]]
        $datastores
    )

    $newRelationship = "" | Select-Object DestinationVolume, Snapmirror, Datastores
    $newRelationship.DestinationVolume = $volume
    $newRelationship.Snapmirror = $snapmirror
    $newRelationship.Datastores = $datastores

    return $newRelationship
}

function BuildNewSnapmirrorRelationships
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        if($null -ne $data.Source.VServer)
        {
            if($null -ne $data.Destination.VServer)
            {
                if(($null -ne $data.AllVolumes) -and ($data.AllVolumes.Length -gt 0))
                {
                    if(($null -ne $data.SnapmirrorDestinations) -and ($data.SnapmirrorDestinations.Count -gt 0))
                    {
                        if(($null -ne $data.Snapmirrors) -and ($data.Snapmirrors.Count -gt 0))
                        {
                            LogInfo "Building new snapmirror data structure..."
                            $data.NewSnapmirrors = [System.Collections.Generic.List[System.Object]]::new()

                            # Remember, all SNAPLOCK volumes were excluded from $data.SnapmirrorDestinations and therefore excluded from $data.Snapmirrors, so no need
                            #   check/report for SNAPLOCK volumes...
                            $a = 0
                            while($a -lt $data.Snapmirrors.Count)
                            {
                                # Reset/clear all variables for each snapmirror process.
                                $newSnapmirror = $newRelationship = $null
                                $smSourceVolume = $smDestinationVolume = $null

                                # Check the snapmirror source....
                                # $smSourceVolumes = @($data.AllVolumes | Where-Object { ($_.VolumeIdAttributes.OwningVserverUuid -eq $data.Snapmirrors[$a].SourceVserverUuid) -and ($_.Name -eq $data.Snapmirrors[$a].SourceVolume) })
                                $smSourceVolumes = @($data.AllVolumes | Where-Object { ($_.VolumeIdAttributes.OwningVserverUuid -eq $data.Snapmirrors[$a].SourceVserverUuid) -and (("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $data.Snapmirrors[$a].SourceLocation) })
                                if($smSourceVolumes.Length -eq 1)
                                {
                                    # Great!  A single source volume found.  I like it.
                                    $smSourceVolume = $smSourceVolumes[0]
                                    if($null -eq $smSourceVolume)
                                    {
                                        LogError ("Null snapmirror source volume detected!")
                                        $data.Good2Go = $false
                                    } `
                                    else
                                    {
                                        # Nothing for now...
                                    }
                                } `
                                elseif($smSourceVolumes.Length -eq 0)
                                {
                                    # No volume found for this snapmirror source.  VERY strange this was not discovered before...
                                    LogError ("No volume located for snapmirror source: {0}." -f @($data.Snapmirrors[$a].SourceLocation))
                                    $data.Good2Go = $false
                                } `
                                else
                                {
                                    # WTH!!  Too many sources...
                                    LogError ("Multiple volumes located for snapmirror source: {0}." -f @($data.Snapmirrors[$a].SourceLocation))
                                    $smSourceVolumes.Foreach({
                                        LogError ("{0}" -f @($_.Identity)) 1
                                    })
                                    $data.Good2Go = $false
                                }

                                # Check the snapmirror destination...
                                # $smDestinationVolumes = @($data.AllVolumes | Where-Object { ($_.VolumeIdAttributes.OwningVserverUuid -eq $data.Snapmirrors[$a].DestinationVserverUuid) -and ($_.Name -eq $data.Snapmirrors[$a].DestinationVolume) })
                                $smDestinationVolumes = @($data.AllVolumes | Where-Object { ($_.VolumeIdAttributes.OwningVserverUuid -eq $data.Snapmirrors[$a].DestinationVserverUuid) -and (("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $data.Snapmirrors[$a].DestinationLocation) })
                                if($smDestinationVolumes.Length -eq 1)
                                {
                                    # Great!  A single destination volume found.  I like it.
                                    $smDestinationVolume = $smDestinationVolumes[0]
                                    if($null -eq $smDestinationVolume)
                                    {
                                        LogError ("Null snapmirror destination volume detected!")
                                        $data.Good2Go = $false
                                    } `
                                    else
                                    {
                                        # Nothing for now...
                                    }
                                } `
                                elseif($smDestinationVolumes.Length -eq 0)
                                {
                                    # No volume found for this snapmirror destination.  VERY strange this was not discovered before...
                                    LogError ("No volume located for snapmirror destination: {0}." -f @($data.Snapmirrors[$a].DestinationLocation))
                                    $data.Good2Go = $false
                                } `
                                else
                                {
                                    # WTH!!  Too many destinations...
                                    LogError ("Multiple volumes located for snapmirror destination: {0}." -f @($data.Snapmirrors[$a].DestinationLocation))
                                    $smDestinationVolumes.Foreach({
                                        LogError ("{0}" -f @($_.Identity)) 1
                                    })
                                    $data.Good2Go = $false
                                }

                                # Record this snapmirror in our list of new snapmirrors...
                                if($data.Good2Go -and ($null -ne $smSourceVolume) -and ($null -ne $smDestinationVolume))
                                {
                                    $newSnapmirror = $data.NewSnapmirrors | Where-Object { $_.SourceVolume.VolumeIdAttributes.Uuid -eq $smSourceVolume.VolumeIdAttributes.Uuid }
                                    if($null -eq $newSnapmirror)
                                    {
                                        # Need to create a new snapmirror object...
                                        #    Initially, the new snapmirror objects will mirror the original snapmirrors.  Once all snapmirrors have been verified,
                                        #      All new snapmirror sources will be swapped with the destination volume.
                                        try
                                        {
                                            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]] $datastores = @()
                                            if(($data.Source.IsNFSHost) -and (-not [String]::IsNullOrEmpty($smSourceVolume.JunctionPath)))
                                            {
                                                $uniqueVServerAddresses = @($data.Source.NetworkInterfaces | Select-Object -Unique -ExpandProperty Address)

                                                # Get all NFS datastores whose RemotePath matches the volume's junction path.
                                                $datastores = @($data.NFSDatastores | Where-Object { ($_.RemotePath -eq $smSourceVolume.JunctionPath) -and (@($_.RemoteHost | Where-Object { $uniqueVServerAddresses -contains $_ }).Length -gt 0) })
                                            }
                                            $newSnapmirror = NewSnapmirrorObject -srcVolume $smSourceVolume -datastores $datastores
                                            $data.NewSnapmirrors.Add($newSnapmirror)
                                        }
                                        catch
                                        {
                                            LogException ("Failed to create new snapmirror object.")
                                            $data.Good2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, no need to add a duplicate snapmirror object to the list of new snapmirrors
                                    }

                                    # Do we have a place to record this snapmirror?
                                    if($null -ne $newSnapmirror)
                                    {
                                        $newRelationship = $newSnapmirror.Relationships | Where-Object {( $_.DestinationVolume.VolumeIdAttributes.Uuid -eq $smDestinationVolume.VolumeIdAttributes.Uuid )}
                                        if($null -eq $newRelationship)
                                        {
                                            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.NasDatastoreImpl[]] $datastores = @()
                                            if($data.Destination.IsNFSHost -and (-not [String]::IsNullOrEmpty($smDestinationVolume.JunctionPath)))
                                            {
                                                $uniqueVServerAddresses = @($data.Destination.NetworkInterfaces | Select-Object -Unique -ExpandProperty Address)

                                                # Get all NFS datastores whose RemotePath matches the volume's junction path.
                                                $datastores = @($data.NFSDatastores | Where-Object { ($_.RemotePath -eq $smDestinationVolume.JunctionPath) -and (@($_.RemoteHost | Where-Object { $uniqueVServerAddresses -contains $_ }).Length -gt 0) })
                                            }
                                            $newRelationship = NewSnapmirrorRelationship -volume $smDestinationVolume -snapmirror $data.Snapmirrors[$a] -datastores $datastores

                                            $newSnapmirror.Relationships.Add($newRelationship)
                                        } `
                                        else
                                        {
                                            LogError ("Duplicate relationship between source {0} and destination {1}." -f @($newSnapmirror.SourceVolume.Identity, $newRelationship.DestinationVolume.Identity))
                                            $data.Good2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, would have already logged an error.
                                    }
                                } `
                                else
                                {
                                    # Nothing, already logged an error.
                                }
                                $a++
                            }
                        } `
                        else
                        {
                            # This should **NEVER** hit because I've already bounds checked it, but still... let's be diligent.
                            LogError "No snapmirrors availables.  Please collect snapmirror data prior to creating new snapmirror relationship objects."
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError "Snapmirror destinations are not available.  Please collect snapmirror destination data prior to creating new snapmirror relationship objects."
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError "No volumes data available.  Volumes data must be collected prior to creating new snapmirror relationship objects."
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Destination VServer is not available.  Please collect VServer data prior to creating new snapmirror relationship objects."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Source VServer is not available.  Please collect VServer data prior to creating new snapmirror relationship objects."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function FixupNewSnapmirrors
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )
    <#
        FixupNewSnapmirrors:
            Swaps source and destination volumes where the destination is hosted on the request failover VServer.
            Verifies the appropriate snapmirror policies exist.
    #>

    if($data.Good2Go)
    {
        LogInfo "Fixing up new snapmirror relationships..."
        $a = 0
        while($a -lt $data.NewSnapmirrors.Count)
        {
            # Capture the snapmirror source volume and datastores so if we swap source and destination we have a way to access them
            $smSourceVolume = $data.NewSnapmirrors[$a].SourceVolume
            $srcDatastores = $data.NewSnapmirrors[$a].Datastores

            $b = 0
            while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
            {
                if($data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VolumeIdAttributes.OwningVserverUuid -eq $data.Destination.VServer.Uuid)
                {
                    # This new snapmirror relationship's destination volume will be the new snapmirror source volume.
                    #    Swap the source and relationship's destination.
                    $data.NewSnapmirrors[$a].SourceVolume = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume
                    $data.NewSnapmirrors[$a].Datastores = $data.NewSnapmirrors[$a].Relationships[$b].Datastores

                    $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume = $smSourceVolume
                    $data.NewSnapmirrors[$a].Relationships[$b].Datastores = $srcDatastores

                    # NOTE: Need to verify $data.NewSnapmirror[$a].Relationships[$b].Snapmirror.Policy exists on $data.NewSnapmirror[$a].DestinationVolume.VServer
                    #   Remember, we've swapped the snapmirror source and destination volumes so $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VServer
                    #   used to be the source and may not have the snapmirror policy -- hint: snapmirrors are managed by the PULLING (or destination) VServer.
                    $funcParams = @{
                        Controller = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NCController
                        # Vserver = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VServer
                        Name = $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy
                    }
                    $result = ReTryCatch -callee "Get-NcSnapmirrorPolicy" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $destinationVServerSnapmirrorPolicy = $result.ReturnValue[0]
                        if($null -ne $destinationVServerSnapmirrorPolicy)
                        {
                            # Nothing, the snapmirror policy exists on the destination
                        } `
                        else
                        {
                            LogError ("Snapmirror policy {0} does not exist on {1}:{2}." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NCController.Identity, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VServer))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Failed to retrieve snapmirror policy {0} from {1}:{2}." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NCController.Identity, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VServer))
                    }
                } `
                else
                {
                    # Nothing, leave the destination as is.
                    #    Additionally, snapmirrors are pulled from the destination VServer, so...
                    #    Since we didn't change the snapmirror destination, the snapmirror policy already exists on the destination VServer -- how else would the snapmirror exist without it??
                }
                $b++
            }
            $a++
        }
    } `
    else
    {
        # Nothing, already displayed an error.
    }
}

function CheckSnapmirrorPolicies
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    LogInfo "Checking snapmirror policies..." 0
    # Make sure the destination volume's cluster has the correct snapshot policy.

    $checkedVserversAndPolicies = [System.Collections.Generic.Dictionary[System.String, [System.Collections.Generic.List[System.String]]]]::new()

    $a = 0
    while($a -lt $data.NewSnapmirrors.Count)
    {
        $b = 0
        while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
        {
            $vServerKey = "{0}:{1}" -f @($data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NcController.Name, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver)
            #Write-Host $vServerKey
            if(-not $checkedVserversAndPolicies.ContainsKey($vServerKey))
            {
                $checkedVserversAndPolicies.Add($vServerKey, [System.Collections.Generic.List[System.String]]::new())
            }
            $policyList = $checkedVserversAndPolicies[$vServerKey]

            $idx = $policyList.BinarySearch($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy)
            if($idx -lt 0)
            {
                # Write-Host ("`tChecking: {0}" -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy))
                # Haven't checked $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver for snapmirrror policy $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy yet.

                # Try to get the snapmirror policy from the destination VServer...
                $funcParams = @{
                    Controller = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NcController
                    # Vserver = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver
                    Name = $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy
                }
                $result = ReTryCatch -callee "Get-NcSnapmirrorPolicy" -funcParameters $funcParams
                if($result.Good2Go)
                {

                    # No matter if we found the snapmirror policy or not, add it to the list of vServers/policies we've already checked for so we don't repeat the process.
                    $policyList.Insert(-bnot $idx, $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy)
                    if($null -ne $result.ReturnValue[0])
                    {
                        # Nothing, the snapmirror policy $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy exists on $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver
                    } `
                    else
                    {
                        LogError ("Snapmirror policy {0} does not exist on {1}.  Create and re-run script." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy, $vServerKey))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to check for snapmirror policy {0} on {1}." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy, $vServerKey))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, already checked for this snapmirror policy on the Vserver
                # Write-Host ("`tSkipped:  {0}" -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy))
            }
            $b++
        }
        $a++
    }
}

function CheckSnapshotPolicies
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    LogInfo "Checking snapshot policies..." 0
    # Make sure the destination volume's cluster has the correct snapshot policy.

    $a = 0
    while($a -lt $data.NewSnapmirrors.Count)
    {
        $b = 0
        while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
        {
            # See TakeAction for an explanation of the following logic...

            # Start by assuming .DestinationVolume is the correct "destination"
            $dstVolume = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume

            if($dstVolume -eq $data.NewSnapmirrors[$a].OriginalSourceVolume)
            {
                # The destination volume for the new snapmirror is the original source volume, so instead of checking $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume,
                #   we need to check $data.NewSnapmirrors[$a].SourceVolume (it was the original destination volume).
                $dstVolume = $data.NewSnapmirrors[$a].SourceVolume
            } `
            else
            {
                # All good, the destination for this new snapmirror is NOT the original source volume.
            }

            $sourceVolumeSnapshotPolicyName = $data.NewSnapmirrors[$a].OriginalSourceVolume.VolumeSnapshotAttributes.SnapshotPolicy

            # LogInfo ("`r`nSRC: {0} / SSSP: {1}" -f @($data.NewSnapmirrors[$a].OriginalSourceVolume.Identity, $sourceVolumeSnapshotPolicyName))
            # LogInfo ("DST: {0} / DSSP: {1}" -f @($dstVolume.Identity, $dstVolume.VolumeSnapshotAttributes.SnapshotPolicy))

            if(-not [String]::IsNullOrEmpty($sourceVolumeSnapshotPolicyName))
            {
                # Is the source volume hosted in an EDC?
                if($sourceVolumeSnapshotPolicyName -match "^clst_(.*)$")
                {
                    # LogInfo "Detected EDC snapshot policy..." 3

                    # Yes...remove clst_ from the front of the policy name...
                    $sourceVolumeSnapshotPolicyName = $Matches[1]
                } `
                else
                {
                    # Nothing, leave the policy name as it is.
                }

                # Is the snapshot policy on the destination volume "different" than the policy on the source?
                #    Does it NOT end with the snapshot policy?  "clst_snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained" -notmatch "snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained$"
                if($dstVolume.VolumeSnapshotAttributes.SnapshotPolicy -notmatch ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))
                {
                    # Yes, different policy...We need to make sure the destination cluster has the right snapshot policy available.

                    # Get any snapshot policy from the destination cluster with a name that matches the source volume's snapshot policy name...
                    $funcParams = @{
                        Controller = $dstVolume.NcController
                    }
                    $result = ReTryCatch -callee "Get-NcSnapshotPolicy" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $destinationSnapshotPolicies = @($result.ReturnValue | Where-Object { $_.Policy -match $sourceVolumeSnapshotPolicyName })

                        # Did we find a single match?
                        if($destinationSnapshotPolicies.Length -eq 1)
                        {
                            # The destination cluster has the right snapshot policy
                            # LogInfo ("{0} has correct snapshot policy: {1}" -f @($dstVolume.NcController.Identity, $destinationSnapshotPolicies[0].Policy)) 1
                        } `
                        elseif ($destinationSnapshotPolicies.Length -gt 1)
                        {
                            LogError ("{0} snapshot policies found which match {1} on {2}." -f @($destinationSnapshotPolicies.Length, ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $dstVolume.NCController.Identity)) 1
                            $destinationSnapshotPolicies.ForEach({
                                LogError ("{0}" -f @($_)) 2
                            })
                            LogError ("Please create snapshot policy on {0} and re-run the script." -f @($dstVolume.NCController.Identity)) 1
                            $data.Good2Go = $false
                        } `
                        else  # there was no matching snapshot policy found on the destination
                        {
                            LogError ("No snapshot policies found which match {0} on {1}." -f @(("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $dstnVolume.NcController.Identity)) 1
                            LogError ("Please create snapshot policy on {0} and re-run the script." -f @($dstVolume.NCController.Identity)) 1
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Failed to retrieve snapshot policies from {0}." -f @($dstVolume.NcController.Identity))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    # Nothing snapshot policy is ok.
                }
            } `
            else
            {
                LogError ("No snapshot policy set on source volume: {0}" -f @($data.NewSnapmirrors[$a].OriginalSourceVolume.Identity)) 1
                LogError "Correct issue and re-run script.." 1
                $data.Good2Go = $false
            }
            $b++
        }
        $a++
    }
}

function CheckVServerPeers
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        if($null -ne $data.Destination.VServer)
        {
            if(($null -ne $data.NewSnapmirrors) -and ($data.NewSnapmirrors.Count -gt 0))
            {
                LogInfo "Checking VServer peerings..."
                $funcParams = @{
                    Controller = $data.Destination.VServer.NcController
                    Template = $true
                }
                $result = ReTryCatch -callee "Get-NcVserverPeer" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    # Get the VServer peerings for the destination VServer
                    $vServerPeerQueryTemplate = $result.ReturnValue[0]

                    if($null -ne $vServerPeerQueryTemplate)
                    {
                        $vServerPeerQueryTemplate.Applications = @("snapmirror")
                        $vServerPeerQueryTemplate.VserverUuid = $data.Destination.VServer.Uuid

                        $funcParams = @{
                            Controller = $data.Destination.VServer.NcController
                            Query = $vServerPeerQueryTemplate
                        }
                        $result = ReTryCatch -callee "Get-NcVserverPeer" -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            $destinationVServerPeers = $result.ReturnValue

                            if($destinationVServerPeers.Length -gt 0)
                            {
                                $a = 0
                                while($a -lt $data.NewSnapmirrors.Count)
                                {
                                    $b = 0
                                    while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                                    {
                                        if($null -ne ($destinationVServerPeers | Where-Object { $_.PeerVserverUuid -eq $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VolumeIdAttributes.OwningVserverUuid }))
                                        {
                                            # VServer peering between the requested destination VServer and the snapmirror destination VServer is intact
                                        } `
                                        else
                                        {
                                            LogError ("Missing VServer peering from {0} to {1}:{2}." -f @($data.Destination.VServer.Identity, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NcController.Name, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver))
                                            $data.Good2Go = $false
                                        }
                                        $b++
                                    }
                                    $a++
                                }
                            } `
                            else
                            {
                                LogError ("No VServer peers found for {0}." -f @($data.Destination.VServer.Identity))
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError ("Failed to retrieve VServer peers for: {0}" -f @($data.Destination.VServer.Identity))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Null VServer peer query template returned from {0}" -f @($data.Destination.VServer.NcController.Identity))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to create VServer peer query template from {0}." -f @($data.Destination.VServer.NcController.Identity))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "New snapmirror relationships are not available.  Please build new snapmirror relationship objects prior to checking VServer peerings."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogError "Destination VServer is not available.  Please collect VServer data prior to checking VServer peerings."
            $data.Good2Go = $false
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function Initialize
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName,

        [Parameter(Mandatory=$false,Position=2)]
        [String[]]
        $VolumesToInclude,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $firstPass
    )

    <#
        Initialize:
            Collects all relevant information required to fail over file services from one VServer to another.
            Verifies all requirements are met (as best I can -- I hope I didn't miss anything)
                Snapshot policies
                Snapmirror policies
                    - I assume the policy has a schedule.
    #>

    LogInfo "Collecting data..."

    # Wish more people understood classes ... $data should be a class ...
    $data = "" | Select-Object RelatedControllers, Source, Destination, Snapmirrors, SnapmirrorDestinations, Good2Go, NewSnapmirrors, NFSDatastores, DatastoreToVMHosts, AllVolumes, AllVServers, FirstPass, ActionSequence, ServicePrincipalNames, CNAMERecords, MigrateAllVolumes
    $data.Good2Go = $true    # This will flip when something is awry.
    $data.AllVolumes = $null
    $data.AllVServers = $null
    $data.RelatedControllers = [System.Collections.Generic.List[System.Object]]::new()
    $data.Source = "" | Select-Object VServer, CIFSServer, CIFSShares, IsNFSHost, NetworkInterfaces
    $data.Source.NetworkInterfaces = $null
    $data.Source.IsNFSHost = $false
    $data.Destination = "" | Select-Object VServer, CIFSServer, CIFSShares, IsNFSHost, NetworkInterfaces
    $data.Destination.NetworkInterfaces = $null
    $data.Destination.IsNFSHost = $false
    $data.Snapmirrors = $null
    $data.NFSDatastores = $null
    $data.MigrateAllVolumes = $true

    # Not really implementing action sequences yet, but putting some of the ground work in...
    #    For now, we are never on the first pass...
    $data.FirstPass = $false
    $data.ActionSequence = [System.Collections.Generic.List[System.Object]]::new()

    if(($null -eq $Global:cDot) -or ($Global:cDot.Count -eq 0))
    {
        LogInfo "Connecting to ONTAP clusters..."
        ConnectTo cdot
    } `
    else
    {
        # Nothing, already connected to ONTAP clusters
    }
    LogInfo ("Connected to {0} ONTAP cluster(s)." -f @($Global:cDot.Count))

    try
    {
        $data.Good2Go = ($null -ne $Global:cDot) -and ($Global:cDot -is [System.Collections.Generic.SortedDictionary[[System.String],[NetApp.Ontapi.Filer.C.NcController]]]) -and ($Global:cDot.Count -gt 0)
    }
    catch
    {
        LogException "Failed to determine connectivity to ONTAP clusters."
        $data.Good2Go = $false
    }

<#
    NOTE: All of the ensuing functions will check the status of $data.Good2Go prior to going any further...
        I considered letting the data collection/validation functions continue processing but decided against it.
        There are to many dependency on the data collected prior to a function.  I felt like too many false positives would
        be reported so I'll just error on the side of caution and quit when an error is present.
#>

<#  NOTE TO SELF:  Man, $data REALLY needs to be a class.  All this passing of $data to functions SCREAMS, "MAKE ME A CLASS!"  -- It's getting hard to ignore!! #>

    GetVServerData -data $data -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName

    $VolumesToInclude = FixVolumesToInclude -data $data -VolumesToInclude $VolumesToInclude

    GetVolumesData -data $data -VolumesToInclude $VolumesToInclude

    GetSnapmirrorDestinations -data $data -VolumesToInclude $VolumesToInclude

    # After this, we will not need to issue queries to all ONTAP controllers since we now have a list of all controllers involved in the fail over.
    GetRelatedControllers -data $data

    GetSnapmirrors -data $data

    GetCIFSData -data $data

    GetADData -data $data

    # NFS/VMware functionality isn't complete yet...
    GetNFSData -data $data

    BuildNewSnapmirrorRelationships -data $data

    FixupNewSnapmirrors -data $data

    CheckSnapmirrorPolicies -data $data

    CheckSnapshotPolicies -data $data

    CheckVServerPeers -data $data

    return $data
}

function ShowCIFSData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [System.Object]
        $cifsData,

        [Parameter(Mandatory=$true, Position=2)]
        [ConsoleColor]
        $color
    )

    $otherCIFSData = $data.Destination
    if($cifsData -eq $data.Destination)
    {
        $otherCIFSData = $data.Source
    } `
    else
    {
        # Nothing
    }

    if($null -ne $cifsData.CIFSServer)
    {
        Write-Host -NoNewline -ForegroundColor Gray "`tCIFS Server: "
        Write-Host -NoNewline -ForegroundColor $color $cifsData.CIFSServer.CifsServer
        Write-Host -NoNewline -ForegroundColor Gray "`tStatus: "
        Write-Host -NoNewline -ForegroundColor $color $cifsData.CIFSServer.AdministrativeStatus
        Write-Host -NoNewline -ForegroundColor Gray "`tDomain: "
        Write-Host -NoNewline -ForegroundColor $color $cifsData.CIFSServer.Domain
        Write-Host -NoNewline -ForegroundColor Gray "`tShares: "
        Write-Host -ForegroundColor $color $cifsData.CIFSShares.Length
        $shareNameMaxLength = (@($cifsData.CIFSShares | Select-Object -ExpandProperty ShareName) | Measure-Object -Maximum Length).Maximum + 3
        $pathMaxLength = (@($cifsData.CIFSShares | Select-Object -ExpandProperty Path) | Measure-Object -Maximum Length).Maximum + 3
        $volumeNameMaxLength = (@($cifsData.CIFSShares | Select-Object -ExpandProperty Volume) | Measure-Object -Maximum Length).Maximum + 3
        $shareFormat = "`t`t{{0,-{0}}}   {{1,-{1}}}   {{2,-{2}}}" -f @($shareNameMaxLength, $pathMaxLength, $volumeNameMaxLength)
        Write-Host -ForegroundColor Gray ($shareFormat -f @("Name","Path","Volume"))
        $cifsData.CIFSShares.Foreach({
            $shareName = $_.ShareName
            $otherShare = $otherCIFSData.CIFSShares | Where-Object { $_.ShareName -eq $shareName }
            Write-Host -NoNewline -ForegroundColor $color ($shareFormat -f @($_.ShareName, $_.Path, $_.Volume))
            if($null -eq $otherShare)
            {
                Write-Host -NoNewline -ForegroundColor Red "Missing on "
                if($cifsData -eq $data.Source)
                {
                    Write-Host -NoNewline -ForegroundColor Red "destination"
                } `
                else
                {
                    Write-Host -NoNewline -ForegroundColor Red "source"
                }
                Write-Host -NoNewline -ForegroundColor Red " CIFS server."
            }
            Write-Host
        })
    } `
    else
    {
        # Nothing, no CIFS Server data...
    }
}

function ShowData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    $srcColor = [ConsoleColor]::Cyan
    $dstColor = [ConsoleColor]::Green

    Write-Host "`r`nNOTE:"
    Write-Host -ForegroundColor $srcColor ("`t{0} represents original source data" -f @($srcColor.ToString()))
    Write-Host -ForegroundColor $dstColor ("`t{0} represents original destination data`r`n" -f @($dstColor.ToString()))

    $color = [System.ConsoleColor]::Green
    Write-Host -NoNewline -ForegroundColor Gray "Good2Go: "
    if(-not $data.Good2Go)
    {
        $color = [ConsoleColor]::Red
    }
    Write-Host -ForegroundColor $color $data.Good2Go
    Write-Host -NoNewline -ForegroundColor Gray "Source VServer: "
    Write-Host -ForegroundColor $srcColor $data.Source.VServer.Identity
    if($null -ne $data.Source.CIFSServer)
    {
        ShowCIFSData $data $data.Source $srcColor
    } `
    else
    {
        # Nothing, no CIFS Server data...
    }
    Write-Host -NoNewline -ForegroundColor Gray "`tNFS Host: "
    Write-Host -ForegroundColor $srcColor $data.Source.IsNFSHost

    Write-Host ("`r`nService Principal Names to be transferred from: {0} to {1}" -f @($data.Source.CIFSServer.CifsServer, $data.Destination.CIFSServer.CifsServer))
    $data.ServicePrincipalNames.ForEach({
        Write-Host ("`t{0}" -f @($_))
    })

    Write-Host ("`r`nAliases (CNAME records) to be transferred from: {0} to {1}" -f @($data.Source.CIFSServer.CifsServer, $data.Destination.CIFSServer.CifsServer))
    $data.CNAMERecords.ToArray().ForEach({
        Write-Host ("`t{0}" -f @($_.HostName))
    })

    Write-Host -NoNewline -ForegroundColor Gray "`r`nCurrent Snapmirrors: "
    Write-Host -ForegroundColor $srcColor $data.Snapmirrors.Count
    $dstMaxLength = (@($data.Snapmirrors | Select-Object -ExpandProperty DestinationLocation) | Measure-Object -Maximum Length).Maximum + 3
    $dstFormat = "{{0,-{0}}}" -f @($dstMaxLength)
    $policyMaxLength = (@($data.Snapmirrors | Select-Object -ExpandProperty Policy) | Measure-Object -Maximum Length).Maximum + 3
    $policyFormat = "{{0,-{0}}}" -f @($policyMaxLength)
    $statusMaxLength = (@($data.Snapmirrors | Select-Object -ExpandProperty Status) | Measure-Object -Maximum Length).Maximum + 3
    $statusFormat = "{{0,-{0}}}" -f @($statusMaxLength)
    $mirrorstateMaxLength = (@($data.Snapmirrors | Select-Object -ExpandProperty MirrorState) | Measure-Object -Maximum Length).Maximum + 3
    $mirrorstateFormat = "{{0,-{0}}}" -f @($mirrorstateMaxLength)
    $smSourceGroups = $data.Snapmirrors | Sort-Object SourceLocation | Group-Object SourceLocation
    $smSourceGroups.ForEach({
        Write-Host -NoNewline -ForegroundColor Gray "`tSource: "
        Write-Host -ForegroundColor $srcColor ("{0}" -f @($_.Name))
        ($_.Group | Sort-Object DestinationLocation).ForEach({
            $destinationMark = " "
            if($_.DestinationVserver -eq $data.Destination.VServer.VserverName) { $destinationMark = "*" } else { <# Nothing #> }
            Write-Host -NoNewline -ForegroundColor Gray ("`t`t{0}Destination: " -f @($destinationMark))
            Write-Host -NoNewline -ForegroundColor $dstColor ($dstFormat -f @($_.DestinationLocation))
            Write-Host -NoNewline -ForegroundColor Gray "Snapmirror Policy: "
            Write-Host -NoNewline -ForegroundColor $dstColor ($policyFormat -f @($_.Policy))
            Write-Host -NoNewline -ForegroundColor Gray "Status: "
            Write-Host -NoNewline -ForegroundColor $dstColor ($statusFormat -f @($_.Status))
            Write-Host -NoNewline -ForegroundColor Gray "Mirror State: "
            Write-Host -ForegroundColor $dstColor ($mirrorstateFormat -f @($_.MirrorState))
        })
    })
    Write-Host "`r`n`t* = Failover destination"

    Write-Host -NoNewline -ForegroundColor Gray "`r`nDestination VServer: "
    Write-Host -ForegroundColor $dstColor $data.Destination.VServer.Identity
    if($null -ne $data.Destination.CIFSServer)
    {
        ShowCIFSData $data $data.Destination $dstColor
    } `
    else
    {
        # Nothing, no CIFS Server data...
    }
    Write-Host ("`tNFS Host: {0}" -f @($data.Destination.IsNFSHost))

    Write-Host ("`r`nNew Snapmirrors ({0}):" -f @(@($data.NewSnapmirrors | Foreach-Object { $_.Relationships | Select-Object Policy }).Length))
    $srcMaxLength = ($data.NewSnapmirrors.SourceVolume.Identity | Measure-Object -Maximum Length).Maximum + "Destination: ".Length
    $dstMaxLength = ($data.NewSnapmirrors.Relationships.DestinationVolume.Identity | Measure-Object -Maximum Length).Maximum + 3

    $dstFormat = "{{0,-{0}}}" -f @($dstMaxLength)

    # For the record, I don't like the following line, but it works...
    $dstSMPMaxLength = ($data.NewSnapmirrors.Relationships.Snapmirror.Policy | Measure-Object -Maximum Length).Maximum + 3
    $dstSMPFormat = "{{0,-{0}}}" -f @($dstSMPMaxLength)

    $srcMaxLength += ($dstSMPMaxLength + "Snapmirror Policy: ".Length + 3)
    $srcFormat = "{{0,-{0}}}" -f @($srcMaxLength)

    $data.NewSnapmirrors.ToArray().ForEach({
        Write-Host -NoNewline -ForegroundColor Gray "`tSource: "
        Write-Host -NoNewline -ForegroundColor $dstColor ($srcFormat -f @($_.SourceVolume.Identity))
        Write-Host -NoNewline -ForegroundColor Gray "Snapshot Policy: "
        Write-Host -ForegroundColor $dstColor ("{0}" -f @($_.SourceVolume.VolumeSnapshotAttributes.SnapshotPolicy))
        $_.Relationships.ToArray().ForEach({
            $color = $dstColor
            if($_.DestinationVolume.Identity -match $data.Source.VServer.Identity)
            {
                $color = $srcColor
            } `
            else
            {
                # Source object in Blue, others in Green
            }
            Write-Host -NoNewline -ForegroundColor Gray "`t`tDestination: "
            Write-Host -NoNewline -ForegroundColor $color ($dstFormat -f @($_.DestinationVolume.Identity))
            Write-Host -NoNewline -ForegroundColor Gray ("Snapmirror Policy: ")
            Write-Host -NoNewline -ForegroundColor $color ($dstSMPFormat -f @($_.Snapmirror.Policy))
            Write-Host -NoNewline -ForegroundColor Gray ("Snapshot Policy: ")
            Write-Host -ForegroundColor $color ("{0}" -f @($_.DestinationVolume.VolumeSnapshotAttributes.SnapshotPolicy))
            if($_.Datastores.Length -gt 0)
            {
                Write-Host -ForegroundColor Gray "`t`t`tDatastores: "
                ($_.Datastores | Sort-Object Name).Foreach({
                    Write-Host -ForegroundColor $color ("`t`t`t`t{0}" -f @($_.Name))
                    if($data.DatastoreToVMHosts[$_.Identity].Count -gt 0)
                    {
                        Write-Host -ForegroundColor Gray "`t`t`t`t`tConnected hosts:"
                        ($data.DatastoreToVMHosts[$_.Identity] | Sort-Object Name).ForEach({
                            Write-Host -ForegroundColor $color ("`t`t`t`t`t`t{0}`tPowerState: {1}`tState: {2}" -f @($_.Name.Replace(".powereng.com",""), $_.PowerState, $_.ConnectionState) )
                        })
                    }
                })
            } `
            else
            {
                # Nothing, no datastores to list
            }
        })
        Write-Host
    })
}

function ShutdownCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer
    )

    $good2Go = $true
    LogInfo ("Stopping CIFS services on: {0}~SIMULATED~" -f @($cifsServer.Identity)) 1
    if($Script:TakeAction)
    {
        $funcParams = @{
            Controller = $cifsServer.NcController
            VserverContext = $cifsServer.Vserver
            Confirm = $false
        }
        $result = ReTryCatch -callee "Stop-NcCifsServer" -funcParameters $funcParams
        if($result.Good2Go)
        {
            # Wait for the CIFS service to be down...
            LogInfo ("Waiting for CIFS server {0} to be off-line.~SIMULATED~" -f @($cifsServer.Identity)) 1 -NoNewLine
            $cifsServerDown = $false
            do
            {
                $funcParams = @{
                    Controller = $cifsServer.NcController
                    VserverContext = $cifsServer.Vserver
                }
                $result = ReTryCatch -callee "Get-NcCifsServer" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $t_cifsServer = $result.ReturnValue[0]
                    if($null -ne $t_cifsServer)
                    {
                        if(-not $Script:TakeAction)
                        {
                            $cifsServerDown = $true
                        } `
                        else
                        {
                            $cifsServerDown = ($t_cifsServer.AdministrativeStatus -eq "down")
                        }

                        if(-not $cifsServerDown)
                        {
                            LogInfo "." -NoNewLine
                            # Pause a moment for station identification...
                            Start-Sleep -Seconds 5
                        } `
                        else
                        {
                            # Nothing, no need to pause...
                        }
                    } `
                    else
                    {
                        LogError ("Failed to retrieve CIFS server data from {0}" -f @($cifsServer.Identity)) 1 -NewLine
                        $good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to retrieve CIFS server data from {0}" -f @($cifsServer.Identity)) 1 -NewLine
                    $good2Go = $false
                }
            } until ((-not $Script:TakeAction) -or (-not $good2Go) -or $cifsServerDown)
            LogInfo ""
        } `
        else
        {
            LogError ("Failed to stop CIFS services on {0}" -f @($cifsServer.Identity)) 1
            $good2Go = $false
        }
    } `
    else
    {
        # Nothing running in simulation mode.
    }

    return $good2Go
}

function StopFileServices
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    <# Step 1: Stop file services on the source to prevent additional changes to source volumes.
        For CIFS: Stop the CIFS server
        For NFS: (not yet complete -- or even really started.)
            For linux NFS mounted volumes
                ???  TODO
                Presumably these would be linux VMs which would themselves be failed over.
                Shutdown services consuming the NFS mount
                Modify fstab file to use the 'new source volume'
                Shutdown the linux host
                    When the linux host is restarted after failing over, the volume for the NFS mount should be available
            For datastore volumes:
                1a. Shutdown VMs stored on datastores
                1b. Remove VMs from source inventory
                1c. Unmount datastore volumes
    #>

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
            # We are creating the action sequence...
        } `
        else
        {
            # We are working off the action sequence.... eventually...

            # If there is a source CIFS server and it's not down, make it down...
            if($null -ne $data.Source.CIFSServer)
            {
                <# Step 1: Stop CIFS services on the source VServer.  This is to ensure the snapmirror update process send all the latest changes to the destination volume.
                    #Stop SMB service at current source
                    vserver cifs stop -vserver LAB-SMB02

                    Where we shutdown the source CIFS server at the start (to avoid more changes on the volumes), we'll wait until the end to start the destination
                        CIFS server (if it's not already up)
                #>
                # This line does not need to be wrapped in the $Script:TakeAction check... that check is in ShutdownCIFSServer
                if($data.Source.CIFSServer.AdministrativeStatus -ne "down")
                {
                    $data.Good2Go = ShutdownCIFSServer -data $data -cifsServer $data.Source.CIFSServer
                }
                else
                {
                    LogInfo ("CIFS server already shutdown on {0}." -f @($data.Source.CIFSServer.Identity))
                }
            } `
            else
            {
                # Nothing, no source CIFS server
            }

            if($data.Source.IsNFSHost)
            {
                # For now, nothing, but here, we'd potentially handle VMware datastores...
                LogWarning ("{0} is an NFS host!  However, NFS failover is incomplete in this version of the script." -f @($data.Source.VServer.Identity))
            } `
            else
            {
                # Nothing, no NFS services to worry about.
            }
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function WaitForSnapmirrorStatusAndMirrorState
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $statuses2WaitFor,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $mirrorStates2WaitFor
    )

    $tmpSnapmirror = $null
    $good2Go = $true

    # Now, wait until the snapmirror is $status2WaitFor...
    $haveWaited = $false
    do
    {
        $funcParams = @{
            Controller = $snapmirror.NcController
            DestinationVserver = $snapmirror.DestinationVserver
            DestinationVolume = $snapmirror.DestinationVolume
        }
        $result = ReTryCatch -callee "Get-NCSnapmirror" -funcParameters $funcParams
        if($result.Good2Go)
        {
            # Refresh the snapmirror info to see if its idle...
            $tmpSnapmirror = $result.ReturnValue[0]
            if($null -ne $tmpSnapmirror)
            {
                if($Script:TakeAction -and (($tmpSnapmirror.Status -notin $statuses2WaitFor) -or ($tmpSnapmirror.MirrorState -notin $mirrorStates2WaitFor)))
                {
                    if(-not $haveWaited)
                    {
                        LogInfo ("Waiting for snapmirror to be status: [{0}] / mirror state: [{1}] (CTRL-C to abort script)." -f @(($statuses2WaitFor -join "|"), ($mirrorStates2WaitFor -join "|"))) 2 -NoNewLine
                    } `
                    else
                    {
                        LogInfo "." -NoNewLine
                    }
                    # Pause a moment for station identification...
                    Start-Sleep -Seconds 5
                    $haveWaited = $true
                } `
                else
                {
                    # Nothing, snapmirror is good to go...
                }
            } `
            else
            {
                LogError ("Failed to refresh snapmirror object while waiting for status: [{0}] / mirror state: [{1}]." -f @(($statuses2WaitFor -join "|"), ($mirrorStates2WaitFor -join "|"))) 2 -NoNewLine
                $good2Go = $false
            }
        } `
        else
        {
            LogError ("Failed to refresh snapmirror object while waiting for status: {0} / mirror state: {1}" -f @($status2WaitFor, $mirrorState2WaitFor)) 2 -NewLine
            $good2Go = $false
        }
    } until((-not $Script:TakeAction) -or (-not $good2Go) -or (($tmpSnapmirror.Status -in $statuses2WaitFor) -and ($tmpSnapmirror.MirrorState -in $mirrorStates2WaitFor)))
    if($haveWaited)
    {
        LogInfo ""
    } `
    else
    {
        # Nothing
    }

    return @($good2Go, $tmpSnapmirror)
}

function UpdateSnapmirror
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = $true

    # If we are running in simulation mode, the following line ensures UpdateSnapmirror returns a non-null value for $tmpSM
    $tmpSM = $snapmirror

    LogInfo ("Updating snapmirror: {0}...~SIMULATED~" -f @($snapmirror.Identity)) 1 -NewLine

    if($Script:TakeAction)
    {
        # Make sure the snapmirror is idle/snapmirrored before issuing the update command...
        $good2Go, $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $snapmirror -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored")

        <#
            $actionParameters = @{
                Controller = $snapmirror.NcController.Name
                DestinationVserver = $snapmirror.DestinationVserver
                DestinationVolume = $snapmirror.DestinationVolume
                PassThru = $true
            }
            $action = NewActionSequenceAction -actionSequence $actionSequence -actionFunction "Invoke-NcSnapmirrorUpdate" -actionParameters $actionParameters
            $result = PerformAction -action $action
        #>

        if($good2Go)
        {
            $funcParams = @{
                Controller = $snapmirror.NcController
                DestinationVserver = $snapmirror.Vserver
                DestinationVolume = $snapmirror.DestinationVolume
                Passthru = $true
            }
            $result = ReTryCatch -callee "Invoke-NcSnapmirrorUpdate" -funcParameters $funcParams
            if($result.Good2Go)
            {
                $tmpSM = $result.ReturnValue[0]
                if($null -ne $tmpSM)
                {
                    $good2Go, $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $tmpSM -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored")
                } `
                else
                {
                    LogError "No snapmirror object returned after invoking snapmirror update." 2
                    $good2Go = $false
                }
            } `
            else
            {
                LogError ("Failed to update snapmirror {0}" -f @($snapmirror.Identity))
                $good2Go = $false
            }
        } `
        else
        {
            # Nothing, already displayed a message
        }
    } `
    else
    {
        # Nothing, just pretending...
    }

    if(-not $good2Go)
    {
        $tmpSM = $null
    } `
    else
    {
        # Nothing, leave $tmpSM as is.
    }

    return @($good2Go, $tmpSM)
}

function BreakSnapmirror
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    LogInfo ("Breaking snapmirror {0}...~SIMULATED~" -f @($snapmirror.Identity)) 1

    # Make sure the snapmirror is idle/snapmirrored|broken-off before proceeding (we won't break snapmirrors which are already broken off)...
    $good2Go, $tSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $snapmirror -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored","broken-off")

    if($good2Go)
    {
        # Update the snapmirror with the object returned from WaitForSnapmirrorStatusAndMirrorState
        $snapmirror = $tSM
        if($snapmirror.MirrorState -ne "broken-off")
        {
            if($Script:TakeAction)
            {
                $funcParams = @{
                    Controller = $snapmirror.NcController
                    DestinationVserver = $snapmirror.Vserver
                    DestinationVolume = $snapmirror.DestinationVolume
                    Confirm = $false
                    Passthru = $true
                }
                $result = ReTryCatch -callee "Invoke-NcSnapmirrorBreak" -funcParameters $funcParams -maxTries 5 -secondsToPause 10
                if($result.Good2Go)
                {
                    $tSM = $result.ReturnValue[0]
                    if($null -ne $tSM)
                    {
                        $snapmirror = $tSM
                    } `
                    else
                    {
                        LogError "No snapmirror object returned after invoking snapmirror break." 2
                        $good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to break snapmirror {0}." -f @($snapmirror.Identity))
                    $good2Go = $false
                }
            } `
            else
            {
                # Nothing, just pretending...
            }
        } `
        else
        {
            LogInfo "Snapmirror was already broken-off." 1
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    return @($good2Go, $snapmirror)
}

function UpdateSnapshotPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=2)]
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

    LogInfo "Checking snapshot policy..." 1
    # Is there a snapshot policy set on the source volume?
    # Capture the source volume's snapshot policy in a variable so we can manipulate it...
    $sourceVolumeSnapshotPolicyName = $sourceVolume.VolumeSnapshotAttributes.SnapshotPolicy
    if(-not [String]::IsNullOrEmpty($sourceVolumeSnapshotPolicyName))
    {
        # Is the source volume hosted in an EDC?
        if($sourceVolumeSnapshotPolicyName -match "^clst_(.*)$")
        {
            LogInfo "Detected EDC snapshot policy..." 2

            # Yes...remove clst_ from the front of the policy name...
            $sourceVolumeSnapshotPolicyName = $Matches[1]
        } `
        else
        {
            # Nothing, leave the policy name as it is.
        }

        # Is the snapshot policy on the destination volume "different" than the policy on the source?
        #    Does it NOT end with the snapshot policy?  "clst_snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained" -notmatch "snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained$"
        if($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy -notmatch ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))
        {
            # Yes, different policy...
            LogInfo ("Snapshot policies are different...") 2
            LogInfo ("Source volume snapshot policy: {0}" -f @($sourceVolumeSnapshotPolicyName)) 3
            LogInfo ("Destination volume snapshot policy: {0}" -f @($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 3

            LogInfo "Getting snapshot policies from the destination cluster which match the source volume snapshot policy" 2
            # Get any snapshot policy from the destination cluster with a name that matches the source volume's snapshot policy name...
            $funcParams = @{
                Controller = $destinationVolume.NcController
            }
            $result = ReTryCatch -callee "Get-NcSnapshotPolicy" -funcParameters $funcParams
            if($result.Good2Go)
            {
                $destinationSnapshotPolicies = @($result.ReturnValue | Where-Object { $_.Policy -match $sourceVolumeSnapshotPolicyName })

                # Did we find a single match?
                if($destinationSnapshotPolicies.Length -eq 1)
                {
                    # Yes, use it for the snapshot policy on the destination volume.
                    $destinationSnapshotPolicyName = $destinationSnapshotPolicies[0].Policy
                    LogInfo ("Using destination snapshot policy: {0}" -f @($destinationSnapshotPolicyName)) 3

                    $funcParams = @{
                        Controller = $destinationVolume.NcController
                        Template = $true
                    }
                    $result = ReTryCatch -callee "Get-NCVol" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        # Set up a query object to ensure we update the correct destination volume.
                        $queryObj = $result.ReturnValue[0]

                        Initialize-NcObjectProperty -Object $queryObj -Name VolumeIdAttributes
                        $queryObj.VolumeIdAttributes.Uuid = $destinationVolume.VolumeIdAttributes.Uuid

                        # I can reuse $funcParams ...
                        $result = ReTryCatch -callee "Get-NCVol" -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            # Set up a volume update object to set the snapshot policy
                            $updateObj = $result.ReturnValue[0]
                            Initialize-NcObjectProperty -Object $updateObj -Name VolumeSnapshotAttributes
                            $updateObj.VolumeSnapshotAttributes.SnapshotPolicy = $destinationSnapshotPolicyName

                            LogInfo ("Sending volume update command to update snapshot policy...~SIMULATED~") 3
                            if($Script:TakeAction)
                            {
                                $funcParams = @{
                                    Controller = $destinationVolume.NcController
                                    Query = $queryObj
                                    Attributes = $updateObj
                                }
                                $result = ReTryCatch -callee "Update-NcVol" -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    $updateResult = $result.ReturnValue[0]

                                    if($null -ne $updateResult)
                                    {
                                        if($updateResult.SuccessList.Length -gt 0)
                                        {
                                            LogInfo "Updated snapshot policy on:" 3
                                            $updateResult.SuccessList.Foreach({
                                                LogInfo ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                                            })
                                        } `
                                        else
                                        {
                                            # Shouldn't have to do anything here... the next block should cover it...BUT... just to make sure, we'll set $good2Go = $false since there weren't any successes.
                                            $good2Go = $false
                                        }

                                        if($updateResult.FailureList.Length -gt 0)
                                        {
                                            LogError "Failed to update snapshot policy on:" 3
                                            $updateResult.FailureList.Foreach({
                                                LogError ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                                            })
                                            $good2Go = $false
                                        } `
                                        else
                                        {
                                            # Nothing... all might be good depending on the SuccessList.
                                        }
                                    } `
                                    else
                                    {
                                        LogWarning "No result object returned after updating snaphot policy." 3
                                        Logwarning "Please verify manually!"
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to set snapshot policy to {0} on {1}." -f @($destinationSnapshotPolicyName, $destinationVolume.Identity)) 3
                                    $good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, just a simulation run.
                            }
                        } `
                        else
                        {
                            LogError ("Failed to create volume update template from {0}." -f @($destinationVolume.NcController.Identity))
                            $good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Failed to create volume query template from {0}." -f @($destinationVolume.NcController.Identity))
                        $good2Go = $false
                    }
                } `
                elseif ($destinationSnapshotPolicies.Length -gt 1)
                {
                    LogWarning ("{0} snapshot policies found which match: {1}." -f @($destinationSnapshotPolicies.Length, ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))) 3
                    $destinationSnapshotPolicies.ForEach({
                        LogWarning ("{0}" -f @($_)) 4
                    })
                    LogWarning ("Please update manually!")
                } `
                else  # there was no matching snapshot policy found on the destination
                {
                    LogError ("No snapshot policies found which match: {0} on {1}." -f @(("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $destinationVolume.NcController.Name)) 3
                    LogError "Please update manually!"
                }
            } `
            else
            {
                LogError ("Failed to retrieve snapshot policies from {0}." -f @($destinationVolume.NcController.Identity))
                $good2Go = $false
            }
        } `
        else
        {
            LogInfo ("Source volume snapshot policy: {0} seems to match {1}.  No changes needed." -f @($sourceVolumeSnapshotPolicyName, $destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 2
        }
    } `
    else
    {
        LogWarning ("No snapshot policy found on source volume: {0}" -f @($sourceVolume.Identity)) 2
        LogWarning "Ensure you check snapshot policies." 2
    }

    return $good2Go
}

function UpdateVolumeEfficiencySettings
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume
    )

    $good2Go = $true
    LogInfo ("Checking status of storage efficiency for: {0}..." -f @($volume.Identity)) 1
    $funcParams = @{
        Controller = $volume.NcController
        VserverContext = $volume.VServer
        Name = $volume.Name
    }
    $result = ReTryCatch -callee "Get-NcSis" -funcParameters $funcParams
    if($result.Good2Go)
    {
        <# Step 5a: Update volume efficiency settings on the destination volume.
            #Enable/update storage efficiency on new source
            --> vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
        #>

        $volSIS = $result.ReturnValue[0]

        # If Get-NCSis returns a null value, then storage efficiencies are not enabled.
        $volSISEnabled = ($null -eq $volSIS) -or ($volSIS.State -eq "enabled")
        if(-not $volSISEnabled)
        {
            # Not enabled, so let's enable it...
            LogInfo ("Storage efficiency not enabled.  Enabling it.~SIMULATED~") 2
            if($Script:TakeAction)
            {
                # I can reuse $funcParams ...
                $result = ReTryCatch -callee "Enable-NcSis" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    LogInfo "Verifying storage efficiency was enabled..." 2 -NoNewline
                    # Again, I can reuse $funcParams...
                    $result = ReTryCatch -callee "Get-NcSis" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $volSIS = $result.ReturnValue[0]
                        if($volSIS.State -eq "enabled")
                        {
                            LogInfo "Success"
                        } `
                        else
                        {
                            LogError "Failed"
                            $good2Go = $false
                        }
                    } `
                    else
                    {
                        LogError ("Failed to verify if storage efficiency was enabled on: {0}." -f @($volume.Identity)) -NewLine
                        $good2Go = $false
                    }
                }
                else
                {
                    LogError ("Failed to enable storage efficiency on: {0}." -f @($volume.Identity))
                    $good2Go = $false
                }
            } `
            else
            {
                # Nothing, just pretending.
            }
        } `
        else
        {
            LogInfo "Storage efficiency already enabled." 2
        }

        if($Script:TakeAction)
        {
            # Need to recheck $volSIS.State since we may have enabled it above.
            if($volSIS.State -eq "enabled")
            {
                <# Step 5b: Update volume efficiency settings on the destination volume.
                    #Enable/update storage efficiency on new source
                        vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                    --> vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                #>
                $funcParams = @{
                    Controller = $volume.NcController
                    VserverContext = $volume.VServer
                    Name = $volume.Name
                    Compression = $true
                    InlineCompression = $true
                    Policy = "default"
                }
                $result = ReTryCatch -callee "Set-NcSis" -funcParameters $funcParams
                if($result.Good2Go)
                {
                    # Nothing, efficiency setting in place
                } `
                else
                {
                    LogError ("Failed to set storage efficiency settings on: {0}." -f @($volume.Identity))
                    $good2Go = $false
                }
            } `
            else
            {
                # Nothing, would have already alerted user.
            }
        } `
        else
        {
            # Nothing, just pretending.
        }
    } `
    else
    {
        LogError ("Failed to get storage efficiency setting for: {0}." -f @($volume.Identity))
        $good2Go = $false
    }

    if(-not $good2Go)
    {
        LogWarning "Manually update storage efficiencies as required." 3
    } `
    else
    {
        # Nothing
    }
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
    # LogInfo ("Refreshing snapmirror data for {0}..." -f @($snapmirror.Identity))
    $funcParams = @{
        Controller = $snapmirror.NcController
        VserverContext = $snapmirror.Vserver
        SourceVserver = $snapmirror.SourceVserver
        SourceVolume = $snapmirror.SourceVolume
    }
    $result = ReTryCatch -callee "Get-NcSnapmirror" -funcParameters $funcParams
    if($result.Good2Go)
    {
        $snapmirror = $result.ReturnValue[0]
        if($null -ne $snapmirror)
        {
            if($Script:TakeAction)
            {
                # Make sure the snapmirror is in the desired state
                if($snapmirror.MirrorState -eq $desiredMirrorState)
                {
                    # Further, make sure the snapmirror status is $desiredStatus
                    if($snapmirror.Status -eq $desiredStatus)
                    {
                        # Nothing all good.
                    } `
                    else
                    {
                        LogError ("Snapmirror {0} has status {1}.  Expected: {2}." -f @($snapmirror.Identity, $snapmirror.MirrorState, $desiredStatus)) 1
                        $good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Snapmirror {0} has mirror state {1}.  Expected: {2}." -f @($snapmirror.Identity, $snapmirror.MirrorState, $desiredMirrorState)) 1
                    $good2Go = $false
                }
            } `
            else
            {
                # Nothing, just pretending, so return $true
            }
        } `
        else
        {
            LogError ("Failed to refresh snapmirror data for {0}.  (`$null returned)" -f @($snapmirror.Identity))
            $good2Go = $false
        }
    } `
    else
    {
        LogError ("Failed to refresh snapmirror data for {0}." -f @($snapmirror.Identity))
        $good2Go = $false
    }

    return $good2Go
}

function DeleteSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus "idle"

    if($good2Go)
    {
        LogInfo ("Removing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
        if($Script:TakeAction)
        {
            $funcParams = @{
                Controller = $snapmirror.NcController
                DestinationVolume = $snapmirror.DestinationVolume
                DestinationVserver = $snapmirror.DestinationVserver
                Confirm = $false
            }
            $result = ReTryCatch -callee "Remove-NcSnapmirror" -funcParameters $funcParams
            if($result.Good2Go)
            {
                # I can reuse $funcParams...sort of
                $funcParams.Remove("Confirm")

                $tSM = $null
                $tries = 0
                do
                {
                    $tries++
                    $result = ReTryCatch -callee "Get-NCSnapmirror" -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $tSM = $result.ReturnValue[0]

                        if(($null -ne $tSM) -and ($tries -lt $Script:maxOperationRetries))
                        {
                            # Snapmirror still exists, so pause a bit then try to confirm again.
                            Start-Sleep -Seconds $Script:actionRetriesWaitSeconds
                        } `
                        else
                        {
                            # Nothing either we've confirmed the snapmirror was deleted, or we tried enough...
                        }
                    } `
                    else
                    {
                        if($tries -eq $Script:maxOperationRetries)
                        {
                            LogError ("Failed to verify removal of snapmirror {0}." -f @($snapmirror.Identity))
                        } `
                        else
                        {
                            # Nothing... yet
                        }
                    }
                } while(($null -ne $tSM) -and ($tries -lt $Script:maxOperationRetries))

                $good2Go = ($null -eq $tSM)
                if($good2Go)
                {
                    # Nothing, we confirmed the snapmirror was deleted.
                } `
                else
                {
                    LogError ("Unable to confirm if snapmirror {0} was not removed.  It appears to still exist on the destination." -f @($snapmirror.Identity))
                }
            } `
            else
            {
                LogError ("Failed to remove snapmirror {0}." -f @($snapmirror.Identity)) 2
                $good2Go = $false
            }
        } `
        else
        {
            # Nothing, simulation only.
        }
    } `
    else
    {
        # Nothing, already displayed a nessage.
    }

    return $good2Go
}

function ReleaseSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = $true
    $snapmirrorReady = $true

    # First, confirm the snapmirror does not exist at the destination
    $funcParams = @{
        Controller = $snapmirror.NcController
        VserverContext = $snapmirror.Vserver
        DestinationVolume = $snapmirror.DestinationVolume
    }
    $result = ReTryCatch -callee "Get-NCSnapmirror" -funcParameters $funcParams
    if($result.Good2Go)
    {
        $snapmirrorReady = ($null -eq $result.ReturnValue[0]) -or (-not $Script:TakeAction)
        if($snapmirrorReady)
        {
            # Now, confirm the relationship DOES exist at the source
            $funcParams = @{
                Controller = $sourceVolume.NcController
                SourceVServer = $sourceVolume.Vserver
                SourceVolume = $sourceVolume.Name
                DestinationVserver = $snapmirror.DestinationVserver
                DestinationVolume = $snapmirror.DestinationVolume
            }
            $result = ReTryCatch -callee "Get-NCSnapmirrorDestination" -funcParameters $funcParams
            if($result.Good2Go)
            {
                $snapmirrorReady = ($null -ne $result.ReturnValue[0]) -or (-not $Script:TakeAction)
                if($snapmirrorReady)
                {
                    LogInfo ("Releasing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
                    if($Script:TakeAction)
                    {
                        # Release the snapmirror relationship at the source.
                        $funcParams = @{
                            Controller = $sourceVolume.NcController
                            SourceVserver = $sourceVolume.Vserver
                            SourceVolume = $sourceVolume.Name
                            DestinationVolume = $snapmirror.DestinationVolume
                            DestinationVserver = $snapmirror.DestinationVserver
                            RelationshipId = $snapmirror.RelationshipId
                            Confirm = $false
                        }
                        $result = ReTryCatch -callee "Invoke-NcSnapmirrorRelease" -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            # Confirm the snapmirror relationship was released.
                            # Reuse $funcParams with 2 changes...
                            $funcParams.Remove("Confirm")
                            $funcParams.Remove("RelationshipId")
                            $result = ReTryCatch -callee "Get-NCSnapmirrorDestination" -funcParameters $funcParams
                            if($result.Good2Go)
                            {
                                $good2Go = ($null -eq $result.ReturnValue[0])
                                if($good2Go)
                                {
                                    # Nothing, snapmirror relationship was released from the source...
                                } `
                                else
                                {
                                    LogError ("Snapmirror {0} relationship still exists at the source." -f @($snapmirror.Identity))
                                }
                            } `
                            else
                            {
                                LogError ("Failed to confirm snapmirror {0} was released." -f @($snapmirror.Identity))
                                $good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError ("Failed to release snapmirror {0} relationship at the source." -f @($snapmirror.Identity))
                            $good2Go = $false
                        }
                    } `
                    else
                    {
                        # Nothing, just faking it.
                    }
                } `
                else
                {
                    LogInfo ("Snapmirror {0} does not exist at the source." -f @($snapmirror.Identity))
                }
            } `
            else
            {
                LogError ("Failed to confirm relationship for {0} still exists at the source." -f @($snapmirror.Identity))
                $good2Go = $false
            }
        } `
        else
        {
            LogError ("Snapmirror {0} still exists at the destination." -f @($snapmirror.Identity))
            $good2Go = $false
        }
    } `
    else
    {
        LogError ("Failed to confirm snapmirror {0} has been deleted at the destination." -f @($snapmirror.Identity))
        $good2Go = $false
    }

    return $good2Go
}

function CreateSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $dstVolume,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [String]
        $snapmirrorPolicyName
    )

    $good2Go = $true
    $newSnapmirror = $null

    if($data.Good2Go)
    {
        LogInfo ("Creating snapmirror source: {0} destination: {1}~SIMULATED~" -f @($srcVolume.Identity, $dstVolume.Identity)) 1
        if($Script:TakeAction)
        {
            $funcParams = @{
                Controller = $dstVolume.NCController
                DestinationVserver = $dstVolume.VServer
                DestinationVolume = $dstVolume.Name
                SourceVolume = $srcVolume.Name
                SourceVserver = $srcVolume.VServer
                Policy = $snapmirrorPolicyName
            }
            $result = ReTryCatch -callee "New-NcSnapmirror" -funcParameters $funcParams
            if($result.Good2Go)
            {
                $newSnapmirror = $result.ReturnValue[0]

                $good2Go = ($null -ne $newSnapmirror)
                if($good2Go)
                {
                    # Nothing
                } `
                else
                {
                    LogError ("Failed to create snapmirror: {0} --> {1}." -f @($srcVolume.Identity, $dstVolume.Identity)) 2
                }
            } `
            else
            {
                LogError ("Failed to create snapmirror source: {0} destination: {1}." -f @($srcVolume.Identity, $dstVolume.Identity)) 2
            }
        } `
        else
        {
            # Return a dummy snapmirror so the ensuing call to ResyncSnapmirror has a value for $snapmirror which passes the ValidateNotNull check.
            $newSnapmirror = [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]::new()
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    # Ensure we ALWAYS return $null for $newSnapmirror if -not $good2Go
    if(-not $good2Go)
    {
        $newSnapmirror = $null
    } `
    else
    {
        # Nothing, leave $newSnapmirror as is.
    }

    return @($good2Go, $newSnapmirror)
}

function ResyncSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = $true
    $snapmirrorReady = $true
    # $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus = "idle"

    if($snapmirrorReady)
    {
        LogInfo ("Resyncing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
        if($Script:TakeAction)
        {
            $funcParams = @{
                Controller = $snapmirror.NcController
                DestinationVserver = $snapmirror.DestinationVserver
                DestinationVolume = $snapmirror.DestinationVolume
            }
            $result = ReTryCatch -callee "Invoke-NcSnapmirrorResync" -funcParameters $funcParams
            if($result.Good2Go)
            {
                $good2Go = (($null -ne $result.ReturnValue[0]) -and ($result.ReturnValue[0].Status -eq "succeeded"))
                if($good2Go)
                {
                    # Nothing
                } `
                else
                {
                    LogError ("Failed to resync snapmirror {0}." -f @($snapmirror.Identity))
                    $good2Go = $false
                }
            } `
            else
            {
                LogError ("Failed to resync snapmirror {0}." -f @($snapmirror.Identity))
                $good2Go = $false
            }
        } `
        else
        {
            # Nothing really, just pretending...
            $good2Go = $true
        }
    } `
    else
    {
        LogError ("Snapmirror {0} is not idle/snapmirrored." -f @($snapmirror.Identity)) 2
        $good2Go = $false
    }

    return $good2Go
}

function GetDomainController
{
    if($null -eq $Script:domainController)
    {
        LogInfo "Acquiring domain controller..." 1
        $funcParams = @{
        }
        $result = ReTryCatch -callee "Get-ADDomainController" -funcParameters $funcParams
        if($result.Good2Go)
        {
            $Script:domainController = $result.ReturnValue[0]
            if($null -ne $Script:domainController)
            {
                LogInfo ("Using: {0}" -f @($Script:domainController.HostName)) 2
            } `
            else
            {
                # LogWarning "AD computer object updates will not be verified.  No domain controller selected." 2
            }
        } `
        else
        {
            # Nothing -- for now..
        }
    } `
    else
    {
        # Nothing, already have a domain controller to use.
    }
}

function GetADComputer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $computerName
    )

    $adComputer = $null
    GetDomainController

    $funcParams = @{
        Identity = $computerName
        Properties = @("servicePrincipalName")
    }

    # If we have a domain controller object then use it to get and set the computer objects so we can verify the changes without having to wait for AD replication.
    if($null -ne $Script:domainController)
    {
        $funcParams.Add("Server", $Script:domainController.Name)
    } `
    else
    {
        # Nothing, Don't have a domain controller object to use...
    }
    $result = ReTryCatch -callee "Get-ADComputer" -funcParameters $funcParams
    if($result.Good2Go)
    {
        $adComputer = $result.ReturnValue[0]
    } `
    else
    {
        LogError ("Failed to acquire AD computer object for: {0}" -f @($computerName)) 2
    }

    return $adComputer
}

function CommitServicePrincipalNameChange2AD
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADComputer]
        $adComp
    )

    $good2Go = $true
    GetDomainController

    $verified = $false

    # This is what the values should be before we update the AD object
    $servicePrincipalNamesStringBefore = (($adComp.servicePrincipalName | Sort-Object) -join "|").ToLower()

    LogInfo ("Committing {0}'s computer account changes to AD.~SIMULATED~" -f @($adComp.Name)) 1
    if($Script:TakeAction)
    {
        $funcParams = @{
            Instance = $adComp
            PassThru = $true
        }

        # If a domain controller is available, add it to the parameter hash table
        if($null -ne $dc)
        {
            $funcParams.Add("Server", $Script:domainController.Name)
        }
        $result = ReTryCatch -callee "Set-ADComputer" -funcParameters $funcParams
        if($result.Good2Go)
        {
            if($null -ne $Script:domainController)
            {
                $tmpComp = GetADComputer -computerName $adComp.Name

                if($null -ne $tmpComp)
                {
                    $servicePrincipalNamesStringAfter = (($tmpComp.servicePrincipalName | Sort-Object) -join "|").ToLower()
                    $verified = ($servicePrincipalNamesStringBefore -eq $servicePrincipalNamesStringAfter)
                    if($verified)
                    {
                        LogInfo "Successfully committed changes to AD." 2
                    } `
                    else
                    {
                        # Nothing here, message below...
                    }
                } `
                else
                {
                    # Nothing here, message below... ($verified is still $false...)
                }
            } `
            else
            {
                # Nothing, can't verify changes since on domain controller object is available.
            }
        } `
        else
        {
            LogError ("Failed to commit service principal name changes to AD for {0}." -f @($adComp.Name))
            $good2Go = $false
        }

        if($good2Go -and (($null -eq $Script:domainController) -or (-not $verified)))
        {
            if($null -eq $Script:domainController)
            {
                LogWarning "No domain controller used to commit changes."
            } `
            else
            {
                # Nothing, not displaying this message because a domain controller was not available.
            }
            LogWarning ("{0} computer object update verification may be erroneous.  Verify manually." -f @($adComp.Name)) 2
            LogWarning "`r`nFrom the PS prompt, the following command will display 'True' if the change was committed to AD." 2
            LogWarning ("`r`n`"{0}`" -eq (((Get-ADComputer -Identity `"{1}`" -Properties `"servicePrincipalName`").servicePrincipalName | Sort-Object) -join `"|`").ToLower()`r`n" -f @($servicePrincipalNamesStringBefore, $adComp.Name)) 3
        } `
        else
        {
            # Nothing, already displayed a message
        }
    } `
    else
    {
        # Nothing, just pretending.
    }

    return $good2Go
}

function AddSPNToList
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.String]]
        $uniqueSPNs,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $spn
    )

    $goodToGo = $true
    $idx = $uniqueSPNs.BinarySearch($spn, [System.StringComparer]::CurrentCultureIgnoreCase)

    # If, while creating the comprehensive list of unique SPNs, a duplicate is detected
    if($idx -ge 0)
    {
        LogError ("Duplicate SPN detected: {0}" -f @($spn))
        $goodToGo = $false
    } `
    else
    {
        $uniqueSPNs.Insert(-bnot $idx, $_)
    }

    return $goodToGo
}

function TransferServicePrinicipalNames
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    <#
        NOTE: I don't like this function!!

        This process works as follows:

            NOTE: Until otherwise indicated, all actions are performed on in-memory objects only.
            Get all service principal names (SPN) assigned to the source AD computer object which do not match the computer's name.  These are the SPNs which need to be transferred to the destination AD computer object.
            For each SPN to transfer:
                Not removed from source's AD computer object
                Not added to destination's AD computer object
                Not safe to add SPN to destination's AD computer object
                If the SPN is assigned to the source's AD computer object
                    then:
                        Remove it from the source's AD computer object
                        If we successfully remove the SPN from the source's AD computer object
                            then:
                                Flag removed from source's AD computer object
                                Safe to add SPN to destination's AD computer object
                            else:
                                Display an error indicating the SPN was not removed from the source's AD computer object
                    else:
                        Safe to add SPN to destination's AD computer object
                If the SPN is not assigned to the destination's AD computer object
                    then:
                        If we are safe to add the SPN to the destination's AD computer object
                            then:
                                Add the SPN to the destination's AD computer object
                                If we successfully add SPN to the destination's AD computer object
                                    then:
                                        Flag added SPN to destination's AD computer object
                                    else:
                                        Display an error message indicating SPN was not added to the destination's AD computer object.
                                        If SPN was removed from the source's AD computer object
                                            then:
                                                Add SPN back to the source's AD computer object
                                                If we successfully added SPN back to the source's AD computer object
                                                    then:
                                                        Flag not removed from source's AD computer object
                                                        Display an error message indicating SPN was not transferred.
                                                    else:
                                                        Display an error indicating SPN will be removed from the source's AD computer object, but was not added to the destination's AD computer object.
                                            else:
                                                Nothing
                            else:
                                Display an error message indicating SPN was not added to the destination's AD computer object because it could not be removed from the source's AD computer object
                    else:
                        Nothing
                SPNs changed if SPN added to source's or removed from destination's AD computer object

            If SPNs changed (potentially committing in memory computer objects to AD)
                then:
                    Safe to commit to AD
                    Create comprehensive list of unique SPNs from the source's and destination's AD computer objects
                        If, while creating the comprehensive list of unique SPNs, a duplicate is detected
                            then:
                                Display an error indicating duplicate SPN
                                Flag not safe to commit to AD
                    If safe to commit to AD
                        then:
                            Commit source's AD computer object to AD and verify
                            Commit destination's AD computer object to AD and verify
                        else:
                            Nothing already displayed an error
                else:
                    Nothing, no changes to commit to AD

    #>
    if($data.Good2Go)
    {
        if($null -ne $data.Source.CIFSServer)
        {
            if($null -ne $data.Destination.CIFSServer)
            {
                LogInfo "Transferring service principal names...~SIMULATED~"

                LogInfo ("Getting computer object for {0} from AD." -f @($data.Source.CIFSServer.CifsServer)) 1
                $sourceCIFSServerADComputer = GetADComputer -computerName $data.Source.CIFSServer.CifsServer

                if($null -ne $sourceCIFSServerADComputer)
                {
                    LogInfo ("Received: {0}" -f @($sourceCIFSServerADComputer.DistinguishedName)) 2

                    LogInfo ("Getting computer object for {0} from AD." -f @($data.Destination.CIFSServer.CifsServer)) 1
                    $destCIFSServerADComputer = GetADComputer -computerName $data.Destination.CIFSServer.CifsServer

                    if($null -ne $destCIFSServerADComputer)
                    {
                        LogInfo ("Received: {0}" -f @($destCIFSServerADComputer.DistinguishedName)) 2

                        # Track the status of the transfers.  Remember, service principal names are unique in the AD forest.
                        #   If the service principal name is still on the source, we can't add it to the destination.
                        $spnXfrStatus = [System.Collections.Generic.Dictionary[[System.String], [System.Object]]]::new()

                        # Get all service principal names (SPN) assigned to the source's AD computer object which do not match its name.
                        #    These are the SPNs which need to be transferred to the destination's AD computer object.
                        $spnsToMove = @($sourceCIFSServerADComputer.servicePrincipalName | Where-Object { $_ -notmatch $sourceCIFSServerADComputer.Name }) | Select-Object -Unique

                        if($spnsToMove.Length -gt 0)
                        {
                            $sourceSPNChangesMade = $false
                            $destinationSPNChangesMade = $false
                            LogInfo "Processing the following service principal names:" 1

                            # For each SPN to transfer:
                            $spnsToMove.ForEach({
                                LogInfo $_ 2

                                $spn = $null
                                if(-not $spnXfrStatus.ContainsKey($_))
                                {
                                    $spn = "" | Select-Object Source, Destination
                                    $spn.Source = "" | Select-Object Removed, CommittedToAD
                                    # Not removed from source's AD computer object
                                    $spn.Source.Removed = $false
                                    $spn.Source.CommittedToAD = $false
                                    $spn.Destination = "" | Select-Object SafeToAdd, Added, CommittedToAD
                                    # Not added to destination's AD computer object
                                    $spn.Destination.Added = $false
                                    # Not safe to add SPN to destination's AD computer object
                                    $spn.Destination.SafeToAdd = $false
                                    $spn.Destination.CommittedToAD = $false

                                    $spnXfrStatus.Add($_, $spn)
                                } `
                                else
                                {
                                    LogError ("Duplicate SPN detected: {0}.  Aborting." -f @($_))
                                    $data.Good2Go = $false
                                    break
                                }

                                # If the SPN is assigned to the source's AD computer object
                                if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                                {
                                    # Remove it from the source's AD computer object
                                    $sourceCIFSServerADComputer.servicePrincipalName.Remove($_)

                                    # If we successfully remove the SPN from the source's AD computer object
                                    if(-not $sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                                    {
                                        # Flag removed from source's AD computer object
                                        $spn.Source.Removed = $true

                                        # Safe to add SPN to destination's AD computer object
                                        $spn.Destination.SafeToAdd = $true
                                    } `
                                    else
                                    {
                                        # Display an error indicating the SPN was not removed from the source's AD computer object
                                        LogError ("Failed to remove {0} from {1}." -f @($_, $destCIFSServerADComputer.Name)) 3
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    # Safe to add SPN to destination's AD computer object
                                    $spn.Destination.SafeToAdd = $true
                                }

                                # If the SPN is not assigned to the destination's AD computer object
                                if(-not $destCIFSServerADComputer.servicePrincipalName.Contains($_))
                                {
                                    # If we are safe to add the SPN to the destination's AD computer object
                                    if($spn.Destination.SafeToAdd)
                                    {
                                        # Add the SPN to the destination's AD computer object
                                        $destCIFSServerADComputer.servicePrincipalName.Add($_) | Out-Null

                                        # If we successfully add SPN to the destination's AD computer object
                                        if($destCIFSServerADComputer.servicePrincipalName.Contains($_))
                                        {
                                            # Flag added SPN to destination's AD computer object
                                            $spn.Destination.Added = $true
                                        } `
                                        else
                                        {
                                            # Display an error message indicating SPN was not added to the destination's AD computer object.
                                            LogError ("Failed to add {0} to {1}." -f @($_, $destCIFSServerADComputer.Name)) 3
                                            $data.Good2Go = $false

                                            # If SPN was removed from the source's AD computer object
                                            if($q.Source.Removed)
                                            {
                                                # Add SPN back to the source's AD computer object
                                                $sourceCIFSServerADComputer.servicePrincipalName.Add($_) | Out-Null

                                                # If we successfully added SPN back to the source's AD computer object
                                                if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                                                {
                                                    # Flag not removed from source's AD computer object
                                                    $spn.Source.Removed = $false

                                                    # Display an error message indicating SPN was not transferred.
                                                    LogWarning ("{0} will not be transferred." -f @($_))
                                                } `
                                                else
                                                {
                                                    # Display an error indicating SPN will be removed from the source's AD computer object, but was not added to the destination's AD computer object.
                                                    LogWarning ("{0} will be removed from {1}, but not added to {2}." -f @($_, $sourceCIFSServerADComputer.Name, $destCIFSServerADComputer.Name))
                                                    $data.Good2Go = $false
                                                }
                                            } `
                                            else
                                            {
                                                # Nothing, didn't remove it, so not putting it back.
                                            }
                                        }
                                    } `
                                    else
                                    {
                                        # Display an error message indicating SPN was not added to the destination's AD computer object because it could not be removed from the source's AD computer object.
                                        LogWarning ("{0} will not be transferred to {1} because it is still assigned to {2}." -f @($_, $destCIFSServerADComputer.Name, $sourceCIFSServerADComputer.Name))
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    # Nothing, don't need to add this SPN it's already there.  How is that possible?  I thought SPNs were unique across a domain???
                                }

                                $sourceSPNChangesMade = $sourceSPNChangesMade -or $spn.Source.Removed
                                $destinationSPNChangesMade = $destinationSPNChangesMade -or $spn.Destination.Added
                            })

                            if($sourceSPNChangesMade -or $destinationSPNChangesMade)
                            {
                                # Safe to commit to AD
                                $safeToCommitToAD = $true

                                # Create comprehensive list of unique SPNs from the source's and destination's AD computer objects
                                $uniqueSPNs = [System.Collections.Generic.List[System.String]]::new()

                                $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                                    $spnAddedToList = AddSPNToList -uniqueSPNs $uniqueSPNs -spn $_
                                    $data.Good2Go = $data.Good2Go -and $spnAddedToList

                                    # Flag not safe to commit to AD -- if -not $spnAddedToList
                                    $safeToCommitToAD = $safeToCommitToAD -and $spnAddedToList
                                })

                                $destCIFSServerADComputer.servicePrincipalName.ForEach({
                                    $spnAddedToList = AddSPNToList -uniqueSPNs $uniqueSPNs -spn $_
                                    $data.Good2Go = $data.Good2Go -and $spnAddedToList

                                    # Flag not safe to commit to AD -- if -not $spnAddedToList
                                    $safeToCommitToAD = $safeToCommitToAD -and $spnAddedToList
                                })

                                # If safe to commit to AD
                                if($safeToCommitToAD)
                                {
                                    # Assume source's AD computer object changes were committed to AD unless it fails.
                                    $spnSourceChangesCommitted = $true
                                    if($sourceSPNChangesMade)
                                    {
                                        # Commit source's AD computer object to AD and verify
                                        $spnSourceChangesCommitted = CommitServicePrincipalNameChange2AD -adComp $sourceCIFSServerADComputer
                                    } `
                                    else
                                    {
                                        # Nothing, No changes to the source's AD computer object
                                    }

                                    if($destinationSPNChangesMade)
                                    {
                                        # Only commit the changes to the destination's AD computer object if:
                                        #    1) There were no changes to the source's AD computer object
                                        #    2) OR the changes to the source's AD computer object were successfully committed to AD
                                        if($spnSourceChangesCommitted)
                                        {
                                            # Commit destination's AD computer object to AD and verify
                                            $spnDestinationChangesCommitted = CommitServicePrincipalNameChange2AD -adComp $destCIFSServerADComputer
                                        } `
                                        else
                                        {
                                            LogError ("Changes to {0} were not committed to AD since committing {1}'s changes to AD failed." -f @($destCIFSServerADComputer.Name, $sourceCIFSServerADComputer.Name))
                                            $data.Good2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        # Nothing, No changes to the destination's AD computer object
                                    }
                                } `
                                else
                                {
                                    LogError "Service principal name changes not committed to AD."
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, no changes to commit to AD...
                            }
                        } `
                        else
                        {
                            LogWarning ("{0}'s AD computer object's service principal name list does not appear to have any alias entries!" -f @($data.Source.CIFSServer.CifsServer))
                            $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                                LogWarning $_ 1
                            })
                            LogWarning "Service principal names not updated!"
                        }
                    } `
                    else
                    {
                        LogError ("Failed to acquire AD computer object for: {0}" -f @($data.Destination.CIFSServer.CifsServer)) 2
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to acquire AD computer object for: {0}" -f @($data.Source.CIFSServer.CifsServer)) 2
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogWarning "Not transferring service principal names.  No destination CIFS server to transfer to."
            }
        } `
        else
        {
            LogWarning "Not transferring service principal names.  No source CIFS server to transfer from."
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function TransferCNAMERecords
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        if($null -ne $data.Destination.CIFSServer)
        {
            GetDomainController
            if($null -ne $Script:domainController)
            {
                LogInfo "Migrating CNAME records...~SIMULATED~" 1
                $result = ReTryCatch -callee "Get-ADDomain"

                if($result.Good2Go -and ($null -ne $result.ReturnValue[0]))
                {
                    $adDomain = $result.ReturnValue[0]

                    LogInfo ("Acquired AD Domain: {0}" -f @($adDomain.DNSRoot)) 1

                    # If we are running in simulation mode, use the source CIFS server because the destination CIFS server will not have the right service principal names attached to it.
                    if($Script:TakeAction)
                    {
                        $computerName = $data.Destination.CIFSServer.CifsServer
                    } `
                    else
                    {
                        $computerName = $data.Source.CIFSServer.CifsServer
                    }
                    LogInfo ("Getting computer object for {0} from AD." -f @($data.Destination.CIFSServer.CifsServer)) 1
                    $destCIFSServerADComputer = GetADComputer -computerName $computerName

                    if($Script:TakeAction)
                    {
                        if(-not [String]::IsNullOrEmpty($destCIFSServerADComputer.DNSHostName))
                        {
                            $hostNameToAlias = $destCIFSServerADComputer.DNSHostName.ToLower()
                        } `
                        else
                        {
                            $hostNameToAlias = ("{0}.{1}" -f @($destCIFSServerADComputer.Name, $adDomain.DNSRoot)).ToLower()
                        }
                    } `
                    else
                    {
                        $hostNameToAlias = ("{0}.{1}" -f @($data.Destination.CIFSServer.CifsServer, $adDomain.DNSRoot)).ToLower()
                    }

                    if($null -ne $destCIFSServerADComputer)
                    {
                        $hostSPNs = @($destCIFSServerADComputer.servicePrincipalName | Where-Object { ($_ -notmatch $destCIFSServerADComputer.Name) -and ($_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($adDomain.DNSRoot)))) })
                        if($hostSPNs.Length -gt 0)
                        {
                            $a = 0
                            while($a -lt $hostSPNs.Length)
                            {
                                $hostSPN = $hostSPNs[$a]

                                if((-not [String]::IsNullOrEmpty($hostSPN)) -and ($hostSPN -match "^HOST/([^.]+)\."))
                                {
                                    $alias = $Matches[1]

                                    LogInfo ("Registering CNAME {0} alias for {1}.~SIMULATED~" -f @($alias, $hostNameToAlias)) 1 -NoNewLine

                                    if($Script:TakeAction)
                                    {
                                        $funcParams = @{
                                            Name = $alias
                                            HostNameAlias = $hostNameToAlias
                                            ZoneName = $adDomain.DNSRoot
                                            ComputerName = $Script:domainController.Name
                                        }
                                        $result = ReTryCatch -callee "Add-DnsServerResourceRecordCName" -funcParameters $funcParams
                                        if($result.Good2Go)
                                        {
                                            LogInfo " Successful"
                                        } `
                                        else
                                        {
                                            LogWarning " Failed"
                                            $data.Good2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        LogInfo ""
                                    }
                                } `
                                else
                                {
                                    LogWarning ("Failed to determine alias(es) from {0} service principal names.  DNS CNAME records not updated." -f @($destCIFSServerADComputer.Name)) 3
                                    $destCIFSServerADComputer.servicePrincipalName.ForEach({
                                        LogWarning ("{0}" -f @($_)) 4
                                    })
                                }

                                $a++
                            }
                        } `
                        else
                        {
                            # Nothing, no aliases to migrate...
                        }
                    } `
                    else
                    {
                        LogError ("Failed to acquire AD computer object for: {0}" -f @($data.Destination.CIFSServer.CifsServer)) 2
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogWarning "Failed to acquire a AD domain data.  CNAME records will not transferred." 3
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogWarning "Unable to acquire a domain controller.  CNAME records will not transferred."
                $data.Good2Go = $false
            }
        } `
        else
        {
            LogWarning "Not transferring CNAME records.  No destination CIFS server to transfer to."
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function TransferServicePrincipalNamesAndCNAMEs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.Good2Go)
    {
        TransferServicePrinicipalNames -data $data
        if($data.Good2Go)
        {
            TransferCNAMERecords -data $data
        } `
        else
        {
            # Nothing, already displayed a message
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function StartCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer
    )

    if($data.Good2Go)
    {
        LogInfo ("Starting CIFS services on: {0}~SIMULATED~" -f @($cifsServer.Identity)) 1

        if($Script:TakeAction)
        {
            $funcParams = @{
                Controller = $cifsServer.NcController
                VserverContext = $cifsServer.Vserver
                Confirm = $false
            }
            $result = ReTryCatch -callee "Start-NcCifsServer" -funcParameters $funcParams
            if($result.Good2Go)
            {
                # Wait for the CIFS service to be up...
                LogInfo ("Waiting for CIFS server {0} to be on-line." -f @($cifsServer.Identity)) 2 -NoNewLine
                $funcParams.Remove("Confirm")
                do
                {
                    $result = ReTryCatch -callee "Get-NcCifsServer" -funcParameters $funcParams
                    if($result.Good2Go -and ($null -ne $result.ReturnValue[0]))
                    {
                        $cifsServer = $result.ReturnValue[0]
                        if($cifsServer.AdministrativeStatus -ne "up")
                        {
                            LogInfo "." -NoNewLine

                            # Pause a moment for station identification...
                            Start-Sleep -Seconds 5
                        } `
                        else
                        {
                            # Nothing, CIFS server is up and ready
                        }
                    } `
                    else
                    {
                        LogError ("Failed to retrieve CIFS server data from {0}." -f @($cifsServer.Identity)) 2
                        $data.Good2Go = $false
                    }
                } until ((-not $data.Good2Go) -or ($cifsServer.AdministrativeStatus -eq "up"))
                LogInfo
            } `
            else
            {
                LogError ("Failed to start CIFS services on {0}" -f @($cifsServer.Identity)) 1
                $data.Good2Go = $false
            }
        } `
        else
        {
            # Nothing, just pretending.
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    if(-not $data.Good2Go)
    {
        LogWarning ("Please remember to check CIFS services on {0}" -f @($cifsServer.Identity)) 1
    } `
    else
    {
        # Nothing, all seems well
    }
}

function StartFileServices
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    <# Step 1: Stop file services on the source to prevent additional changes to source volumes.
        For CIFS: Stop the CIFS server
        For NFS: (not yet complete -- or even really started.)
            For linux NFS mounted volumes
                ???  TODO
                Presumably these would be linux VMs which would themselves be failed over.
                Shutdown services consuming the NFS mount
                Modify fstab file to use the 'new source volume'
                Shutdown the linux host
                    When the linux host is restarted after failing over, the volume for the NFS mount should be available
            For datastore volumes:
                1a. Shutdown VMs stored on datastores
                1b. Remove VMs from source inventory
                1c. Unmount datastore volumes
    #>

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
            # We are creating the action sequence...
        } `
        else
        {
            # We are working off the action sequence.... eventually...

            # If there is a destination CIFS server and it's not up, make it up...
            if($null -ne $data.Destination.CIFSServer)
            {
                <# Step 11: Start CIFS services on the destination VServer.
                    #Stop SMB service at current source
                    vserver cifs start -vserver LABDR-SMB02
                #>
                if($data.Destination.CIFSServer.AdministrativeStatus -ne "up")
                {
                    $data.Good2Go = StartCIFSServer -data $data -cifsServer $data.Destination.CIFSServer
                }
                else
                {
                    LogInfo ("CIFS server already running on {0}." -f @($data.Destination.CIFSServer.Identity))
                }
            } `
            else
            {
                # Nothing, $data.Destination is not a CIFS server...
            }

            if($data.Source.IsNFSHost)
            {
                # For now, nothing, but here, we'd potentially handle VMware datastores...
                LogWarning ("{0} is an NFS host!  However, NFS failover is incomplete in this version of the script." -f @($data.Source.VServer.Identity))
                if($data.Good2Go)
                {
                    # Attempt to start NFS services (whatever that means) when the NFS portion is available.
                } `
                else
                {
                    # Warning that NFS services will not be started on the destination since an error occurred.
                }
            } `
            else
            {
                # Nothing, no NFS services to worry about.
            }
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function TakeAction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    <#
        Instead of having nested if($data.Good2Go) constructs, I added the check to each of the individual processing
            functions to have a cleaner look here.

        Step  1: Stop file services at the source to prevent changes to the source volumes.
        Step  2: Update snapmirror
        Step  3: Break snapmirror
        Step  4: Make sure snapshot policies match on source/destination pairs
            This has to be done prior to creating the new snapmirrors and re-syncing them or we run the risk of losing snapshots on the original source that do not match snapshots on the new source.
        Step  5: Update volume efficiency settings on the destination volumes.
        Step  6: Delete snapmirror
        Step  7: Release snapmirror
        Step  8: Create "reverse" snapmirror
        Step  9: (Re)sync "reverse" snapmirror
        Step 10: Update service principal names and CNAME records for CIFS
        Step 11: Start file services at the destination.

    #>

    if($data.Good2Go)
    {
        # Step  1: Stop file services at the source to prevent changes to the source volumes.
        StopFileServices -data $data

        if($data.Good2Go)
        {

            <#
                For creating the new snapmirrors, I won't use $data.Good2Go to determine if processing should continue.  I'll handle each NewSnapmirror on it's own.
                However, I will track whether the entire process was completed without issue in a separate variable.
                Infact, when it comes to updating, breaking, deleting and releasing snapmirrors, each .Relationship is handled atomically.  Just because
                the first snapmirror relationship failed to process completely does not mean the second/third/etc doesn't need to be processed.

                However, if $data.Good2Go -ne $true then before transferring service principal names and DNS aliases I'll prompt the user to confirm before proceeding.

            #>

            # On to the snapmirrors...

            # Track the overall status of processing all the snapmirrors.
            $snapmirrorsProcessedSuccessfully = $true
            $a = 0
            while($a -lt $data.NewSnapmirrors.Count)
            {
                LogInfo ("`r`nProcessing volume {0} of {1}..." -f @(($a + 1), $data.NewSnapmirrors.Count)) -NewLine

                # Only create and resync the new snapmirror(s) if the old snapmirrors are completely processed.
                $newSnapmirrorsGood2Go = $true

                # First, tear down all the old snapmirrors for the source volume...
                $b = 0
                while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                {
                    # Track the status for the snapmirror object we are processing.  The
                    #    idea is, if something goes wrong with a single snapmirror, we will
                    #    stop processing it, but proceed with the rest, as best we can.

                    # Step 2: Update snapmirror
                    $snapmirrorUpdated, $tmpSM = UpdateSnapmirror -data $data -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror
                    if($snapmirrorUpdated)
                    {
                        if($null -ne $tmpSM)
                        {
                            # Replace the snapmirror object we are tracking with the snapmirror object returned from UpdateSnapmirror.  Its status may have changed.
                            $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror = $tmpSM

                            # Step 3: Break snapmirror
                            $snapmirrorBroken, $tmpSM = BreakSnapmirror -data $data -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror
                            if($snapmirrorBroken)
                            {
                                if($null -ne $tmpSM)
                                {
                                    # Replace the snapmirror object we are tracking with the snapmirror object returned from BreakSnapmirror
                                    $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror = $tmpSM

                                    <# Step 4: Update snapshot policy - This might be some confusing code, so I'll explain it.

                                        When $data is initialized the new snapmirror objects are "fixed".  This involves setting .SourceVolume to the volume which
                                            will ultimately be the new source of truth and .DestinationVolume (hosted on the requested destination VServer) to the original
                                            snapmirror source volume.

                                            So, here, we CAN NOT just blindly set the snapshot policy on .DestinationVolume to match the snapshot
                                            policy of .OriginalSourceVolume.  Hence the confusing code below.  I considered moving FixupNewSnapmirrors until after
                                            this point in the code, but I wanted ShowData to be able to accurately display what the new snapmirrors will look like.
                                    #>

                                    # Start by assuming .DestinationVolume is the correct "destination"
                                    $dstVolume = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume

                                    if($dstVolume -eq $data.NewSnapmirrors[$a].OriginalSourceVolume)
                                    {
                                        # The destination volume for the new snapmirror is the original source volume, so instead of updating $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume,
                                        #   we need to update $data.NewSnapmirrors[$a].SourceVolume (it was the original destination volume).
                                        $dstVolume = $data.NewSnapmirrors[$a].SourceVolume
                                    } `
                                    else
                                    {
                                        # All good, the destination for this new snapmirror is NOT the original source volume.
                                    }

                                    # Step 4: Update snapshot policy
                                    #    Always use the snapshot policy from .OriginalSourceVolume
                                    $snapshotPolicyUpdated = UpdateSnapshotPolicy -data $data -sourceVolume $data.NewSnapmirrors[$a].OriginalSourceVolume -destinationVolume $dstVolume

                                    if($snapshotPolicyUpdated)
                                    {
                                        # Step 5: Update volume efficiency policies on the destination volume.  No return value since it's not vital to set the efficiencies.
                                        UpdateVolumeEfficiencySettings -data $data -volume $dstVolume

                                        # Step 6: Delete snapmirror
                                        $snapmirrorDeleted = DeleteSnapmirror -data $data -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror
                                        if($snapmirrorDeleted)
                                        {
                                            # Step 7: Release snapmirror
                                            $snapmirrorReleased = ReleaseSnapmirror -data $data -sourceVolume $data.NewSnapmirrors[$a].OriginalSourceVolume -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror

                                            $newSnapmirrorsGood2Go = $snapmirrorReleased
                                        } `
                                        else
                                        {
                                            # Do not establish the new snapmirror relationships since we did not successfully process all of the current snapmirrors.
                                            $newSnapmirrorsGood2Go = $false
                                        }
                                    } `
                                    else
                                    {
                                        $newSnapmirrorsGood2Go = $false
                                    }
                                } `
                                else
                                {
                                    $snapmirrorBroken = $false
                                    $newSnapmirrorsGood2Go = $false
                                    LogError ("Breaking of snapmirror {0} seems to have succeeded, but the resulting snapmirror object was not returned from BreakSnapmirror." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Identity))
                                }
                            } `
                            else
                            {
                                # Do not establish the new snapmirror relationships since we did not successfully process all of the current snapmirrors -- for this snapmirror source.
                                $newSnapmirrorsGood2Go = $false
                            }
                        } `
                        else
                        {
                            $snapmirrorUpdated = $false
                            $newSnapmirrorsGood2Go = $false
                            LogError ("Update of snapmirror {0} seems to have succeeded, but the resulting snapmirror object was not returned from UpdateSnapmirror." -f @($data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Identity))
                        }
                    } `
                    else
                    {
                        # Do not establish the new snapmirror relationships since we did not successfully process all of the current snapmirrors.
                        $newSnapmirrorsGood2Go = $false
                    }

                    $b++
                }

                # Make sure we update $snapmirrorsProcessedSuccessfully
                $snapmirrorsProcessedSuccessfully = $snapmirrorsProcessedSuccessfully -and $newSnapmirrorsGood2Go

                # If ALL the current snapmirrors for this source volume were UPDATED, BROKEN, DELETED, and RELEASED, then proceed to create the reverse snapmirrors.
                if($newSnapmirrorsGood2Go)
                {
                    LogInfo ""  # Just add a space between updating/breaking/etc... and creating and resyncing.
                    $b = 0

                    # After the old snapmirrors for this source are cleared, recreate the "reverse" snapmirrors.
                    while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                    {
                        $newSnapmirrorResyncd = $false
                        # Step 8: Create new snapmirror
                        $newSnapmirrorCreated, $newSnapmirror = CreateSnapmirror -data $data -srcVolume $data.NewSnapmirrors[$a].SourceVolume -dstVolume $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume -snapmirrorPolicyName $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy

                        # Did CreateSnapmirror say the new snapmirror was created?  Remember if running in simulation mode, it will say a new snapmirror was created, but will return $null for $newSnapmirror
                        if($newSnapmirrorCreated)
                        {
                            # Snapmirror was created or simulated...
                            if($null -ne $newSnapmirror)
                            {
                                # Step 9: Resync new snapmirror
                                $newSnapmirrorResyncd = ResyncSnapmirror -data $data -snapmirror $newSnapmirror
                            } `
                            else
                            {
                                # CreateSnapmirror says it created a snapmirror, but didn't return a new snapmirror object....
                                LogError ("Please check snapmirror status for {0} --> {1}" -f @($data.NewSnapmirrors[$a].SourceVolume.Identity, $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Identity))
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed a message
                        }

                        # Make sure we update $snapmirrorsProcessedSuccessfully
                        $snapmirrorsProcessedSuccessfully = $snapmirrorsProcessedSuccessfully -and $newSnapmirrorResyncd
                        $b++
                    }
                } `
                else
                {
                    # Nothing, already displayed an error.
                }

                $a++
            }

            $xferSPNsCNames = $true

            # There was an issue processing the old/new snapmirrors, give the user a choice whether or not to transfer service principal names and CNAMEs
            if((-not $snapmirrorsProcessedSuccessfully) -or (-not $data.MigrateAllVolumes))
            {
                if(-not $snapmirrorsProcessedSuccessfully)
                {
                    Write-Host -ForegroundColor Yellow "`r`nAt least one issue was encountered when creating the reverse snapmirrors."
                }
                else
                {
                    # Nothing.
                }

                if(-not $data.MigrateAllVolumes)
                {
                    Write-Host -ForegroundColor Yellow "`r`nNot all volumes were migrated."
                }
                else
                {
                    # Nothing.
                }

                do
                {
                    $result = Read-Host -Prompt "Transfer service prinicipal names and CNAME records and start file services on the destination? (Y/N)"
                    if(($result -ne "Y") -and ($result -ne "N"))
                    {
                        Write-Host -ForegroundColor Red "`tIncorrect input, please redo!"
                    } `
                    else
                    {
                        # Nothing
                    }
                } while (($result -ne "Y") -and ($result -ne "N"))
                $xferSPNsCNames = ($result -eq "Y")
            } `
            else
            {
                # Nothing, proceed without prompting.
            }

            if($xferSPNsCNames)
            {
                # Step 10: Update service principal names and CNAME records for CIFS
                TransferServicePrincipalNamesAndCNAMEs -data $data

                # Step 11: Start files services at the destination.
                StartFileServices -data $data
            } `
            else
            {
                Write-Host -ForegroundColor Yellow "Service prinicipal names and CNAME records not transferred."
            }
        } `
        else
        {
            # Nothing already displayed a message.
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function Main
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName,

        [Parameter(Mandatory=$false,Position=2)]
        [String[]]
        $VolumesToInclude
    )

    if(-not $Script:TakeAction)
    {
        LogInfo "No changes will be made.  Running in simulation mode."
    } `
    else
    {
        # Nothing
    }

    AddTypeExtensions

    <#
        When Initialize returns, if $data.Good2Go -eq $true, then we should be safe to execute all changes.

        The goal is to have everything checked and verified prior to calling TakeAction.  I want to avoid making ANY changes unless I believe
            ALL changes will complete successfully.
            VServer Peerings are good, Snapshot policies are available where needed, etc...

    #>

    $data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass

    if($data.Good2Go)
    {
        if($data.Snapmirrors.Count -gt 0)
        {
            ShowData -data $data
            if($Script:TakeAction)
            {
                $go = Read-Host -Prompt "`r`nConfirm settings then enter 'GO!' to continue failover (case matters) anything else to abort"
            }
            else
            {
                $go = "GO!"
            }

            if($go -ceq "GO!")
            {
                TakeAction -data $data
            } `
            else
            {
                LogWarning "Script abort."
            }
        } `
        else
        {
            LogWarning "No snapmirrors to process.  Failover aborted."
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    if(-not [String]::IsNullOrEmpty($Script:LogFileName))
    {
        Write-Host ("`r`nLog file written to: {0}" -f @($Script:LogFileName))
    } `
    else
    {
        # Nothing
    }
}

if($PSVersionTable.PSVersion.ToString().StartsWith("5.1"))
{
    Main -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $Script:VolumesToInclude
} `
else
{
    LogError "Please run this script under PowerShell v 5.1x (powershell.exe)"
}
