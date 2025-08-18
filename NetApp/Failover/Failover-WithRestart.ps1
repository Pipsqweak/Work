[CmdletBinding(DefaultParameterSetName = "Normal")]
param (
    [Parameter(Mandatory=$true, ParameterSetName="Normal", Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $SourceVServerName,

    [Parameter(Mandatory=$true, ParameterSetName="Normal", Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $DRVServerName,

    [Parameter(Mandatory=$false, ParameterSetName="Normal", Position=2)]
    [String[]]
    $VolumesToInclude,

    [Parameter(Mandatory=$false, ParameterSetName="Retry", Position=0)]
    [String]
    $RetryFile,

    [Parameter(Mandatory=$false, ParameterSetName="Retry", Position=1)]
    [Parameter(Mandatory=$false, ParameterSetName="Normal", Position=3)]
    [Switch]
    $TakeAction
)
<#
    NOTES:

        To help with the ability to restart/retry a failover, I need to keep change affecting functions separate from decision making.  This
        will allow the first pass to decide which change affecting functions need to be called, and later, if a retry is performed, the change
        affecting functions will not need to make decisions on what to do.

        But now I'm second guessing this thought.  Should the change functions check before acting?  It really wouldn't hurt anything, just take
        a little more coding and execution time.  I'll ponder this.

        Here is what I know.  When the script is ran against a pristine environment, it will be able to determine (given the proper inputs) which
        volumes to failover to where and the sequence of events to affect the failover.  However, once change has occurred, the script may not be
        able to determine what actions need to be performed.  Consider snapmirrors; once a snapmirror has been deleted (not released), there is no
        way to confirm the relationship from the destination.  Further, when the snapmirror is released, now if can no longer be detected from the
        source.  Rhetorical question:  So what?  What if I were not not make the script "restartable", but rather, just let the script run from the
        start again?  What if some snapmirrors had been broken/released?  Doesn't that just mean successive runs of the script would just do less
        and less until the process is finished?  I guess I made the assumption, without a pristine environment to start with, I couldn't reliably
        determine a course of action.  Perhaps I need to model this out.  What if the script fails at any of the following points?

            1. Stop CIFS server to prevent further changes to volumes
                Not a problem, we can still determing all the information we need.

            2. Determine all the volumes which need to be failed over.  This is accomplished by examining snapmirror relationships.


            3. For each source volume to failover:
                A. For each snapmirror destination volume:
                    1) Update the destination volume
                    2) Break the snapmirror
                    3) Update snapshot policies as needed
                    4) Update storage efficieny settings as needed
                    5) Delete the snapmirror
                    6) Release the snapirror

                Once all snapmirrors related to this source are updated/broken/deleted/released
                B. For each volume not selected as the failover destination (new source):
                    1) Create snapmirror from new source to destination
                    2) Resync new snapmirror

            4. Update service principal names in Active Directory

            5. Migrate any DNS aliases for the original CIFS server to the failover CIFS server.

            6. Start CIFS server on the failover destination VServer



        Given the source SVM to failover, it can be determined which volumes can be failed over based on which ones have snapmirror destinations.

        About snapshot policies:
            Snapmirror destination volumes can have a snapshot policy set.  However, it's not active since

        Since snapmirror destinations do not have active snapshot policies

        ------------------------------------------------------------------------------------------------------------------------------

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
                                        NOTE: Only set this to $false if the script needs to stop.
        .FirstPass                 - $true if the script is running through the processing section the first time to create .ActionSequence
        .ActionSequence            - The actions which need to be preformed on the second pass of the processing section
        .AllVolumes                - All volumes from all ONTAP clusters where the volume name does not match $Script:volumesToIgnoreRegex
        .AllVServers               - All VServers (SVMs) from all ONTAP clusters
        .AllCIFSServers            - All CIFS servers from all ONTAP clusters
        .RelatedControllers        - Once all snapmirror destinations are know, this will be the controllers we need to query for information instead of relying on $Global:cDot
        .Snapmirrors               - All the currently established snapmirrors related to this failover.  (From the perspective of the destination cluster -- Get-NCSnapmirror)
        .SnapmirrorDestinations    - All the snapmirror destinations related to theis failover.  (From the perspective of the source VServer -- Get-NCSnapmirrorDestination)
        .NFSDatastores             - vSphere NFS datastores related to this failover.
        .DatastoreToVMHosts        - Dictionary of datastore IDs to list of VMHosts connected to the datastore
        .ServicePrincipalNames     - Service principal names to transfer from the source AD computer to the destination computer object
        .CNAMERecords              - CNAME records to transfer from the current CIFS server to the destination CIFS server
        .Source | .Destination     - These store the following information for the source and destination
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

        NOTES:
            If data is initialized as a result of a retry, then .Snapmirrors = all snapmirrors from all ONTAP clusters.


    As of 4/24/2024 the NFS part of the fail over is not complete.  The script can be used to process the snapmirrors related the the NFS volumes, but the vSphere integration is not yet complete.

    As of 5/16/2024 most of the action sequence is in place, but not fully tested.  I'm leaving in the old notes for informational reasons.

        The script can be ran in 2 different ways.

            If Source, Destination and volumes to include are specified, then the script runs "FirstPass".

            During FirstPass, things are checked to ensure everything is in order (as best I can) and an action sequence is built.  The action sequence is then saved to a temporary file
                and ProcessActionSequence is called -- see below.

            If RetryFile is specified, then the script skips FirstPass and jumps right to ProcessActionSequence.

            ProcessActionSequence executes the commands in the action sequence until something goes wrong.  After each command is successfully processed, the action sequence file is updated
                indicating which commands have been completed successfully.  This ensure when the script is restarted in "retry" mode, only action commands which have not already completed
                will be executed.

        The action sequence file is a .JSON file.  This makes it easy to read and provides a sort of road map as to what will happen.  It also lends itself to manually completing some of the
            steps yet allow most of the processing to happen "automatically."  For instance, if a snapmirror break action fails an causes the script to abort, the user may well choose to manually
            break the snapmirror but want the script to process the rest of the failover.  Once the snapmirror has been broken, the .JSON fila can be edited to mark the appropriate command as
            complete.  This will ensure on the subsequent run of the script (in retry mode), the command will not be attempted.

    As of 4/24/2024 the action sequence is also not implemented.  The idea is, during the first pass, I generate an action sequence representing the actions which need to happen to complete
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

<#

    Script wide initialization...

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

# Some script wide variables
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
$Script:adDomain = $null

<#
    NOTE: If types other than String, String[], and Boolean are added to this table, remember to add the appropriate validation below in CheckActionSequence
#>
$Script:calleeParamsTable = @(
    @{ callee = "Stop-NcCifsServer";                 Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "VserverContext";        Type = "String";   Mandatory = $true },
        @{ Name = "Confirm";               Type = "Boolean";  Mandatory = $true })},

    @{ callee = "Invoke-NcSnapmirrorUpdate";         Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "Passthru";              Type = "Boolean";  Mandatory = $true })},

    @{ callee = "Invoke-NcSnapmirrorBreak";          Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "Passthru";              Type = "Boolean";  Mandatory = $true },
        @{ Name = "Confirm";               Type = "Boolean";  Mandatory = $true })},

    @{ callee = "Update-NcVol";                      Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "SourceVolume";          Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true })},

    @{ callee = "Enable-NcSis";                      Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "VserverContext";        Type = "String";   Mandatory = $true },
        @{ Name = "Name";                  Type = "String";   Mandatory = $true })},

    @{ callee = "Set-NcSis";                         Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "VserverContext";        Type = "String";   Mandatory = $true },
        @{ Name = "Name";                  Type = "String";   Mandatory = $true },
        @{ Name = "Compression";           Type = "Boolean";  Mandatory = $true },
        @{ Name = "InlineCompression";     Type = "Boolean";  Mandatory = $true },
        @{ Name = "Policy";                Type = "String";   Mandatory = $true })},

    @{ callee = "Remove-NcSnapmirror";               Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true },
        @{ Name = "Confirm";               Type = "Boolean";  Mandatory = $true })},

    @{ callee = "Invoke-NcSnapmirrorRelease";        Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "SourceVolume";          Type = "String";   Mandatory = $true },
        @{ Name = "SourceVserver";         Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true },
        @{ Name = "RelationshipId";        Type = "String";   Mandatory = $true },
        @{ Name = "Confirm";               Type = "Boolean";  Mandatory = $true })},

    @{ callee = "New-NcSnapmirror";                  Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "SourceVolume";          Type = "String";   Mandatory = $true },
        @{ Name = "SourceVserver";         Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true },
        @{ Name = "Policy";                Type = "String";   Mandatory = $true })},

    @{ callee = "Invoke-NcSnapmirrorResync";         Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVolume";     Type = "String";   Mandatory = $true },
        @{ Name = "DestinationVserver";    Type = "String";   Mandatory = $true })},

    @{ callee = "Set-ADComputer";                    Params = @(
        @{ Name = "Instance";              Type = "String";   Mandatory = $true },
        @{ Name = "Server";                Type = "String";   Mandatory = $false },
        @{ Name = "PassThru";              Type = "Boolean";  Mandatory = $true },
        @{ Name = "servicePrincipalNames"; Type = "String[]"; Mandatory = $true})},

    @{ callee = "Add-DnsServerResourceRecordCName";  Params = @(
        @{ Name = "Name";                  Type = "String";   Mandatory = $true },
        @{ Name = "HostNameAlias";         Type = "String";   Mandatory = $true },
        @{ Name = "ZoneName";              Type = "String";   Mandatory = $true },
        @{ Name = "ComputerName";          Type = "String";   Mandatory = $true })},

    @{ callee = "Start-NcCifsServer";                Params = @(
        @{ Name = "Controller";            Type = "String";   Mandatory = $true },
        @{ Name = "VserverContext";        Type = "String";   Mandatory = $true },
        @{ Name = "Confirm";               Type = "Boolean";  Mandatory = $true })}
)


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
        [ValidateNotNull()]
        [HashTable]
        $funcParameters,

        [Parameter(Mandatory=$false, Position=1)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $IgnoreException
    )

    # Capture vital information is $result which is returned to the caller.
    $result = "" | Select-Object ActionComplete, Good2Go, ReturnValue, Tries, Error
    $result.Good2Go = $true              # .Good2Go does NOT imply the result of & $callee was successful, just that & $callee was successfully called.  It's up to the caller to check .ReturnValue
    $result.ReturnValue = $null          # ALWAYS an array of the results of calling $callee
    $result.ActionComplete = $false      # Did $callee complete without an exception?
    $result.Error = $null                # $Error[0].ErrorRecord if the call failed
    $result.Tries = 0                    # How many times was $callee called?

    if($funcParameters.ContainsKey("callee"))
    {
        $callee = $funcParameters["callee"]
        $funcParameters.Remove("callee")
        $Error.Clear()
        try
        {
            # Make sure there is a function or cmdlet named $callee...
            if(($null -ne (Get-Command -Name $callee -ErrorAction Stop)) -or ($null -ne (Get-Item -Path ("Function:\{0}" -f @($callee)) -ErrorAction Stop)))
            {
                # Add the ErrorAction parameter to $funcParameters if it's not already there.
                if(-not $funcParameters.ContainsKey("ErrorAction"))
                {
                    $funcParameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop)
                } `
                else
                {
                    # Nothing, ErrorAction already specified.
                }

                # Call $callee until we succeed for fail $maxTries times.
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
                LogError ("No cmdlet or function named {0} found." -f @($callee))
                $result.Good2Go = $false
            }
        }
        catch
        {
            LogError ("No cmdlet or function named {0} found." -f @($callee))
            $result.Good2Go = $false
        }
    } `
    else
    {
        LogError "Missing callee parameter in call to ReTryCatch!"
    }

    return $result
}

function NewDatastructure
{
    # Wish more people understood classes ... $data should be a class ...
    $data = "" | Select-Object RelatedControllers, Source, Destination, Snapmirrors, SnapmirrorDestinations, Good2Go, NewSnapmirrors, NFSDatastores, DatastoreToVMHosts, AllVolumes, AllVServers, FirstPass, ActionSequence, ServicePrincipalNames, CNAMERecords, MigrateAllVolumes, VolumesToInclude, ActionSequenceFileName, AllCIFSServers
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
    $data.VolumesToInclude = @()
    $data.FirstPass = $false
    $data.ActionSequence = [System.Collections.Generic.List[System.Object]]::new()
    $data.ActionSequenceFileName = [String]::Empty

    return $data
}

function GetVServerData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$false, Position=1)]
        [System.String] $SourceVServerName,

        [Parameter(Mandatory=$false, Position=2)]
        [System.String] $DRVServerName
    )

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
            if(-not [String]::IsNullOrEmpty($SourceVServerName))
            {
                if(-not [String]::IsNullOrEmpty($DRVServerName))
                {
                    # Get a collection of all VServers...
                    LogInfo "Collecting VServers..."
                    # Get all VServer objects ...

                    $funcParams = @{
                        callee = "Get-NCVserver"
                        Controller = @($cDot.Values)
                    }

                    $result = ReTryCatch -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        $data.AllVServers = $result.ReturnValue

                        # Get enough VServers?
                        if($data.AllVServers.Length -ge 2)
                        {
                            LogInfo ("Located {0} VServer(s)." -f @($data.AllVServers.Length)) 1

                            # Find the source VServer...
                            $sourceVServers = @($data.AllVServers | Where-Object { $_.VServerName -eq $SourceVServerName })
                            if($sourceVServers.Length -eq 1)
                            {
                                # Unique source VServer was found...
                                $data.Source.VServer = $sourceVServers[0]
                                LogInfo ("Source VServer: {0}" -f @($data.Source.VServer.Identity)) 1
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

                            # Find the destination VServer...
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
                    LogError "Destination VServer name not provided in first pass of GetVServerData."
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError "Source VServer name not provided in first pass of GetVServerData."
                $data.Good2Go = $false
            }
        } `
        else
        {
            # Nothing only need to collect VServer data if we are running in the first pass
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

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
            $tmpList = [System.Collections.Generic.List[System.String]]::new()
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

                if($data.Good2Go)
                {
                    $data.VolumesToInclude = $tmpList.ToArray()
                } `
                else
                {
                    # Nothing
                }
            } `
            else
            {
                # Nothing, already displayed an error.
            }
        } `
        else
        {
            # Nothing, only fix up the volumes to include during the first pass.
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function GetVolumesData
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
        # Collect volumes we might care about.  Exclude JP_, ROOT_
        LogInfo "Collecting volumes..."

        $funcParams = @{
            callee = "Get-NCVol"
            Controller = @($cDot.Values)
        }
        $result = ReTryCatch -funcParameters $funcParams
        if($result.Good2Go)
        {
            $data.AllVolumes = @($result.ReturnValue | Where-Object { $_.Name -notmatch $Script:volumesToIgnoreRegex })
            if($data.AllVolumes.Length -gt 0)
            {
                LogInfo ("{0} volumes collected." -f @($data.AllVolumes.Length)) 1

                # Check to make sure the volumes in the list of volumes to include are valid.
                if($data.VolumesToInclude.Length -gt 0)
                {
                    $invalidIncludedVolumes = [System.Collections.Generic.List[System.String]]::new()
                    $a = 0
                    while($a -lt $data.VolumesToInclude.Length)
                    {
                        if($null -eq ($data.AllVolumes | Where-Object { ("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $data.VolumesToInclude[$a] }))
                        {
                            $idx = $invalidIncludedVolumes.BinarySearch($data.VolumesToInclude[$a])
                            if($idx -lt 0)
                            {
                                $invalidIncludedVolumes.Insert(-bnot $idx, $data.VolumesToInclude[$a])
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
        $data
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
        if($data.FirstPass)
        {
            if($null -ne $data.Source.VServer)
            {
                if(($null -ne $data.AllVolumes) -and ($data.AllVolumes.Length -gt 0))
                {
                    LogInfo "Collecting snapmirror destinations from the source VServer..."

                    # Get all the snapmirror destinations from the requested source VServer.
                    #   Include all snapmirrors if $Script:VolumesToInclude is empty, otherwise only include snapmirrors where SourceLocation is contained in $Script:VolumesToInclude
                    $funcParams = @{
                        callee = "Get-NcSnapmirrorDestination"
                        Controller = $data.Source.VServer.NcController
                        SourceVServer = $data.Source.VServer.VServerName
                    }
                    $result = ReTryCatch -funcParameters $funcParams
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
                                # Filter out snapmirrors where the source location is not included in $data.VolumesToInclude (remember, if $data.VolumesToInclude.Length -eq 0, include all snapmirrors)
                                if(($data.VolumesToInclude.Length -eq 0) -or ($data.VolumesToInclude -contains $allSourceSnapmirrorDestinations[$a].SourceLocation))
                                {
                                    # Verify there is a source volume for $allSourceSnapmirrorDestinations[$a]...
                                    $snapmirrorSourceVolumes = @($data.AllVolumes | Where-Object { ("{0}:{1}" -f @($_.VServer, $_.Name)) -eq $allSourceSnapmirrorDestinations[$a].SourceLocation })
                                    if($snapmirrorSourceVolumes.Length -eq 1)
                                    {
                                        $snapmirrorSourceVolume = $snapmirrorSourceVolumes[0]

                                        # Filter out SNAPLOCK source volumes...(if that's even possible)
                                        if($snapmirrorSourceVolume.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock")
                                        {
                                            # Verify there is a destination volume for $allSourceSnapmirrorDestinations[$a]...
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
                                } `
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
            # Nothing, only need to collect snapmirror destinations during the first pass.
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
        if($data.FirstPass)
        {
            LogInfo "Collecting related controllers data."
            if($null -ne $data.Source.VServer)
            {
                if(($null -ne $data.SnapmirrorDestinations) -and ($data.SnapmirrorDestinations.Count -gt 0))
                {
                    # Build the list of controllers involved with all the snapmirrors
                    #    Seed the list with the source controller
                    $data.RelatedControllers.Add($data.Source.VServer.NcController)
                    $a = 0
                    while($a -lt $data.SnapmirrorDestinations.Count)
                    {
                        $snapmirrorDestinationVServersByName = @($data.AllVServers | Where-Object { $_.VServerName -eq $data.SnapmirrorDestinations[$a].DestinationVserver })
                        if($snapmirrorDestinationVServersByName.Length -eq 1)
                        {
                            $existingController = $data.RelatedControllers | Where-Object { $_.Name -eq $snapmirrorDestinationVServersByName[0].NcController.Name }
                            if($null -eq $existingController)
                            {
                                $data.RelatedControllers.Add($snapmirrorDestinationVServersByName[0].NcController)
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
            # Nothing, only need to determine related controllers during the first pass.
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
        if($data.FirstPass)
        {
            LogInfo "Collecting snapmirror relationships."
            # During the first pass, collect specific snapmirrors related to this failover...
            if($null -ne $data.Source.VServer)
            {
                if(($null -ne $data.SnapmirrorDestinations) -and ($data.SnapmirrorDestinations.Count -gt 0))
                {
                    # Before we can check the other VServer peerings, we need to get all the snapmirrors related to the source VServer
                    $funcParams = @{
                        callee = "Get-NCSnapmirror"
                        Controller = $data.Source.VServer.NcController
                        Template = $true
                    }
                    $result = ReTryCatch -funcParameters $funcParams
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
                                    callee = "Get-NCSnapmirror"
                                    Controller = $data.RelatedControllers
                                    Query = $snapmirrorQueryTemplate
                                }
                                $result = ReTryCatch -funcParameters $funcParams
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
                                    LogError ("Failed to retrieve snapmirrors where {0} is the source VServer." -f @($data.Source.VServer.Identity))
                                    $data.Good2Go = $false
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
            # During a retry, we are not relying on data we collect from the source and destination VServer, but we still need
            #   the snapmirrors so we can set parameters in ExecuteActionCommand so just get a list of all of them.

            LogInfo "Refreshing snapmirror relationship data."
            $funcParams = @{
                callee = "Get-NCSnapmirror"
                Controller = @($Global:cDot.Values)
            }
            $result = ReTryCatch -funcParameters $funcParams
            if($result.Good2Go)
            {
                $result.ReturnValue.Foreach({ $data.Snapmirrors.Add($_) })
                LogInfo ("{0} snapmirrors collected." -f @($data.Snapmirrors.Count)) 1
            } `
            else
            {
                # Nothing, already displayed a message
            }
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
        if($data.FirstPass)
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
                            callee = "Get-NCCifsServer"
                            Controller = $data.Source.VServer.NcController
                            VserverContext = $data.Source.VServer.VserverName
                        }
                        $result = ReTryCatch -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            $data.Source.CifsServer = $result.ReturnValue[0]
                            LogInfo ("Is CIFS Server: {0}" -f @(($null -ne $data.Source.CIFSServer))) 1

                            if($null -ne $data.Source.CIFSServer)
                            {
                                # Get the CIFS shares for the CIFS Server which are included in $data.SnapmirrorDestination
                                $funcParams = @{
                                    callee = "Get-NcCifsShare"
                                    Controller = $data.Source.VServer.NcController
                                    VserverContext = $data.Source.VServer.VserverName
                                }
                                $result = ReTryCatch -funcParameters $funcParams
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
                                    callee = "Get-NCCifsServer"
                                    Controller = $data.Destination.VServer.NcController
                                    VserverContext = $data.Destination.VServer.VserverName
                                }
                                $result = ReTryCatch -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    $data.Destination.CIFSServer = $result.ReturnValue[0]
                                    LogInfo ("Is CIFS Server: {0}" -f @(($null -ne $data.Destination.CIFSServer))) 1

                                    if($null -ne $data.Destination.CIFSServer)
                                    {
                                        # Get the CIFS shares for the CIFS Server
                                        $funcParams = @{
                                            callee = "Get-NcCifsShare"
                                            Controller = $data.Destination.VServer.NcController
                                            VserverContext = $data.Destination.VServer.VserverName
                                        }
                                        $result = ReTryCatch -funcParameters $funcParams
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
            $data.AllCIFSServers = [System.Collections.Generic.List[DataONTAP.C.Types.Cifs.CifsServerConfig]]::new()
            LogInfo "Collecting CIFS servers..."
            $funcParams = @{
                callee = "Get-NCCifsServer"
                Controller = @($Global:cDot.Values)
            }
            $result = ReTryCatch -funcParameters $funcParams
            if($result.Good2Go)
            {
                $result.ReturnValue.ForEach({ $data.AllCIFSServers.Add($_) })
            } `
            else
            {
                LogError "Failed to collect CIFS server data."
                $data.Good2Go = $false
            }
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function GetDomainController
{
    if($null -eq $Script:domainController)
    {
        LogInfo "Acquiring domain controller..." 1
        $funcParams = @{
            callee = "Get-ADDomainController"
        }
        $result = ReTryCatch -funcParameters $funcParams
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

function GetADDomain
{
    if($null -eq $Script:adDomain)
    {
        LogInfo "Acquiring AD Domain..." 1
        $funcParams = @{
            callee = "Get-ADDomain"
        }
        $result = ReTryCatch -funcParameters $funcParams
        if($result.Good2Go)
        {
            $Script:adDomain = $result.ReturnValue[0]
        } `
        else
        {
            # Nothing -- for now..
        }
    } `
    else
    {
        # Nothing, already have the AD domain information.
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

        if($null -ne $data.Source.CIFSServer)
        {
            if($null -ne $data.Destination.CIFSServer)
            {
                LogInfo "Collecting AD data..."

                $funcParams = @{
                    callee = "Get-ADComputer"
                    Identity = $data.Source.CIFSServer.CifsServer
                    Properties = @("servicePrincipalName")
                }
                $result = ReTryCatch -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $sourceCIFSServerADComputer = $result.ReturnValue[0]

                    if($null -ne $sourceCIFSServerADComputer)
                    {
                        $data.ServicePrincipalNames = @($sourceCIFSServerADComputer.servicePrincipalName | Where-Object { $_ -notmatch $sourceCIFSServerADComputer.Name })

                        GetDomainController
                        if($null -ne $Script:domainController)
                        {
                            if($data.ServicePrincipalNames.Length -gt 0)
                            {
                                GetADDomain
                                if($null -ne $Script:adDomain)
                                {
                                    # Find the HOST/FQDN alias service principal names we need to transfer...
                                    $hostFQDNSPNs = @($data.ServicePrincipalNames | Where-Object { $_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($Script:adDomain.DNSRoot))) })
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
                                                    # Get DNS CNAME records for the source AD computer

                                                    $funcParams = @{
                                                        callee = "Get-DnsServerResourceRecord"
                                                        Name = $alias
                                                        ZoneName = $Script:adDomain.DNSRoot
                                                        ComputerName = $Script:domainController.Name
                                                        RRType = "CName"
                                                    }
                                                    $result = ReTryCatch -funcParameters $funcParams -IgnoreException
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
        if($data.FirstPass)
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
                                callee = "Get-NcNfsService"
                                Controller = $data.Source.VServer.NcController
                                VserverContext = $data.Source.VServer.VserverName
                            }
                            $result = ReTryCatch -funcParameters $funcParams
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
                                        callee = "Get-NcNetInterface"
                                        Controller = $data.Source.VServer.NcController
                                        Vserver = $data.Source.VServer.VserverName
                                    }
                                    $result = ReTryCatch -funcParameters $funcParams
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
                                                    callee = "Get-Datastore"
                                                    Server = @($Global:vCenterServers.Values)
                                                }
                                                $result = ReTryCatch -funcParameters $funcParams
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
                                                            callee = "Get-VMHost"
                                                            Server = @($Global:vCenterServers.Values)
                                                        }
                                                        $result = ReTryCatch -funcParameters $funcParams
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
                                                    callee = "Get-NcNfsService"
                                                    Controller = $data.Destination.VServer.NcController
                                                    VserverContext = $data.Destination.VServer.VserverName
                                                }
                                                $result = ReTryCatch -funcParameters $funcParams
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
                                                    callee = "Get-NcNetInterface"
                                                    Controller = $data.Destination.VServer.NcController
                                                    Vserver = $data.Destination.VServer.VserverName
                                                }
                                                $result = ReTryCatch -funcParameters $funcParams
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
            # Nothing, until the NFS piece is ready...
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function NewActionSequenceCommand
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [HashTable]
        $funcParameters
    )

    $tParams = $null
    try
    {
        $tParams = $funcParameters.Clone()
    }
    catch
    {
        LogError "Failed to clone action command parameters!"
    }

    if($null -ne $tParams)
    {
        if($tParams.ContainsKey("ErrorAction"))
        {
            $tParams.Remove("ErrorAction")
        } `
        else
        {
            # Nothing
        }
        $paramNames = @($tParams.Keys)
        if($paramNames -contains "callee")
        {
            $a = 0
            while($a -lt $paramNames.Length)
            {
                switch($tParams[$paramNames[$a]].GetType())
                {
                    { $_ -eq [NetApp.Ontapi.Filer.C.NcController] }              { $tParams[$paramNames[$a]] = $tParams[$paramNames[$a]].Identity }
                    { $_ -eq [DataONTAP.C.Types.Volume.VolumeAttributes] }       { $tParams[$paramNames[$a]] = $tParams[$paramNames[$a]].Identity }
                    { $_ -eq [Microsoft.ActiveDirectory.Management.ADComputer] } { $tParams[$paramNames[$a]] = $tParams[$paramNames[$a]].DistinguishedName }
                    default { <# Nothing, everything exports ok #> }
                }
                $a++
            }

            # Was this command completed successfully?
            $tParams.Add("Complete", $false)

            # Track the order of commands.
            $tParams.Add("SequenceNumber", $data.ActionSequence.Count)
            $data.ActionSequence.Add($tParams)
        } `
        else
        {
            LogError "Action command parameters missing 'callee'!"
        }
    } `
    else
    {
        # Nothing, already displayed a message
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
        if($data.FirstPass)
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
            # Nothing, only build new snapmirror relationships during the first pass.
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
            Swaps source and destination volumes where the destination is hosted on the requested failover VServer.
            Verifies the appropriate snapmirror policies exist.
    #>

    if($data.Good2Go)
    {
        if($data.FirstPass)
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
                            callee = "Get-NcSnapmirrorPolicy"
                            Controller = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NCController
                            # Vserver = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.VServer
                            Name = $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy
                        }
                        $result = ReTryCatch -funcParameters $funcParams
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
                            $data.Good2Go = $false
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
            # Nothing, only fix up the snapmirrors if running a first pass.
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

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
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
                            callee = "Get-NcSnapmirrorPolicy"
                            Controller = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.NcController
                            # Vserver = $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume.Vserver
                            Name = $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror.Policy
                        }
                        $result = ReTryCatch -funcParameters $funcParams
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
        } `
        else
        {
            # Nothing, only check snapmirror policies on the first pass.
        }
    } `
    else
    {
        # Nothing, already displayed a message
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

    if($data.Good2Go)
    {
        if($data.FirstPass)
        {
            LogInfo "Checking snapshot policies..." 0
            # Make sure the destination volume's cluster has the correct snapshot policy.

            $a = 0
            while($a -lt $data.NewSnapmirrors.Count)
            {
                $b = 0
                while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                {
                    # See BuildActionSequence for an explanation of the following logic...

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
                                callee = "Get-NcSnapshotPolicy"
                                Controller = $dstVolume.NcController
                            }
                            $result = ReTryCatch -funcParameters $funcParams
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
        } `
        else
        {
            # Nothing, only check snapshot policies during the first pass.
        }
    } `
    else
    {
        # Nothing, already displayed a message
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
        if($data.FirstPass)
        {
            if($null -ne $data.Destination.VServer)
            {
                if(($null -ne $data.NewSnapmirrors) -and ($data.NewSnapmirrors.Count -gt 0))
                {
                    LogInfo "Checking VServer peerings..."
                    $funcParams = @{
                        callee = "Get-NcVserverPeer"
                        Controller = $data.Destination.VServer.NcController
                        Template = $true
                    }
                    $result = ReTryCatch -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        # Get the VServer peerings for the destination VServer
                        $vServerPeerQueryTemplate = $result.ReturnValue[0]

                        if($null -ne $vServerPeerQueryTemplate)
                        {
                            $vServerPeerQueryTemplate.Applications = @("snapmirror")
                            $vServerPeerQueryTemplate.VserverUuid = $data.Destination.VServer.Uuid

                            $funcParams = @{
                                callee = "Get-NcVserverPeer"
                                Controller = $data.Destination.VServer.NcController
                                Query = $vServerPeerQueryTemplate
                            }
                            $result = ReTryCatch -funcParameters $funcParams
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
            # Nothing, only check vServer peerings during the first pass.
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function Initialize
{
    [CmdLetBinding(DefaultParameterSetName = "Default")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName,

        [Parameter(Mandatory=$false, ParameterSetName="FirstPass", Position=2)]
        [String[]]
        $VolumesToInclude,

        [Parameter(Mandatory=$false, ParameterSetName="Default", Position=0)]
        [Switch]
        $ItDoesNotMatter
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

    $data = NewDatastructure
    $data.FirstPass = $PSCmdlet.ParameterSetName -eq "FirstPass"

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
    FixVolumesToInclude -data $data -VolumesToInclude $VolumesToInclude
    GetVolumesData -data $data
    GetSnapmirrorDestinations -data $data

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

function Quoted
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Object] $myValue
    )

    $quotedValue = ""
    if ($null -ne $myValue)
    {
        # TRUE

        $myValueStr = $myValue.ToString()

        if (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # TRUE

            $quotedValue = "`"{0}`"" -f @($myValue.ToString())
        }
        else # NOT (-not [String]::IsNullOrEmpty($myValueStr))
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ($null -ne $myValue)
    {
        # FALSE

        # Nothing.
    }

    return $quotedValue
}

function ShutdownCIFSServer
{
    [CmdletBinding(DefaultParameterSetName="FirstPass")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $cifsServer = $data.AllCIFSServers | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.VServer -eq $actionCommand.VserverContext) }
            if($null -ne $cifsServer)
            {
                LogInfo ("Stopping CIFS services on: {0}~SIMULATED~" -f @($cifsServer.Identity)) 1
                if($Script:TakeAction)
                {
                    $funcParams = @{
                        callee = "Stop-NcCifsServer"
                        Controller = $cifsServer.NcController
                        VserverContext = $cifsServer.Vserver
                        Confirm = $false
                    }
                    $result = ReTryCatch -funcParameters $funcParams
                    if($result.Good2Go)
                    {
                        # Wait for the CIFS service to be down...
                        LogInfo ("Waiting for CIFS server {0} to be off-line.~SIMULATED~" -f @($cifsServer.Identity)) 1 -NoNewLine
                        $cifsServerDown = $false
                        do
                        {
                            $funcParams = @{
                                callee = "Get-NcCifsServer"
                                Controller = $cifsServer.NcController
                                VserverContext = $cifsServer.Vserver
                            }
                            $result = ReTryCatch -funcParameters $funcParams
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
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                LogError ("Failed to retrieve CIFS server data from {0}" -f @($cifsServer.Identity)) 1 -NewLine
                                $data.Good2Go = $false
                            }
                        } until ((-not $Script:TakeAction) -or (-not $data.Good2Go) -or $cifsServerDown)
                        LogInfo ""
                    } `
                    else
                    {
                        LogError ("Failed to stop CIFS services on {0}" -f @($cifsServer.Identity)) 1
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    # Nothing running in simulation mode.
                }
            } `
            else
            {
                LogError ("Unable to locate CIFS server {0}:{1} for {2}." -f @($controller.Identity, $actionCommand.VserverContext, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            $funcParams = @{
                callee = "Stop-NcCifsServer"
                Controller = $cifsServer.NcController
                VserverContext = $cifsServer.Vserver
                Confirm = $false
            }

            NewActionSequenceCommand -data $data -funcParameters $funcParams
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
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
                # Invokes ParameterSet "FirstPass"
                ShutdownCIFSServer -data $data -cifsServer $data.Source.CIFSServer
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
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function RefreshSnapmirrorObject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $tmpSnapmirror = $null

    $funcParams = @{
        callee = "Get-NCSnapmirror"
        Controller = $snapmirror.NcController
        DestinationVserver = $snapmirror.DestinationVserver
        DestinationVolume = $snapmirror.DestinationVolume
    }
    $result = ReTryCatch -funcParameters $funcParams
    if($result.Good2Go)
    {
        # Refresh the snapmirror info to see if its idle...
        $tmpSnapmirror = $result.ReturnValue[0]
        if($null -eq $tmpSnapmirror)
        {
            LogError ("Failed to refresh snapmirror object {0}." -f @($snapmirror.Identity)) 2 -NoNewLine
        } `
        else
        {
            # Nothing, got a fresh copy of $snapmirror
        }
    } `
    else
    {
        LogError ("Failed to refresh snapmirror object while waiting for status: {0} / mirror state: {1}" -f @($status2WaitFor, $mirrorState2WaitFor)) 2 -NewLine
    }

    return $tmpSnapmirror
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

    # Now, wait until the snapmirror is $status2WaitFor...
    $haveWaited = $false
    do
    {
        # Refresh the snapmirror info to see if its idle...
        $tmpSnapmirror = RefreshSnapmirrorObject -snapmirror $snapmirror
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
            $data.Good2Go = $false
        }
    } until((-not $Script:TakeAction) -or (-not $data.Good2Go) -or (($tmpSnapmirror.Status -in $statuses2WaitFor) -and ($tmpSnapmirror.MirrorState -in $mirrorStates2WaitFor)))

    if($haveWaited)
    {
        LogInfo ""
    } `
    else
    {
        # Nothing
    }

    return $tmpSnapmirror
}

function UpdateSnapmirrorObject
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
        $newSnapmirrorObject
    )

    if($data.Good2Go)
    {
        if($null -ne $tmpSM)
        {
            # Find the snapmirror by RelationshipId
            $tmpSM = $data.Snapmirrors | Where-Object { $_.RelationshipId -eq $newSnapmirrorObject.RelationshipId }
            if($null -ne $tmpSM)
            {
                $snapmirrorIdx = $data.Snapmirrors.IndexOf($tmpSM)
                if(($snapmirrorIdx -gt -1) -and ($snapmirrorIdx -lt $data.Snapmirrors.Count))
                {
                    $data.Snapmirrors[$snapmirrorIdx] = $tmpSM
                } `
                else
                {
                    $data.Good2Go = $false
                    LogError ("Unable to update in-memory snapmirror data.  Snapmirror index [{0}] out of range." -f @($snapmirrorIdx))
                }
            } `
            else
            {
                # Not sure ... what if I can't update the "master" snapmirror object??
            }
        } `
        else
        {
            # Nothing don't want to update the snapmirror object with a null one.
        }
    } `
    else
    {
        # Nothing, already displayed a message.
    }
}

function SyncSnapmirror
{
    [CmdLetBinding(DefaultParameterSetName="FirstPass")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) }
            if($null -ne $snapmirror)
            {
                LogInfo ("`r`nUpdating snapmirror: {0}...~SIMULATED~" -f @($snapmirror.Identity)) 1 -NewLine
                if($Script:TakeAction)
                {
                    $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $snapmirror -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored")

                    if($data.Good2Go)
                    {
                        $funcParams = @{
                            callee = "Invoke-NcSnapmirrorUpdate"
                            Controller = $snapmirror.NcController
                            DestinationVserver = $snapmirror.Vserver
                            DestinationVolume = $snapmirror.DestinationVolume
                            Passthru = $true
                        }

                        $result = ReTryCatch -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            $tmpSM = $result.ReturnValue[0]
                            if($null -ne $tmpSM)
                            {
                                $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $tmpSM -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored")
                                if($data.Good2Go)
                                {
                                    if($null -ne $tmpSM)
                                    {
                                        UpdateSnapmirrorObject -data $data -newSnapmirrorObject $tmpSM
                                    } `
                                    else
                                    {
                                        $data.Good2Go = $false
                                        LogError ("Unable to update in-memory snapmirror data for {0}.  Snapmirror object returned from WaitForSnapmirrorStatusAndMirrorState is null." -f @($snapmirror))
                                    }
                                } `
                                else
                                {
                                    # Nothing, already displayed a message
                                }
                            } `
                            else
                            {
                                LogError "No snapmirror object returned after invoking snapmirror update." 2
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError ("Failed to update snapmirror {0}" -f @($snapmirror.Identity))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed a message
                    }
                } `
                else
                {
                    # If we are running in simulation mode or running the first pass, the following line ensures UpdateSnapmirror returns a non-null value for $tmpSM
                    $tmpSM = $snapmirror
                }
            } `
            else
            {
                LogError ("Unable to locate snapmirror destination {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.DestinationVserver, $actionCommand.DestinationVserver, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            $funcParams = @{
                callee = "Invoke-NcSnapmirrorUpdate"
                Controller = $snapmirror.NcController
                DestinationVserver = $snapmirror.Vserver
                DestinationVolume = $snapmirror.DestinationVolume
                Passthru = $true
            }
            NewActionSequenceCommand -data $data -funcParameters $funcParams

            # If we are running in simulation mode or running the first pass, the following line ensures UpdateSnapmirror returns a non-null value for $tmpSM
            $tmpSM = $snapmirror
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    if(-not $data.Good2Go)
    {
        $tmpSM = $null
    } `
    else
    {
        # Nothing, leave $tmpSM as is.
    }

    return $tmpSM
}

function BreakSnapmirror
{
    [CmdLetBinding(DefaultParameterSetName="FirstPass")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) }
            if($null -ne $snapmirror)
            {
                # Make sure the snapmirror is idle/snapmirrored|broken-off before proceeding (we won't break snapmirrors which are already broken off)...
                $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $snapmirror -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored","broken-off")

                if($tmpSM.MirrorState -ne "broken-off")
                {
                    LogInfo ("Breaking snapmirror {0}...~SIMULATED~" -f @($snapmirror.Identity)) 1
                    if($Script:TakeAction)
                    {
                        $funcParams = @{
                            callee = "Invoke-NcSnapmirrorBreak"
                            Controller = $snapmirror.NcController
                            DestinationVserver = $snapmirror.Vserver
                            DestinationVolume = $snapmirror.DestinationVolume
                            Confirm = $false
                            Passthru = $true
                        }

                        $result = ReTryCatch -funcParameters $funcParams -maxTries 5 -secondsToPause 10
                        if($result.Good2Go)
                        {
                            $tmpSM = $result.ReturnValue[0]
                            if($null -ne $tmpSM)
                            {
                                $snapmirror = $tmpSM
                                UpdateSnapmirrorObject -data $data -newSnapmirrorObject $tmpSM
                            } `
                            else
                            {
                                LogError "No snapmirror object returned after invoking snapmirror break." 2
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError ("Failed to break snapmirror {0}." -f @($snapmirror.Identity))
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        # Nothing, just pretending...
                    }
                } `
                else
                {
                    # Nothing, the snapmirror is already broken off.
                }
            } `
            else
            {
                LogError ("Unable to locate snapmirror destination {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.DestinationVserver, $actionCommand.DestinationVserver, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            # Make sure the snapmirror is idle/snapmirrored|broken-off before proceeding (we won't break snapmirrors which are already broken off)...
            $tmpSM = WaitForSnapmirrorStatusAndMirrorState -snapmirror $snapmirror -statuses2WaitFor @("idle") -mirrorStates2WaitFor @("snapmirrored","broken-off")

            if($null -ne $tmpSM)
            {
                if($tmpSM.MirrorState -ne "broken-off")
                {
                    $funcParams = @{
                        callee = "Invoke-NcSnapmirrorBreak"
                        Controller = $snapmirror.NcController
                        DestinationVserver = $snapmirror.Vserver
                        DestinationVolume = $snapmirror.DestinationVolume
                        Confirm = $false
                        Passthru = $true
                    }

                    NewActionSequenceCommand -data $data -funcParameters $funcParams

                    # Pretend we broke the snapmirror...
                    $snapmirror.MirrorState = "broken-off"
                } `
                else
                {
                    # Nothing, snapmirror is already broken-off.
                }
            } `
            else
            {
                LogError ("Failed to refresh snapmirror data for {0}." -f @($snapmirror.Identity))
                $data.Good2Go = $false
            }
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    return $snapmirror
}

function Need2UpdateSnapshotPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $destinationVolume
    )

    $needToChange = $false
    $newPolicyName = [String]::Empty
    if($data.Good2Go)
    {
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
                # Nothing, leave the source snapshot policy name as it is.
            }

            # Is the snapshot policy on the destination volume "different" than the policy on the source?
            #    Does it NOT end with the snapshot policy?  "clst_snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained" -notmatch "snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained$"
            if($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy -notmatch ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))
            {
                LogInfo "Getting snapshot policies from the destination cluster which match the source volume snapshot policy" 2
                # Get any snapshot policy from the destination cluster with a name that matches the source volume's snapshot policy name...
                $funcParams = @{
                    callee = "Get-NcSnapshotPolicy"
                    Controller = $destinationVolume.NcController
                }
                $result = ReTryCatch -funcParameters $funcParams
                if($result.Good2Go)
                {
                    $destinationSnapshotPolicies = @($result.ReturnValue | Where-Object { $_.Policy -match $sourceVolumeSnapshotPolicyName })

                    # Did we find a single match?
                    if($destinationSnapshotPolicies.Length -eq 1)
                    {
                        # Yes, different policy...
                        $needToChange = $true
                        $newPolicyName = $destinationSnapshotPolicies[0].Policy
                    } `
                    elseif ($destinationSnapshotPolicies.Length -gt 1)
                    {
                        LogError ("{0} snapshot policies found which match: {1}." -f @($destinationSnapshotPolicies.Length, ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))) 3
                        $destinationSnapshotPolicies.ForEach({
                            LogError ("{0}" -f @($_)) 4
                        })
                        LogError ("Please update manually!")
                        $data.Good2Go = $false
                    } `
                    else  # there was no matching snapshot policy found on the destination
                    {
                        LogError ("No snapshot policies found which match: {0} on {1}." -f @(("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $destinationVolume.NcController.Name)) 3
                        LogError "Please update manually!"
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError ("Failed to retrieve snapshot policies from {0}." -f @($destinationVolume.NcController.Identity))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, no changes needed.
                # LogInfo ("Source volume snapshot policy: {0} seems to match {1}.  No changes needed." -f @($sourceVolumeSnapshotPolicyName, $destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 2
            }
        } `
        else
        {
            LogWarning ("No snapshot policy found on source volume: {0}" -f @($sourceVolume.Identity)) 2
            LogWarning "Ensure you check snapshot policies." 2
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    return @($needToChange, $newPolicyName)
}

function UpdateSnapshotPolicy
{
    [CmdletBinding(DefaultParameterSetName="FirstPass")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=2)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $destinationVolume,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            LogInfo "Checking snapshot policy..." 1

            $sourceVolume = $data.AllVolumes | Where-Object { $_.Identity -eq $actionCommand.SourceVolume }
            if($null -ne $sourceVolume)
            {
                $destinationVolume = $data.AllVolumes | Where-Object { $_.Identity -eq $actionCommand.DestinationVolumeVolume }
                if($null -ne $destinationVolume)
                {
                    $needToChangeSnapshotPolicy, $newSnapshotPolicyName = Need2UpdateSnapshotPolicy -data $data -sourceVolume $sourceVolume -destinationVolume $destinationVolume
                    if($data.Good2Go)
                    {
                        if($needToChangeSnapshotPolicy)
                        {
                            if(-not [String]::IsNullOrEmpty($newSnapshotPolicyName))
                            {
                                # Yes, use it for the snapshot policy on the destination volume.
                                $destinationSnapshotPolicyName = $destinationSnapshotPolicies[0].Policy
                                $funcParams = @{
                                    callee = "Get-NCVol"
                                    Controller = $destinationVolume.NcController
                                    Template = $true
                                }
                                $result = ReTryCatch -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    # Set up a query object to ensure we update the correct destination volume.
                                    $queryObj = $result.ReturnValue[0]

                                    Initialize-NcObjectProperty -Object $queryObj -Name VolumeIdAttributes
                                    $queryObj.VolumeIdAttributes.Uuid = $destinationVolume.VolumeIdAttributes.Uuid

                                    $funcParams = @{
                                        callee = "Get-NCVol"
                                        Controller = $destinationVolume.NcController
                                        Query = $queryObj
                                    }
                                    $result = ReTryCatch -funcParameters $funcParams
                                    if($result.Good2Go)
                                    {
                                        # Set up a volume update object to set the snapshot policy
                                        $updateObj = $result.ReturnValue[0]
                                        Initialize-NcObjectProperty -Object $updateObj -Name VolumeSnapshotAttributes
                                        $updateObj.VolumeSnapshotAttributes.SnapshotPolicy = $newSnapshotPolicyName
                                        LogInfo ("Updating snapshot policy on {0} to {1}.~SIMULATED~" -f @($destinationVolume.Identity, $newSnapshotPolicyName)) 3

                                        if($Script:TakeAction)
                                        {
                                            <# Step 4 make sure the snapshot policy is correct on the destination volume.
                                                #Update snapshot policy on new source
                                                # NOTE: EDC snapshot policies are pre-pended with clst_  Check this.
                                                vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                            #>
                                            $funcParams = @{
                                                callee = "Update-NcVol"
                                                Controller = $destinationVolume.NcController
                                                Query = $queryObj
                                                Attributes = $updateObj
                                            }
                                            $result = ReTryCatch -funcParameters $funcParams
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
                                                        # Shouldn't have to do anything here... the next block should cover it...BUT... just to make sure, we'll set $data.Good2Go = $false since there weren't any successes.
                                                        $data.Good2Go = $false
                                                    }

                                                    if($updateResult.FailureList.Length -gt 0)
                                                    {
                                                        LogError "Failed to update snapshot policy on:" 3
                                                        $updateResult.FailureList.Foreach({
                                                            LogError ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                                                        })
                                                        $data.Good2Go = $false
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
                                                $data.Good2Go = $false
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
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    LogError ("Failed to create volume query template from {0}." -f @($destinationVolume.NcController.Identity))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                LogError ("Missing new snapshot policy name while trying to update snapshot policy for {0}." -f @($destinationVolume.Identity))
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            # Nothing, snapshot policy is good.
                        }
                    } `
                    else
                    {
                        # Nothing already displayed a message
                    }
                } `
                else
                {
                    LogError ("Unable to location destination volume: {0} for UpdateSnapshotPolicy." -f @($actionCommand.DestinationVolume))
                    $data.Good2Go = $false
                }
            } `
            else
            {
                LogError ("Unable to location source volume: {0} for UpdateSnapshotPolicy." -f @($actionCommand.SourceVolume))
                $data.Good2Go = $false
            }
        } `
        else
        {
            $needToChangeSnapshotPolicy, $newSnapshotPolicyName = Need2UpdateSnapshotPolicy -data $data -sourceVolume $sourceVolume -destinationVolume $destinationVolume
            if($data.Good2Go)
            {
                if($needToChangeSnapshotPolicy)
                {
                    # Update-NCVol is a bit different.  I can't use just the Update-NCVol parameters for the action command.
                    #   Since it needs the Query and Attributes parameter, I need to be able to rehydrate them from the
                    #   source and destination volumes, so I'll build an action command with those.
                    $funcParams = @{
                        callee = "Update-NcVol"
                        Controller = $destinationVolume.NcController
                        SourceVolume =  $sourceVolume
                        DestinationVolume = $destinationVolume
                    }

                    NewActionSequenceCommand -data $data -funcParameters $funcParams
                } `
                else
                {
                    # Nothing, snapshot policy is good.
                }
            } `
            else
            {
                # Nothing, already displayed a message
            }
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function IsVolumeSISEnabled
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume
    )

    $volSISEnabled = $false

    $funcParams = @{
        callee = "Get-NcSis"
        Controller = $volume.NcController
        VserverContext = $volume.VServer
        Name = $volume.Name
    }
    $result = ReTryCatch -funcParameters $funcParams
    if($result.Good2Go)
    {
        $volSIS = $result.ReturnValue[0]

        # If Get-NCSis returns a null value, then storage efficiencies are not enabled.
        $volSISEnabled = ($null -eq $volSIS) -or ($volSIS.State -eq "enabled")
    } `
    else
    {
        LogError ("Failed to determine status of volume efficiency for {0}." -f @($volume.Identity))
        $data.Good2Go = $false
    }

    return $volSISEnabled
}

function EnableVolumeEfficiency
{
    [CmdletBinding(DefaultParameterSetName="FirstPass")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    # It's not imperative that we enable storage efficiency, so we'll only set $data.Good2Go = $false when the script needs to stop.
    $good2Go = $true
    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $volume = $data.AllVolumes | Where-Object { ($_.Name -eq $actionCommand.Name) -and ($_.Vserver -eq $actionCommand.VserverContext) -and ($_.NCController.Identity -eq $controller.Identity) }
            if($null -ne $volume)
            {
                $volSISEnabled = IsVolumeSISEnabled -data $data -volume $volume
                if($data.Good2Go)
                {
                    if(-not $volSISEnabled)
                    {
                        # Not enabled, so let's enable it...
                        LogInfo ("Storage efficiency not enabled.  Enabling it.~SIMULATED~") 2

                        if($Script:TakeAction)
                        {
                            # I can reuse $funcParams ... sort of...
                            if($funcParams.ContainsKey("callee"))
                            {
                                $funcParams["callee"] = "Enable-NcSis"
                            } `
                            else
                            {
                                $funcParams.Add("callee", "Enable-NcSis")
                            }
                            <# Step 5a: Update volume efficiency settings on the destination volume.
                                #Enable/update storage efficiency on new source
                                --> vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                    vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                            #>
                            $result = ReTryCatch -funcParameters $funcParams
                            if($result.Good2Go)
                            {
                                LogInfo "Verifying storage efficiency was enabled..." 2
                                $volSISEnabled = IsVolumeSISEnabled -data $data -volume $volume
                                if($data.Good2Go)
                                {
                                    if($volSISEnabled)
                                    {
                                        LogInfo "Success" 3
                                    } `
                                    else
                                    {
                                        LogError "Failed" 3
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

                    if(-not $good2Go)
                    {
                        LogWarning "Manually enable storage efficiency as required." 3
                    } `
                    else
                    {
                        # Nothing
                    }
                } `
                else
                {
                    # Nothing, already displayed a message
                }
            } `
            else
            {
                LogError ("Unable to locate volume {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.VserverContext, $actionCommand.Name, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            $volSISEnabled = IsVolumeSISEnabled -data $data -volume $volume
            if($data.Good2Go)
            {
                if(-not $volSISEnabled)
                {
                    $funcParams = @{
                        callee = "Enable-NcSis"
                        Controller = $volume.NcController
                        VserverContext = $volume.VServer
                        Name = $volume.Name
                    }

                    NewActionSequenceCommand -data $data -funcParameters $funcParams
                } `
                else
                {
                    LogInfo "Storage efficiency already enabled." 2
                }
            } `
            else
            {
                # Nothing, already displayed a message
            }
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    return $good2Go
}

function SetVolumeEfficiency
{
    [CmdletBinding(DefaultParameterSetName="FirstPass")]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    $good2Go = $true
    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $volume = $data.AllVolumes | Where-Object { ($_.Name -eq $actionCommand.Name) -and ($_.Vserver -eq $actionCommand.VserverContext) -and ($_.NCController.Identity -eq $controller.Identity) }
            if($null -ne $volume)
            {
                $volSISEnabled = IsVolumeSISEnabled -data $data -volume $volume
                if($data.Good2Go)
                {
                    if(-not $volSISEnabled)
                    {
                        # I can use the same actionCommand for EnableVolumeEfficiency since the only parameters in $actionCommand that EnableVolumeEfficiency
                        #    really cares about are "Name" - for the volume name and "VServerContext"
                        $volSISEnabled = EnableVolumeEfficiency -data $data -actionCommand $actionCommand -controller $controller
                    } `
                    else
                    {
                        # Nothing, volume SIS already enabled.
                    }

                    # Now, volume SIS should be enabled, but let's make sure again.
                    if($volSISEnabled)
                    {
                        if($Script:TakeAction)
                        {
                            <# Step 5b: Update volume efficiency settings on the destination volume.
                                #Enable/update storage efficiency on new source
                                    vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                --> vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                            #>
                            $funcParams = @{
                                callee = "Set-NcSis"
                                Controller = $volume.NcController
                                VserverContext = $volume.VServer
                                Name = $volume.Name
                                Compression = $true
                                InlineCompression = $true
                                Policy = "default"
                            }

                            $result = ReTryCatch -funcParameters $funcParams
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
                            # Nothing, just pretending.
                        }
                    } `
                    else
                    {
                        LogInfo "Storage efficiency not enabled." 2
                        $good2Go = $false
                    }

                    if(-not $good2Go)
                    {
                        LogWarning "Manually update storage efficiencies settings as required." 3
                    } `
                    else
                    {
                        # Nothing
                    }
                } `
                else
                {
                    # Nothing, already displayed a message
                }
            } `
            else
            {
                LogError ("Unable to locate volume {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.VserverContext, $actionCommand.Name, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            # During the first pass, it's difficult to know if we need to set the storage efficiency settings or not, so I'll just assume
            #    they need to be set, and let the second pass deal with it.
            $funcParams = @{
                callee = "Set-NcSis"
                Controller = $volume.NcController
                VserverContext = $volume.VServer
                Name = $volume.Name
                Compression = $true
                InlineCompression = $true
                Policy = "default"
            }

            NewActionSequenceCommand -data $data -funcParameters $funcParams
        }
    } `
    else
    {
        # Nothing, already displayed a message
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
    $good2Go = EnableVolumeEfficiency -data $data -volume $volume
    if($good2Go)
    {
        $good2Go = SetVolumeEfficiency -data $data -volume $volume
    } `
    else
    {
        # Nothing, already displayed a message.
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
        callee = "Get-NcSnapmirror"
        Controller = $snapmirror.NcController
        VserverContext = $snapmirror.Vserver
        SourceVserver = $snapmirror.SourceVserver
        SourceVolume = $snapmirror.SourceVolume
    }
    $result = ReTryCatch -funcParameters $funcParams
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
    [CmdLetBinding(DefaultParameterSetName="FirstPass")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=0)]
        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, ParameterSetName="FirstPass", Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand,

        [Parameter(Mandatory=$true, ParameterSetName="ProcessActionSequence", Position=2)]
        [ValidateNotNullOrEmpty()]
        [NetApp.Ontapi.Filer.C.NcController]
        $controller
    )

    if($data.Good2Go)
    {
        if($PSCmdlet.ParameterSetName -eq "ProcessActionSequence")
        {
            $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) }

            if($null -ne $snapmirror)
            {
                $data.Good2Go = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus "idle"

                if($data.Good2Go)
                {
                    LogInfo ("Removing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
                    if($Script:TakeAction)
                    {
                        $funcParams = @{
                            callee = "Remove-NcSnapmirror"
                            Controller = $snapmirror.NcController
                            DestinationVolume = $snapmirror.DestinationVolume
                            DestinationVserver = $snapmirror.DestinationVserver
                            Confirm = $false
                        }
                        $result = ReTryCatch -funcParameters $funcParams
                        if($result.Good2Go)
                        {
                            # I can reuse $funcParams...sort of
                            $funcParams.Remove("Confirm")
                            if($funcParams.ContainsKey("callee"))
                            {
                                $funcParams["callee"] = "Get-NCSnapmirror"
                            } `
                            else
                            {
                                $funcParams.Add("callee", "Get-NCSnapmirror")
                            }
                            $tSM = $null
                            $tries = 0
                            do
                            {
                                $tries++
                                $result = ReTryCatch -funcParameters $funcParams
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
                                        # We'll set $data.Good2Go after the do-while loop.
                                    } `
                                    else
                                    {
                                        # Nothing... yet
                                    }
                                }
                            } while(($null -ne $tSM) -and ($tries -lt $Script:maxOperationRetries))

                            $data.Good2Go = ($null -eq $tSM)
                            if($data.Good2Go)
                            {
                                # Nothing, we confirmed the snapmirror was deleted.
                            } `
                            else
                            {
                                LogError ("Unable to confirm if snapmirror {0} was removed.  It appears to still exist on the destination." -f @($snapmirror.Identity))
                            }
                        } `
                        else
                        {
                            LogError ("Failed to remove snapmirror {0}." -f @($snapmirror.Identity)) 2
                            $data.Good2Go = $false
                        }
                    } `
                    else
                    {
                        # Nothing, simulation only.
                    }
                } `
                else
                {
                    # Nothing, already displayed a message
                }
            } `
            else
            {
                LogError ("Unable to locate snapmirror destination {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.DestinationVserver, $actionCommand.DestinationVserver, $actionCommand.callee))
                $data.Good2Go = $false
            }
        } `
        else
        {
            $funcParams = @{
                callee = "Remove-NcSnapmirror"
                Controller = $snapmirror.NcController
                DestinationVolume = $snapmirror.DestinationVolume
                DestinationVserver = $snapmirror.DestinationVserver
                Confirm = $false
            }

            NewActionSequenceCommand -data $data -funcParameters $funcParams
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }

    if(-not $data.FirstPass)
    {
    } `
    else
    {
        # Nothing
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
        callee = "Get-NCSnapmirror"
        Controller = $snapmirror.NcController
        VserverContext = $snapmirror.Vserver
        DestinationVolume = $snapmirror.DestinationVolume
    }
    $result = ReTryCatch -funcParameters $funcParams
    if($result.Good2Go)
    {
        $snapmirrorReady = ($null -eq $result.ReturnValue[0]) -or (-not $Script:TakeAction) -or $data.FirstPass
        if($snapmirrorReady)
        {
            # Now, confirm the relationship DOES exist at the source
            $funcParams = @{
                callee = "Get-NCSnapmirrorDestination"
                Controller = $sourceVolume.NcController
                SourceVServer = $sourceVolume.Vserver
                SourceVolume = $sourceVolume.Name
                DestinationVserver = $snapmirror.DestinationVserver
                DestinationVolume = $snapmirror.DestinationVolume
            }
            $result = ReTryCatch -funcParameters $funcParams
            if($result.Good2Go)
            {
                $snapmirrorReady = ($null -ne $result.ReturnValue[0]) -or (-not $Script:TakeAction) -or $data.FirstPass
                if($snapmirrorReady)
                {
                    if($Script:TakeAction)
                    {
                        # Release the snapmirror relationship at the source.
                        $funcParams = @{
                            callee = "Invoke-NcSnapmirrorRelease"
                            Controller = $sourceVolume.NcController
                            SourceVserver = $sourceVolume.Vserver
                            SourceVolume = $sourceVolume.Name
                            DestinationVolume = $snapmirror.DestinationVolume
                            DestinationVserver = $snapmirror.DestinationVserver
                            RelationshipId = $snapmirror.RelationshipId
                            Confirm = $false
                        }

                        if($data.FirstPass)
                        {
                            NewActionSequenceCommand -data $data -funcParameters $funcParams
                        } `
                        else
                        {
                            LogInfo ("Releasing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
                            $result = ReTryCatch -funcParameters $funcParams
                            if($result.Good2Go)
                            {
                                # Confirm the snapmirror relationship was released.
                                # Reuse $funcParams with 3 changes...
                                $funcParams.Remove("Confirm")
                                $funcParams.Remove("RelationshipId")
                                if($funcParams.ContainsKey("callee"))
                                {
                                    $funcParams["callee"] = "Get-NCSnapmirrorDestination"
                                } `
                                else
                                {
                                    $funcParams.Add("callee", "Get-NCSnapmirrorDestination")
                                }
                                $result = ReTryCatch -funcParameters $funcParams
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
        if($Script:TakeAction)
        {
            $funcParams = @{
                callee = "New-NcSnapmirror"
                Controller = $dstVolume.NCController
                DestinationVserver = $dstVolume.VServer
                DestinationVolume = $dstVolume.Name
                SourceVolume = $srcVolume.Name
                SourceVserver = $srcVolume.VServer
                Policy = $snapmirrorPolicyName
            }

            if($data.FirstPass)
            {
                NewActionSequenceCommand -data $data -funcParameters $funcParams

                # Create a bogus snapmirror for TakeAction to pass on to ResyncSnapmirror
                $newSnapmirror = [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]::new()
                $newSnapmirror.SourceVserver = $srcVolume.Vserver
                $newSnapmirror.SourceVolume = $srcVolume.Name
                $newSnapmirror.SourceLocation = "{0}:{1}" -f @($srcVolume.Vserver, $srcVolume.Name)
                $newSnapmirror.DestinationVserver = $dstVolume.Vserver
                $newSnapmirror.DestinationVolume = $dstVolume.Name
                $newSnapmirror.DestinationLocation = "{0}:{1}" -f @($dstVolume.Vserver, $dstVolume.Name)
                $newSnapmirror.NcController = $dstVolume.NcController
            } `
            else
            {
                LogInfo ("Creating snapmirror source: {0} destination: {1}~SIMULATED~" -f @($srcVolume.Identity, $dstVolume.Identity)) 1
                $result = ReTryCatch -funcParameters $funcParams
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
        if($Script:TakeAction)
        {
            $funcParams = @{
                callee = "Invoke-NcSnapmirrorResync"
                Controller = $snapmirror.NcController
                DestinationVserver = $snapmirror.DestinationVserver
                DestinationVolume = $snapmirror.DestinationVolume
            }

            if($data.FirstPass)
            {
                NewActionSequenceCommand -data $data -funcParameters $funcParams
            } `
            else
            {
                LogInfo ("Resyncing snapmirror {0}~SIMULATED~" -f @($snapmirror.Identity)) 1
                $result = ReTryCatch -funcParameters $funcParams
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
        callee = "Get-ADComputer"
        Identity = $computerName
        Properties = @("servicePrincipalName", "DNSHostName")
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
    $result = ReTryCatch -funcParameters $funcParams
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
            callee = "Set-ADComputer"
            Instance = $adComp
            PassThru = $true
        }

        # If a domain controller is available, add it to the parameter hash table
        if($null -ne $Script:domainController)
        {
            $funcParams.Add("Server", $Script:domainController.Name)
        } `
        else
        {
            # Nothing.
        }

        if($data.FirstPass)
        {
            $funcParams.Add("servicePrincipalNames", $adComp.servicePrincipalName)
            NewActionSequenceCommand -data $data -funcParameters $funcParams
        } `
        else
        {
            $result = ReTryCatch -funcParameters $funcParams
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

    <#
        Until the SPN changes are committed to AD, this function will not know which SPNs to create aliases for, so...

        If the script is running in simulation mode ($Script:TakeAction -eq $false) or running a first pass ($data.FirstPass -eq $true), then for this function to "feel" correct, it
        has to use the service principal names from the source computer object as the basis of what aliases to register CNAME records for.  However, it will still need to use the
        destination computer object's DNSHostName for what host name to create the alias for.

                    Source:                                             Destination:
                        Host: DEN-SMB01                                     Host: DENDR-SMB01
                        DNSHostName: DEN-SMB01.POWERENG.COM                 DNSHostName: DENDR-SMB01.POWERENG.COM     <--- Host name to add the CNAME record for
                        SPNs:                                               SPNs:
                            *HOST/litnas1.powereng.com                          HOST/dendr-smb01.powereng.com
                            HOST/litnas1                                        HOST/DENDR-SMB01
                            *HOST/litfs1.powereng.com
                            HOST/litfs1
                            *HOST/denfs1.powereng.com
                            HOST/denfs1
                            CIFS/litnas1.powereng.com
                            CIFS/litnas1
                            CIFS/litfs1.powereng.com
                            CIFS/litfs1
                            CIFS/denfs1.powereng.com
                            CIFS/denfs1
                            HOST/den-smb01.powereng.com
                            HOST/DEN-SMB01
                        * = SPNs to create CNAME records.

    #>
    if($data.Good2Go)
    {
        if($null -ne $data.Destination.CIFSServer)
        {
            GetDomainController
            if($null -ne $Script:domainController)
            {
                if(-not $data.FirstPass)
                {
                    LogInfo "Migrating CNAME records...~SIMULATED~" 1
                } `
                else
                {
                    # Nothing
                }

                GetADDomain

                if($null -ne $Script:adDomain)
                {
                    if(-not $data.FirstPass)
                    {
                        LogInfo ("Acquired AD Domain: {0}" -f @($Script:adDomain.DNSRoot)) 1
                    } `
                    else
                    {
                        # Nothing
                    }

                    # Computer name for the AD computer object where we will get the DNSHostName value from.
                    $dnsHostNameSourceADComputerName = $data.Destination.CIFSServer.CifsServer

                    # If we are running in simulation mode or running pass 1, use the source CIFS server because the destination CIFS server will not have the right service principal names attached to it yet.
                    if((-not $Script:TakeAction) -or ($data.FirstPass))
                    {
                        # Computer name for the AD computer object where we will get the service principal name values from.
                        $spnSourceADComputerName = $data.Source.CIFSServer.CifsServer

                    } `
                    else
                    {
                        # Computer name for the AD computer object where we will get the service principal name values from.
                        $spnSourceADComputerName = $data.Destination.CIFSServer.CifsServer
                    }

                    if(-not $data.FirstPass)
                    {
                        LogInfo ("Getting computer objects for {0} and {1} from AD." -f @($spnSourceADComputerName, $dnsHostNameSourceADComputerName)) 1
                    } `
                    else
                    {
                        # Nothing
                    }
                    $spnSourceADComputer = GetADComputer -computerName $spnSourceADComputerName
                    if($null -ne $spnSourceADComputer)
                    {
                        $hostSPNsToRegisterCNAMEsFor = @($spnSourceADComputer.servicePrincipalName | Where-Object { ($_ -notmatch $spnSourceADComputer.Name) -and ($_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($Script:adDomain.DNSRoot)))) })
                        if($hostSPNsToRegisterCNAMEsFor.Length -gt 0)
                        {
                            $dnsHostNameSourceADComputer = GetADComputer -computerName $dnsHostNameSourceADComputerName
                            if($null -ne $dnsHostNameSourceADComputer)
                            {
                                $hostNameToAlias = $dnsHostNameSourceADComputer.DNSHostName.ToLower()
                                if(-not [String]::IsNullorEmpty($hostNameToAlias))
                                {
                                    $a = 0
                                    while($a -lt $hostSPNsToRegisterCNAMEsFor.Length)
                                    {
                                        $hostSPNToRegisterCNAMEsFor = $hostSPNsToRegisterCNAMEsFor[$a]

                                        if((-not [String]::IsNullOrEmpty($hostSPNToRegisterCNAMEsFor)) -and ($hostSPNToRegisterCNAMEsFor -match "^HOST/([^.]+)\."))
                                        {
                                            $alias = $Matches[1]

                                            if(-not $data.FirstPass)
                                            {
                                                LogInfo ("Registering CNAME {0} alias for {1}.~SIMULATED~" -f @($alias, $hostNameToAlias)) 1 -NoNewLine
                                            } `
                                            else
                                            {
                                                # Nothing
                                            }

                                            if($Script:TakeAction)
                                            {
                                                $funcParams = @{
                                                    callee = "Add-DnsServerResourceRecordCName"
                                                    Name = $alias
                                                    HostNameAlias = $hostNameToAlias
                                                    ZoneName = $Script:adDomain.DNSRoot
                                                    ComputerName = $Script:domainController.Name
                                                }

                                                if($data.FirstPass)
                                                {
                                                    NewActionSequenceCommand -data $data -funcParameters $funcParams
                                                } `
                                                else
                                                {
                                                    $result = ReTryCatch -funcParameters $funcParams
                                                    if($result.Good2Go)
                                                    {
                                                        LogInfo " Successful"
                                                    } `
                                                    else
                                                    {
                                                        LogWarning " Failed"
                                                        $data.Good2Go = $false
                                                    }
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
                                    LogWarning ("No DNS Host name for {0}.  Check CNAME records." -f @($dnsHostNameSourceADComputer.Name))
                                }
                            } `
                            else
                            {
                                # Nothing, already displayed a message
                            }
                        } `
                        else
                        {
                            # Nothing, no SPNs on the computer object that don't match its name.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed a message
                    }
                } `
                else
                {
                    LogWarning "Failed to acquire AD domain data.  CNAME records will not transferred." 3
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
                callee = "Start-NcCifsServer"
                Controller = $cifsServer.NcController
                VserverContext = $cifsServer.Vserver
                Confirm = $false
            }

            if($data.FirstPass)
            {
                NewActionSequenceCommand -data $data -funcParameters $funcParams
            } `
            else
            {
                $result = ReTryCatch -funcParameters $funcParams
                if($result.Good2Go)
                {
                    # Wait for the CIFS service to be up...
                    LogInfo ("Waiting for CIFS server {0} to be on-line." -f @($cifsServer.Identity)) 2 -NoNewLine
                    $funcParams.Remove("Confirm")
                    if($funcParams.ContainsKey("callee"))
                    {
                        $funcParams["callee"] = "Get-NcCifsServer"
                    } `
                    else
                    {
                        $funcParams.Add("callee", "Get-NcCifsServer")
                    }
                    do
                    {
                        $result = ReTryCatch -funcParameters $funcParams
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

                if(-not $data.Good2Go)
                {
                    LogWarning ("Please remember to check CIFS services on {0}" -f @($cifsServer.Identity)) 1
                } `
                else
                {
                    # Nothing, all seems well
                }
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
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function BuildActionSequence
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
        if($data.FirstPass)
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
                    # Only create and resync the new snapmirror(s) if the old snapmirrors are completely processed.
                    $newSnapmirrorsGood2Go = $true

                    # First, tear down all the old snapmirrors for the source volume...
                    $b = 0
                    while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                    {
                        $snapmirrorDeleted = $snapmirrorReleased = $false
                        $tmpSM = $null

                        <#
                            Track the status for the snapmirror object we are processing.  The idea is, if something goes wrong
                                with a single snapmirror, we will stop processing it, but proceed with the rest, as best we can.

                            NOTE: Remember, do NOT set $data.Good2Go in many of the following functions, or we'll stop the script
                                    completely.
                        #>
                        # Step 2: Update snapmirror
                        # Invokes ParameterSet "FirstPass"
                        $tmpSM = SyncSnapmirror -data $data -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror

                        if($data.Good2Go)
                        {
                            if($null -ne $tmpSM)
                            {
                                # Replace the snapmirror object we are tracking with the snapmirror object returned from UpdateSnapmirror.  Its status may have changed.
                                $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror = $tmpSM

                                # Step 3: Break snapmirror
                                # Invokes ParameterSet "FirstPass"
                                $tmpSM = BreakSnapmirror -data $data -snapmirror $data.NewSnapmirrors[$a].Relationships[$b].Snapmirror

                                if($data.Good2Go)
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
                                        # Invokes ParameterSet "FirstPass"
                                        UpdateSnapshotPolicy -data $data -sourceVolume $data.NewSnapmirrors[$a].OriginalSourceVolume -destinationVolume $dstVolume

                                        if($data.Good2Go)
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
                        $newSnapmirrorCreated = $newSnapmirrorResyncd = $data.FirstPass
                        $newSnapmirror = $null

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

            # And finally, since the first pass is complete...
            $data.FirstPass = $false
        } `
        else
        {
            # Nothing, this function only performs the first pass.
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function SaveActionSequence
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    if($data.ActionSequence.Count -gt 0)
    {
        $actionSequenceJSON = $data.ActionSequence | ConvertTo-Json
        # $actionSequenceJSON = $data.ActionSequence | ConvertTo-Json | Set-Clipboard

        if([String]::IsNullOrEmpty($data.ActionSequenceFileName))
        {
            try
            {
                $tempPath = [System.IO.Path]::GetTempPath()
            }
            catch
            {
                $tempPath = $HOME
            }
            $data.ActionSequenceFileName = "{0}{1}-{2}-{3}.json" -f @($tempPath, $data.Source.VServer.Vserver, $data.Destination.VServer.Vserver, [DateTime]::Now.Ticks)
        } `
        else
        {
            # Nothing reuse the existing .JSON file.
        }

        try
        {
            Set-Content -Path $data.ActionSequenceFileName -Value $actionSequenceJSON -Force -Confirm:$false
            LogInfo ("Failover retry file: {0}" -f @($data.ActionSequenceFileName)) -NewLine
        }
        catch
        {
            LogError ("Failed to save/update action sequence JSON file: {0}!" -f @($data.ActionSequenceFileName))
        }
    } `
    else
    {
        # Nothing, no need to save an empty file.
    }
}

function CheckActionSequence
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object[]]
        $actionSequence
    )

    if($data.Good2Go)
    {
        if(-not $data.FirstPass)
        {
            $sbError = [System.Text.StringBuilder]::new()
            $seqNums = [System.Collections.Generic.List[Int32]]::new()
            $a = 0
            while($a -lt $actionSequence.Length)
            {
                $parameterNames = [System.Collections.Generic.List[String]]::new()
                @($actionSequence[$a] | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $_ -notin @("callee","Complete","SequenceNumber")}).ForEach( { $parameterNames.Add($_) })

                # Check "Complete"
                if($null -ne $actionSequence[$a].Complete)
                {
                    if($actionSequence[$a].Complete -is [bool])
                    {
                        # Nothing.
                    } `
                    else
                    {
                        [void] $sbError.AppendLine(("Value for Complete [{0}] is not a boolean value." -f @($actionSequence[$a].Complete)))
                    }
                } `
                else
                {
                    [void] $sbError.AppendLine("Missing 'Complete' property.")
                }

                # Check "SequenceNumber"
                if($null -ne $actionSequence[$a].SequenceNumber)
                {
                    if($actionSequence[$a].SequenceNumber -is [Int32])
                    {
                        if($seqNums -notcontains $actionSequence[$a].SequenceNumber)
                        {
                            $seqNums.Add($actionSequence[$a].SequenceNumber)
                        } `
                        else
                        {
                            [void] $sbError.AppendLine(("Duplicate SequenceNumber {0} for command '{1}'." -f @($actionSequence[$a].SequenceNumber, $actionSequence[$a].callee)))
                        }
                    } `
                    else
                    {
                        [void] $sbError.AppendLine(("Value for SequenceNumber [{0}] is not an Int32 value." -f @($actionSequence[$a].SequenceNumber)))
                    }
                } `
                else
                {
                    [void] $sbError.AppendLine("Missing 'SequenceNumber' property.")
                }

                # Check "callee".  Also, if callee is valid, continue to check the rest of the parameters.  If callee is invalid, then we clearly can't check the paramaters.
                if($null -ne $actionSequence[$a].callee)
                {
                    if($actionSequence[$a].callee -is [String])
                    {
                        if(-not [String]::IsNullOrEmpty($actionSequence[$a].callee))
                        {
                            $calleeParams = $Script:calleeParamsTable | Where-Object { $_.callee -eq $actionSequence[$a].callee }
                            if($null -ne $calleeParams)
                            {
                                # If we made it here, then Complete, SequenceNumber, and callee are valid... Just need to check all the other parameters for the callee
                                $p = 0
                                while($p -lt $calleeParams.Params.Count)
                                {
                                    [void] $parameterNames.Remove($calleeParams.Params[$p].Name)
                                    if($null -ne $actionSequence[$a].$($calleeParams.Params[$p].Name))
                                    {
                                        switch($calleeParams.Params[$p].Type)
                                        {
                                            "STRING"
                                            {
                                                if($actionSequence[$a].$($calleeParams.Params[$p].Name) -is [String])
                                                {
                                                    if((-not $calleeParams.Params[$p].Mandatory) -or (-not [String]::IsNullOrEmpty($actionSequence[$a].$($calleeParams.Params[$p].Name))))
                                                    {
                                                        # Let's see if .Controller is valid...
                                                        if($calleeParams.Params[$p].Name -eq "Controller")
                                                        {
                                                            if($actionSequence[$a].callee -in @("Stop-NcCifsServer", "Invoke-NcSnapmirrorUpdate", "Invoke-NcSnapmirrorBreak", "Enable-NcSis", "Set-NcSis", "Remove-NcSnapmirror", "Update-NcVol", "Invoke-NcSnapmirrorRelease", "New-NcSnapmirror", "Invoke-NcSnapmirrorResync", "Start-NcCifsServer"))
                                                            {
                                                                if($Global:cDot.ContainsKey($actionSequence[$a].Controller))
                                                                {
                                                                    # Nothing, but we did confirm .Controller is a valid value.
                                                                } `
                                                                else
                                                                {
                                                                    [void] $sbError.AppendLine(("Unknown NetApp cluster name '{0}' for command '{1}'." -f @($actionSequence[$a].Controller, $actionSequence[$a].callee)))
                                                                }
                                                            } `
                                                            else
                                                            {
                                                                # Nothing, some other command has a .Controller parameter.
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            # Nothing.
                                                        }
                                                    } `
                                                    else
                                                    {
                                                        [void] $sbError.AppendLine(("Missing value for parameter '{0}' for command '{1}'." -f @($calleeParams.Params[$p].Name, $actionSequence[$a].callee)))
                                                    }
                                                } `
                                                else
                                                {
                                                    [void] $sbError.AppendLine(("'{0}' is not a '{1}' value for command '{2}'." -f @($calleeParams.Params[$p].Name, $calleeParams.Params[$p].Type, $actionSequence[$a].callee)))
                                                }
                                            }

                                            "BOOLEAN"
                                            {
                                                if($actionSequence[$a].$($calleeParams.Params[$p].Name) -is [Boolean])
                                                {
                                                    # Nothing, since we've already verified there is a parameter named $actionSequence[$a].$($calleeParams.Params[$p].Name
                                                    #   and we know [Boolean] is not a nullable type, then we are ok.
                                                } `
                                                else
                                                {
                                                    [void] $sbError.AppendLine(("'{0}' is not a '{1}' value for command '{2}'." -f @($calleeParams.Params[$p].Name, $calleeParams.Params[$p].Type, $actionSequence[$a].callee)))
                                                }
                                            }

                                            "STRING[]"
                                            {
                                                # This is a little difference.  Powershell will say the overarching type is an Object[], and not a String[], so...
                                                #   First, make sure $actionSequence[$a].$($calleeParams.Params[$p].Name) is an Object[], then make sure each member of the array is a [String]
                                                if($actionSequence[$a].$($calleeParams.Params[$p].Name) -is [Object[]])
                                                {
                                                    # Ok, we have an Object[], not check each member to make sure its value is a string.
                                                    $objArray = $actionSequence[$a].$($calleeParams.Params[$p].Name)
                                                    $i = 0
                                                    while($i -lt $objArray.Length)
                                                    {
                                                        if($objArray[$i] -is [String])
                                                        {
                                                            # Handle $objArray[$i] as a single String parameter
                                                            if((-not $calleeParams.Params[$p].Mandatory) -or (-not [String]::IsNullOrEmpty($objArray[$i])))
                                                            {
                                                                # Nothing, either this parameter is optional, or we have a value.
                                                            } `
                                                            else
                                                            {
                                                                [void] $sbError.AppendLine(("Missing value {0} for parameter '{1}' for command '{2}'." -f @(($i + 1), $calleeParams.Params[$p].Name, $actionSequence[$a].callee)))
                                                            }
                                                        } `
                                                        else
                                                        {
                                                            [void] $sbError.AppendLine(("Value {0} of parameter '{1}' is not a '{2}' value for command '{3}'." -f @($i, $calleeParams.Params[$p].Name, ($calleeParams.Params[$p].Type.Replace("[]","")), $actionSequence[$a].callee)))
                                                        }

                                                        $i++
                                                    }
                                                } `
                                                else
                                                {
                                                    [void] $sbError.AppendLine(("'{0}' is not a '{1}' value for command '{2}'." -f @($calleeParams.Params[$p].Name, $calleeParams.Params[$p].Type, $actionSequence[$a].callee)))
                                                }
                                            }
                                        }
                                    } `
                                    else
                                    {
                                        if($calleeParams.Params[$p].Mandatory)
                                        {
                                            [void] $sbError.AppendLine(("Missing parameter '{0}' for command '{1}'." -f @($calleeParams.Params[$p].Name, $actionSequence[$a].callee)))
                                        } `
                                        else
                                        {
                                            # Nothing, optional parameter.
                                        }
                                    }

                                    $p++
                                }

                                if($parameterNames.Count -gt 0)
                                {
                                    $parameterNames.ToArray().ForEach({
                                        [void] $sbError.AppendLine(("Extra parameter '{0}' for command '{1}'." -f @($_, $actionSequence[$a].callee)))
                                    })
                                } `
                                else
                                {
                                    # Nothing all parameters check and nothing extra.
                                }
                            } `
                            else
                            {
                                [void] $sbError.AppendLine(("Value for callee [{0}] is invalid." -f @($actionSequence[$a].callee)))
                            }
                        } `
                        else
                        {
                            [void] $sbError.AppendLine("Missing value for callee.")
                        }
                    } `
                    else
                    {
                        [void] $sbError.AppendLine(("Value for callee [{0}] is not a string value." -f @($actionSequence[$a].callee)))
                    }
                } `
                else
                {
                    [void] $sbError.AppendLine("Missing 'callee' parameter.")
                }

                $a++
            }

            # No errors reported?
            $data.Good2Go = ($sbError.Length -eq 0)
            if($sbError.Length -gt 0)
            {
                LogError "Restored action sequence contains issues:"
                $lines = $sbError.ToString() -split "`r`n"
                $lines.ForEach({
                    LogError $_ 1
                })
            } `
            else
            {
                # Nothing, all good.
            }
        } `
        else
        {
            # Nothing, can only check the action sequence after 'BuildActionSequence'
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function IsCalleeNetAppCmdlet
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand
    )

    $retVal = $false
    if($null -ne $actionCommand)
    {
        if(-not [String]::IsNullOrEmpty($actionCommand.callee))
        {
            try
            {
                [void] (Get-Command -Module @("DataONTAP","NetApp.ONTAP") -Name $actionCommand.callee -ErrorAction Stop)
                $retVal = $true
            }
            catch
            {
                # Nothing, only here to stop the exception output...
            }
        } `
        else
        {
            # Nothing, no callee in $actionCommand.
        }
    } `
    else
    {
        # Nothing, don't have an actionCommand to process.
    }

    return $retVal
}

function GetController
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand
    )

    $controller = $null

    if(IsCalleeNetAppCmdlet -actionCommand $actionCommand)
    {
        # If the action command contains a .Controller parameter...
        if(-not [String]::IsNullOrEmpty($actionCommand.Controller))
        {
            # Then try to find the right controller to use.
            if($Global:cDot.ContainsKey($actionCommand.Controller))
            {
                $controller = $Global:cDot[$actionCommand.Controller]
            } `
            else
            {
                LogError ("Unknown NetApp cluster name '{0}' for command '{1}'." -f @($actionCommand.Controller, $actionCommand.callee))
                $data.Good2Go = $false
                break
            }
        } `
        else
        {
            LogError ("Missing NetApp cluster name for command '{0}'.  This is odd!" -f @($actionCommand.callee))
            $data.Good2Go = $false
            break
        }
    } `
    else
    {
        # Nothing, only process action commands for NetApp cmdlets.
    }

    return $controller
}

function ExecuteActionCommand
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $actionCommand
    )

    if($data.Good2Go)
    {
        if(-not $data.FirstPass)
        {
            # Preset $controller for NetApp cmdlets...
            if(IsCalleeNetAppCmdlet -actionCommand $actionCommand)
            {
                $controller = GetController -data $data -actionCommand $actionCommand
                if($null -eq $controller)
                {
                    LogError ("Unable to set controller instance for {0}." -f @($actionCommand.callee))
                    $data.Good2Go = $false
                } `
                else
                {
                    # Nothing.
                }
            } `
            else
            {
                # Nothing.
            }

            if($data.Good2Go)
            {
                switch($actionCommand.callee)
                {
                    "Stop-NcCifsServer"
                    {
                        # Invokes ParameterSet "ProcessActionSequence"
                        ShutdownCIFSServer -data $data -actionCommand $actionCommand -controller $controller
                        break
                    }

                    "Invoke-NcSnapmirrorUpdate"
                    {
                        # Invokes ParameterSet "ProcessActionSequence"
                        SyncSnapmirror -data $data -actionCommand $actionCommand -controller $controller
                        break
                    }

                    "Invoke-NcSnapmirrorBreak"
                    {
                        # Invokes ParameterSet "ProcessActionSequence"
                        BreakSnapmirror -data $data -actionCommand $actionCommand -controller $controller
                        break
                    }

                    "Update-NcVol"
                    {
                        # Invokes ParameterSet "ProcessActionSequence"
                        UpdateSnapshotPolicy -data $data -actionCommand $actionCommand -controller $controller
                        break
                    }

                    "Enable-NcSis"
                    {
                        # Surpress the return value ...
                        [void] (EnableVolumeEfficiency -data $data -actionCommand $actionCommand -controller $controller)
                        break
                    }

                    "Set-NcSis"
                    {
                        # Surpress the return value ...
                        [void] (SetVolumeEfficiency -data $data -actionCommand $actionCommand -controller $controller)
                        break
                    }

                    "Remove-NcSnapmirror"
                    {

                        break
                    }

                    "Invoke-NcSnapmirrorRelease"
                    {
                        $sourceVolume = $data.AllVolumes | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.Vserver -eq $actionCommand.SourceVserver) -and ($_.Name -eq $actionCommand.SourceVolume) }
                        if($null -ne $sourceVolume)
                        {
                            $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) -and ($_.RelationshipId -eq $actionCommand.RelationshipId) }
                            if($null -eq $snapmirror)
                            {
                                # Ok, so the snapmirror was likely deleted in the first run of this script, so we'll have to fabricate a bogus snapmirror object for the call to ReleaseSnapmirror
                                $destinationVolume = $data.AllVolumes | Where-Object { ($_.Vserver -eq $actionCommand.DestinationVserver) -and ($_.Name -eq $actionCommand.DestinationVolume) }
                                if($null -ne $destinationVolume)
                                {
                                    $snapmirror = [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]::new()

                                    # Populate the properties which will be needed for ReleaseSnapmirror
                                    $snapmirror.NcController = $destinationVolume.NcController
                                    $snapmirror.Vserver = $destinationVolume.Vserver
                                    $snapmirror.DestinationVolume = $destinationVolume.Name
                                    $snapmirror.DestinationVserver = $destinationVolume.Vserver
                                    $snapmirror.RelationshipId = $actionCommand.RelationshipId

                                    # These are needed for $snapmirror.Identity to work...
                                    $snapmirror.SourceLocation = "{0}:{1}" -f @($sourceVolume.Vserver, $sourceVolume.Name)
                                    $snapmirror.DestinationLocation = "{0}:{1}" -f @($destinationVolume.Vserver, $destinationVolume.Name)
                                } `
                                else
                                {
                                    LogError ("Failed to release snapmirror.  Unable to fabricate artificial snapmirror.  Could not locate destination volume: {0}:{1}!" -f @($actionCommand.DestinationVserver, $actionCommand.DestinationVolume))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                # Nothing, we have the snapmirror object.
                            }

                            # Make sure we have an actual or fabricated snapmirror object...
                            if($null -ne $snapmirror)
                            {
                                $data.Good2Go = ReleaseSnapmirror -data $data -sourceVolume $sourceVolume -snapmirror $snapmirror
                            } `
                            else
                            {
                                # Nothing, already displayed a message.
                            }
                        } `
                        else
                        {
                            LogError ("Failed to release snapmirror.  Unable to locate source volume {0}:{1}!" -f @($actionCommand.SourceVserver, $actionCommand.SourceVolume))
                            $data.Good2Go = $false
                        }

                        break
                    }

                    "New-NcSnapmirror"
                    {
                        $sourceVolume = $data.AllVolumes | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.Vserver -eq $actionCommand.SourceVserver) -and ($_.Name -eq $actionCommand.SourceVolume) }
                        if($null -ne $sourceVolume)
                        {
                            $destinationVolume = $data.AllVolumes | Where-Object { ($_.Vserver -eq $actionCommand.DestinationVserver) -and ($_.Name -eq $actionCommand.DestinationVolume) }
                            if($null -ne $destinationVolume)
                            {
                                $data.Good2Go, $newSnapmirror = CreateSnapmirror -data $data -srcVolume $sourceVolume -dstVolume $destinationVolume -snapmirrorPolicyName $actionCommand.Policy

                                if($data.Good2Go)
                                {
                                    # Snapmirror was created or simulated...
                                    if($null -ne $newSnapmirror)
                                    {
                                        # Add the new snapmirror to the list of all snapmirrors so it can be found later.
                                        $data.Snapmirrors.Add($newSnapmirror)
                                    } `
                                    else
                                    {
                                        # CreateSnapmirror says it created a snapmirror, but didn't return a new snapmirror object....
                                        LogError ("Please check snapmirror status for {0} --> {1}" -f @($sourceVolume.Identity, $destinationVolume.Identity))
                                        LogError ("Additionally, if the snapmirror was created, update the retry file (SequenceNumber: {0}) to indicate the command was completed. (`"Complete`": true)" -f @($actionCommand.SequenceNumber))
                                        $data.Good2Go = $false
                                    }
                                } `
                                else
                                {
                                    # Nothing, already displayed a message
                                }
                            } `
                            else
                            {
                                LogError ("Unable to created new snapmirror.  Unable to locate destination volume: {0}:{1}!" -f @($actionCommand.DestinationVserver, $actionCommand.DestinationVolume))
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError ("Unable to created new snapmirror.  Unable to locate source volume {0}:{1}!" -f @($actionCommand.SourceVserver, $actionCommand.SourceVolume))
                            $data.Good2Go = $false
                        }

                        break
                    }

                    "Invoke-NcSnapmirrorResync"
                    {
                        $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) }

                        if($null -eq $snapmirror)
                        {
                            # Perhaps we just created the snapmirror and it didn't get added to the list of all snapmirrors.  Let's refresh and look another time.
                            GetSnapmirrors -data $data
                            $snapmirror = $data.Snapmirrors | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.DestinationVserver -eq $actionCommand.DestinationVserver) -and ($_.DestinationVolume -eq $actionCommand.DestinationVolume) }
                        } `
                        else
                        {
                            # Nothing, we have a snapmirror.
                        }

                        # Check $snapmirror again, might have just refreshed the list.
                        if($null -ne $snapmirror)
                        {
                            $data.Good2Go = ResyncSnapmirror -data $data -snapmirror $snapmirror
                            if($data.Good2Go)
                            {
                                # Nothing, the snapmirror was successfully resync'd
                            } `
                            else
                            {
                                # Nothing, already displayed a message
                            }
                        } `
                        else
                        {
                            LogError ("Unable to locate snapmirror destination {0}:{1}:{2} for {3}." -f @($controller.Identity, $actionCommand.DestinationVserver, $actionCommand.DestinationVserver, $actionCommand.callee))
                            $data.Good2Go = $false
                        }
                        break
                    }

                    "Start-NcCifsServer"
                    {
                        $cifsServer = $data.AllCIFSServers | Where-Object { ($_.NCController.Identity -eq $controller.Identity) -and ($_.VServer -eq $actionCommand.VserverContext) }
                        if($null -ne $cifsServer)
                        {
                            $data.Good2Go = StartCIFSServer -data $data -cifsServer $cifsServer
                        } `
                        else
                        {
                            LogError ("Unable to locate CIFS server {0}:{1} for {2}." -f @($controller.Identity, $actionCommand.VserverContext, $actionCommand.callee))
                            $data.Good2Go = $false
                        }
                        break
                    }

                    "Set-ADComputer"
                    {
                        $adComp = GetADComputer -computerName $actionCommand.Instance
                        if($null -ne $adComp)
                        {
                            # Clear the current service principal names...
                            $adComp.servicePrincipalName.Clear()

                            # Add the correct ones.
                            $actionCommand.servicePrincipalNames.ForEach({ [void] $adComp.servicePrincipalName.Add($_) })

                            # Commit the change to AD...
                            $data.Good2Go = CommitServicePrincipalNameChange2AD -adComp $adComp
                        } `
                        else
                        {
                            LogError ("Unable to update AD computer.  Computer account {0} not found." -f @($actionCommand.Instance))
                            $data.Good2Go = $false
                        }
                        break
                    }

                    "Add-DnsServerResourceRecordCName"
                    {
                        GetADDomain
                        if($null -ne $Script:adDomain)
                        {
                            GetDomainController

                            if($null -ne $Script:domainController)
                            {
                                $funcParams = @{
                                    callee = $actionCommand.callee
                                    Name = $actionCommand.Name
                                    HostNameAlias = $actionCommand.HostNameAlias
                                    ZoneName = $Script:adDomain.DNSRoot
                                    ComputerName = $Script:domainController.Name
                                }

                                $result = ReTryCatch -funcParameters $funcParams
                                if($result.Good2Go)
                                {
                                    # Nothing
                                } `
                                else
                                {
                                    LogError ("Failed to register CNAME record {0} to {1}." -f @($actionCommand.Name, $actionCommand.HostNameAlias))
                                    $data.Good2Go = $false
                                }
                            } `
                            else
                            {
                                LogError ("Failed to acquire a domain controller.  CNAME record {0} will not transferred to {1}." -f @($actionCommand.Name, $actionCommand.HostNameAlias))
                                $data.Good2Go = $false
                            }
                        } `
                        else
                        {
                            LogError "Failed to acquire AD domain data.  CNAME records will not transferred." 3
                            $data.Good2Go = $false
                        }
                        break
                    }

                    default
                    {
                        LogError ("Unknown action command: {0}." -f @($actionCommand.callee))
                        $data.Good2Go = $false
                    }
                }
            } `
            else
            {
                # Nothing, already displayed a message.
            }
        } `
        else
        {
            # Nothing, only call ExecuteActionCommand after BuildActionSequence
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function RebuildActionSequenceFromFile
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
        if(-not $data.FirstPass)
        {
            if(($null -eq $data.ActionSequence) -or ($data.ActionSequence.Count -eq 0))
            {
                if(-not [String]::IsNullOrEmpty($data.ActionSequenceFileName))
                {
                    try
                    {
                        $actionSequenceJSON = Get-Content -Path $data.ActionSequenceFileName -ErrorAction Stop

                        try
                        {
                            $newActionSequence = $actionSequenceJSON | ConvertFrom-Json -ErrorAction Stop
                            CheckActionSequence -actionSequence $newActionSequence
                            if($data.Good2Go)
                            {
                                ($newActionSequence | Sort-Object -Property SequenceNumber).ForEach({ $data.ActionSequence.Add($_) })
                            } `
                            else
                            {
                                # Nothing, already display a message.
                            }
                        }
                        catch
                        {
                            LogError ("Failed to convert JSON contents of {0} into an action sequence." -f @($Script:RetryFile))
                            $data.Good2Go = $false
                        }
                    }
                    catch
                    {
                        LogError ("Failed to read JSON contents from {0}." -f @($Script:RetryFile))
                        $data.Good2Go = $false
                    }
                } `
                else
                {
                    LogError "Missing action sequence file name!"
                    $data.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, already have an action sequence to work with... likely after just running BuildActionSequence
            }
        } `
        else
        {
            # Nothing, can only rebuild the action sequence from file AFTER 'BuildActionSequence'
        }
    } `
    else
    {
        # Nothing, already displayed a message
    }
}

function ProcessActionSequence
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
        if(-not $data.FirstPass)
        {
            # During the first pass, some of the in-memory snapmirror objects would have been updated to ensure
            #    correct future processing.  For instance during the first pass, I marked snapmirrors as "broken-off"
            #    so later functions would think the snapmirror was broken off.  To remedy this, let's just reload
            #    all the snapmirrors from the clusters.
            GetSnapmirrors -data $data

            # Rebuild the action sequence from file if there isn't one already
            RebuildActionSequenceFromFile -data $data

            # While everything is ok and there are more actions to run....do so.
            $a = 0
            while($data.Good2Go -and ($a -lt $data.ActionSequence.Count))
            {
                if(-not $data.ActionSequence[$a].Completed)
                {
                    # Execute the action here.
                    $data.Good2Go = ExecuteActionCommand -data $data -actionCommand $data.ActionSequence[$a]
                    if($data.Good2Go)
                    {
                        if($Script:TakeAction)
                        {
                            $data.ActionSequence[$a].Complete = $true
                            SaveActionSequence -data $data
                        } `
                        else
                        {
                            # Nothing, only a trial run.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed a message
                    }
                } `
                else
                {
                    # Nothing, already completed this action...
                }

                $a++
            }
        } `
        else
        {
            # Nothing, only process the action sequence after its been created...
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
        [Parameter(Mandatory=$true, ParameterSetName="Default", Position=0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SourceVServerName,

        [Parameter(Mandatory=$true, ParameterSetName="Default", Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName,

        [Parameter(Mandatory=$false, ParameterSetName="Default", Position=2)]
        [String[]]
        $VolumesToInclude,

        [Parameter(Mandatory=$true, ParameterSetName="Retry", Position=0)]
        [String]
        $RetryFile
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

    if($PSCmdlet.ParameterSetName -eq "Retry")
    {
        $data = Initialize
        $data.ActionSequenceFileName = $RetryFile
        ProcessActionSequence -data $data
    } `
    else
    {
        <#
            When Initialize returns, if $data.Good2Go -eq $true, then we should be safe to execute all changes.

            The goal is to have everything checked and verified prior to calling TakeAction.  I want to avoid making ANY changes unless I believe
                ALL changes will complete successfully.
                VServer Peerings are good, Snapshot policies are available where needed, etc...
        #>
        $data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude

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
                    # Build the action sequence...
                    BuildActionSequence -data $data

                    SaveActionSequence -data $data

                    if($Script:TakeAction)
                    {
                        # Let's make some changes...
                        ProcessActionSequence -data $data
                    } `
                    else
                    {
                        # Nothing, just pretending
                    }
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
    if($PSCmdlet.ParameterSetName -eq "Retry")
    {
        # Main -RetryFile $RetryFile
    }
    else
    {
        # Main -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $Script:VolumesToInclude
    }
} `
else
{
    LogError "Please run this script under PowerShell v 5.1x (powershell.exe)"
}
