[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$false,HelpMessage="Enter the ProjectWise project number associated with the source folders.")]
    [ValidatePattern("^[0-9]+$")]
    [System.String]
    $pwProjectNumber,

    [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$false,HelpMessage="Enter the path where the archive volume(s) and log will be placed. A new folder matching the project number will be created here to contain the archive(s) and log.")]
    [System.String]
    $projectWiseDiscoveryFolder,

    [Parameter(Mandatory=$true,Position=2,ValueFromPipeline=$false,HelpMessage="Enter the path to the file contain a list of source folders to copy.")]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceLocationListFile,

    [Parameter(Mandatory=$false,Position=3,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of ROBOCOPY processes the script can spawn.  Default: 8")]
    [ValidateRange(MinRange=1, MaxRange=16)]
    [System.Int32]
    $maxRobocopyProcesses=8,

    [Parameter(Mandatory=$false,Position=4,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of threads each ROBOCOPY process can spawn.  Default: 8")]
    [ValidateRange(MinRange=1,MaxRange=16)]
    [System.Int32]
    $maxRobocopyThreads=8,

    [Parameter(Mandatory=$false,Position=5,ValueFromPipeline=$false,HelpMessage="Copy archive to discovery folder.  Default: No")]
    [switch]
    $copyToDiscovery
)
    
<#
    Given a set of command line parameters:

        1. Copy various ProjectWise files and folder into a temporary folder.
            a. Log ROBOCOPY output into individual files.
        2. Call 7-ZIP to archive all the copied files and folders into a split volume.
            a. -sdel is used to delete files/folders as they are added to the archive file.
        3. Merge all log files into a single log.
            a. Remove individual log files.
        4. Move 7-ZIP archive volumes to ProjectWise discovery folder.
        5. Move merged log file to ProjectWise discovery folder.

        Command line parameters:
            $pwProjectNumber: Project number associated with this copy
            $projectWiseDiscoveryFolder: Path to where 7-ZIP archive and log file will be copied.  Combined with $pwProjectNumber to form the complete path.
            $sourceLocationListFile: Text file containing a list of source folders to copy, 1 folder per line.
            $maxRobocopyProcesses: The maximum number of ROBOCOPY processes allowed to spawn.
            $maxRobocopyThreads: The maximum number of threads each ROBOCOPY process is allowed to spawn.
                NOTE: ($maxRobocopyProcesses * $maxRobocopyThreads) files could be copied at the same time.  Use caution.

#>

<#
    WaitForRobocopyProcesses

        Inputs:

            $roboProcesses: An array of processes (returned from Start-Process -PassThru) to check
            $maxRoboProcesses: The maximum number of ROBOCOPY processes to allow to run.  Default: 0 (Wait for all)

        Outputs:

            $procs.Length: The number of child ROBOCOPY processes returned from our WMI query (and PS filter)...
                @(GWMI -Class Win32_Process | Where-Object { ($_.Caption -match "robocopy") -and ($_.ParentProcessId -eq $myProcId) })

        Description:

            Call Get-Process with all process IDs from $roboProcesses to determine which of the processes are still running.

            Once the number of active processes is less than $maxRoboProcesses, the function returns.
#>
function WaitForRobocopyProcesses
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeline=$false)]
        [System.Int32]
        $maxRoboProcesses=0
    )

    do
    {
        # Use WMI to get running processes since Get-Process does not include ParentProcessId...
        $procs = @(GWMI -Class Win32_Process | Where-Object { ($_.Caption -match "robocopy") -and ($_.ParentProcessId -eq $Global:myProcID ) })

        if($Global:DoDebugging)
        {
            Write-Host ("`tRobocopy processes running: {0}/Max allowed: {1}...`r`n" -f @($procs.Length,$maxRoboProcesses))
        }

        # If we are at the limit, pause for a bit to allow the processes to run...
        # NOTE: Using just ($procs.Length -ge $maxRoboProcesses) here and at the end of the loop is not enough.
        #    If $maxRoboProcesses -eq 0, the -ge 0 will still be $true and the loop continues, so I have to add: "($procs.Length -gt 0) -and"
        if(($procs.Length -gt 0) -and ($procs.Length -ge $maxRoboProcesses))
        {
            Start-Sleep -Milliseconds 100
        }
    } while (($procs.Length -gt 0) -and ($procs.Length -ge $maxRoboProcesses))

    return $procs.Length
}

# Get the process ID of this POWERSHELL process so we can isolate child ROBOCOPY processes we started
$Global:myProcID = [System.Diagnostics.Process]::GetCurrentProcess().Id

$sw = [System.Diagnostics.Stopwatch]::new()
$sw.Start()

<#
# FOR DEBUGGING:
$Global:DoDebugging =  $true
if($Global:DoDebugging)
{
    # Provided on command line.  Default: 8
    $Global:maxRobocopyProcesses = 8

    # Number of threads per robocopy process.  Default: 8
    $Global:maxRobocopyThreads = 8

    # ProjectWise Project number associated with the copy.
    $Global:pwProjectNumber = "144176"

    $Global:projectWiseDiscoveryFolder = "\\boifs1\Discovery\PPL EU\ProjectWise"

    # File containing the list of source folders
    $Global:sourceLocationListFile = "C:\Users\kbriney-adm\PSScripts\PWLegalHoldCopy\144176.txt"
}
#>

# Test to see if the ProjectWise Discovery folder is viable
if(-not (Test-Path -Path $projectWiseDiscoveryFolder))
{
    Write-Error ("ProjectWise Discovery folder: {0} does not exist or is inaccessible.  Exiting." -f @($projectWiseDiscoveryFolder))
    return
}

# Final path for archive and logs.
$finalProjectWiseDiscoveryFolder = "{0}\{1}" -f @($projectWiseDiscoveryFolder, $pwProjectNumber)

if($copyToDiscovery)
{
    # Make sure the final destination does NOT exist
    if(Test-Path -Path $finalProjectWiseDiscoveryFolder)
    {
        Write-Error ("Folder: {0} already exists in discovery folder: {1}.  Exiting." -f @($pwProjectNumber, $projectWiseDiscoveryFolder))
        return
    }

    # Try to create the final destination folder...
    try
    {
        New-Item -ItemType Directory -Path $projectWiseDiscoveryFolder -Name $pwProjectNumber -ErrorAction stop
    }
    catch
    {
        Write-Error ("Failed to create project folder: {0} in discovery folder {1}.  Exiting." -f @($pwProjectNumber, $projectWiseDiscoveryFolder))
        return
    }
}

# Check to see if 7-Zip is available
$sevenZipPath = [String]::Empty
$itemProperty = $null
try
{
    $itemProperty = Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\7-Zip -ErrorAction Stop
}
catch
{
    Write-Error "7-Zip does not appear to be installed.  Exiting."
    return
}

if(($null -ne $itemProperty) -and (-not [String]::IsNullOrEmpty($itemProperty.Path)))
{
    $sevenZipPath = "{0}7z.exe" -f @($itemProperty.Path)
    if(-not (Test-Path -Path $sevenZipPath))
    {
        Write-Error "7-Zip executable not found.  Exiting."
        return
    }
}

if(-not (Test-Path -Path $sourceLocationListFile))
{
    Write-Error ("{0} not found or is inaccessible.  Exiting." -f @($Global:sourceLocationListFile))
    return
}

# Read in the list of source locations to copy and archive.
try
{
    $sourceLocations = Get-Content -Path $sourceLocationListFile -ErrorAction Stop
}
catch
{
    Write-Error ("Unable to read source location list from {0}.  Exiting." -f @($sourceLocationListFile))
    return
}


# This is were the script will do it's work.
$tmpFolder = $env:TEMP
$tmpFolder = "E:\TMP\LHTMP"

# Path the the merged log file.
$mergedLogFile = "{0}\{1}.log" -f @($tmpFolder, $pwProjectNumber)

# An array of robocopy log files.  Used to merge them all into a single file.
$logFiles = @()

# Create a string builder to hold warnings we'll add to the merged log file.
$sbWarnings = [System.Text.StringBuilder]::new()

# How many robocopy processes were running when we last checked?
$robocopyProcessesRunning = 0

# Process each source location listed in $sourceLocationListFile
$uniqueSourceLocations = @($sourceLocations | Sort-Object | Select-Object -Unique)
foreach($sourceLocation in $uniqueSourceLocations)
{
    # Make sure $sourceLocation is viable.
    if(Test-Path -Path $sourceLocation)
    {
        # Parse out the source folder from $sourceLocation
        $sourceFolder = [System.IO.Path]::GetFileName($sourceLocation)

        # Name of log file for the next ROBOCOPY process
        $logFile = "{0}\{1}.log" -f @($tmpFolder, $sourceFolder)

        # Temporary destination for ROBOCOPY
        $tmpDestination = "{0}\{1}\{2}" -f @($tmpFolder, $pwProjectNumber, $sourceFolder)

        # Array of command-line parameters for ROBOCOPY
        $cmdArgs = @(
            ("`"{0}`"" -f @($sourceLocation)),        # Source Directory (drive:\path or \\server\share\path).
            ("`"{0}`"" -f @($tmpDestination)),        # Destination Dir  (drive:\path or \\server\share\path).
            "/E",                                     # copy subdirectories, including Empty ones.
            "/ZB",                                    # use restartable mode; if access denied use Backup mode.
            "/COPYALL",                               # COPY ALL file info (equivalent to /COPY:DATSOU).
            "/R:1",                                   # Number of Retries on failed copies: default 1 million.
            "/W:1",                                   # Wait time between retries: default is 30 seconds.
            "/NP",                                    # No Progress - don't display percentage copied.
            ("/MT:{0}" -f @($maxRobocopyThreads)),    # Do multi-threaded copies with n threads (default 8).
#            "/L",                                     # List only - don't copy, timestamp or delete any files.
            ("/LOG:{0}" -f @($logFile))               # output status to LOG file (overwrite existing log). 
        )

        # Keep track of all log files so they can be merged.
        $logFiles += $logFile

        if($Global:DoDebugging)
        {
            Write-Host ("robocopy {0}" -f @([String]::Join(" ", $cmdArgs)))
        }

        <#
            The below logic was used because calling WaitForRobocopyProcesses uses Get-WMI which is slow enough that
            rarely were there more than 2/3 ROBOCOPY processes running, which only slows then entire process down.

            So, if I *KNOW" I can't possibly have too many ROBOCOPY processes running, because I haven't started
            them, then no need to even look.  When I think I have $maxRobocopyProcesses running, then I'll call
            WaitForRobocopyProcesses to actually check and wait if necessary.
        #>
        if($robocopyProcessesRunning -lt ($maxRobocopyProcesses - 1))
        {
            # Don't wait yet... just start another and increment the number of processes we think are running...
            $robocopyProcessesRunning++
        }
        else
        {
            # Wait until there are fewer than $maxRobocopyProcesses ROBOCOPY processes running.
            #    ...and re-get the number of robocopy processes that are running...
            $robocopyProcessesRunning = WaitForRobocopyProcesses $maxRobocopyProcesses
        }

        # Spawn a new ROBOCOPY process to copy this $sourceLocation
        Start-Process -WindowStyle Minimized robocopy $cmdArgs | Out-Null
    }
    else
    {
        $warning = "Source location: {0} is unavailable.  Skipping" -f @($sourceLocation)
        Write-Warning $warning
        [void] $sbWarnings.AppendLine($warning)
    }
}

# Wait for any remaining ROBOCOPY processes to complete.
$x = WaitForRobocopyProcesses

# If there were any warning, put them at the top of the merged log file.
if($sbWarnings.Length -gt 0)
{
    # Append some whitespace to the warnings to separate them from the ROBOCOPY logs.
    [void] $sbWarnings.AppendLine("`r`n`r`n")
    $sbWarnings.ToString() | Out-File -FilePath $mergedLogFile
}

# Merge all the log files into a single file.  And remove the individual log files.
$logFiles | ForEach-Object {
    Get-Content -Path $_ | Out-File -Append -FilePath $mergedLogFile
    Remove-Item -Path $_ -Force
}

# Base file name for the 7-Zip archive.
$sevenZipArchiveFileName = "{0}\{1}\{1}.zip" -f @($tmpFolder, $pwProjectNumber)

# Files/Folder
$archiveFilter = "{0}\{1}\*" -f @($tmpFolder, $pwProjectNumber)    # NOTE: *.* means add files/folder that have a name AND extension.  To get all files/folders regardless of extension or not, use just "*"

# Create an array of command line parameters for 7-zip
$cmdArgs = @(
    "a",                       # Add files to archive
    "-r",                      # Recurse subdirectories
    "-sdel",                   # delete files after compression
#    "-mx9",                    # set compression level: mx9 = ultra (best compression, slowest processing)  -- Turns out, this is WAY, WAY too slow...
    "-v8g",                    # Create volumes (8GB in size)
    $sevenZipArchiveFileName,  # archive name
    $archiveFilter             # list of files to add to the archive
)


$copyTime = $sw.Elapsed
Write-Host ("Copy took: {0}" -f @($copyTime.ToString()))

# Spawn 7-Zip to compress the files and folders
Start-Process  -WindowStyle Minimized $sevenZipPath $cmdArgs -Wait | Out-Null

# Move the merged log file into the project folder.  NOTE: Do this after 7-Zip finishes so it doesn't get added to the archive...
Move-Item -Path $mergedLogFile -Destination ("{0}\{1}" -f @($tmpFolder, $pwProjectNumber)) -Confirm:$false -Force

# Still need to add code to move the archive(s) and logs to $projectWiseDiscoveryFolder

$zipTime = $sw.Elapsed - $copyTime
Write-Host ("Zip time: {0}" -f @($zipTime.ToString()))

if($copyToDiscovery)
{
    # Copy the archive volumes and merged log to the discovery folder.
}

$sw.Stop()
Write-Host ("Overall time: {0}" -f @($sw.Elapsed.ToString()))

