<#
    ExecuteSecureCommand is a wrapper used to call scp or ssh given an array of parameters
#>
function ExecuteSecureCommand
{
    [CmdLetBinding()]
    Param(
        # Command to run.  i.e. "ssh" or "scp"
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cmd,

        # Parameters to pass to $cmd
        [Parameter(Mandatory=$false,Position=1)]
        [System.String[]]
        $extraCmdParams
    )

    $cmdResult = "" | Select-Object Successful, ExitCode, Command, Output, ExceededMaximumFailures

    # Return value
    $cmdResult.Output = [String]::Empty
    $cmdResult.ExitCode = -1
    $cmdResult.ExceededMaximumFailures = $false
    $cmdResult.Successful = $false

    if(-not [String]::IsNullOrEmpty($cmd))
    {
        # Make sure $cmd is only "scp" or "ssh"
        if($cmd -match "^s(cp|sh)$")
        {
            # Create $cmdParams using a standard list of parameters, combined with $extraCmdParams
            $cmdParams = @(
                "-o",
                "`"BatchMode yes`"",
                "-q"
            )
            # If the command is scp, combine $Global:secureLogon and $extraCmdParams[0] as the next parameter, otherwise
            #    just add $Global:secureLogon to $cmdParams.
            $firstExtraParam = 0

            # If $cmd is "scp", the next parameter needs to be the secure login combined with the sourceFileName
            if($cmd -eq "scp")
            {
                $failedExitCode
                if($extraCmdParams.Length -gt 0)
                {
                    $cmdParams += "{0}:{1}" -f @($Global:secureLogon, $extraCmdParams[$firstExtraParam])

                    # Bump $firstExtraParam by 1 since we just used [0]...
                    $firstExtraParam++
                }
                else
                {
                    [Log]::Error("Missing arguments for {0} in {1}" -f @($cmd, $MyInvocation.MyCommand))
                }
            }
            else
            {
                $cmdParams += $Global:secureLogon
            }

            # Now add the remaining extra parameters to $cmdParams
            for($a = $firstExtraParam; $a -lt $extraCmdParams.Length; $a++)
            {
                $cmdParams += $extraCmdParams[$a]
            }

            $cmdResult.Command = "{0} {1}" -f @($cmd, ($cmdParams -join " "))
            # No need to put the following in a try-catch block, I was unable to prevent errors from being output on the screen, short of
            #    redirecting stderr to a file, and I decided I didn't want to do that.
            [Log]::Trace("Executing: {0}" -f @($cmdResult.Command))

            # Try to complete the command until we reach the maximum failure count.
            $failureCount = 0
            do
            {
                # Execute the command and capture stdout in $retval.Output
                #   NOTE: At the time of writing, I tried several ways to invoke $cmd, but the following is the only way I could make it work 100% of the time.
                #         I kept running into issues when parameters had embedded single and double quotes.
                #   I have toyed with the idea of trying to run the command in the background so I can kill the process if it runs for too long, but as of now,
                #         I'm leaving it as is.
                $cmdResult.Output = @(& $cmd $cmdParams 2>&1)
                $cmdResult.ExitCode = $LASTEXITCODE

                # https://man.openbsd.org/ssh.1
                #   ssh exits with the exit status of the remote command or with 255 if an error occurred.
                # https://man.openbsd.org/scp.1
                #   The scp utility exits 0 on success, and >0 if an error occurs.
                if((($cmd -eq "ssh") -and ($cmdResult.ExitCode -ne 255)) -or (($cmd -eq "scp") -and ($cmdResult.ExitCode -eq 0)))
                {
                    $cmdResult.Successful = $true
                    # Nothing, all is well.
                }
                else
                {
                    $failureCount++
                    [Log]::Warning("Failed to execute [{0} {1}] {2} time(s)." -f @($cmd, $cmdResult.Command, $failureCount))
                    $cmdResult.ExceededMaximumFailures = ($failureCount -ge $Global:maxFailures)
                    if($cmdResult.ExceededMaximumFailures)
                    {
                        [Log]::Error("Reached maximum failures.")
                    }
                    else
                    {
                        # Pause for a bit...
                        Start-Sleep -Milliseconds 250
                    }
                }
            }
            while ( ($cmdResult.ExitCode -ne 0) -and (-not $cmdResult.ExceededMaximumFailures) )
        }
        else
        {
            $cmdResult.ExitCode = -2
            [Log]::Error("Only ssh and scp are valid command to {0}" -f @($MyInvocation.MyCommand))
        }
    }
    else
    {
        $cmdResult.ExitCode = -1
        [Log]::Error("Missing command in {0}" -f @($MyInvocation.MyCommand))
    }

    return $cmdResult
}

function ExecuteSSH
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0)]
        [String]
        $sshCmd=[String]::Empty
    )

    $cmdResult = ExecuteSecureCommand "ssh" ("`"{0}`"" -f @($sshCmd))

    return $cmdResult
}

function ExecuteSCP
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $sourceFileName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $destinationFolder
    )

    $cmdResult = ExecuteSecureCommand "scp" @($sourceFileName, $destinationFolder)

    return $cmdResult
}

function ExecuteCliSH
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $cliSHCmd
    )

    $cmdResult = ExecuteSSH ("clish -i -c '{0}'" -f @($cliSHCmd))

    return $cmdResult
}

<#
    GetCheckPointSnapshotDetails

    Return detailed information about a single snapshot
        *Detailed ... as much as CheckPoint will give me.
#>
function GetCheckPointSnapshotDetails
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName
    )

    $cmdResult = ExecuteCliSH ("show snapshot {0} all" -f @($snapshotName))

    # Make sure the command executed successfully
    if($cmdResult.Successful)
    {
        $snapshotDetails = "" | Select-Object Name,WhenCreated,Size,Description
        $snapshotDetails.Name = $snapshotName

        $whenCreatedStr = @($cmdResult.Output -match "^date ")
        if($whenCreatedStr.Length -eq 1)
        {
            if($whenCreatedStr[0] -match "date\s+(\w+)\s+(\w+)\s+(\d+)\s+([^\s]+)\s+(\d+)")
            {
                $dtStr = "{1} {2} {4} {0} {3}" -f $Matches[1..5]
                $snapshotDetails.WhenCreated = [DateTime]::Parse($dtStr)
            }
        }

        $sizeStr = @($cmdResult.Output -match "^size\s+([0-9\.]+\w+)")
        if($sizeStr.Length -eq 1)
        {
            if($sizeStr[0] -match "^size\s+([0-9\.]+\w+)")
            {
                $snapshotDetails.Size = $Matches[1]
            }
        }

        $descriptionStr = @($cmdResult.Output -match "^description\s+(.*)")
        if($descriptionStr.Length -eq 1)
        {
            if($descriptionStr[0] -match "^description\s+(.*)")
            {
                $snapshotDetails.Description = $Matches[1]
            }
        }

        $cmdResult.Output = $snapshotDetails
    }
    else
    {
        # Nothing, already logged an error
    }

    return $cmdResult
}

<#
    GetCheckPointSnapshots

    Return detailed information about all snapshots
        *Detailed ... as much as CheckPoint will give me.
#>
function GetCheckPointSnapshots
{
    $cmdResult = ExecuteCliSH "show snapshots"

    if($cmdResult.Successful)
    {
        # An array of regex strings to ignore in the output
        $regexToIgnore = @("Config lock", "Restore point", "------", "Creation of an additional", "Amount of space available", "Export image", "\(\d+%\)", "^$")

        # Initialize return value
        $snapShotData = @()

        foreach($regex in $regexToIgnore)
        {
            $cmdResult.Output = @($cmdResult.Output | Where-Object { ($_ -notmatch $regex) })
        }

        for($l = 0; ($cmdResult.Successful) -and ($l -lt $cmdResult.Output.Length); $l++)
        {
            $ln = $cmdResult.Output[$l]
            $ssDetailsResult = GetCheckPointSnapshotDetails $ln
            if($ssDetailsResult.Successful)
            {
                $snapShotData += $ssDetailsResult.Output
            }
            else
            {
                $cmdResult.ExitCode = $ssDetailsResult.ExitCode
                $cmdResult.Successful = $ssDetailsResult.Successful
            }
        }

        if($cmdResult.Successful)
        {
            $cmdResult.Output = $snapShotData
        }
        else
        {
            $cmdResult.Output = $null
        }
    }
    else
    {
        # Nothing, already logged an error
    }

    return $cmdResult
}

function GetWorkingDirectory
{
    $cmdResult = ExecuteSSH "pwd"

    return $cmdResult
}

function CreateCheckPointSnapshot
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$false,Position=1)]
        [String]
        $snapshotDescription
    )

    # Assume the snapshot creation failed until we know otherwise.
    $snapshotCreated = $false

    # If no snapshot name was provided, create one based on device name and date/time
    if([String]::IsNullOrEmpty($snapshotName))
    {
        $snapshotName = "{0}_{1}" -f @($Global:deviceName,[DateTime]::Now.ToString("yyyyMMddHHmmss"))
    }

    # If no snapshot description was provided, create one.
    if([String]::IsNullOrEmpty($snapshotDescription))
    {
        $snapshotDescription = "Created by script"
    }

    # There can be no spaces in the snapshot name.
    if($snapshotName -notmatch "\s")
    {
        # Make sure there is not already a snapshot named $snapshotName
        [Log]::Info("Checking for a pre-existing snapshot named: {0}" -f @($snapshotName))

        $cmdResult = GetCheckPointSnapshots
        if($cmdResult.Successful)
        {
            if(($cmdResult.Output -match $snapshotName).Length -eq 0)
            {
                [Log]::Info("No pre-existing snapshot named {0}.  Creating new snapshot." -f @($snapshotName))

                $cmdResult = ExecuteCliSH ("add snapshot {0} desc \`"{1}\`"" -f @($snapshotName, $snapshotDescription))
                $snapshotCreated = $cmdResult.Successful
                if($snapshotCreated)
                {
                    [Log]::Info("Created snapshot {0}." -f @($snapshotName))
                }
                else
                {
                    [Log]::Error("Failed to create snapshot {0}." -f @($snapshotName))
                }
            }
            else
            {
                [Log]::Error("There is already a snapshot named {0}." -f @($snapshotName))
            }
        }
        else
        {
            [Log]::Error("Failed to get a list of the current snapshots.")
        }
    }
    else
    {
        [Log]::Error("Snapshot name [{0}] contains whitespace." -f @($snapshotName))
    }

    return $snapshotCreated
}

function WaitForCheckPointToCreateSnapshot
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$false,Position=2)]
        [TimeSpan]
        $waitTime=[TimeSpan]::new(0,10,0)
    )

    $retval = "" | Select-Object TimedOut, ExceededMaximumFailures, HaveSnapshot, Elapsed
    $retval.TimedOut = $false

    # Track the if I have exceeded the maximum allowed failures.
    $retval.ExceededMaximumFailures = $false

    # Track if we have seen the snapshot name in the snapshot list
    $retval.HaveSnapshot = $false

    # Track when we started waiting for the snapshot to be discovered.
    $startTime = [DateTime]::Now

    [Log]::Info("Waiting for creation of {0} to complete." -f @($snapshotName))
    # Keep checking the list of snapshots for $snapshotName until we get it.
    #   This is to determine if the clish add snapshot command has completed...
    do
    {
        $retval.Elapsed = [DateTime]::Now - $startTime
        $retval.TimedOut = ($retval.Elapsed -ge $waitTime)
        if(-not $retval.TimedOut)
        {
            $cmdResult = GetCheckPointSnapshots
            $retval.ExceededMaximumFailures = $cmdResult.ExceededMaximumFailures
            if($cmdResult.Successful)
            {
                $retval.HaveSnapshot = (@($cmdResult.Output -match $snapshotName).Length -gt 0)
            }
            else
            {
                # Nothing, already logged an error
            }

            if( (-not $retval.HaveSnapshot) -and (-not $retval.ExceededMaximumFailures) )
            {
                Start-Sleep -Seconds 1
            }
        }
        else
        {
            [Log]::Error("Timeout waiting for snapshot {0} to be created.  Elapsed time: {1}" -f @($snapshotName, $retval.Elapsed.ToString()))
        }
    }
    while( (-not $retval.TimedOut) -and (-not $retval.HaveSnapshot) -and (-not $retval.ExceededMaximumFailures))

    if($retval.HaveSnapshot)
    {
        [Log]::Info("Creation of snapshot {0} complete in {1}." -f @($snapshotName, $retval.Elapsed.ToString()))
    }

    return $retval
}

<#
    ExportCheckPointSnapshot

    Export an existing snapshot from a CheckPoint management server.

         1. Verify parameters
             1a. Snapshot name is provided

         2. Verify a snapshot exists on the CheckPoint device with the given name

         3. Get the working directory for the user account

         4. Verify there is not an exported snapshot of the same name in the user's working directory

         5. Call clish to start exporting the snapshot into the user's working directory
 #>
function ExportCheckPointSnapshot
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $workingDirectory,

        [Parameter(Mandatory=$false,Position=2)]
        [TimeSpan]
        $waitTime=[TimeSpan]::new(0,10,0)
    )

    $snapShotExported = $false

    # Make sure a snapshot name was provided
    if(-not [String]::IsNullOrEmpty($snapshotName))
    {
        # Make sure a working directory was provided.
        if(-not [String]::IsNullOrEmpty($workingDirectory))
        {
            $result = WaitForCheckPointToCreateSnapshot $snapshotName

            if($result.HaveSnapshot)
            {
                [Log]::Info("Checking for existence of snapshot named {0} in {1}." -f @($snapshotName, $workingDirectory))
                # Check to see if there is already a file with the same name...
                $cmdResult = ExecuteSSH ("ls -1 {0}" -f @($workingDirectory))

                # Make sure the ssh call completed successfully...
                if($cmdResult.Successful)
                {
                    if(@($cmdResult.Output -match $snapShotName).Length -eq 0)
                    {
                        [Log]::Info("No snapshot named {0} in {1}." -f @($snapshotName, $workingDirectory))
                        [Log]::Info("Exporting {0} to {1}" -f @($snapshotName, $workingDirectory))
                        # NOTE: path argument sent to set snapshot export must end with "/"
                        $cmdResult = ExecuteCliSH ("set snapshot export {0} path {1}/ name {0}" -f @($snapShotName, $workingDirectory, $snapShotName))

                        if($cmdResult.Successful)
                        {
                            $snapShotExported = @($cmdResult.Output -match "Exporting snapshot").Length -gt 0
                            if($snapShotExported)
                            {
                                [Log]::Info("Snapshot {0} exporting to {1}." -f @($snapshotName, $workingDirectory))
                            }
                            else
                            {
                                [Log]::Error("Failed to export snapshot {0}." -f @($snapshotName))
                            }
                        }
                        else
                        {
                            [Log]::Error("Failed to start snapshot export for {0} in {1}." -f @($snapshotName, $MyInvocation.MyCommand))
                        }
                    }
                    else
                    {
                        [Log]::Error("There is already a file name {0} in {1}." -f @($snapshotName, $workingDirectory))
                    }
                }
                else
                {
                    [Log]::Error("Failed to get directory listing for {0} in {1}." -f @($workingDirectory, $MyInvocation.MyCommand))
                }
            }
            else
            {
                # Nothing, already logged a message
            }
        }
        else
        {
            [Log]::Error("Missing working directory in {0}" -f @($MyInvocation.MyCommand))
        }
    }
    else
    {
        [Log]::Error("Missing snapshot name in {0}." -f @($MyInvocation.MyCommand))
    }

    return $snapShotExported
}

function WaitForCheckPointToExportSnapshot
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $workingDirectory,

        [Parameter(Mandatory=$false,Position=2)]
        [TimeSpan]
        $waitTime=[TimeSpan]::new(0,10,0)
    )

    $retval = "" | Select-Object TimedOut, ExceededMaximumFailures, HaveExportedFile, Elapsed
    $retval.TimedOut = $false

    # Track the if I have exceeded the maximum allowed failures.
    $retval.ExceededMaximumFailures = $false

    # Track if we have seen the snapshot name in the file list
    $retval.HaveExportedFile = $false

    # Track when we started waiting for the snapshot to be discovered.
    $startTime = [DateTime]::Now

    [Log]::Info("Waiting for CheckPoint to complete export of {0}." -f @($snapshotName))

    # Keep trying to get a file listing of the snapshot until we get it.
    #   This is to determine if the clish set snapshot export command has completed...
    do
    {
        $retval.Elapsed = [DateTime]::Now - $startTime
        $retval.TimedOut = ($retval.Elapsed -ge $waitTime)
        if(-not $retval.TimedOut)
        {
            # Try to get a file listing of the snapshot...
            $cmdResult = ExecuteSSH ("ls -lA {0}" -f @($workingDirectory))

            if($cmdResult.Successful)
            {
                # Is the snapshot in the list?
                $retval.HaveExportedFile = (@($cmdResult.Output -match $snapshotName).Length -gt 0)
            }
            else
            {
                # Nothing, already logged an error
            }

            $retval.ExceededMaximumFailures = $cmdResult.ExceededMaximumFailures
            if((-not $retval.HaveExportedFile) -and (-not $retval.ExceededMaximumFailures))
            {
                Start-Sleep -Seconds 1
            }
        }
        else
        {
            [Log]::Error("Timeout waiting for exported snapshot {0} to appear in {1}.  Elapsed: {2}" -f @($snapshotName, $workingDirectory, $retval.Elapsed.ToString()))
        }
    }
    while( (-not $retval.TimedOut) -and (-not $retval.HaveExportedFile) -and (-not $retval.ExceededMaximumFailures) )

    if($retval.HaveExportedFile)
    {
        [Log]::Info("Export of snapshot {0} complete in {1}." -f @($snapshotName, $retval.Elapsed.ToString()))
    }

    return $retval
}

function WaitForConstantSnapshotImageSize
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $workingDirectory,

        [Parameter(Mandatory=$false,Position=2)]
        [TimeSpan]
        $waitTime=[TimeSpan]::new(0,10,0)
    )

    $retval = "" | Select-Object TimedOut, ExceededMaximumFailures, HaveFixedFileSize, ImageSize, Elapsed
    $retval.TimedOut = $false

    # Track the if I have exceeded the maximum allowed failures.
    $retval.ExceededMaximumFailures = $false

    # Track if we have a fixed size for the exported snapshot image
    $retval.HaveFixedFileSize = $false

    # Track the snapshot image size
    [Int64] $retval.ImageSize = 0

    # Track the last image size so we can compare it to the current image size
    [Int64] $lastImageSize = [Int64]::MinValue

    # Track when I started waiting for the image size to stabilize
    $startTime = [DateTime]::Now

    # Track the number of times the file size did not change
    $sameFileSizeCounter = 0

    [Log]::Info("Waiting for exported snapshot {0} to be fully copied to {1}." -f @($snapshotName, $workingDirectory))

    # Keep getting a file listing of $workingDirectory until the file size stops changing, maximum failures are exceeded, or time out
    do
    {
        $retval.Elapsed = [DateTime]::Now - $startTime
        $retval.TimedOut = ($retval.Elapsed -ge $waitTime)
        if(-not $retval.TimedOut)
        {
            $cmdResult = ExecuteSSH ("ls -lA {0}" -f @($workingDirectory))
            $retval.ExceededMaximumFailures = $cmdResult.ExceededMaximumFailures

            if($cmdResult.Successful)
            {
                $output = @($cmdResult.Output -match ("^[^\s]+\s+\d+\s+[^\s]+\s+[^\s]+\s+(\d+).*?{0}\.tar$" -f ($snapShotName)))
                if($output.Length -eq 1)
                {
                    if($output[0] -match ("^[^\s]+\s+\d+\s+[^\s]+\s+[^\s]+\s+(\d+).*?{0}\.tar$" -f ($snapShotName)))
                    {
                        $retval.ImageSize = [Convert]::ToInt64($Matches[1])

                        if($retval.ImageSize -ne $lastImageSize)
                        {
                            $sameFileSizeCounter = 0
                        }
                        else
                        {
                            $sameFileSizeCounter++
                        }
                        $lastImageSize = $retval.ImageSize
                        $retval.HaveFixedFileSize = ($sameFileSizeCounter -ge 5)
                    }
                    else
                    {
                        # WTH?  -match worked once, now it fails??

                        throw ("Match failed after success in {0}" -f @($MyInvocation.MyCommand))
                    }
                }
                else
                {
                    throw ("Failed to parse file listing for file size in {0}." -f @($MyInvocation.MyCommand))
                }
            }
            else
            {
                # Nothing, would have already logged a message
            }

            if((-not $retval.ExceededMaximumFailures) -and (-not $retval.TimedOut) -and (-not $retval.HaveFixedFileSize))
            {
                Start-Sleep -Seconds 1
            }
            $retval.TimedOut = (([DateTime]::Now - $startTime) -ge $waitTime)
        }
        else
        {
            [Log]::Error("Timeout waiting for snapshot image to be moved to {0}." -f @($workingDirectory))
        }
    }
    while((-not $retval.ExceededMaximumFailures) -and (-not $retval.TimedOut) -and (-not $retval.HaveFixedFileSize))

    if($retval.HaveFixedFileSize)
    {
        [Log]::Info("Copy of snapshot {0} to {1} complete in {2}." -f @($snapshotName, $workingDirectory, $retval.Elapsed.ToString()))
    }

    return $retval
}

function CopyCheckPointSnapshotToFolder
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $workingDirectory,

        [Parameter(Mandatory=$true,Position=2)]
        [String]
        $destinationFolder,

        [Parameter(Mandatory=$true,Position=3)]
        [Int64]
        $imageSize,

        [Parameter(Mandatory=$false,Position=4)]
        [Switch]
        $leaveSourceFile
    )

    # Assume the snapshot failed to copy
    $snapshotCopied = $true

    $filePath = "{0}/{1}.tar" -f @($workingDirectory, $snapshotName)

    [Log]::Info("Copying {0} to {1}" -f @($filePath, $destinationFolder))

    $startTime = [DateTime]::Now

    # Copy the snapshot from the CheckPoint device to a folder
    $cmdResult = ExecuteSCP $filePath $destinationFolder

    $endTime = [DateTime]::Now

    if($cmdResult.ExitCode -eq 0)
    {
        $destinationFileName = "{0}\{1}.tar" -f @($destinationFolder, $snapshotName)
        if(Test-Path -LiteralPath $destinationFileName)
        {
            $destinationFile = Get-Item -LiteralPath $destinationFileName
            if($destinationFile.Length -eq $imageSize)
            {
                $elapsed = $endTime - $startTime
                [Log]::Info("Copy completed in {0}." -f @($elapsed.ToString()))
                $snapshotCopied = $true
            }
            else
            {
                [Log]::Error("Destination file size [{0}] does not match source file size [{1}]" -f @($destinationFile.Length, $fileSize))
                [Log]::Error("Not removing source file [{0}]" -f @($filePath))
            }
        }
        else
        {
            [Log]::Error("Destination file {0} not found." -f @($destinationFileName))
        }
    }
    else
    {
        [Log]::Error("Failed to download snapshot {0}.  Manually check for files on source and destination." -f @($snapshotName))
    }

    return $snapshotCopied
}

function RemoveCheckPointSnapshotImage
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $workingDirectory
    )

    # Assume the image was not removed
    $snapshotImageRemoved = $false

    $filePath = "{0}/{1}.tar" -f @($workingDirectory, $snapshotName)

    [Log]::Info("Removing {0}." -f @($filePath))

    $cmdResult = ExecuteSSH ("rm {0}" -f $filePath)

    if($cmdResult.ExitCode -eq 0)
    {
        $cmdResult = ExecuteSSH ("ls -lA {0}" -f @($workingDirectory))

        if($cmdResult.ExitCode -eq 0)
        {
            if(@($cmdResult.Output -match $snapshotName).Length -eq 0)
            {
                [Log]::Info("{0} successfully removed." -f @($filePath))
                $snapshotImageRemoved = $true
                # Nothing, all's well that ends well
            }
            else
            {
                [Log]::Warning("Failed to remove snapshot image {0} in {1}.  Remove manually." -f @($snapshotName, $workingDirectory))
            }
        }
        else
        {
            [Log]::Warning("Failed to verify if snapshot image {0} was removed from {1}." -f @($snapshotName, $workingDirectory))
        }
    }
    else
    {
        [Log]::Error("Failed to remove source file {0}." -f @($filePath))
    }

    return $snapshotImageRemoved
}

<#
    DownloadCheckPointSnapshot

         1. Verify parameters
             1a. Snapshot name is provided
             1b. Destination folder is provided

         2. Verify the destination folder exists

         3. Verify a file with the snapshot name does not exist in the destination folder

         4. Get the working directory for the user account

         5. Monitor the user's working directory until the snapshot file exists.
             5a. Parse "ls -lA $workingDirectory" output looking for snapshot file
             5b. Sleep the script for a bit to give the export process time to run
             5c. Return to 5a

         6. Fail with an error if the snapshot file does not show up within a predetermined amount of time

         7. If the snapshot file was found in the ls -lA listing, then continue monitoring the file until
            its filesize remains constant for 5 seconds or until a predetermined amount of time elapses
             7a. Parse "ls -lA $workingDirectory" output looking for snapshot file
             7b. If the file if found, parse out the file size and compare it to the previous file size
             7c. If the file size is unchange for 5 consecutive seconds continue to 12.
             7b. Continue sleeping the script until the file size remains constant
             7c. Return to 7a

         8. If the monitor times out, fail with an error

         9. SCP the snapshot image file to the destination file

        10. Verify file size between source and destination
            10a. Fail with an error message if sizes do not match
            10b. Remove snapshot image from user's working directory, unless requested to leave it
#>
function DownloadCheckPointSnapshot
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $snapshotName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $destinationFolder,

        [Parameter(Mandatory=$true,Position=2)]
        [String]
        $workingDirectory,

        [Parameter(Mandatory=$false,Position=3)]
        [TimeSpan]
        $waitTime=[TimeSpan]::new(0,10,0),

        [Parameter(Mandatory=$false,Position=4)]
        [Switch]
        $leaveSourceFile
    )

    $snapShotDownloaded = $false

    if(-not [String]::IsNullOrEmpty($snapshotName))
    {
        if(-not [String]::IsNullOrEmpty($destinationFolder))
        {
            if(Test-Path -LiteralPath $destinationFolder)
            {
                $destinationFileName = "{0}\{1}.tar" -f @($destinationFolder, $snapshotName)
                if(-not (Test-Path -LiteralPath $destinationFileName))
                {
                    $result = WaitForCheckPointToExportSnapshot $snapshotName $workingDirectory
                    if($result.HaveExportedFile)
                    {
                        $result = WaitForConstantSnapshotImageSize $snapshotName $workingDirectory

                        if($result.HaveFixedFileSize)
                        {
                            if($result.ImageSize -gt 0)
                            {
                                $snapshotCopied = CopyCheckPointSnapshotToFolder $snapshotName $workingDirectory $destinationFolder $result.ImageSize
                                $snapShotDownloaded = $snapshotCopied
                                if($snapshotCopied)
                                {
                                    if(-not $leaveSourceFile.IsPresent)
                                    {
                                        $snapshotImageRemoved = RemoveCheckPointSnapshotImage $snapshotName $workingDirectory

                                        if(-not $snapshotImageRemoved)
                                        {
                                            [Log]::Error("Failed to remove snapshot image for {0} in {1}.  Check manually." -f @($snapshotName, $workingDirectory))
                                        }
                                    }
                                    else
                                    {
                                        [Log]::Info("Snapshot {0} left in {1}." -f @($workingDirectory, $filePath))
                                    }
                                }
                                else
                                {
                                    [Log]::Error("Failed to copy snapshot image for {0} to {1}." -f @($snapshotName, $destinationFolder))
                                }
                            }
                            else
                            {
                                [Log]::Error("Exported snapshot ({0}) is a 0 byte file." -f @($snapshotName))
                            }
                        }
                        elseif($result.ExceededMaximumFailures)
                        {
                            [Log]::Error("Maximum failures reached waiting for snapshot image size to stabilize for {0} to appear in folder {1}." -f @($snapshotName, $workingDirectory))
                        }
                        elseif($result.TimedOut)
                        {
                            [Log]::Error("Timeout waiting for snapshot image size to stabilize for {0} in folder {1}." -f @($snapshotName, $workingDirectory))
                        }
                    }
                    elseif($result.ExceededMaximumFailures)
                    {
                        [Log]::Error("Maximum failures reached waiting for snapshot image for {0} to appear in folder {1}." -f @($snapshotName, $workingDirectory))
                    }
                    elseif($result.TimedOut)
                    {
                        [Log]::Error("Timeout waiting for snapshot image for {0} to appear in folder {1}." -f @($snapshotName, $workingDirectory))
                    }
                }
                else
                {
                    [Log]::Error("Existing file {0}" -f @($destinationFileName))
                }
            }
            else
            {
                [Log]::Error("{0} does not exist in {1}." -f @($destinationFolder, $MyInvocation.MyCommand))
            }
        }
        else
        {
            [Log]::Error("Missing destination folder in {0}." -f @($MyInvocation.MyCommand))
        }
    }
    else
    {
        [Log]::Error("Missing snapshot name in {0}." -f @($MyInvocation.MyCommand))
    }

    return $snapShotDownloaded
}

<#
    CleanCheckPointSnapshots

    Remove all but the newest snapshots, excluding:
        1. AutoSnapshots
        2. If -scriptedSnapshotsOnly
            2a. snapshots that match $Global:deviceName_yyyyMMddHHmmss
#>
function CleanCheckPointSnapshots
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [Switch]
        $scriptedSnapshotsOnly
    )

    # Unless an error occurs, assume snapshots were successfully cleaned
    $snapShotsCleaned = $true

    # Get a list of all snapshots
    $cmdResults = GetCheckPointSnapshots

    if($cmdResults.ExitCode -eq 0)
    {
        $snapshots = $cmdResults.Output

        # Remove any AutoSnaps from the list
        $manualSnapshots = @($snapshots | Where-Object { $_.Name -notmatch "^AutoSnap" })

        # Array of snapshots to be removed
        $snapshotsToRemove = @()

        # If deleting only scripted snapshots, filter everything else out.
        if($scriptedSnapshotsOnly.IsPresent)
        {
            $deviceRegex = "{0}_\d{{14}}" -f @($Global:deviceName)
            $snapshotsToRemove = @($manualSnapshots | Where-Object { $_.Name -match $deviceRegex } | Sort-Object -Descending WhenCreated | Select-Object -Skip 1)
        }
        else
        {
            $snapshotsToRemove = @($manualSnapshots | Sort-Object -Descending WhenCreated | Select-Object -Skip 1)
        }

        foreach($snapshotToRemove in $snapshotsToRemove)
        {
            $cmdResult = ExecuteCliSH ("delete snapshot {0}" -f $snapshotToRemove.Name)
            if($cmdResult.ExitCode -eq 0)
            {
                [Log]::Info("Successfully deleted snapshot {0}." -f $($snapshotToRemove.Name))
            }
            else
            {
                [Log]::Error("Failed to remove snapshot {0} from {1}." -f @($snapshotToRemove.Name, $Global:deviceName))
                $snapShotsCleaned = $false
            }
        }
    }
    else
    {
        # Nothing, already logged a message.
    }

    return $snapShotsCleaned
}

function PurgeBackedUpCheckPointSnapshots
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $deviceName,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $destinationFolder,

        [Parameter(Mandatory=$true,Position=2)]
        [Int32]
        $savedSnapshotsBackups
    )

    # Unless an error occurs, assume snapshots were successfully cleaned
    $snapshotBackupsPurged = $true

    if (-not [String]::IsNullOrEmpty($deviceName))
    {
        if(-not [String]::IsNullOrEmpty($destinationFolder))
        {
            if (Test-Path -LiteralPath $destinationFolder)
            {
                $snapshotsToPurge = @(Get-ChildItem -Path $destinationFolder -Filter ("{0}*.tar" -f @($deviceName)) | Sort-Object -Descending LastWriteTime | Select-Object -Skip $savedSnapshotsBackups)

                $a = 0
                while($a -lt $snapshotsToPurge.Length)
                {
                    Remove-Item -Path $snapshotsToPurge[$a].FullName -Force -Confirm -ErrorAction SilentlyContinue | Out-Null
                    if(Test-Path -Path $snapshotsToPurge[$a].FullName)
                    {
                        [Log]::Warning("Failed to remove old snapshot backup {0}." -f $($snapshotsToPurge[$a].FullName))
                        $snapshotBackupsPurged = $false
                    }

                }
            }
            else   # NOT (Test-Path -LiteralPath $destinationFolder)
            {
                [Log]::Warning("Destination folder {0} does not exist in {1}." -f ($destinationFolder, $MyInvocation.MyCommand))
            }
        }
        else
        {
            [Log]::Warning("Missing destination folder name in {0}." -f @($MyInvocation.MyCommand))
        }
    }
    else   # NOT (-not [String]::IsNullOrEmpty($deviceName))
    {
        [Log]::Warning("Missing device name in {0}." -f @($MyInvocation.MyCommand))
    }

    return $snapshotBackupsPurged
}

function BackupUserDefFW1
{
    # Check to see if there is a file named: $Global:userDefFW1Path
    $userDefFW1PathParts = $Global:userDefFW1Path -split '/'
    if($userDefFW1PathParts.Length -gt 1)
    {
        # Split the path so we can get a directory listing of the parent folder of the file.
        #    This was done because I ran into issue executing "ssh -l filedoesnotexist"
        #    So instead, I do a listing for the parent folder, then search the output looking
        #       for the file.

        # folderPath is all but the ending filename
        $folderPath = [String]::Join("/",$userDefFW1PathParts,0,$userDefFW1PathParts.Length-1)

        # Now for the filename...
        $fileName = $userDefFW1PathParts[$userDefFW1PathParts.Length - 1]

        # Grab a file listing of the folder...
        $cmdResult = ExecuteSSH ("ls -l {0}/" -f @($folderPath))

        # Make sure the ssh command completed successfully
        if($cmdResult.Successful)
        {
            # Make sure there is output from the command.
            if($cmdResult.Output.Length -gt 0)
            {
                # Search for the line with the file name in it.
                $linesWithFileName = @($cmdResult.Output | Where-Object { $_.EndsWith($fileName) })

                # Did we find the file we are looking for?
                if($linesWithFileName.Length -eq 1)
                {
                    # Make sure a destination folder name has been provided.
                    if(-not [String]::IsNullOrEmpty($Global:destinationFolder))
                    {
                        # Make sure there is somewhere to place the copied file.
                        if(Test-Path -LiteralPath $Global:destinationFolder)
                        {
                            # Construct a destination file name
                            $destinationFileName = "{0}\{1}-{2}-{3}" -f @($Global:destinationFolder, [DateTime]::Now.ToString("yyyyMMddHHmmss"), $Global:deviceName, $fileName)
                            if(-not (Test-Path -LiteralPath $destinationFileName))
                            {
                                # Attempt to copy the file to the destination
                                $cmdResult = ExecuteSCP $Global:userDefFW1Path $destinationFileName

                                # Did the copy complete successfully?
                                if($cmdResult.Successful)
                                {
                                    # Double check to see if the file exists in the destination.
                                    if(-not (Test-Path -LiteralPath $destinationFileName))
                                    {
                                        [Log]::Warning("Failed to copy {0} to {1}." -f @($Global:userDefFW1Path, $destinationFileName))
                                    }
                                    else
                                    {
                                        [Log]::Info("{0} copied to {1}." -f @($Global:userDefFW1Path, $destinationFileName))
                                    }
                                }
                                else
                                {
                                    [Log]::Warning("Failed to copy {0} to {1}." -f @($Global:userDefFW1Path, $destinationFileName))
                                }
                            }
                            else
                            {
                                [Log]::Error("Existing file {0}" -f @($destinationFileName))
                            }
                        }
                        else
                        {
                            [Log]::Error("{0} does not exist in {1}." -f @($destinationFolder, $MyInvocation.MyCommand))
                        }
                    }
                    else
                    {
                        [Log]::Error("Missing destination folder in {0}." -f @($MyInvocation.MyCommand))
                    }
                }
                elseif($linesWithFileName.Length -gt 1)
                {
                    [Log]::Warning("Multiple files found matching {0}." -f @($Global:userDefFW1Path))
                }
                else
                {
                    [Log]::Warning("No files found matching {0}." -f @($Global:userDefFW1Path))
                }
            }
            else
            {
                [Log]::Warning("No files found matching {0}." -f @($Global:userDefFW1Path))
            }
        }
        else
        {
            [Log]::Warning("Failed to check for the existance of {0}." -f @($Global:userDefFW1Path))
        }
    }
    else
    {
        [Log]::Warning("Check user defined VPN options definition file path. [{0}]" -f @($Global:userDefFW1Path))
    }
}

function Usage()
{
    $usageLines = @(
        "  Backup-CheckPoint -deviceName '<deviceName>' -userName '<userName>' -destinationFolder 'destinationFolder'",
        "    [-maxFailures <maxFailures>] [-waitTimeInSeconds <seconds>] [-leaveSourceFile] [-cleanScriptedSnapshotsOnly]",
        "`t",
        "    deviceName:",
        "      Name of CheckPoint device to be backed up.",
        "    userName:",
        "      User name to use to connect to <deviceName>.  Must have an identity file to use with SSH/SCP",
        "    destinationFolder:",
        "      Path to folder where the snapshot will be copied to.  ex: \\server\share\folder",
        "    maxFailures: Optional",
        "      Number of times an SSH command can fail before giving up.  Used while waiting for CheckPoint",
        "      to export the snapshot.",
        "      Default: 5",
        "    waitTimeInSeconds: Optional",
        "      Number of seconds to wait for: 1) export to complete and 2) exported image to be copied to working directory.",
        "      Default: 600 seconds (10 minutes)",
        "    leaveSourceFile: [Switch] Optional",
        "      Leave the exported image in the working directory after it was been copied.",
        "      Default: remove snapshot image after copying it to destinationFolder.",
        "    cleanScriptedSnapshotsOnly: [Switch] Optional",
        "      When cleaning up old snapshots, does the script consider all snapshots, or only ones",
        "      that 'appear' to have been created by this script.",
        "      Default: remove all but newest snapshot",
        "`t",
        "Example:",
        "  Backup-CheckPoint -deviceName 'boimgmt' -userName 'Manager' -destinationFolder 'D:\SFTP-Backups\Checkpoint'",
        "    This will create a snapshot on boimgmt, export it to Manager's working directory and copy it to D:\SFTP-Backups\Checkpoint."
        "      maxFailures=5, waitTimeInSeconds=600, exported image will be removed from Manager's working directory, all but the most recent snapshot will be removed",
        "`t",
        "  Backup-CheckPoint -deviceName 'boimgmt' -userName 'Manager' -destinationFolder 'D:\SFTP-Backups\Checkpoint' -waitTimeInSeconds 900 -leaveSourceFile",
        "    This will create a snapshot on boimgmt, export it to Manager's working directory and copy it to D:\SFTP-Backups\Checkpoint."
        "      maxFailures=5, waitTimeInSeconds=900, exported image will not be removed from Manager's working directory, only snapshots create by this script will be removed"
    )

    [Log]::Info("Usage:")
    foreach($ln in $usageLines)
    {
        [Log]::Info($ln)
    }
}

<#
    1. Verify parameters

    2. Verify SSH and SCP are available

    3. Create a CheckPoint snapshot
        2a. CreateCheckPointSnapshot

    4. Export the snapshot to the user's working directory
        4a. ExportCheckPointSnapshot

    5. Download the snapshot
        5a. DownloadCheckPointSnapshot
            5a1. WaitForCheckPointToExportSnapshot
            5a2. WaitForConstantSnapshotImageSize
            5a3. CopyCheckPointSnapshotToFolder
            5a4. RemoveCheckPointSnapshotImage

    6. Clean up old snapshot
        6a. CleanCheckPointSnapshots
#>

function Main
{
    $Global:secureLogon = "{0}@{1}" -f @($userName,$deviceName)

    # See if SSH and SCP are available
    $haveSSHSCP = (@(Get-Command -Name @("ssh","scp")).Length -eq 2)
    if($haveSSHSCP)
    {
        [Log]::Info("SSH and SCP are available.")
        # Verify I can use SSH...
        $cmdResult = ExecuteSSH "ls -lA"
        $canSSH = ($cmdResult.ExitCode -eq 0)
        if($canSSH)
        {
            [Log]::Info("Successfully executed test 'ls -lA'.")

            <#
                Changed the script to use /var/log/tmp as the working directory vs /home/Manager in-lieu of disk space availability.

                LEGACY-BOIMGMT:
                    [Expert@legacy-boimgmt:0]# df -h /home/Manager
                    Filesystem                          Size  Used Avail Use% Mounted on
                    /dev/mapper/vg_splat-lv_current     50G   27G   21G  58% /

                    [Expert@legacy-boimgmt:0]# df -h /var/log/tmp
                    Filesystem                          Size  Used Avail Use% Mounted on
                    /dev/mapper/vg_splat-lv_log         1.6T  782G  714G  53% /var/log
            #>
#            # Get the user's working directory
#            $cmdResult = GetWorkingDirectory

#            if($cmdResult.ExitCode -eq 0)
#            {
                # $workingDirectory = $cmdResult.Output[0]
                $workingDirectory = "/var/log/tmp"
                [Log]::Info("Working directory: {0}" -f @($workingDirectory))
                # Make sure a working directory was returned.
                if(-not [String]::IsNullOrEmpty($workingDirectory))
                {
                    $newSnapshotName = "{0}_{1}" -f @($deviceName, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
                    $snapShotCreated = CreateCheckPointSnapshot -snapshotName $newSnapshotName

                    if($snapShotCreated)
                    {
                        $snapShotExported = ExportCheckPointSnapshot -snapshotName $newSnapshotName -workingDirectory $workingDirectory

                        if($snapShotExported)
                        {
                            $waitTime = [TimeSpan]::FromSeconds($waitTimeInSeconds)
                            $snapShotDownloaded = DownloadCheckPointSnapshot -snapshotName $newSnapshotName -destinationFolder $destinationFolder -workingDirectory $workingDirectory -waitTime $waitTime -leaveSourceFile:$leaveSourceFile

                            if($snapShotDownloaded)
                            {
                                [Log]::Info("Snapshot {0} successfully exported and downloaded to {1}." -f @($newSnapshotName, $destinationFolder))
                                $snapShotsCleaned = CleanCheckPointSnapshots -scriptedSnapshotsOnly:$cleanScriptedSnapshotsOnly

                                if(-not $snapShotsCleaned)
                                {
                                    [Log]::Error("Failed to clean snapshots.  Manually check snapshots.")
                                }
                                else
                                {
                                    # Nothing, all's well that ends well.
                                }

                                $snapshotBackupsPurged = PurgeBackedUpCheckPointSnapshots -deviceName $Global:deviceName -destinationFolder $Global:destinationFolder -savedSnapshotsBackups $Global:savedSnapshotsBackups

                                if(-not $snapshotBackupsPurged)
                                {
                                    [Log]::Error("Failed to purge old snapshot backups.")
                                }
                                else
                                {
                                    # Nothing, all's well that ends well.
                                }

                                if($backupUserDefFW1)
                                {
                                    [Log]::Info("Backing up {0}." -f @($Global:userDefFW1Path))
                                    BackupUserDefFW1
                                }
                                else
                                {
                                    [Log]::Info("Not backing up {0}." -f @($Global:userDefFW1Path))
                                }
                            }
                            else
                            {
                                [Log]::Error("Failed to download snapshot {0}.  Manually check for snapshots." -f @($newSnapshotName))
                            }
                        }
                        else
                        {
                            [Log]::Error("Failed to export new snapshot {0}." -f @($newSnapshotName))
                        }
                    }
                    else
                    {
                        [Log]::Error("Failed to create snapshot {0}" -f @($newSnapshotName))
                    }
                }
                else
                {
                    [Log]::Error("Unable to get working directory for {0}." -f @($Global:secureLogon))
                }
#            }
#            else
#            {
#                # Nothing, already logged a message
#            }
        }
        else
        {
            [Log]::Error("Unable to connect to {0} using account {1}" -f @($deviceName, $userName))
        }
    }
    else
    {
        [Log]::Error("This script requires both SSH and SCP be install and executable from the command line.")
    }
}


# Function called from ScriptApp.ps1
function ScriptAppMain()
{
    Main
}
