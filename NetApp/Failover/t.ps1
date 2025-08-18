
# "BDC-SVMA01:vol_DR_vmware_DMZ_SATA_01",
$Script:bdcSVMA01VolumesToInclude = @("BDC-SVMA02:vol_DR_vmware_SAS_01", "BDC-SVMA01:vol_DR_vmware_SAS_01", "BDC-SVMA01:vol_DR_vmware_SATA_01", "BDC-SVMA01:vol_NFS_BDC_SAS_GITLAB_BACKUP_SATA_01", "BDC-SVMA01:vol_NFS_CSP_Backups_01", "BDC-SVMA01:vol_NFS_DDC_REPO_01_RepoData_SATA_01", "BDC-SVMA01:vol_SMB_AppsScm_Backups_01", "BDC-SVMA01:vol_SMB_ArcGIS_HA_01", "BDC-SVMA01:vol_SMB_CAE_Apps_SAS_01", "BDC-SVMA01:vol_SMB_CAE_SAS_01", "BDC-SVMA01:vol_SMB_Env_GIS_01", "BDC-SVMA01:vol_SMB_Facilities_01", "BDC-SVMA01:vol_SMB_Generation_01", "BDC-SVMA01:vol_SMB_IEB_01", "BDC-SVMA01:vol_SMB_PD_Scans_01", "BDC-SVMA01:vol_SMB_Projects_01", "BDC-SVMA01:vol_SMB_Reference_01", "BDC-SVMA01:vol_SMB_SCCMSoftware_01", "BDC-SVMA01:vol_SMB_SQL_DB_Backups_01", "BDC-SVMA01:vol_SMB_UpdateManager_01", "BDC-SVMA01:vol_SMB_Xchange_01")
$Script:labVolsToInclude = @("LAB-SMB01:vol_SMB_REPLICATE_01", "vol_SMB_TEST_01", "LAB-SMB01:vol_SMB_TEST_02", "LAB-SMB01:vol_SMB_TEST_03", "LAB-SMB01:vol_SMB_TEST_04", "LAB-SMB01:vol_SMB_TEST_05", "LAB-SMB01:vol_SMB_TEST_06", "LAB-SMB01:vol_SMB_TEST_07", "LAB-SMB01:vol_SMB_TEST_08", "LAB-SMB01:vol_SMB_TEST_09", "LAB-SMB01:vol_SMB_TEST_10", "LAB-SMB01:vol_SMB_REPLICATE_01", "LAB-SMB01:vol_SMB_TEST_01", "LAB-SMB01:vol_SMB_TEST_02", "LAB-SMB01:vol_SMB_TEST_03", "LAB-SMB01:vol_SMB_TEST_04", "LAB-SMB01:vol_SMB_TEST_05", "LAB-SMB01:vol_SMB_TEST_06", "LAB-SMB01:vol_SMB_TEST_07", "LAB-SMB01:vol_SMB_TEST_08", "LAB-SMB01:vol_SMB_TEST_09", "LAB-SMB01:vol_SMB_TEST_10")
$Script:VolumesToInclude = $Script:labVolsToInclude


$Script:VolumesToInclude = $Script:bdcSVMA01VolumesToInclude

$Script:SourceVServerName = "LAB-SMB01"
$Script:DRVServerName = "LABDR-SMB01"
$Script:VolumesToInclude = $null
$Script:TakeAction = $false
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

$Script:SourceVServerName = "LABDR-SMB01"
$Script:DRVServerName = "LABDR-SMB02"
$Script:VolumesToInclude = $null
$Script:TakeAction = $false
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }


Clear-Host
$Script:SourceVServerName = "BOI-SMB01"
$Script:DRVServerName = "BOIDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "HLY-SMB01"
$Script:DRVServerName = "HLYDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "SE4-SMB01"
$Script:DRVServerName = "SE4DR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "VAN-SMB01"
$Script:DRVServerName = "VANDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "PTL-SMB01"
$Script:DRVServerName = "PTLDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "ITO-SMB01"
$Script:DRVServerName = "ITODR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "CLK-SMB01"
$Script:DRVServerName = "CLKDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "BIL-SMB01"
$Script:DRVServerName = "BILDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

Clear-Host
$Script:SourceVServerName = "DEN-SMB01"
$Script:DRVServerName = "DENDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }


Clear-Host
$Script:SourceVServerName = "SE4-NFS01"
$Script:DRVServerName = "SE4DR-NFS01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude
if($data.Good2Go) { ShowData -data $data } else { Write-Host "OOPS!!" }

# DA11
$Script:SourceVServerName = "AST-SMB01"
$Script:DRVServerName = "ASTDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass
$data.ActionSequence.Clear()
FirstPass -data $data

$Script:SourceVServerName = "AUS-SMB01"
$Script:DRVServerName = "AUSDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass


$Script:SourceVServerName = "DA11-NFS01"
$Script:DRVServerName = "DA11DR-NFS01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass


$Script:SourceVServerName = "DA11-SMB01"
$Script:DRVServerName = "DA11DR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass


$Script:SourceVServerName = "FTW-SMB01"
$Script:DRVServerName = "FTWDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass


$Script:SourceVServerName = "HOU-SMB01"
$Script:DRVServerName = "HOUDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass


$Script:SourceVServerName = "SAT-SMB01"
$Script:DRVServerName = "SATDR-SMB01"
$Script:VolumesToInclude = $null
$data = Initialize -SourceVServerName $SourceVServerName -DRVServerName $DRVServerName -VolumesToInclude $VolumesToInclude -firstPass




$Script:TakeAction = $false

<#

    NOTES:

        $Script:TakeAction - only affects actions which effect a change.  All query only actions will still be performed.
            However, the outcome of the query will always be positive.  For example:
                WaitForSnapmirrorAction -snapmirror $data.Snapmirrors[$a] -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored"

                Even if the snapmirror's status/mirrorstate does not match status2WaitFor/mirrorState2WaitFor, because the script is NOT taking action, the returned status will be $true


        $VolumesToInclude - An array of source volumes (snapmirror SourceLocations (SVM:VolumeName)) to include in the failover.  If none are provided, all snapmirror source volumes are included.
            Volumes are filtered by $data.SnapmirrorDestinations.  When $data.SnapmirrorDestinations is populated, only sources which are included are kept in the list.  Later, when deciding which
            volumes to process, only volumes which are source locations within $data.SnapmirrorDestinations qualify.


    4/16/2024 - Changing tack a bit.  Instead of processing all the snapmirror updates then all the breaks, etc, I think it better to process each snapmirror relationship individually.  So, the process will be:

        foreach snapmirror in snapmirrors:
            Section 1:
                Update Snapmirror
                Break Snapmirror
                Delete Snapmirror
                Release Snapmirror
                Update Snapshot Policy
                Update Efficiency Settings

            Section 2: When all snapmirror relationships based on the same snapmirror source have been handled in section 1:
                Create new snapmirrors
                ReSync new snapmirrors

        Finally, Update SPNs and CNAMEs

        This way, I can report any errors on a per snapmirror basis, while being able to continue with the rest of the snapmirrors.



            Section

#>

<#
    ActionSequence thoughts: none of this is actually implemented.  Just some thoughts...

    The general idea behind the "ActionSequence" is to create a simplified script, of sorts, which can be created and saved during the first pass.  If the fail
        over script needs is re-ran with -Continue, the action sequence can be loaded from a .JSON file and continued with the first action where .Completed is $null i.e. it did not complete.

    During normal running of the fail over script, (after relevant data has been collected), 2 passes will be ran for the "action" phase of the fail over.
        First Pass: Create the action sequence without actually performing any actions.  -- Exact method yet to be completely fleshed out
            The action sequence will be saved to a .JSON file so subsequent executions of the fail over script with -Continue can read the action sequence
                from the file and pick up where it left off without needing to collect all the relevant data.  Keep in mind, once actions are completed,
                the original data (if collected a second time) may appear faulty.  Snapmirrors broken off and released, but not re-created.  If the data was
                collected a second time, there would be no way to know a "reverse" snapmirror needs to be created  -- the snapmirror wouldn't exist after
                the first, failed, run.  Hence the need to be able to continue without first collecting data.  However, actions should DEFINITELY be verified and
                confirmed during a -Continue run.

        Second Pass: Consume the action sequence created during the first pass, just as if the script had been started with -Continue  -- with the exception of not
            verifying and confirming every action prior to execution.
            Start processing actions where .Completed is $null.  Updating the action sequence file each time an action is successfully completed.
            When an action fails, stop processing the action sequence allowing the user to correct any issues (and possibly marking an action complete)
                so they can then re-execute the fail over script with the -Continue option to start where the script left off due to an error.

        Concerns:

            While it's not difficult to save an action and perform it later (see PerformAction and ShutdownCIFSServer), I'm at a quandry trying to figure out how I would perform a follow-up
                action.  For instance: if I use PerformAction to stop a CIFS server, how would I know I need to use the actions parameters to then check if the CIFS
                server was actually down.  And yes, I know I can hard code this, but I'm thinking more generically.  How can I use the action object to logically determine
                I need to do some follow up action?  Perhaps an .ExpectedResult property???  I think doing that would then require an .ExpectedResultType property and
                maybe a .FollowUpAction??  Definitely needs more thought.  Would be easy to just fire and forget actions.  :P

#>


<#
    $Script:TakeAction = $false
#>

function PauseForErrorResolution
{
    [Console]::TreatControlCAsInput = $True
    do
    {
        Write-Host -NoNewline "Paused for error.  Enter '"
        Write-Host -NoNewline -ForegroundColor Cyan "RETRY"
        Write-Host -NoNewline "', '"
        Write-Host -NoNewline -ForegroundColor Cyan "SKIP"
        Write-Host -NoNewline "' or '"
        Write-Host -NoNewline -ForegroundColor Cyan "ABORT"
        try
        {
            $resumeMode = Read-Host "'"
        }
        finally
        {
            $resumeMode = "exception"
            Write-Host -ForegroundColor Yellow "Please do not break the script."
            $Error.Clear()
        }
        if(-not [String]::IsNullOrEmpty($resumeMode))
        {
            $resumeMode = $resumeMode.ToLower()
            if($resumeMode -notin @("abort","skip","retry"))
            {
                Write-Host -ForegroundColor Red "Invalid response.  Redo"
            }
            else
            {
                # Nothing, good response.
            }
        }
    } while ($resumeMode -notin @("abort","skip","retry"))
    [Console]::TreatControlCAsInput = $false
    return $resumeMode
}

function NewActionSequenceAction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $actionSequence,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $actionFunction,

        [Parameter(Mandatory=$true, Position=2)]
        [ValidateNotNull()]
        $actionParameters
    )

    <#
        .ActionParameters needs to be a dictionary which lends itself to easily be exported in a .JSON file.

        So, for complex parameters, I'll provide a reference which can be reconstituded later.  example:

            When creating actionParameters, NCController will be populated as such:

                $actionParameters = @{
                    NCController = $data.Source.VServer.NCController.Name
                    .
                    .
                    .
                }

            Then, when the parameters need to be consumed, I can rehydrate actionParameters as such:

                $actionParameters.NCController = $cDOT[$actionParameters.NCController]

            I may need to get creative for some parameters.  We'll see where this goes.


    #>
    $newASAction = "" | Select-Object Function, SequenceNumber, ActionParameters, Completed
    $newASAction.Function = $actionFunction
    $newASAction.SequenceNumber = $actionSequence.Count

    if(-not $actionParameters.ContainsKey("ErrorAction"))
    {
        $actionParameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop)
    }
    else
    {
        # Nothing, ErrorAction is already included.
    }
    $newASAction.ActionParameters = $actionParameters
    $newASAction.Completed = $false
    $actionSequence.Add($newASAction)

    return $newASAction
}

function PerformAction
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $action
    )

    $good2Go = $true
    $result = $null
    $actionParameters = $action.ActionParameters
    if($null -ne $actionParameters)
    {
        # Fix up the .Controller parameter if there is one.
        if($actionParameters.ContainsKey("Controller"))
        {
            $controllers = $actionParameters.Controller

            # If the controller parameter is not an array, make it one.
            if($controllers -isnot [Array])
            {
                $controllers = @($controllers)
            }
            else
            {
                # Nothing, it's already an array.
            }
            $controllerObjects = [System.Collections.Generic.List[NetApp.Ontapi.Filer.C.NcController]]::new()
            $a = 0
            while($a -lt $controllers.Length)
            {
                if(-not [String]::IsNullOrEmpty($controllers[$a]))
                {
                    if($Global:cDot.ContainsKey($controllers[$a]))
                    {
                        $controllerObjects.Add($Global:cDot[$controllers[$a]])
                    }
                    else
                    {
                        LogError ("Unknown controller [{0}] specified for {1}:{2}." -f @($controllers[$a], $action.SequenceNumber, $action.Function))
                        $good2Go = $false
                    }
                }
                else
                {
                    LogError ("Action {0}:{1} parameters missing value for .Controller." -f @($action.SequenceNumber, $action.Function))
                    $good2Go = $false
                }

                $a++
            }
            $actionParameters.Controller = $controllerObjects
        }
        else
        {
            # Nothing, no .Controller parameter to fix up.
        }
    }
    else
    {
        $actionParameters = @{ ErrorAction = [System.Management.Automation.ActionPreference]::Stop }
    }

    if(-not [String]::IsNullOrEmpty($action.Function))
    {
        try
        {
            $result = & $action.Function @actionParameters
        }
        catch
        {
            $result = $_
        }
    }
    else
    {
        LogError ("Action sequence {0} is missing its function." -f @($action.SequenceNumber))
    }

    return @($good2Go, $result)
}

function WaitForCurrentSnapmirrorsToProcess
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object] $data,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $status2WaitFor,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $mirrorState2WaitFor
    )

    # Flag to determine if we've displayed a waiting message
    $waiting = $false

    # First time, do not take $Script:TakeAction into account...(see bottom of outer while loop.)
    $snapmirrorsStillProcessing = @($data.Snapmirrors | Where-Object { ($_.Status -ne $status2WaitFor) -or ($_.MirrorState -ne $mirrorState2WaitFor) })

    while(($data.Good2Go) -and ($snapmirrorsStillProcessing.Length -gt 0))
    {
        $a = 0
        while($a -lt $data.Snapmirrors.Count)
        {
            if(($data.Snapmirrors[$a].Status -ne $status2WaitFor) -or ($data.Snapmirrors[$a].MirrorState -ne $mirrorState2WaitFor))
            {
                if(-not $waiting)
                {
                    LogInfo "Waiting for all snapmirrors to finish processing. [CTRL-C to abort script]" 1 -NewLine -NoNewLine
                    $waiting = $true
                }
                else
                {
                    LogInfo "." -NoNewLine
                }

                $tmpSM = $null
                $tries = 0
                $actionComplete = $false
                do
                {
                    $tries++

                    try
                    {
                        $Error.Clear()

                        $tmpSM = Get-NcSnapmirror -Controller $data.Snapmirrors[$a].NCController -DestinationVserver $data.Snapmirrors[$a].DestinationVserver -DestinationVolume $data.Snapmirrors[$a].DestinationVolume -ErrorAction Stop

                        $actionComplete = $true
                    }
                    catch
                    {
                        $data.Good2Go = CatchActionException -tries $tries
                    }
                } while($data.Good2Go -and (-not $actionComplete) -and ($tries -lt $Script:maxOperationRetries))

                # $good2Go implies $actionComplete
                if($data.Good2Go)
                {
                    if($null -ne $tmpSM)
                    {
                        if($data.Snapmirrors[$a].RelationshipId -eq $tmpSM.RelationshipId)
                        {
                            $data.Snapmirrors[$a] = $tmpSM
                        }
                        else
                        {
                            LogError "Processing status is green in WaitForCurrentSnapmirrorsToProcess, however, the relationship ID for the snapmirror object returned from Get-NCSnapmirror does not match the expected ID."
                            LogError ("Expected ID: {0}" -f $data.Snapmirrors[$a].RelationshipId)
                            LogError ("Returned ID: {0}" -f @($tmpSM.RelationshipId))
                            $data.Good2Go = $false
                        }
                    }
                    else
                    {
                        LogError ("Failed to refresh snapmirror object.  {0}" -f @($data.Snapmirrors[$a].Identity)) 0 -NewLine
                        $data.Good2Go = $false
                    }
                }
                else
                {
                    LogError ("Failed to refresh snapmirror object.  {0}" -f @($data.Snapmirrors[$a].Identity)) 0 -NewLine
                }
            }
            else
            {
                # Nothing, this snapmirror is already updated.
            }

            $a++
        }

        # If we are not taking action, then ignore the status/mirrorstate, otherwise...
        #    are there still snapmirrors which haven't completed processing?
        #
        $snapmirrorsStillProcessing = @($data.Snapmirrors | Where-Object { $data.Good2Go -and $Script:TakeAction -and (($_.Status -ne $status2WaitFor) -or ($_.MirrorState -ne $mirrorState2WaitFor)) })
    }

    if($waiting)
    {
        LogInfo ""     # Close out the newline
    }
    else
    {
        # Nothing, never displayed the waiting message...
    }
}

function UpdateSnapshotPolicies
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object] $data,

        [Parameter(Mandatory=$true, Position=1)]
        [System.Collections.Generic.List[System.Object]]
        $actionSequence,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch]
        $firstPass
    )

    <# Step  4: Make sure snapshot policies match on source/destination pairs
        Loop through all $data.NewSnapmirrors making sure snapshot policies match
            One time loop
    #>

    if($data.Good2Go)
    {
        if($data.NewSnapmirrors.Count -gt 0)
        {
            LogInfo "Checking snapshot policies..."
            $a = 0
            while($data.Good2Go -and ($a -lt $data.NewSnapmirrors.Count))
            {
                <#
                    FIRST make sure the new snapmirror source volume's snapshot policy matches the original snapmirror source volume's snapshot policy
                #>
                $data.Good2Go = UpdateSnapshotPolicy -sourceVolume $data.NewSnapmirrors[$a].OriginalSourceVolume -destinationVolume $data.NewSnapmirrors[$a].SourceVolume
                $b = 0
                while($b -lt $data.NewSnapmirrors[$a].Relationships.Count)
                {
                    <# TODO:  I think I only need to worry about snapshot policies then the snapmirror policy type is#>
                    $data.Good2Go = UpdateSnapshotPolicy -sourceVolume $data.NewSnapmirrors[$a].SourceVolume -destinationVolume $data.NewSnapmirrors[$a].Relationships[$b].DestinationVolume
                    $b++
                }

                $a++
            }

            if($data.Good2Go)
            {
                WaitForCurrentSnapmirrorsToProcess -data $data -status2WaitFor "idle" -mirrorState2WaitFor "broken-off"
            }
            else
            {
                # No need to wait, we are out of here.
            }
        }
        else
        {
            LogWarning "No snapmirrors to break."
        }
    }
    else
    {
        # Nothing, already displayed a message
    }
}

function ExportData
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )

    $d2 = "" | Select-Object RelatedControllers, Source, Destination, Snapmirrors, SnapmirrorDestinations, Good2Go, NewSnapmirrors, NFSDatastores, DatastoreToVMHosts, AllVolumes, AllVServers, FirstPass, ActionSequence, ServicePrincipalNames, CNAMERecords, MigrateAllVolumes
    $d2.Good2Go = $data.Good2Go
    $d2.AllVolumes = $null
    $d2.AllVServers = $null
    $d2.RelatedControllers = [System.Collections.Generic.List[System.Object]]::new()
    $d2.Source = "" | Select-Object VServer, CIFSServer, CIFSShares, IsNFSHost, NetworkInterfaces
    $d2.Source.NetworkInterfaces = $null
    $d2.Source.IsNFSHost = $false
    $d2.Destination = "" | Select-Object VServer, CIFSServer, CIFSShares, IsNFSHost, NetworkInterfaces
    $d2.Destination.NetworkInterfaces = $null
    $d2.Destination.IsNFSHost = $false
    $d2.Snapmirrors = $null
    $d2.NFSDatastores = $null
    $d2.MigrateAllVolumes = $true

    # Not really implementing action sequences yet, but putting some of the ground work in...
    #    For now, we are never on the first pass...
    $d2.FirstPass = $false
    $d2.ActionSequence = [System.Collections.Generic.List[System.Object]]::new()

}

$t1 = ($data.ActionSequence | ConvertTo-Json) | ConvertFrom-Json
$sb = [System.Text.StringBuilder]::new()
$a = 0
while($a -lt $t1.Length)
{
    $o = $t1[$a]
    $props = @($o | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -notin @("callee", "Complete", "ErrorAction", "Controller", "Confirm", "PassThru")} | Select-Object -ExpandProperty Name)

    [void] $sb.Append(("{0}" -f @($o.callee)))
    Write-Host -NoNewline ("{0}" -f @($o.callee))

    if(-not [String]::IsNullOrEmpty($o.Controller))
    {
        [void] $sb.Append((" -Controller `$cDOT[`"{0}`"]" -f @($o.Controller)))
        Write-Host -NoNewline (" -Controller `$cDOT[`"{0}`"]" -f @($o.Controller))
    }

    $b = 0
    while($b -lt $props.Length)
    {
        [void] $sb.Append((" -{0} `"{1}`"" -f @($props[$b], $o.($props[$b]))))
        Write-Host -NoNewline (" -{0} `"{1}`"" -f @($props[$b], $o.($props[$b])))
        $b++
    }

    if(-not [String]::IsNullOrEmpty($o.Confirm))
    {
        [void] $sb.Append((" -Confirm:`${0}" -f @($o.Confirm)))
        Write-Host -NoNewline (" -Confirm:`${0}" -f @($o.Confirm))
    }

    [void] $sb.AppendLine(" -ErrorAction `"Stop`"")
    Write-Host " -ErrorAction `"Stop`""
    $a++
}
$sb.ToString() | Set-Clipboard


($data.ActionSequence | ConvertTo-Json) | Set-Clipboard

$testBlock = {
    Write-Host ("{0}" -f @($MyInvocation.InvocationName))
    foreach($paramName in @($MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -notin @("Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction", "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable", "OutBuffer", "PipelineVariable")}))
    {
        $paramValue = Get-Variable -Name $paramName
        Write-Host ("{0} = {1}" -f @($paramName, $paramValue.Value))
    }
}

function test2 {
    [CmdletBinding()]
    param (
          [string] $Bar = 'test'
        , [string] $Baz
        , [string] $Asdf
    )

    $funcParams = @{
        callee = $MyInvocation.MyCommand.Name
    }
        # Write-Host ("{0}" -f @($MyInvocation.MyCommand.Name))
        foreach($paramName in @($MyInvocation.MyCommand.Parameters.Keys | Where-Object { $_ -notin @("Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction", "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable", "OutBuffer", "PipelineVariable")}))
        {
            $paramValue = (Get-Variable -Name $paramName).Value
            # Write-Host ("{0} = {1}" -f @($paramName, $paramValue.Value))
            $funcParams.Add($paramName, $paramValue)
        }

        $funcParams

}

test2 -asdf blah


$cvRole = "AriaTovCenterAdapter"
$cvRolePermFile = "C:\Users\kbriney-adm\Tmp\ariaperms.txt"
$viserver = $vCenter

$cvRoleIds = @()

Get-Content $cvRolePermFile | Foreach-Object {
    $cvRoleIds += $_
}

New-VIRole -name $cvRole -Privilege (Get-VIPrivilege -Server $viserver -id $cvRoleIds) -Server $viserver
Set-VIRole -Role $cvRole -AddPrivilege (Get-VIPrivilege -Server $viserver -id $cvRoleIds) -Server $viserver

Disconnect-VIServer -server $viserver -Confirm:$false


$nonDRVMs = [System.Collections.Generic.List[System.String]]::new()
$drVMs = [System.Collections.Generic.List[System.String]]::new()

# Non DR datastores
$datastores = Get-Datastore -Server $vcenter | Where-Object { $_.Name -notmatch "_DR_" }

# DR datastores
$datastores = Get-Datastore -Server $vcenter | Where-Object { $_.Name -match "_DR_" }


$a = 0
while($a -lt $datastores.Length)
{
    $ds = $datastores[$a]
    $dsVMs = @($ds.ExtensionData.Vm | ForEach-Object { $vmId = "{0}-{1}" -f @($_.Type, $_.Value); $vm = Get-VM -Server $vCenter -Id $vmId -ErrorAction SilentlyContinue; <# Write-Host ("{0}:{1}" -f @($vm.Name, $vmID));#> if(($null -ne $vm) -and (-not $vm.Name.StartsWith("vCLS"))) { $vm } })
    $b = 0
    while($b -lt $dsVMs.Length)
    {
        $i = $drVMs.BinarySearch($dsVMs[$b].Name)
        if($i -lt 0)
        {
            $drVMs.Insert(-bnot $i, $dsVMs[$b].Name)
        }

        $i = $nonDRVMs.BinarySearch($dsVMs[$b].Name)
        if($i -ge 0)
        {
            Write-Host ("DR VM in non DR list: {0}/{1}" -f @($ds.Name, $nonDRVMs[$i]))
        }

        $b++
    }

    $a++
}



$a = 0
while($a -lt $datastores.Length)
{
    $ds = $datastores[$a]
    $dsVMs = @($ds.ExtensionData.Vm | ForEach-Object { $vmId = "{0}-{1}" -f @($_.Type, $_.Value); $vm = Get-VM -Server $vCenter -Id $vmId -ErrorAction SilentlyContinue; <# Write-Host ("{0}:{1}" -f @($vm.Name, $vmID));#> if(($null -ne $vm) -and (-not $vm.Name.StartsWith("vCLS"))) { $vm } })
    $b = 0
    while($b -lt $dsVMs.Length)
    {
        if($dsVMs[$b].Name -match "^vcls")
        {
            Write-Host ("{0}/{1}" -f @($ds.Name, $dsVMs[$b].Name))

        }

        $b++
    }

    $a++
}

$b = 0
$a = 26
while($a -lt $cVols.Length)
{
    if((-not $cVols[$a].VolumeStateAttributes.IsVserverRoot))
    {
        if((-not $cVols[$a].VolumeStateAttributes.IsNodeRoot))
        {
            Write-Host ("Start-NcVolumeEncryptionConversion -Controller {0} -VserverContext {1} -Volume {2} [{3} of {4}]" -f @($cVols[$a].NcController.Name, $cVols[$a].Vserver, $cVols[$a].Name, $a, $cVols.Length))
            try
            {
                $Error.Clear()
                Start-NcVolumeEncryptionConversion -Controller $cVols[$a].NcController -VserverContext $cVols[$a].Vserver -Volume $cVols[$a].Name -ErrorAction Stop
                $a = $cVols.Length
            }
            catch
            {
                Write-Host -ForegroundColor Red ("`t{0}" -f @($Error[0].Exception.Message))
            }
        }
        else
        {
            Write-Host -ForegroundColor Green ("Skipping node root volume: {0}:{1}:{2}" -f @($cVols[$a].NcController.Name, $cVols[$a].Vserver, $cVols[$a].Name))
        }
    }
    else
    {
        Write-Host -ForegroundColor Green ("Skipping vServer root volume: {0}:{1}:{2}" -f @($cVols[$a].NcController.Name, $cVols[$a].Vserver, $cVols[$a].Name))
    }
    $a++
}

$k = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $data.RelatedControllers.Count)
{
    $controller = $data.RelatedControllers[$a]
    $l = Get-NcSnapmirror -Controller $controller
    $l | ForEach-Object
    {
        $k.Add($_)
    }
    $a++
}

$cifsServers = Get-NCCifsServer -Controller @($cdot.Values)
$a = 0
while($a -lt $cifsServers.Length)
{
    $cs = Get-NcCifsSecurity -Controller $cifsServers[$a].NcController -VserverContext $cifsServers[$a].Vserver
    if($cs.IsSigningRequiredSpecified)
    {
        if(-not $cs.IsSigningRequired)
        {
            Write-Host -ForegroundColor Red ("{0}:{1}:SMB Signing Required: {2}" -f @($cifsServers[$a].NcController.Name, $cifsServers[$a].Vserver, $cs.IsSigningRequired))
            Set-NcCifsSecurity -Controller $cifsServers[$a].NcController -VserverContext $cifsServers[$a].Vserver -IsSigningRequired $true
        }
    }
    else
    {
        Write-Host -ForegroundColor Yellow ("{0}:{1}:SMB Signing Required: {2}" -f @($cifsServers[$a].NcController.Name, $cifsServers[$a].Vserver, $cs.IsSigningRequired))
    }
    $a++
}

$sharesToCheck = @(
    "\\PECWACWD2019\Share",
    "\\DDC-BIMSTN01\PrimtechServer",
    "\\DDCSQLS3D-19\S3DBackups",
    "\\DDCSQLS3D-19\S3DTempBackups",
    "\\BDC-LIC10\SESLicenseLog",
    "\\AUSCW01\Attachments_KSMMS",
    "\\BDC-LIC16\PRG",
    "\\PECWSANDBOX\CityworksAttachments",
    "\\PECWSANDBOX\CWNotificationService_website",
    "\\PECWSANDBOX\Downloads",
    "\\PECWSANDBOX\E",
    "\\PECWSANDBOX\Software",
    "\\BDC-LIC11\RISA",
    "\\BDC-LIC11\TILOS",
    "\\BDC-LIC33\SESLicenseLog",
    "\\PECWDEMOTRUNK\Attachments_Training",
    "\\BDC-CSS01\Orchestrator",
    "\\BDC-CSS01\ScheduledTasks",
    "\\CDC-APP05\Bluebeam",
    "\\CDC-APP05\ProjectWise",
    "\\CDC-APP05\Win10",
    "\\PESCEA01\Share",
    "\\BDC-LIC18\TOPSAPPS",
    "\\CDC-MGMT01\Backups$",
    "\\CDC-MGMT01\VIExports",
    "\\BDC-LIC21\dsp67",
    "\\CDC-APP06\Pro99T22",
    "\\CDC-WINDSXDB02\Temp",
    "\\CDCZ-WEB04\Installations",
    "\\GAMSQL01\Derek",
    "\\DDC-LIC02\VisualFoundation"
)


$shareACLs = [System.Collections.Generic.SortedDictionary[[System.String],[System.Collections.Generic.List[System.Object]]]]::new()

$a = 0
while($a -lt $sharesToCheck.Length)
{
    $shareACLs.Add($sharesToCheck[$a], [System.Collections.Generic.List[System.Object]]::new())
    try
    {
        $acl = Get-ACL -Path $sharesToCheck[$a]
        $b = 0
        while($b -lt $acl.Access.Count)
        {
            if($acl.Access[$b].IdentityReference.ToString() -in @("BUILTIN\Users", "Everyone", "NT AUTHORITY\Authenticated Users", "POWERENG\Domain Users"))
            {
                $shareACLs[$sharesToCheck[$a]].Add($acl.Access[$b])
            }
            $b++
        }
    }
    catch
    {

    }
    $a++
}

$aclData = [System.Collections.Generic.List[System.Object]]::new()
$keys = @($shareACLs.Keys)
$a = 0
while($a -lt $keys.Length)
{
    $smbSigningEnabled = $false
    $parts = $keys[$a].Split("\\", [System.StringSplitOptions]::RemoveEmptyEntries)
    $serverName = $parts[0]
    try
    {
        $comp = Get-ADComputer -Identity $serverName
        $smbSigningEnabled = $comp.DistinguishedName.EndsWith("OU=Servers,OU=PEI,DC=powereng,DC=com")
    }
    catch
    {
    }

    $b = 0
    while($b -lt $shareACLs[$keys[$a]].Count)
    {
        $d = "" | Select-Object ShareName,SigningEnabled,FileSystemRights,AccessControlType,IdentityReference,IsInherited,InheritanceFlags,PropagationFlags
        $d.ShareName = $keys[$a]
        $d.SigningEnabled = $smbSigningEnabled
        $d.FileSystemRights = $shareACLs[$keys[$a]][$b].FileSystemRights
        $d.AccessControlType = $shareACLs[$keys[$a]][$b].AccessControlType
        $d.IdentityReference = $shareACLs[$keys[$a]][$b].IdentityReference.ToString()
        $d.IsInherited = $shareACLs[$keys[$a]][$b].IsInherited
        $d.InheritanceFlags = $shareACLs[$keys[$a]][$b].InheritanceFlags
        $d.PropagationFlags = $shareACLs[$keys[$a]][$b].PropagationFlags

        $aclData.Add($d)
        $b++
    }
    $a++
}

$fsRights = [Enum]::GetValues([System.Security.AccessControl.FileSystemRights])
$a = 0
while($a -lt $fsRights.Count)
{
    if(-536805376 -band $fsRights[$a].value__)
    {
        $fsRights[$a]
    }
    $a++
}




$cifsShares = Get-NcCifsShare -Controller @($cdot.Values) | Where-Object { $_.ShareName -notin @("admin`$","ipc`$","c`$")} | Sort-Object CifsServer,ShareName

$shareExceptions = [System.Collections.Generic.List[System.String]]::new()
$aclData = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $cifsShares.Length)
{
    $sharePath = "\\{0}\{1}" -f @($cifsShares[$a].CifsServer, $cifsShares[$a].ShareName)
    try
    {
        $acl = Get-ACL -Path $sharePath -ErrorAction Stop
        $b = 0
        while($b -lt $acl.Access.Count)
        {
            $d = "" | Select-Object ShareName,FileSystemRights,AccessControlType,IdentityReference,IsInherited,InheritanceFlags,PropagationFlags
            $d.ShareName = $sharePath
            $d.FileSystemRights = $acl.Access[$b].FileSystemRights
            $d.AccessControlType = $acl.Access[$b].AccessControlType
            $d.IdentityReference = $acl.Access[$b].IdentityReference.ToString()
            $d.IsInherited = $acl.Access[$b].IsInherited
            $d.InheritanceFlags = $acl.Access[$b].InheritanceFlags
            $d.PropagationFlags = $acl.Access[$b].PropagationFlags

            $aclData.Add($d)
            Write-Host ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f @($d.ShareName,$d.FileSystemRights,$d.AccessControlType,$d.IdentityReference,$d.IsInherited,$d.InheritanceFlags,$d.PropagationFlags))

            $b++
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red $sharePath
        $shareExceptions.Add($sharePath)
    }
    $a++
}

$shareACLData

$sb = [System.Text.StringBuilder]::new()
$a = 0
while($a -lt $fsfcGrps.Length)
{
    try
    {
        $g = Get-ADGroupMember -Identity $fsfcGrps[$a].Group -Recursive -ErrorAction Stop
        if($null -ne $g)
        {
            $g | ForEach-Object {
                if($_ -match "Domain")
                {
                    Write-Host ("{0}: {1}" -f @($fsfcGrps[$a].Group, $_))
                    [void] $sb.AppendLine(("{0}: {1}" -f @($fsfcGrps[$a].Group, $_)))
                }
            }
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("{0}" -f @($fsfcGrps[$a].Group))
    }
    $a++
}

<#
# Grant SSH access from CDC-NTAPMGMT01
iptables -I INPUT 1 -p tcp -s 10.245.3.200 --dport 22 -j ACCEPT

# Grant SSH access from DDC-NTAPMGMT01
iptables -I INPUT 2 -p tcp -s 10.247.3.21 --dport 22 -j ACCEPT

# Block SSH access for everything else
iptables -I INPUT 3 -p tcp -s 0.0.0.0/0 --dport 22 -j DROP

#>


$id = 'sshServer'
$spec = [VMware.Vim.HostFirewallRulesetRulesetSpec]::new()
$spec.AllowedHosts = [VMware.Vim.HostFirewallRulesetIpList]::new()
$spec.AllowedHosts.AllIp = $false
$spec.AllowedHosts.IpAddress = [String[]]::new(3)

$spec.AllowedHosts.IpAddress[0] = '10.245.3.200'
$spec.AllowedHosts.IpAddress[1] = '10.247.3.21'
$spec.AllowedHosts.IpNetwork = [VMware.Vim.HostFirewallRulesetIpNetwork[]]::new(0)


$vmHost = Get-VMHost -Server $labvCenter -Name "lab-esx-offsim-01.powereng.com"
$fwHostID = "HostFirewallSystem-firewallSystem-{0}" -f @(($vmHost.Id.Replace("HostSystem-host-","")))
$_this = Get-View -Server $labvCenter -Id $fwHostID
$_this.UpdateRuleset($id, $spec)


$ddcDisks | Select-Object @{N='Owner';E={$_.DiskOwnershipInfo.OwnerNodeName}},@{N='StackID';E={$_.DiskInventoryInfo.StackId}},Shelf,Bay,Aggregate,Model,Capacity | Sort-Object Owner,StackID,Shelf,Bay | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
$cdcDisks | Select-Object @{N='Owner';E={$_.DiskOwnershipInfo.OwnerNodeName}},@{N='StackID';E={$_.DiskInventoryInfo.StackId}},Shelf,Bay,@{N='Aggregate';E={if($_.DiskRaidInfo.ContainerType -eq "spare") { "spare" } else { $_.Aggregate }}},Model,Capacity | Sort-Object Owner,StackID,Shelf,Bay | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard


$cdcDisks | Where-Object { $_.DiskRaidInfo.ContainerType -eq "spare" } | Select-Object @{N='Owner';E={$_.DiskOwnershipInfo.OwnerNodeName}},@{N='StackID';E={$_.DiskInventoryInfo.StackId}},Shelf,Bay,Aggregate,Model,Capacity | Sort-Object Owner,StackID,Shelf,Bay | ogv

$bdcAggrs | Sort-Object Name | Select-Object Name,TotalSize,Available,@{N='Used';E={$_.TotalSize-$_.Available}}  | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
$cdcAggrs | Sort-Object Name | Select-Object Name,TotalSize,Available,@{N='Used';E={$_.TotalSize-$_.Available}}  | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard

$bdcVols | Select-Object Name,Aggregate,TotalSize,Available,@{N='Used';E={$_.TotalSize-$_.Available}}  | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
$cdcVols | Select-Object Name,Aggregate,TotalSize,Available,@{N='Used';E={$_.TotalSize-$_.Available}}  | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard


$gciPath = "\\bdcfs1\shares$"
$elapsedXferTime=Invoke-Command -ComputerName "BDC-MGMT01" -Credential $creds -ScriptBlock {
    param($gciPath)
    $null = New-PSDrive -Name RdcShare -Root "\\bdcfs1\shares$" -Credential $Using:creds -PSProvider FileSystem -ErrorAction Stop
    $f = @(Get-ChildItem -Path $gciPath)
    Write-Host ("{0}" -f @($f.Length))
    Remove-PSDrive -Name RdcShare
    $f
} -ArgumentList $gciPath
