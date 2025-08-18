[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$false,HelpMessage="Enter the path to the file containing a list of source folders to copy.")]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceLocationListFile,

    [Parameter(Mandatory=$false,Position=1,ValueFromPipeline=$false,HelpMessage="Enter the path where files and folders from `$sourceLocationListFile will be copied to.")]
    [System.String]
    $pwLHDestinationFolder,

    [Parameter(Mandatory=$false,Position=2,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of ROBOCOPY processes the script can spawn.  Default: 8")]
    [ValidateRange(1, 16)]
    [System.Int32]
    $maxRobocopyProcesses=8,

    [Parameter(Mandatory=$false,Position=3,ValueFromPipeline=$false,HelpMessage="Enter the maximum number of threads each ROBOCOPY process can spawn.  Default: 8")]
    [ValidateRange(1, 16)]
    [System.Int32]
    $maxRobocopyThreads=8,

    [Parameter(Mandatory=$false,Position=4,ValueFromPipeline=$false,HelpMessage="Copy archive to discovery folder.  Default: No")]
    [switch]
    $listOnly,

    [Parameter(Mandatory=$true,Position=5,ValueFromPipeline=$false,HelpMessage="Folder for log files.")]
    [String]
    $logFolder
)

<#


    Given a set of command line parameters:

        1. Copy various ProjectWise files and folder into a temporary folder.
            a. Log ROBOCOPY output into individual files.
        2. Merge all log files into a single log.
            a. Remove individual log files.
        3. Move merged log file to ProjectWise discovery folder.

        Command line parameters:
            $pwProjectNumber: Project number associated with this copy
            $pwLHDestinationFolder: Path to where 7-ZIP archive and log file will be copied.  Combined with $pwProjectNumber to form the complete path.
            $sourceLocationListFile: Text file containing a list of source folders to copy, 1 folder per line.
            $maxRobocopyProcesses: The maximum number of ROBOCOPY processes allowed to spawn.
            $maxRobocopyThreads: The maximum number of threads each ROBOCOPY process is allowed to spawn.
                NOTE: ($maxRobocopyProcesses * $maxRobocopyThreads) files could be copied at the same time.  Use caution.

#>

<#
    WaitForRobocopyProcesses

        Inputs:
            $maxRoboProcesses: The maximum number of ROBOCOPY processes to allow to run.  Default: 0 (Wait for all)

        Outputs:
            $procs.Length: The number of child ROBOCOPY processes returned from our CIM query (and PS filter)...
                @(Get-CimInstance -Class Win32_Process | Where-Object { ($_.Caption -match "robocopy") -and ($_.ParentProcessId -eq $myProcId) })

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
        $procs = @(Get-CimInstance -ClassName Win32_Process | Where-Object { ($_.Caption -match "robocopy") -and ($_.ParentProcessId -eq $Global:myProcID ) })

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
$Global:DoDebugging =  $true

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

    $Global:pwLHDestinationFolder = "\\boifs1\Discovery\PPL EU\ProjectWise"

    # File containing the list of source folders
    $Global:sourceLocationListFile = "C:\Users\kbriney-adm\PSScripts\PWLegalHoldCopy\144176.txt"
}
#>

if(-not (Test-Path -Path $pwLHDestinationFolder))
{
    Write-Error ("ProjectWise Discovery folder: {0} does not exist or is inaccessible.  Exiting." -f @($pwLHDestinationFolder))
    return
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
#  Before: I was copying the files to a temporary folder to zip them, since Karalee now wants them raw, I'll just robocopy them to the destination.
# $tmpFolder = "E:\TMP\LHTMP"
$tmpFolder = $pwLHDestinationFolder

# Path to the merged log file.
$mergedLogFile = "{0}\Merged.log" -f @($logFolder)

# Path to the condensed log file.
$condensedLogFile = "{0}\Condensed_Log.csv" -f @($logFolder)

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

    $Script:goodPath = $false
    $testTime = Measure-Command -Expression {
        $Script:goodPath = [System.IO.Directory]::Exists($sourceLocation)
    }

    if($Global:DoDebugging)
    {
        Write-Host ("{0}: Test-Path -Path {1}" -f @($testTime.ToString(), $sourceLocation))
    }

    # Make sure $sourceLocation is viable.
    if($Script:goodPath)
    {
        # Parse out the source folder from $sourceLocation
        $sourceFolder = [System.IO.Path]::GetFileName($sourceLocation)

        # Name of log file for the next ROBOCOPY process
        $logFile = "{0}\{1}.log" -f @($logFolder, $sourceFolder)

        # Temporary destination for ROBOCOPY
        $tmpDestination = $pwLHDestinationFolder

        # Array of command-line parameters for ROBOCOPY
        $cmdArgs = @(
            ("`"{0}`"" -f @($sourceLocation)),        # Source Directory (drive:\path or \\server\share\path).
            ("`"{0}`"" -f @($tmpDestination)),        # Destination Dir  (drive:\path or \\server\share\path).
            "/E",                                     # copy subdirectories, including Empty ones.
            "/ZB",                                    # use restartable mode; if access denied use Backup mode.
            "/COPY:DAT",                              # COPY Data, Attributes, and Timestamps
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

        <#
            The logic below was used because calling WaitForRobocopyProcesses uses Get-CimInstance which is slow enough that
            rarely were there more than 2/3 ROBOCOPY processes running, which only slows then entire process down.

            So, if I *KNOW" I can't possibly have too many ROBOCOPY processes running, because I haven't started
            them, then no need to even look.  When I think I have $maxRobocopyProcesses running, then I'll call
            WaitForRobocopyProcesses to actually check and wait if necessary.
        #>
        if($robocopyProcessesRunning -ge $maxRobocopyProcesses)
        {
            # Wait until there are fewer than $maxRobocopyProcesses ROBOCOPY processes running.
            #    ...and re-get the number of robocopy processes that are running...
            if($Global:DoDebugging)
            {
                Write-Host "Waiting for an open robocopy instance..."
            }

            $robocopyProcessesRunning = WaitForRobocopyProcesses $maxRobocopyProcesses
        }

        # Spawn a new ROBOCOPY process to copy this $sourceLocation
        $robocopyProcessesRunning++
        $roboStartTime = Measure-Command -Expression {
            Start-Process -WindowStyle Minimized robocopy $cmdArgs | Out-Null
        }

        if($Global:DoDebugging)
        {
            Write-Host ("{0} of {1} ({3}): robocopy {2}" -f @($robocopyProcessesRunning, $maxRobocopyProcesses, [String]::Join(" ", $cmdArgs), $roboStartTime.ToString()))
        } `
        else
        {
            $percentComplete = ($a / ($uniqueSourceLocations.Length / 0.99)) * 100
            Write-Progress -Activity "Copying ProjectWise projects..." -Status ("{0:N1}% Complete:" -f @($percentComplete)) -PercentComplete $percentComplete -CurrentOperation ("{0} Robocopy processes running" -f @(($robocopyProcessesRunning + 1)))
        }
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

    # Move the merged log file into the project folder.
    Move-Item -Path $mergedLogFile -Destination ("{0}\{1}" -f @($tmpFolder, $pwProjectNumber)) -Confirm:$false -Force
}

$sw.Stop()

# Still need to add code to move the archive(s) and logs to $pwLHDestinationFolder

if(-not $listOnly)
{
    $discoveryCopyTime = $sw.Elapsed
    Write-Host ("Copy to ProjectWise Discovery time: {0}" -f @($discoveryCopyTime.ToString()))
    Set-Content -Path ("{0}\{1}\DONE.TXT" -f @($pwLHDestinationFolder, $pwProjectNumber)) -Value "Complete"
    Write-Host ("Overall time: {0}" -f @($sw.Elapsed.ToString()))
}
