[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$false,HelpMessage="Enter the ProjectWise project associated with the source folders.")]
    [System.String]
    $pwProjectNumber,

    [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$false,HelpMessage="Enter the path to the file contain a list of source folders to copy.")]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceLocationListFile,

    [Parameter(Mandatory=$false,Position=2,ValueFromPipeline=$false,HelpMessage="Enter the path where the archive volume(s) and log will be placed. A new folder matching the project number will be created here to contain the archive(s) and log.")]
    [System.String]
    $projectWiseDiscoveryFolder,

    [Parameter(Mandatory=$false,Position=3,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of ROBOCOPY processes the script can spawn.  Default: 8")]
    [ValidateRange(1, 16)]
    [System.Int32]
    $maxRobocopyProcesses=8,

    [Parameter(Mandatory=$false,Position=4,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of threads each ROBOCOPY process can spawn.  Default: 8")]
    [ValidateRange(1, 16)]
    [System.Int32]
    $maxRobocopyThreads=8,

    [Parameter(Mandatory=$false,Position=5,ValueFromPipeline=$false,HelpMessage="Copy archive to discovery folder.  Default: No")]
    [switch]
    $copyToDiscovery,

    [Parameter(Mandatory=$false,Position=6,ValueFromPipeline=$false,HelpMessage="Copy archive to discovery folder.  Default: No")]
    [switch]
    $listOnly
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

function WaitFor7ZipProcess
{
    do
    {
        # Use WMI to get running processes since Get-Process does not include ParentProcessId...
        $procs = @(GWMI -Class Win32_Process | Where-Object { ($_.Caption -match "7z") -and ($_.ParentProcessId -eq $Global:myProcID ) })

        if($procs.Length -gt 0)
        {
            Start-Sleep -Milliseconds 100
        }
    } while ($procs.Length -gt 0)
}


function FindReportLine($report, $startLine, $searchStr)
{
    $l = $startLine
    while(($null -ne $report) -and ($report -is [Array]) -and ($l -lt $report.Length) -and ($report[$l] -notmatch $searchStr))
    {
        $l++
    }

    return $l
}

function ConvertToBytes($str)
{
    $v = 0
    $parts = $str -split ' '
    if($parts.Length -eq 2)
    {
        switch($parts[1])
        {
            "k" { $v = [int64](([decimal]$parts[0]) * 1024) }
            "m" { $v = [int64](([decimal]$parts[0]) * 1024 * 1024) }
            "g" { $v = [int64](([decimal]$parts[0]) * 1024 * 1024 * 1024) }
        }
    }
    else
    {
        $v = [decimal]$parts[0]
    }

    return $v
}

function FindReportStatLine($report, $startLine, $stat)
{
    $d = $null
    $statSearchStr = "\s+{0} :\s+([0-9\.]+\s*\w*)\s+([0-9\.]+\s*\w*)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)" -f @($stat)
    $statLine = FindReportLine $report $startLine $statSearchStr
    if(($statLine -lt $report.Length) -and ($report[$statLine] -match $statSearchStr))
    {
        $d = "" | Select-Object Total,Copied,Skipped,Mismatched,Failed,Extras,NextLine

        if($stat -ne "Bytes")
        {
            $d.Total = [int64]$Matches[1]
            $d.Copied = [int64]$Matches[2]
            $d.Skipped = [int64]$Matches[3]
            $d.Mismatched = [int64]$Matches[4]
            $d.Failed = [int64]$Matches[5]
            $d.Extras = [int64]$Matches[6]
        }
        else
        {
            $d.Total = ConvertToBytes $Matches[1]
            $d.Copied =  ConvertToBytes $Matches[2]
            $d.Skipped = ConvertToBytes $Matches[3]
            $d.Mismatched = ConvertToBytes $Matches[4]
            $d.Failed = ConvertToBytes $Matches[5]
            $d.Extras = ConvertToBytes $Matches[6]
        }

        $d.NextLine = [int64]$statLine + 1
    }

    return $d
}

function ProcessRoboReport($report)
{
    $totals = "" | Select-Object Dirs,Files,Bytes

    $totals.Dirs = "" | Select-Object Total,Copied,Skipped,Mismatched,Failed,Extras
    $totals.Files = "" | Select-Object Total,Copied,Skipped,Mismatched,Failed,Extras
    $totals.Bytes = "" | Select-Object Total,Copied,Skipped,Mismatched,Failed,Extras

    $logData = @()
    $startLine = 0
    while($startLine -lt $report.Length)
    {
        $startedLine = FindReportLine $report $startLine "^\s+Started :"
        if($Global:DoDebugging)
        {
            Write-Host ("Started line: {0}" -f @($startedLine))
        }
        if(($startedLine -lt $report.Length) -and ($report[$startedLine] -match "\s+Started : (.*)"))
        {
            $started = $Matches[1]
            if($Global:DoDebugging)
            {
                Write-Host ("Started: {0}" -f @($started))
            }
            $sourceLine = FindReportLine $report ($startLine + 1) "^\s+Source :"
            if($Global:DoDebugging)
            {
                Write-Host ("Source line: {0}" -f @($sourceLine))
            }
            if(($sourceLine -lt $report.Length) -and ($report[$sourceLine] -match "\s+Source : (.*)"))
            {
                $source = $Matches[1]
                if($Global:DoDebugging)
                {
                    Write-Host ("Source: {0}" -f @($source))
                }
                $dirs = FindReportStatLine $report ($sourceLine + 1) "Dirs"
                if($null -ne $dirs)
                {
                    if($Global:DoDebugging)
                    {
                        Write-Host ("Dirs: Total: {0}, Copied: {1}, Skipped: {2}, Mismatched: {3}, Failed: {4}, Extras: {5}, NextLine: {6}" -f @($dirs.Total, $dirs.Copied, $dirs.Skipped, $dirs.Mismatched, $dirs.Failed, $dirs.Extras, $dirs.NextLine))
                    }
                    if(($dirs.Copied -ne $dirs.Total) -or ($dirs.Failed -ne 0))
                    {
                        Write-Host -ForegroundColor Red ("Dirs copy error.`r`nSource: {0}: {1}`r`n`tTotal: {2}, Copied: {3}, Skipped: {4}, Mismatch: {5}, FAILED: {6}, Extras: {7}" -f @($report[$sourceLine], $sourceLine, $dirs.Total, $dirs.Copied, $dirs.Skipped, $dirs.Mismatched, $dirs.Failed, $dirs.Extras))
                    }
                    $files = FindReportStatLine $report $dirs.NextLine "Files"
                    if($null -ne $files)
                    {
                        if($Global:DoDebugging)
                        {
                            Write-Host ("Files: Total: {0}, Copied: {1}, Skipped: {2}, Mismatched: {3}, Failed: {4}, Extras: {5}, NextLine: {6}" -f @($files.Total, $files.Copied, $files.Skipped, $files.Mismatched, $files.Failed, $files.Extras, $files.NextLine))
                        }
                            
                        if(($files.Copied -ne $files.Total) -or ($files.Failed -ne 0))
                        {
                            Write-Host -ForegroundColor Red ("Files copy error.`r`nSource: {0}: {1}`r`n`tTotal: {2}, Copied: {3}, Skipped: {4}, Mismatch: {5}, FAILED: {6}, Extras: {7}" -f @($report[$sourceLine], $sourceLine, $files.Total, $files.Copied, $files.Skipped, $files.Mismatched, $files.Failed, $files.Extras))
                        }
                        $bytes = FindReportStatLine $report $files.NextLine "Bytes"
                        if($null -ne $bytes)
                        {
                            if($Global:DoDebugging)
                            {
                                Write-Host ("Bytes: Total: {0}, Copied: {1}, Skipped: {2}, Mismatched: {3}, Failed: {4}, Extras: {5}, NextLine: {6}" -f @($bytes.Total, $bytes.Copied, $bytes.Skipped, $bytes.Mismatched, $bytes.Failed, $bytes.Extras, $bytes.NextLine))
                            }
                                    
                            $d = "" | Select-Object Started, Source, Directories, Files, Bytes
                            $d.Started = $started
                            $d.Source = $source
                            $d.Directories = $dirs
                            $d.Files = $files
                            $d.Bytes = $bytes

                            $logData += $d
                                                
                            $totals.Dirs.Total += [int64]$dirs.Total
                            $totals.Dirs.Copied += [int64]$dirs.Copied
                            $totals.Dirs.Skipped += [int64]$dirs.Skipped
                            $totals.Dirs.Mismatched += [int64]$dirs.Mismatched
                            $totals.Dirs.Failed += [int64]$dirs.Failed
                            $totals.Dirs.Extras += [int64]$dirs.Extras
                                                
                            $totals.Files.Total += [int64]$files.Total
                            $totals.Files.Copied += [int64]$files.Copied
                            $totals.Files.Skipped += [int64]$files.Skipped
                            $totals.Files.Mismatched += [int64]$files.Mismatched
                            $totals.Files.Failed += [int64]$files.Failed
                            $totals.Files.Extras += [int64]$files.Extras

                            $totals.Bytes.Total += [int64]$bytes.Total
                            $totals.Bytes.Copied += [int64]$bytes.Copied
                            $totals.Bytes.Skipped += [int64]$bytes.Skipped
                            $totals.Bytes.Mismatched += [int64]$bytes.Mismatched
                            $totals.Bytes.Failed += [int64]$bytes.Failed
                            $totals.Bytes.Extras += [int64]$bytes.Extras

                            $startLine = $bytes.NextLine
                        }
                        else
                        {
                            Write-Host -ForegroundColor Red ("Unable to locate Bytes line on/after line: {0}" -f @($files.NextLine))
                            $startLine = $report.Length
                        }
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red ("Unable to locate Files line on/after line: {0}" -f @($dirs.NextLine))
                        $startLine = $report.Length
                    }
                }
                else
                {
                    Write-Host -ForegroundColor Red ("Unable to locate Dirs line on/after line: {0}" -f @($sourceLine + 1))
                    $startLine = $report.Length
                }
            }
            else
            {
                Write-Host -ForegroundColor Red ("Unable to locate Source line on/after line: {0}" -f @($startLine + 1))
                $startLine = $report.Length
            }
        }
        else
        {
            # End of file...
            $d = "" | Select-Object Started, Source, Directories, Files, Bytes
            $d.Started = "Totals"
            $d.Source = ""
            $d.Directories = $totals.Dirs
            $d.Files = $totals.Files
            $d.Bytes = $totals.Bytes

            $logData += $d

            $startLine = $report.Length
        }
    }

    return $logData
}

# Get the process ID of this POWERSHELL process so we can isolate child ROBOCOPY processes we started
$Global:myProcID = [System.Diagnostics.Process]::GetCurrentProcess().Id

# Just some timing diagnostics...
$sw = [System.Diagnostics.Stopwatch]::new()
$sw.Start()
$Global:DoDebugging =  $false

<#
# FOR DEBUGGING:

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
if($copyToDiscovery)
{
    if(-not (Test-Path -Path $projectWiseDiscoveryFolder))
    {
        Write-Error ("ProjectWise Discovery folder: {0} does not exist or is inaccessible.  Exiting." -f @($projectWiseDiscoveryFolder))
        return
    }

    # Final path for archive and logs.
    $finalProjectWiseDiscoveryFolder = "{0}\{1}" -f @($projectWiseDiscoveryFolder, $pwProjectNumber)

    # Make sure the final destination does NOT exist
    if(Test-Path -Path $finalProjectWiseDiscoveryFolder)
    {
        Write-Error ("Folder: {0} already exists in discovery folder: {1}.  Exiting." -f @($pwProjectNumber, $projectWiseDiscoveryFolder))
        return
    }

    # Try to create the final destination folder...
    <#
    try
    {
        New-Item -ItemType Directory -Path $projectWiseDiscoveryFolder -Name $pwProjectNumber -ErrorAction stop
    }
    catch
    {
        Write-Error ("Failed to create project folder: {0} in discovery folder {1}.  Exiting." -f @($pwProjectNumber, $projectWiseDiscoveryFolder))
        return
    }
    #>
}

$sevenZipPath = [String]::Empty
if(-not $listOnly)
{
    # Check to see if 7-Zip is available
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

# Flag to determine if copying to the projectwise discovery folder should be skipped due to an existing folder.
$skipFinalCopy = $false

# This is were the script will do it's work.
$tmpFolder = "E:\TMP\LHTMP"

# Path the the merged log file.
$mergedLogFile = "{0}\{1}.log" -f @($tmpFolder, $pwProjectNumber)

# Path the the condensed log file.
#   Since this file is written AFTER 7-Zip is done, we are safe to write it straight to the project folder.
$condensedLogFile = "{0}\{1}\{1}.csv" -f @($tmpFolder, $pwProjectNumber)

# An array of robocopy log files.  Used to merge them all into a single file.
$logFiles = @()

# Create a string builder to hold warnings we'll add to the merged log file.
$sbWarnings = [System.Text.StringBuilder]::new()

# How many robocopy processes were running when we last checked?
$robocopyProcessesRunning = 0

# Process each source location listed in $sourceLocationListFile
$uniqueSourceLocations = @($sourceLocations | Sort-Object | Select-Object -Unique)
$a = 0
while($a -lt $uniqueSourceLocations.Length)
{
    $sourceLocation = $uniqueSourceLocations[$a]

    # Make sure $sourceLocation is viable.
    if(Test-Path -Path $sourceLocation)
    {
        # Parse out the source folder from $sourceLocation
        $sourceFolder = [System.IO.Path]::GetFileName($sourceLocation)

        # Name of log file for the next ROBOCOPY process
        $logFile = "{0}\{1}.log" -f @($tmpFolder, $sourceFolder)

        # Temporary destination for ROBOCOPY
        $tmpDestination = "{0}\{1}\{2}" -f @($tmpFolder, $pwProjectNumber, $sourceFolder)

        <#
        if($copyToDiscovery)
        {
            $realDestination = "{0}\{1}" -f @($projectWiseDiscoveryFolder, $pwProjectNumber)
            if(Test-Path -Path $realDestination)
            {
                Write-Host -ForegroundColor Yellow ("WARNING: ProjectWise discovery folder {0} already exists." -f @($realDestination))
                $skipFinalCopy = $true
            }
        }
        #>
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
            ("/LOG:{0}" -f @($logFile))               # output status to LOG file (overwrite existing log). 
        )

        if($listOnly)
        {
            $cmdArgs += "/L"                          # List only - don't copy, timestamp or delete any files.
        }

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

        $percentComplete = ($a / ($uniqueSourceLocations.Length / 0.99)) * 100
        Write-Progress -Activity "Copying ProjectWise projects..." -Status ("{0:N1}% Complete:" -f @($percentComplete)) -PercentComplete $percentComplete -CurrentOperation ("{0} Robocopy processes running" -f @($robocopyProcessesRunning))
    }
    else
    {
        $warning = "Source location: {0} is unavailable.  Skipping" -f @($sourceLocation)
        Write-Warning $warning
        [void] $sbWarnings.AppendLine($warning)
    }

    $a++
}

# Wait for any remaining ROBOCOPY processes to complete.
$x = WaitForRobocopyProcesses

Write-Progress -Activity "Copying ProjectWise projects..." -Status "100% Complete:" -PercentComplete 100

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

$copyTime = $sw.Elapsed
if($listOnly)
{
    Write-Host ("Listing took: {0}" -f @($copyTime.ToString()))
}
else
{
    Write-Host ("Copying took: {0}" -f @($copyTime.ToString()))

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

#    Write-Host ("[{0}]" -f @($cmdArgs -join "]["))

    Write-Progress -Activity "Zipping ProjectWise projects..." -Status "0% Complete:" -PercentComplete 0

    # Spawn 7-Zip to compress the files and folders

    #Write-Host ("Start-Process  -WindowStyle Minimized {0} {1} -Wait | Out-Null" -f @($sevenZipPath, ($cmdArgs -join " ")))
#    Start-Process -WindowStyle Normal -FilePath $sevenZipPath -ArgumentList $cmdArgs -Wait | Out-Null
    & $sevenZipPath $cmdArgs
    WaitFor7ZipProcess

    Write-Progress -Activity "Zipping ProjectWise projects..." -Status "100% Complete:" -PercentComplete 100

    $zipTime = $sw.Elapsed - $copyTime
    Write-Host ("Zip time: {0}" -f @($zipTime.ToString()))
    
    <#
        New way to process the log file.  Makes it easier to check everything.
    #>

    $a = 0
    $sb = [System.Text.StringBuilder]::new()

    # Read in the contents of the merged ROBOCOPY log files
    $report = Get-Content -Path $mergedLogFile

    # Reduce the logs to something more manageable
    $logData = ProcessRoboReport $report

    # Convert the collected log data into a tab delimited file.

    # Column names
    $str = @("Started", "Source", "Directories.Total", "Directories.Copied", "Directories.Skipped", "Directories.Mismatched", "Directories.Failed", "Directories.Extras", "Files.Total", "Files.Copied", "Files.Skipped", "Files.Mismatched", "Files.Failed", "Files.Extras", "Bytes.Total", "Bytes.Copied", "Bytes.Skipped", "Bytes.Mismatched", "Bytes.Failed", "Bytes.Extras") -join "`t"
    [void] $sb.AppendLine($str)

    # Put the totals at the top.
    $str = @($logData[$logData.Length-1].Started, $logData[$logData.Length-1].Source, $logData[$logData.Length-1].Directories.Total, $logData[$logData.Length-1].Directories.Copied, $logData[$logData.Length-1].Directories.Skipped, $logData[$logData.Length-1].Directories.Mismatched, $logData[$logData.Length-1].Directories.Failed, $logData[$logData.Length-1].Directories.Extras, $logData[$logData.Length-1].Files.Total, $logData[$logData.Length-1].Files.Copied, $logData[$logData.Length-1].Files.Skipped, $logData[$logData.Length-1].Files.Mismatched, $logData[$logData.Length-1].Files.Failed, $logData[$logData.Length-1].Files.Extras, $logData[$logData.Length-1].Bytes.Total, $logData[$logData.Length-1].Bytes.Copied, $logData[$logData.Length-1].Bytes.Skipped, $logData[$logData.Length-1].Bytes.Mismatched, $logData[$logData.Length-1].Bytes.Failed, $logData[$logData.Length-1].Bytes.Extras) -join "`t"
    [void] $sb.AppendLine($str)

    # Convert each array element into a tab delimited line of text.
    $b = 0
    while($b -lt ($logData.Length - 1)) # last line is totals
    {
        $str = @($logData[$b].Started, $logData[$b].Source, $logData[$b].Directories.Total, $logData[$b].Directories.Copied, $logData[$b].Directories.Skipped, $logData[$b].Directories.Mismatched, $logData[$b].Directories.Failed, $logData[$b].Directories.Extras, $logData[$b].Files.Total, $logData[$b].Files.Copied, $logData[$b].Files.Skipped, $logData[$b].Files.Mismatched, $logData[$b].Files.Failed, $logData[$b].Files.Extras, $logData[$b].Bytes.Total, $logData[$b].Bytes.Copied, $logData[$b].Bytes.Skipped, $logData[$b].Bytes.Mismatched, $logData[$b].Bytes.Failed, $logData[$b].Bytes.Extras) -join "`t"

        [void] $sb.AppendLine($str)
        $b++
    }

    # Now, write the condensed data back out to a file.
    Set-Content -Path $condensedLogFile -Value $sb.ToString()

    # Finally, remove the merged log file.

    # Move the merged log file into the project folder.  NOTE: Do this after 7-Zip finishes so it doesn't get added to the archive...
    Move-Item -Path $mergedLogFile -Destination ("{0}\{1}" -f @($tmpFolder, $pwProjectNumber)) -Confirm:$false -Force
}

# Still need to add code to move the archive(s) and logs to $projectWiseDiscoveryFolder

if((-not $listOnly) -and ($copyToDiscovery) -and (-not $skipFinalCopy))
{
    # Copy the archive volumes and merged log to the discovery folder.
    
    # Name of log file for the next ROBOCOPY process
    $logFile = "E:\TMP\{0}-finalCopy.log" -f @($pwProjectNumber)

    # Copy source
    $source = "`"{0}\{1}`"" -f @($tmpFolder,$pwProjectNumber)

    # Copy destination
    $destination = "`"{0}\{1}`"" -f @($projectWiseDiscoveryFolder,$pwProjectNumber)

    # Multi-threaded option
    $mt = "/MT:{0}" -f @($maxRobocopyThreads)

    # Log file option
    $logOption = "/LOG:{0}" -f @($logFile)

    # Array of command-line parameters for ROBOCOPY
    $cmdArgs = @(
        $source,          # Source Directory (drive:\path or \\server\share\path).
        $destination,     # Destination Dir  (drive:\path or \\server\share\path).
        "/E",             # copy subdirectories, including Empty ones.
        "/ZB",            # use restartable mode; if access denied use Backup mode.
        "/COPY:DAT",      # COPY Data, Attributes, and Timestamps
        "/R:1",           # Number of Retries on failed copies: default 1 million.
        "/W:1",           # Wait time between retries: default is 30 seconds.
        "/NP",            # No Progress - don't display percentage copied.
        $mt,              # Do multi-threaded copies with n threads (default 8).
        $logOption        # output status to LOG file (overwrite existing log). 
    )

    Write-Progress -Activity "Moving zipped ProjectWise projects to discovery folder..." -Status "0% Complete:" -PercentComplete 0

    # Spawn a new ROBOCOPY process to copy this $sourceLocation
    # Start-Process -WindowStyle Normal robocopy $cmdArgs -Wait | Out-Null
    & robocopy $cmdArgs

    Write-Progress -Activity "Moving zipped ProjectWise projects to discovery folder..." -Status "100% Complete:" -PercentComplete 100
    
    Set-Content -Path ("{0}\{1}\DONE.TXT" -f @($projectWiseDiscoveryFolder, $pwProjectNumber)) -Value "Complete"

    $discoveryCopyTime = $sw.Elapsed - ($copyTime  + $zipTime)
    Write-Host ("Copy to ProjectWise Discovery time: {0}" -f @($discoveryCopyTime.ToString()))    
}

$sw.Stop()
if(-not $listOnly)
{
    Write-Host ("Overall time: {0}" -f @($sw.Elapsed.ToString()))
}

