<#
.SYNOPSIS

Removes files and folders in a given path based on creation and access date/time.

.DESCRIPTION

Cleans old files and folders based on settings provided from a JSON formatted configuration file.

{
    "FolderExclusions": [
        "{{PATHROOT}}\\Scanfiles"
    ],
    "FileExclusions": [
    ],
    "MaxAge": 7,
    "PathToLogs": "E:\\Scripts\\TempTest\\Logs",
    "SMTPServer": "smtp.powereng.com",
    "SenderAddress": "Path Cleaner <pathcleaner@powereng.com>",
    "AlertRecipients": [
        "Ken Briney <ken.briney@powereng.com>"
    ],
    "AlertSubject": "Files and Folders cleaner error report.",
    "PathsToClean": [
        "\\\\slcfs1\\xchange",
        "\\\\astfs1\\xchange",
        "\\\\adcfs1\\xchange",
        "\\\\boifs1\\xchange"
    ]
}

“FolderExclusions” (1,3) : ARRAY (notice the [ ] characters…MUST be there even if there are no exclusions) of strings that are used to exclude folders
                           from being removed.  If any part of a folder name contains any of the strings in the array, it is excluded from being removed.
“FileExclusions” (1,3)   : Same as FolderExclusions, except for use with files.
“PathToLogs” (3)         : Self explanatory.  Though I should point out, a new log file is created for each run of the script and the logs are not managed,
                           so clean this folder once in a while.
“MaxAge”                 : Minimum number of days ago a file has to have been created or accessed before it is deleted.
“SMTPServer”             : Self explanatory
“SenderAddress” (2)      : Self explanatory
“AlertRecipients” (2)    : An ARRAY of recipient address.  Yes, array, the [ ] must be there.
“AlertSubject”           : Self explanatory
“PathsToClean” (3)       : An array of paths to clean.  Again, it’s an array, so they (even if it’s only 1) must be contained in [ ] characters.

NOTES:
    1. Both FolderExclusions and FileExclusions support a single substitution {{PATHROOT}}.  When a path is processed, the exclusions used will have
       {{PATHROOT}} replaced by whatever path is listed in PathsToClean.
       Example, from the .JSON data above, when \\adcfs1\xchange is processed, it’s FolderExclusions will be @(“\\adcfs1\xchange\Scanfiles”).
       If you want files cleaned from an excluded folder, then do not include the folder name in the FileExclusions array.   If you want files and
       folders excluded from the same folder, make sure to include the string in both FolderExclusions and FileExclusions.
       The comparisons are case-insensitive.
    2. Email addresses, can be in either form:
        a. “DisplayName <emailAddr@somedomain.com>"
        b. “emailAddr@somedomain.com”
    3. “\” characters have to be escaped in JSON files, so double them up like you see above.


.PARAMETER configFile
Specifies the path to the script configuration json file.

.INPUTS

None -- does not utilize the pipeline

.OUTPUTS
Logs any action taken or error conditions to the path specified in pathToLogs

.EXAMPLE

PS> Clean-Path -configFile E:\Scripts\TempTest\Clean-Path.json

.EXAMPLE

PS> Clean-Path -configFile E:\Scripts\TempTest\Clean-Path-DoesNotExist.json
Configuration file: E:\Scripts\TempTest\Clean-Path-DoesNotExist.json does not exist, or access is denied.

.NOTES

Author: Briney, Ken
Date: 30 Oct 2020
Version: 1.0
#>

[CmdLetBinding(SupportsShouldProcess)]
Param(
    # Path to clean
    [Parameter(
        Mandatory=$true,
        Position=0,
        HelpMessage="Enter path to configuration file.")]
    [ValidateNotNullOrEmpty()] [String] $configFile
)

<#
    Writes a formatted message to $Global:logFile, and adds message with msgLevel of ERROR to an alert stringbuilder object so the messages
    can eventually be emailed to concerned citizens.
#>
function Log
{
    [CmdLetBinding()]
    Param(
        # Message to log
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [String] $logMessage,

        [Parameter(
            Mandatory=$false,
            Position=1)]
        [String] $msgLevel = [String]::Empty
    )

    $Error.Clear()

    # Create a formatted string to log .. and replace any \\?\UNC\ with \\
    if(-not [String]::IsNullOrEmpty($msgLevel))
    {
        $fmtMessage = "{0}: {1}: {2}" -f @([DateTime]::Now.ToString("yyyyMMdd HHmmss.fff"), $msgLevel, $logMessage.Replace("\\?\UNC\","\\"))
    }
    else
    {
        $fmtMessage = "{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HHmmss.fff"), $logMessage.Replace("\\?\UNC\","\\"))
    }

    $retries = 0
    do
    {
        $fmtMessage | Out-File -FilePath $Global:logFile -Append -Encoding ascii -WhatIf:$false -ErrorAction SilentlyContinue

        # If an error occurred while trying to append to the log, pause for 50ms, and retry until the retry attempts are exceeded.
        if(-not $?)
        {
            Start-Sleep -Milliseconds 50
        }
        else
        {
            # Nothing, the message was successfully appended to the log.
        }
    } while((-not $?) -and ($retries -lt 10))

    # Is this an error?  If so, save the message so it can be emailed to concerned citizens.
    if($msglevel -eq "ERROR")
    {
        # Has the global alert data stringbuilder been created?
        if($null -eq $Global:sbAlertData)
        {
            # Nope, create it.
            $Global:sbAlertData = [System.Text.StringBuilder]::new()
        }
        else
        {
            # Nothing, the alert data stringbuilder has already been created.
        }

        # Append the error message to the alert stringbuilder
        [void] $Global:sbAlertData.AppendLine($fmtMessage)
    }
}

<#
    Verifies exclusions substitutions are supported.
    Returns a new array of unique exclusions.
#>
function CheckExclusionSubstitutions
{
    [CmdLetBinding()]
    Param(
        # Message to log
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [AllowEmptyCollection()] [Object[]] $exclusions,

        [Parameter(
            Mandatory=$true,
            Position=1)]
        [System.Text.StringBuilder] $sbErr
    )

    $validExclusions = $true

    # Build a array of unique, parsed exclusions.
    $newExclusions = @()

    # Check each exclusion for substitutions I don't understand.
    #   Supported substitutions:
    #      {{PATHROOT}}: Replaced with path to clean
    for($l = 0; $l -lt $exclusions.Length; $l++)
    {
        $exclusionIsOK = $true

        # Ignore empty exclusions
        if(-not [String]::IsNullOrEmpty($exclusions[$l]))
        {
            # Find all substitutions in the exclusion {{SUBSTITUTION}}
            if($exclusions[$l] -match "\{\{([^\}]+)\}\}")
            {
                $uniqueSubstitutions = @($Matches.Values | Select-Object -Unique -Skip 1)
                for($m = 0; $m -lt $uniqueSubstitutions.Length; $m++)
                {
                    if($uniqueSubstitutions[$m] -ne "{{PATHROOT}}")
                    {
                        [void] $sbErr.AppendLine(("Unsupported substitution constant: {0}" -f @($uniqueSubstitutions[$m])))
                        $exclusionIsOK = $false
                        $validExclusions = $false
                    }
                }
            }

            if($exclusionIsOK)
            {
                # If the list of parsed exclusions does not already contain $exclusions[$l], add it..
                if(@($newExclusions | Where-Object { $_ -eq $exclusions[$l].ToUpper() }).Length -eq 0)
                {
                    $newExclusions += $exclusions[$l].ToUpper()
                }
            }
        }
    }

    # If any of the exclusions is not valid, set $newExclusions to null to signal an error
    if(-not $validExclusions)
    {
        $newExclusions = $null
    }

    return @( ,$newExclusions)
}

<#
    Reads the configuration file, validates the values, and transforms some of them into a more useful type.

    For instance, AlertRecipients is transformed from an array of strings to an array of [MailAddress].
#>
function ParseConfigFile
{
    [CmdLetBinding()]
    Param(
        # Message to log
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [String] $configFile
    )

    # StringBuilder object to capture error messages
    $sbErr = [System.Text.StringBuilder]::new()

    # Initialize $configData to null so the sender can check for a $null value to verify the configuration data was successfully read and parsed.
    $configData = $null

    # Read the configuration data file
    $configDataContent = Get-Content -Path $configFile -Raw -ErrorAction SilentlyContinue

    if($null -ne $configDataContent)
    {
        # Convert the contents into an object
        $configData = $configDataContent | ConvertFrom-Json -ErrorAction SilentlyContinue

        if($null -ne $configData)
        {
            # Check for all the required configuration data

            # FolderExclusions...
            if($null -ne $configData.FolderExclusions)
            {
                $configData.FolderExclusions = CheckExclusionSubstitutions $configData.FolderExclusions $sbErr
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing FolderExclusions array.")
            }

            # FileExclusions...
            if($null -ne $configData.FileExclusions)
            {
                $configData.FileExclusions = CheckExclusionSubstitutions $configData.FileExclusions $sbErr
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing FileExclusions array.")
            }

            # MaxAge
            if($null -ne $configData.MaxAge)
            {
                if($configData.MaxAge -isnot [Int32])
                {
                    [Int32] $newMaxAge = 0
                    if(-not [Int32]::TryParse($configData.MaxAge, [ref] $newMaxAge))
                    {
                        [void] $sbErr.AppendLine(("Configuration data MaxAge value {0} is invalid." -f @($configData.MaxAge)))
                    }
                    else
                    {
                        $configData.MaxAge = $newMaxAge
                    }
                }

                if($configData.MaxAge -le 0)
                {
                    [void] $sbErr.AppendLine(("Configuration data MaxAge value {0} is invalid." -f @($configData.MaxAge)))
                }
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing MaxAge value.")
            }

            # PathToLogs
            if(-not [String]::IsNullOrEmpty($configData.PathToLogs))
            {
                if(-not [System.IO.Directory]::Exists($configData.PathToLogs))
                {
                    [void] $sbErr.AppendLine(("Logging path: {0} does not exist or access is denied." -f @($configData.PathToLogs)))
                }
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing PathToLogs value.")
            }

            # SMTPServer
            if(-not [String]::IsNullOrEmpty($configData.SMTPServer))
            {
                if(-not (Test-NetConnection -ComputerName ($configData.SMTPServer) -Port 25 -InformationLevel "Quiet"))
                {
                    [void] $sbErr.AppendLine(("Unable to connect to SMTP server: {0}" -f @($configData.SMTPServer)))
                }
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing SMTPServer value.")
            }

            # SenderAddress
            if(-not [String]::IsNullOrEmpty($configData.SenderAddress))
            {
                try
                {
                    # Try to convert the sender address into a [mailaddress]
                    $configData.SenderAddress = [mailaddress]::new($configData.SenderAddress)
                }
                catch
                {
                    [void] $sbErr.AppendLine(("Sender address {0} is invalid." -f @($configData.SenderAddress)))
                }
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing SenderAddress value.")
            }

            # AlertRecipients
            if($null -ne $configData.AlertRecipients)
            {
                $alertRecipients = @()
                for($a = 0; $a -lt $configData.AlertRecipients.Length; $a++)
                {
                    try
                    {
                        # Try to convert the sender address into a [mailaddress]
                        $ma = [mailaddress]::new($configData.AlertRecipients[$a])

                        $existingRecipients = @($alertRecipients | Where-Object { ($_.Address -eq $ma.Address) })
                        if($existingRecipients.Length -eq 0)
                        {
                            $alertRecipients += $ma
                        }
                    }
                    catch
                    {
                        [void] $sbErr.AppendLine(("Alert recipient address {0} is invalid." -f @($configData.AlertRecipients[$a])))
                    }
                }
                $configData.AlertRecipients = $alertRecipients
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data missing SenderAddress value.")
            }

            # AlertSubject
            if([String]::IsNullOrEmpty($configData.AlertSubject))
            {
                [void] $sbErr.AppendLine("Configuration data missing AlertSubject value.")
            }

            # PathsToClean
            #   Note: Not checking for the existance of the paths here, the main script can handle that so it can
            #         continue processing good ones and log bad ones along the way.
            if($null -ne $configData.PathsToClean)
            {
                if($configData.PathsToClean -is [Array])
                {
                    $uniquePathsToClean = @()
                    for($a = 0; $a -lt $configData.PathsToClean.Length; $a++)
                    {
                        if(-not [String]::IsNullOrEmpty($configData.PathsToClean[$a]))
                        {
                            $existingPaths = @($uniquePathsToClean | Where-Object { $_ -eq $configData.PathsToClean[$a] })
                            if($existingPaths.Length -eq 0)
                            {
                                $uniquePathsToClean += $configData.PathsToClean[$a]
                            }
                        }
                        else
                        {
                            # Nothing, ignore blank/empty paths...
                        }
                    }

                    $configData.PathsToClean = $uniquePathsToClean
                }
                else
                {
                    [void] $sbErr.AppendLine("Configuration data file PathsToClean is not an array.")
                }
            }
            else
            {
                [void] $sbErr.AppendLine("Configuration data file missing PathsToClean data.")
            }

        }
        else
        {
            [void] $sbErr.AppendLine(("Failed to convert configuration data file ({0}) contents into a JSON object." -f @($configFile)))
            [void] $sbErr.AppendLine($configDataContent)
        }
    }
    else
    {
        [void] $sbErr.AppendLine(("Failed to read configuration data file: {0}" -f @($configFile)))
    }

    if($sbErr.Length -gt 0)
    {
        Write-Error $sbErr.ToString()
        $configData = $null
    }

    return $configData
}

function BuildExclusions
{
    [CmdLetBinding()]
    Param(
        # Exclusions to fix
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [AllowEmptyCollection()] [Object[]] $exclusions,

        [Parameter(
            Mandatory=$true,
            Position=1)]
        [String] $uncPathToClean,

        [Parameter(
            Mandatory=$true,
            Position=2)]
        [String] $label
    )

    $fixedExclusions = [System.Collections.Generic.List[System.String]]::new()
    if(-not [String]::IsNullOrEmpty($uncPathToClean))
    {
        # Build the folder exclusions...
        for($e = 0; $e -lt $exclusions.Length; $e++)
        {
            $exclusion = $exclusions[$e]
            if($exclusion.Contains("{{PATHROOT}}"))
            {
                $exclusion = $exclusion.Replace("{{PATHROOT}}", $uncPathToClean)
            }

            $fixedExclusions.Add($exclusion)
        }
    }
    else
    {
        Log "Null/empty path to clean passed to BuildExclusions."
        throw "Null/empty path to clean passed to BuildExclusions."
    }

    Log ("`t{0} exclusions:" -f @($label))

    for($a = 0; $a -lt $fixedExclusions.Count; $a++)
    {
        Log ("`t`t  {0}" -f @($fixedExclusions[$a]))
    }

    return @( ,$fixedExclusions)
}

function GetFoldersAndFiles
{
    [CmdLetBinding()]
    Param(
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [String] $uncPathToClean
    )

    Log "`tGetting files and folders..."

    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $folders = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    if(-not [String]::IsNullOrEmpty($uncPathToClean))
    {
        $enumerator = [System.IO.Directory]::EnumerateFileSystemEntries($uncPathToClean, "*", [System.IO.SearchOption]::AllDirectories).GetEnumerator()
        while($enumerator.MoveNext())
        {
            $nxtPathToClean = $enumerator.Current
            $fileInfo = [System.IO.FileInfo]::new($nxtPathToClean)

            # Separate files and folders
            if(($fileInfo.Attributes -band [System.IO.FileAttributes]::Directory) -eq [System.IO.FileAttributes]::Directory)
            {
                $folders.Add($fileInfo)
            }
            else
            {
                $files.Add($fileInfo)
            }
        }

        # Sort the folders in descending order so child sub folders are checked first.
        #    Example of using an anonymous function for a delegate in PowerShell to provide a custom comparison function for the sort algorithm.
        $folders.Sort(
            {
                param($o1, $o2)

                return $o2.FullName.CompareTo($o1.FullName)
            }
        )
    }
    else
    {
        Log "Null/empty path to clean passed to GetFoldersAndFiles."
        throw "Null/empty path to clean passed to GetFoldersAndFiles."
    }

    Log ("`tFolders: {0}" -f @($folders.Count))
    Log ("`t  Files: {0}" -f @($files.Count))

    return @($folders, $files)
}

function DeleteOldFiles
{
    [CmdLetBinding()]
    Param(
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [AllowEmptyCollection()] [System.Collections.Generic.List[System.IO.FileInfo]] $files,

        [Parameter(
            Mandatory=$true,
            Position=1)]
        [DateTime] $oldDateTime,

        [Parameter(
            Mandatory=$true,
            Position=2)]
        [AllowEmptyCollection()] [System.Collections.Generic.List[System.String]] $fileExclusions
    )

    # Sorted Dictionary of removed files, used to determine if files remaining in a subfolder "should" have been deleted.
    $deletedFilesByFolder = [System.Collections.Generic.SortedDictionary[String, [System.Collections.Generic.List[String]]]]::new()

    # Count of deleted files
    $deletedFileCount = 0

    # Remove files if they were:
    #    Created before $oldDateTime
    #       AND Last Accessed before $oldDateTime
    #       AND Last Written to before $oldDateTime
    $f = 0
    while($f -lt $files.Count)
    {
        $file = $files[$f]

        # See if the file should be excluded
        if(@($fileExclusions | Where-Object { $file.FullName.ToUpper().Contains($_) }).Length -eq 0)
        {
            # Make sure the file is "old"...
            if(($file.LastAccessTime -lt $oldDateTime) -or ($file.CreationTime -lt $oldDateTime))
            {
                # Do we need to update $deletedFileCount and $deletedFilesByFolder?
                $captureDeletedFile = $true

                # To avoid problems trying to remove a file that may have been removed since the list of files and folders was obtained, let's make sure the
                #   file still exists.
                if([System.IO.File]::Exists($file.FullName))
                {
                    Log ("Deleting file: Created: {1} (-{2,4}), Last Written: {3} (-{4,4}), Last Accessed: {5} (-{6,4}) [{0}]" -f @(
                        $file.FullName,
                        $file.CreationTime.ToString("yyyyMMdd hh:mm:ss"),
                        ([DateTime]::Now - $file.CreationTime).Days,
                        $file.LastWriteTime.ToString("yyyyMMdd hh:mm:ss"),
                        ([DateTime]::Now - $file.LastWriteTime).Days,
                        $file.LastAccessTime.ToString("yyyyMMdd hh:mm:ss"),
                        ([DateTime]::Now - $file.LastAccessTime).Days))

                    if($PSCmdlet.ShouldProcess($file.FullName, "Delete file"))
                    {
                        try
                        {
                            $Error.Clear()
                            # $file.Delete()
                        }
                        catch
                        {
                            Log ("Failed to delete file: {0}" -f @($file.FullName)) "ERROR"
                            Log ($Error[0].ToString()) "ERROR"
                            $captureDeletedFile = $false
                        }
                    }
                    else
                    {
                        # Nothing
                        # Only add the file to the deleted files list if it was successfully deleted.
                    }
                }
                else
                {
                    # Nothing...
                    # Still need to add the file to the list of files that were deleted since it no longer exists, so leave $captureDeletedFile set to $true
                }

                if($captureDeletedFile)
                {
                    $deletedFileCount++
                    if(-not $deletedFilesByFolder.ContainsKey($file.DirectoryName))
                    {
                        $newFileNameList = [System.Collections.Generic.List[String]]::new()
                        $deletedFilesByFolder.Add($file.DirectoryName, $newFileNameList)
                    }

                    $i = $deletedFilesByFolder[$file.DirectoryName].BinarySearch($file.FullName)
                    if($i -lt 0)
                    {
                        $deletedFilesByFolder[$file.DirectoryName].Insert(-bnot $i, $file.FullName)
                    }
                }
                else
                {
                    # Nothing...
                }
            }
        }
        else
        {
            Log ("Excluding file: {0}" -f @($file.FullName))
        }
        $f++
    }

    return @($deletedFileCount, $deletedFilesByFolder)
}

function RemoveEmptySubFolders
{
    [CmdLetBinding()]
    Param(
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [AllowEmptyCollection()] [System.Collections.Generic.List[System.IO.FileInfo]] $folders,

        [Parameter(
            Mandatory=$true,
            Position=1)]
        [DateTime] $oldDateTime,

        [Parameter(
            Mandatory=$true,
            Position=2)]
        [AllowEmptyCollection()] [Object[]] $folderExclusions,

        [Parameter(
            Mandatory=$true,
            Position=3)]
        [System.Collections.Generic.SortedDictionary[String, [System.Collections.Generic.List[String]]]] $deletedFilesByFolder
    )

    # List of removed folders
    $removedFoldersCount = 0

    <#
        It might be considered to use the list of files and folder obtained above to determine if a given folder is empty after files are cleaned.
        However, I feel this is a bad design since a file or subfolder could have been added to the folder after the initial list was created.  So, I've
        decided, even though this will be a bit slower, it's safer
    #>

    # Sorted Dictionary of removed subfolder, used to determine if subfolder remaining in a folder "should" have been deleted.
    $deletedFoldersByFolder = [System.Collections.Generic.SortedDictionary[String, [System.Collections.Generic.List[String]]]]::new()

    Log "Scanning for empty folders..."
    $f = 0
    while($f -lt $folders.Count)
    {
        $folder = $folders[$f]

        # See if the folder should be excluded
        if(@($folderExclusions | Where-Object { $folder.FullName.ToUpper().Contains($_) }).Length -eq 0)
        {
            # Get an array of subfolders in the folder
            $folderSubfolders = [System.IO.Directory]::GetDirectories($folder.FullName)

            # Track how many folders "should" have been deleted to get an accurate count for the log.
            $folderSubFoldersDeletedCount = 0

            # Did we delete any subfolders from $folder?
            if($deletedFoldersByFolder.ContainsKey($folder.FullName))
            {
                # Yes...

                # Check each remaining subfolder in the folder to see if it was deleted...
                #   Even a single remaining subfolder means we do not remove the folder...

                $q = 0
                while($q -lt $folderSubfolders.Length)
                {
                    if($deletedFoldersByFolder[$folder.FullName].BinarySearch($folderSubfolders[$q]) -ge 0)
                    {
                        $folderSubFoldersDeletedCount++
                    }
                    else
                    {
                        # Nothing
                    }

                    $q++
                }
            }
            else
            {
                # Nothing
            }

            $remainingSubfolderCount = $folderSubFolders.Length - $folderSubFoldersDeletedCount

            # If $folder contains any subfolders, then no need to look for files, were not going to remove folders that contain subfolders, so save some cycles
            #    by skipping files...
            if($remainingSubfolderCount -eq 0)
            {
                # Get an array of files left in the folder -- except any that were deleted (or would have been)
                $folderFiles = [System.IO.Directory]::GetFiles($folder.FullName)

                # Check to make sure the folder only contains files that were deleted (or should be deleted -- during script creation)...
                #    Under normal circumstances, tracking deleted files wouldn't matter, if the subfolder contains any files,
                #    it is not removed, however during creation of this script, I wasn't actually removing files, so I needed to have
                #    some way to not count files that would normally be deleted.  By leaving the code here, the script can later be debugged easier
                #    and honestly, it doesn't make much of a difference when running the script.

                # Track how many files "should" have been deleted to get an accurate count for the log.
                $folderFilesDeletedCount = 0

                # Did we delete any files from $folder?
                if($deletedFilesByFolder.ContainsKey($folder.FullName))
                {
                    # Yes...

                    # Check each remaining file in the folder to see if it was deleted...
                    #   Even a single remaining file means we do not remove the folder...

                    $q = 0
                    while($q -lt $folderFiles.Length)
                    {
                        if($deletedFilesByFolder[$folder.FullName].BinarySearch($folderFiles[$q]) -ge 0)
                        {
                            $folderFilesDeletedCount++
                        }
                        else
                        {
                            # Nothing
                        }

                        $q++
                    }
                }
                else
                {
                    # Nothing
                }

                $remainingFileCount = $folderFiles.Length - $folderFilesDeletedCount

                # If the $folder contains no files (except ones marked for deletion) and no subfolders, then delete it.
                if(($remainingFileCount -le 0) -and ($remainingSubfolderCount -le 0))
                {
                    # To avoid exceptions, check to make sure the folder still exists.  Might have been removed after we got a list of folders.
                    if([System.IO.Directory]::Exists($folder.FullName))
                    {
                        # Do we need to update $deletedFileCount and $deletedFilesByFolder?
                        $captureDeletedFolder = $true

                        Log ("Removing folder: {0}" -f @($folder.FullName))

                        if($PSCmdlet.ShouldProcess($folder.FullName, "Remove folder"))
                        {
                            try
                            {
                                $Error.Clear()
                                # $folder.Delete()
                            }
                            catch
                            {
                                Log ("Failed to remove subfolder: {0}" -f @($folder.FullName)) "ERROR"
                                Log ($Error[0].ToString()) "ERROR"
                                $captureDeletedFolder = $false
                            }
                        }
                        else
                        {
                            # Simulate removing the folder is -WhatIf was used.  -- leave $captureDeletedFolder = $true
                        }

                        if($captureDeletedFolder)
                        {
                            $removedFoldersCount++
                            if(-not $deletedFoldersByFolder.ContainsKey($folder.DirectoryName))
                            {
                                $newFolderNameList = [System.Collections.Generic.List[String]]::new()
                                $deletedFoldersByFolder.Add($folder.DirectoryName, $newFolderNameList)
                            }

                            $i = $deletedFoldersByFolder[$folder.DirectoryName].BinarySearch($folder.FullName)
                            if($i -lt 0)
                            {
                                $deletedFoldersByFolder[$folder.DirectoryName].Insert(-bnot $i, $folder.FullName)
                            }
                        }
                    }
                    else
                    {
                        # Nothing, folder has already been removed.
                    }
                }
            }
        }
        else
        {
            Log ("Excluding folder: {0}" -f @($folder.FullName))
        }

        $f++
    }

    return $removedFoldersCount
}

function SendAlertReport
{
    [CmdLetBinding()]
    Param(
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [String] $smtpServer,

        [Parameter(
            Mandatory=$true,
            Position=1)]
        [String] $alertSubject,

        [Parameter(
            Mandatory=$true,
            Position=2)]
        [mailaddress] $fromAddress,

        [Parameter(
            Mandatory=$true,
            Position=3)]
        [mailaddress[]] $toAddresses,

        [Parameter(
            Mandatory=$true,
            Position=4)]
        [String] $message
    )

    $smtpClient = [System.Net.Mail.SmtpClient]::new($smtpServer)
    $mailMessage = [System.Net.Mail.MailMessage]::new()
    $mailMessage.Subject = "{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMdd"), $alertSubject)
    $mailMessage.From = $fromAddress
    $toAddresses | ForEach-Object { $mailMessage.To.Add($_) }
    $mailMessage.Body = $message
    $mailMessage.ReplyTo = [mailaddress]::new("DoNotReply <donotreply@powereng.com>")

    try
    {
        $Error.Clear()
        $smtpClient.Send($mailMessage)
    }
    catch
    {
        Log "Failed to send alert email."
        Write-Error "Failed to send alert email."
        throw
    }
}

# Just some performance stuff...
$scriptStartTime = [DateTime]::Now
$sw = [System.Diagnostics.Stopwatch]::new()
$elapsedTimes = @()

if(-not [System.IO.File]::Exists($configFile))
{
    Write-Error ("Configuration file: {0} does not exist, or access is denied." -f @($configFile))
    break
}

# Load configuration data and sanity check it.
$configData = ParseConfigFile $configFile
if($null -eq $configData)
{
    break
}

# Create a log file name -- using a global scoped variable so each call to "Log" does not have to include the log file name.
$Global:logFile = "{0}\{1}-{2}.log" -f @($configData.PathToLogs, ($MyInvocation.MyCommand.Name -replace ".ps1",""), [DateTime]::Now.ToString("yyyyMMdd-HHmm"))

Log ("{0} -configFile `"{1}`"" -f @($MyInvocation.MyCommand.Name, $configFile))

# How old do files/folders need to be to be removed?
$oldDateTime = [DateTime]::Now.AddDays(-1 * $configData.MaxAge)

# Now, clean each path ...
$p = 0
while($p -lt $configData.PathsToClean.Length)
{
    # Restart the stopwatch
    [void] $sw.Restart()

    $pathToClean = $configData.PathsToClean[$p].ToUpper()

    # Strip off any ending [System.IO.Path]::DirectorySeparatorChar
    while($pathToClean.EndsWith([System.IO.Path]::DirectorySeparatorChar))
    {
        $pathToClean = $pathToClean.Substring(0, $pathToClean.Length - 1)
    }

    # Makes sure $pathToClean exists and the script has access to it
    if(-not [System.IO.Directory]::Exists($pathToClean))
    {
        Log ("Path does not exist, or access is denied: {0}.  Skipped" -f @($pathToClean)) "ERROR"
        continue    # To the next path to clean
    }

    Log ("Processing {0}..." -f @($pathToClean))

    # Change $pathToClean so unicode API calls are used, which are long path safe
    $uncPathToClean = $pathToClean -replace '^(\\\\([^\\]+))','\\?\UNC\$2'

    # List of files and folders to exclude from cleansing.
    #   Before a file or folder is removed, the appropriate list checked.  To be a successful match,
    #   the FULLNAME of the file or folder must contain (not case sensitive) any string in the list.
    #      Example: If the string ange\ScanFi is added to the folder exclusions list, then any folder whose FULLNAME
    #               contains "ange\ScanFi" anywhere in it will match, and thus be skipped.
    #
    # Note: I started with a single exclusions list, then realized, files and folder might be handled differently, yeah, like "Scanfiles"...
    #       I need to clean old files from ScanFiles, but do not delete any subfolders from it.
    #
    #       So, for files AND folder to be excluded, you'll need to add the string to BOTH exclusion lists.
    $folderExclusions = BuildExclusions $configData.FolderExclusions $uncPathToClean "Folder"
    $fileExclusions = BuildExclusions $configData.FileExclusions $uncPathToClean "File"

    # Get a list of all files and folder in $uncPathToClean
    $folders, $files = GetFoldersAndFiles $uncPathToClean

    # Delete old files.  Return the count of deleted files and a sorted dictionary of files deleted by folder.
    #   The dictionary of deleted files is needed by RemoveEmptySubFolders to determine if files "should" have been
    #   deleted, but were not due to the use of -WhatIf
    $deletedFileCount, $deletedFilesByFolder = DeleteOldFiles $files $oldDateTime $fileExclusions

    <#
        Reminder: $folders needs to be sorted in descending order by full name so the directory tree is walked backward.  In other words, check all child folders before the parent.
    #>

    # Remove empty subfolders and return the count of removed subfolders
    $removedFoldersCount = RemoveEmptySubFolders $folders $oldDateTime $folderExclusions $deletedFilesByFolder

    # Just more performance stuff
    $sw.Stop()
    $elapsedData = "" | Select-Object Path, Elapsed, RemovedFiles, RemovedFolders
    $elapsedData.Path = $uncPathToClean.Replace("\\?\UNC","\")
    $elapsedData.Elapsed = $sw.Elapsed.ToString()
    $elapsedData.RemovedFiles = $deletedFileCount
    $elapsedData.RemovedFolders = $removedFoldersCount
    $elapsedTimes += $elapsedData

    Log ("Removed files: {0}" -f @($elapsedData.RemovedFiles))
    Log ("Removed folders: {0}" -f @($elapsedData.RemovedFolders))
    Log ("Elapsed: {0}" -f @($elapsedData.Elapsed))

    $p++
}

$elapsedTimes = $elapsedTimes | Sort-Object Elapsed | ForEach-Object { Log ("Path: {0}`tElapsed: {1}`tRemoved Folders: {2}`tRemoved Files: {3}" -f $($_.Path, $_.Elapsed, $_.RemovedFolders, $_.RemovedFiles)) }

# Just some performance info..
$scriptEndTime = [DateTime]::Now
$elapsed = $scriptEndTime - $scriptStartTime
Log ("Overall Elapsed: {0}" -f @($elapsed.ToString()))

# Are there any alert messages to send?
if($null -ne $Global:sbAlertData)
{
    # Ah, yep...
    SendAlertReport $configData.SMTPServer $configData.AlertSubject $configData.SenderAddress $configData.AlertRecipients $Global:sbAlertData.ToString()
}
else
{
    # Nope, I'm out!  Have a great day.
}
