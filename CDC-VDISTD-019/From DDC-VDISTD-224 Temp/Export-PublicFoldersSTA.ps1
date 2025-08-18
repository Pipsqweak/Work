<#
    This script will export a list of public folders, one at a time, to a local folder then upload the local folder to ProjectWise.

    Given a public folder's EntryID, all items in the public folder will be uploaded to a similiarly named folder in ProjectWise.
    Calendars are exported as a single .ICS file.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String]
    $publicFolderListFile,

    [Parameter(Mandatory = $true, Position = 1)]
    [String]
    $PWServerFQDN,

    [Parameter(Mandatory = $true, Position = 2)]
    [String]
    $PWDatasourceName,

    [Parameter(Mandatory = $true, Position = 3)]
    [String]
    $PWUserName,

    [Parameter(Mandatory = $true, Position = 4)]
    [String]
    $PWEncryptedUserPassword,  # This is the result of: ConvertTo-SecureString -String "plainTextPassword" -AsPlainText -Force  | ConvertFrom-SecureString

    [Parameter(Mandatory = $true, Position = 5)]
    [String]
    $ProjectWiseBaseFolderName,

    [Parameter(Mandatory = $true, Position = 6)]
    [String]
    $LogFolder,

    [Parameter(Mandatory = $true, Position = 7)]
    [String]
    $BaseWorkingFolder
)

# Import the ProjectWise powershell module.
[Environment]::SetEnvironmentVariable('SuppressPSOutput',$true)
Import-Module -Name PWPS_DAB -Force -DisableNameChecking

$Script:LogFileNamePrefix = "ExportPF"

. C:\Users\kbriney\Documents\LogFunctions.ps1
. C:\Users\kbriney\Documents\RetryCatch.ps1

$Script:ListOfExportedPublicFoldersFile = "\\boifs1\ITxchange\klbtest\ListOfExportedPublicFolders.csv"

# Where the results from Import-PWDocuments and PFObjects are saved.
$Script:ResultsFolder = "\\boifs1\ITxchange\klbtest\PFExportResults"

$Script:DoDebugging = $true

# Maximum length of a ProjectWise path
$Script:MaximumProjectWisePathLength = 201

# Maximum number of time to try to get an item from Exchange.
$Script:MaxItemGetRetries = 15

# How long to delay between retry attempts to retrieve an item from Exchange.
$Script:ItemGetDelay = 1000

# Maximum times to try an action
$Script:MaxRetries = 3

# How many times to try to save a message file before giving up.
$Script:MaxSaveRetries = 5

# How much time to delay when saving a message file fails.
$Script:SaveDelayInMS = 1500

# How long to we keep trying to get a file stream?
$Script:MaxFileStreamRetryPeriodMS = 30000

# Setting $Script:LogProcessID will cause the log output function to include it in the timestamp of each message.
#  NOTE: must be set AFTER LogFunctions.ps1 has been dot sourced
# $Script:LogProcessID = [System.Diagnostics.Process]::GetCurrentProcess().Id

# This object is returned to the caller for external processing.
$Script:ReturnObject = [PSCustomObject]@{
    Good2Go = $true                   # So long as everything goes smooth, this will remain $true
    PublicFolder = [PSCustomObject]@{
        Name = [String]::Empty
        EntryID = [String]::Empty
        ItemCount = 0
        Type = [String]::Empty
    }
    ProjectWise = [PSCustomObject]@{
        ImportFolder = [String]::Empty
    }
    Process = [PSCustomObject]@{
        ID = [System.Diagnostics.Process]::GetCurrentProcess().Id
        Start = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff")
        End = [String]::Empty
        Status = [String]::Empty
    }
    ExportedItems = [PSCustomObject]@{
        Count = 0
        Size = 0
    }
    ImportedItems = [PSCustomObject]@{
        Count = 0
        Size = 0
    }
}

$Script:OutlookApp = $null
$Script:OutlookNamespace = $null

# Characters which are illegal in file and path names.  This is used so I don't call the functions in a loop
$Script:BadFilePathChars = @([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()) | Select-Object -Unique
$Script:BadFilenameChars = [System.IO.Path]::GetInvalidFileNameChars()

# Character which are illegal in paths.  This is used so [System.IO.Path]::GetInvalidPathChars() is not called in a loop
$Script:BadPathChars = [System.IO.Path]::GetInvalidPathChars()

$Script:topPublicFolder = $null
$Script:ExportedPublicFolderPath = [String]::Empty

$Script:ProjectWiseBaseFolder = $null

# Move out of function...
$Script:ConversationPrefix = "Conv {{0,{0}}} {1} "
$Script:MessagePrefix = "Msg {{0,{0}}} of {{1,{0}}} {1} "

# List of public folder items in the public folder we are exporting.
$Script:PublicFolderItems = $null

# List of imported files -- results from Import-PWDocuments
$Script:ImportResults = $null

# Dictionary of lists of public folder items by conversation ID
$Script:ItemsByConversation = $null

# Maximum number of files to import at once to ProjectWise
$Script:MaxFilesPerImport = 1000

$Script:pfObjsFilename = [String]::Empty
$Script:importResultsFilename = [String]::Empty
$Script:UniqueImportFileNames = $null

$Script:EntryIDPrefix = [String]::Empty
<#
    Seems the .EntryID of an object is dependent on the user and session looking at the object.
        Since I export the list of folders via ExchangeOnline powershell cmdlets (to avoid timeouts),
        I have to "fix" .EntryID for each object accessed via my normal Outlook user credentials.

        For any given .EntryID, the first 44 characters always match, so I'll get the .EntryID for the top level
        public folder and use it's .EntryID (first 44 characters) to create the .EntryID I need for this script.
            It seems, at run-time, the first 44 characters of any given entry is a "session ID".

        Example:

        Exported using ExchangeOnline cmdlets using POWERENG\kbriney-adm account
            .EntryID =    "000000009598E9A20E04F041B38518182890A2D50100A3DF33FCC9BD1644BD14FCA330AA978500002C9DB2BF0000"
            .FolderPath = "\Divisions\ENV\Environmental Boise\142963 TSCHACHE LANE WETLAND DELIN"

        If I try to .GetFolderFromID using the EntryID, the call fails.

        Top Level Public Folder as seen by POWERENG\kbriney via the Outlook.Application ComObject.
            .EntryID =    "000000001A447390AA6611CD9BC800AA002FC45A0300C0B86B30DBD611CEB31700AA00574CC60000000000030000"
            .FolderPath = "\\Public Folders - ken.briney@powereng.com\All Public Folders"

        Now if I use the first 44 characters on the top level public folder's EntryID, and the last 48 characters of the
        .EntryID exported via ExchangeOnline, I get:

            .EntryID =    "000000001A447390AA6611CD9BC800AA002FC45A0300A3DF33FCC9BD1644BD14FCA330AA978500002C9DB2BF0000"

        Finally, $namespace.GetFolderFromID("000000001A447390AA6611CD9BC800AA002FC45A0300A3DF33FCC9BD1644BD14FCA330AA978500002C9DB2BF0000") yields:
            .EntryID =    "000000001A447390AA6611CD9BC800AA002FC45A0300A3DF33FCC9BD1644BD14FCA330AA978500002C9DB2BF0000"
            .FolderPath = "\\Public Folders - ken.briney@powereng.com\All Public Folders\Divisions\ENV\Environmental Boise\142963 TSCHACHE LANE WETLAND DELIN"

        This matches the export from above.
#>

class PFObjectComparerByConversationIndex:System.Collections.Generic.IComparer[System.Object]
{
    [int] Compare([System.Object] $pfObj1, [System.Object] $pfObj2) {
        $retVal = 0
        if(($null -eq $pfObj1) -and ($null -eq $pfObj2))
        {
            $retVal = 0
        } `
        elseif($null -eq $pfObj1)
        {
            $retVal = -1
        } `
        elseif($null -eq $pfObj2)
        {
            $retVal = 1;
        } `
        else
        {
            if(($null -eq $pfObj1.ConversationIndex) -and ($null -eq $pfObj2.ConversationIndex))
            {
                $retVal = 0
            } `
            elseif($null -eq $pfObj1.ConversationIndex)
            {
                $retVal = -1
            } `
            elseif($null -eq $pfObj2.ConversationIndex)
            {
                $retVal = 1;
            } `
            else
            {
                $retval = $pfObj1.ConversationIndex.CompareTo($pfObj2.ConversationIndex)
            }
        }

        return $retval
    }
}

function ImportInteropDLL
{
    try
    {
        $original_pwd = (Get-Location).Path
        Set-Location -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) + "\Assembly")
        $interop_assemply_location = (Get-ChildItem -Recurse  Microsoft.Office.Interop.Outlook.dll).Directory
        Set-Location -Path $interop_assemply_location
        Add-Type -AssemblyName "Microsoft.Office.Interop.Outlook"
        Set-Location -Path $original_pwd
        LogInfo "Interop Assembly loaded"
    }
    catch
    {
        LogError "Failed to load Interop DLL"
        $Script:ReturnObject.Good2Go = $false
    }
}

function SetEntryIDPrefix
{
    try
    {
        $Script:topPublicFolder = $Script:OutlookNamespace.GetDefaultFolder([Microsoft.Office.Interop.Outlook.OlDefaultFolders]::olPublicFoldersAllPublicFolders)
    }
    catch
    {
        LogError ("Failed to get top level public folder.")
        $Script:ReturnObject.Good2Go = $false
    }

    if($null -ne $Script:topPublicFolder)
    {
        if(-not [String]::IsNullOrEmpty($Script:topPublicFolder.EntryID))
        {
            if($Script:topPublicFolder.EntryID.Length -gt 44)
            {
                # Use the first 44 characters of the top public folder EntryID to "fix" exported EntryIDs.
                $Script:EntryIDPrefix = $Script:topPublicFolder.EntryID.Substring(0, 44)
                LogInfo ("Using entry ID prefix: {0} to fix up public folder EntryID." -f @($Script:EntryIDPrefix))
            } `
            else
            {
                LogError ("Unable to use [{0}] to fix exported EntryID.  It is not long enough." -f @($Script:topPublicFolder.EntryID))
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else
        {
            LogError ("Null/empty EntryID for top public folder.")
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else
    {
        LogError "No top level public folder found.  Try resetting Outlook then try again."
        $Script:ReturnObject.Good2Go = $false
    }
}

function ConnectToProjectWise
{
    LogInfo ("ProjectWise Server: {0}" -f @($Script:PWServerFQDN))
    LogInfo ("ProjectWise Data source: {0}" -f @($Script:PWDatasourceName))
    LogInfo ("ProjectWise User name: {0}" -f @($Script:PWUserName))

    $alreadyConnectedToPW = $false
    try
    {
        # See if a connection to PW already exists...
        $null = Get-PWCurrentDSSession -ErrorAction Stop
        $alreadyConnectedToPW = $true
    }
    catch
    {
        # Nothing, just trapping the exception.
    }

    if(-not $alreadyConnectedToPW)
    {
        $pwEnvironment = "{0}:{1}" -f @($Script:PWServerFQDN, $Script:PWDatasourceName)

        try
        {
            $pwSSPass = ConvertTo-SecureString -String $Script:PWEncryptedUserPassword
        }
        catch
        {
            LogError "Invalid encrypted ProjectWise password."
            $Script:ReturnObject.Good2Go = $false
        }

        if($Script:ReturnObject.Good2Go)
        {
            try
            {
                $null = New-PWLogin -DatasourceName $pwEnvironment -UserName $Script:PWUserName -Password $pwSSPass -ErrorAction Stop
                LogInfo "Connected to ProjectWise"
            }
            catch
            {
               LogError ("Failed to connect to ProjectWise (env: {0}, user: {1})" -f @($pwEnvironment, $Script:PWUserName))
               $Script:ReturnObject.Good2Go = $false
            }
        } `
        else
        {
            # Nothing, already logged an error.
        }
    } `
    else # NOT (-not $alreadyConnectedToPW)
    {
        # Nothing.
    }

    if($Script:ReturnObject.Good2Go)
    {
        # Verify the base ProjectWise Folder exists.
        try
        {
            $Script:ProjectWiseBaseFolder = Get-PWFolders -FolderPath $Script:ProjectWiseBaseFolderName -JustOne -ErrorAction Stop
            LogInfo ("Found PW base folder: {0}" -f @($Script:ProjectWiseBaseFolder.Name))
        }
        catch
        {
            LogError ("ProjectWise base folder {0} does not exist." -f @($Script:ProjectWiseBaseFolderName))
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}

function InitializeExporter
{
    LogInfo "Initializing public folder exporter..."

    if($null -eq $Script:PFObjectConversationIndexComparer)
    {
        $Script:PFObjectConversationIndexComparer = [PFObjectComparerByConversationIndex]::new()
    } `
    else # NOT ($null -eq $Script:PFObjectConversationIndexComparer)
    {
        # Nothing.
    }

    ImportInteropDLL
    if($Script:ReturnObject.Good2Go)
    {
        try
        {
            $Script:OutlookApp = [System.Activator]::CreateInstance([Type]::GetTypeFromProgID("Outlook.Application"))
            LogInfo "Outlook Application object created."
        }
        catch
        {
            LogError ("Failed to create Outlook application object.")
            $Script:ReturnObject.Good2Go = $false
        }

        if($null -ne $Script:OutlookApp)
        {
            try
            {
                $Script:OutlookNamespace = $Script:OutlookApp.GetNameSpace("MAPI")
                LogInfo "Outlook MAPI Namespace created."
            }
            catch
            {
                LogError ("Failed to attach to the Outlook Application namespace.")
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else
        {
            $Script:ReturnObject.Good2Go = $false
        }

        if($Script:ReturnObject.Good2Go)
        {
            SetEntryIDPrefix
        } `
        else
        {
            # Nothing, already displayed an error message
        }

        if($Script:ReturnObject.Good2Go)
        {
            # Connect to ProjectWise...
            ConnectToProjectWise
        } `
        else
        {
            # Nothing, already displayed a message.
        }
    } `
    else
    {
        # Nothing, already displayed an error
    }
}

function PublicFolderActivelyBeingExported
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $entryID
    )

    if($false)
    {
    $alreadyExported = $false
    $header = $null
    $fs = $null

    if(-not [String]::IsNullOrEmpty($entryID) -and ($entryID.Length -gt 44))
    {
        $haveFileStream = $false
        $sw = [System.Diagnostics.Stopwatch]::new()
        $sw.Start()
        $fs = $null
        $sr = $null

        do
        {
            try
            {
                $fs = [System.IO.FileStream]::new($Script:ListOfExportedPublicFoldersFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $haveFileStream = ($null -ne $fs)
            }
            catch
            {
                if($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    LogError ("Failed to open a file stream to {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                } `
                else # NOT ($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    # Wait a bit and try again.

                    Start-Sleep -Milliseconds 10
                }
            }
        } while($Script:ReturnObject.Good2Go -and (-not $haveFileStream))
        $sw.Stop()

        if($haveFileStream)
        {
            try
            {
                $sr = [System.IO.StreamReader]::new($fs)

                try
                {
                    $headerText = $sr.ReadLine()
                    $headerText = $headerText.Replace("`"", "")
                    $header = $headerText -split "`t"

                    while((-not $alreadyExported) -and (-not $sr.EndOfStream))
                    {
                        try
                        {
                            $lineText = $sr.ReadLine()

                            try
                            {
                                $lineData = $lineText | ConvertFrom-CSV -Delimiter "`t" -Header $header -ErrorAction Stop
                                $alreadyExported = ((-not [String]::IsNullOrEmpty($lineData.EntryID)) -and ($lineData.EntryID.Length -gt 44) -and ($lineData.EntryID.Substring(44) -eq $entryID.SubString(44)) -and $lineData.Success)
                            }
                            catch
                            {
                                LogException ("Failed to convert export data line {0} to object." -f @($lineText))
                                $Script:ReturnObject.Good2Go = $false
                            }
                        }
                        catch
                        {
                            LogException ("Failed to read export data line from {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                            $Script:ReturnObject.Good2Go = $false
                        }
                    }
                }
                catch
                {
                    LogException ("Failed to read export data header from {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                }
            }
            catch
            {
                LogException "Failed to create stream reader from file stream."
                $Script:ReturnObject.Good2Go = $false
            }
            finally
            {
                if($null -ne $sr)
                {
                    $sr.Close()
                } `
                else # NOT ($null -ne $sr)
                {
                    # Nothing
                }
            }

            $fs.Close()
        } `
        else # NOT ($haveFileStream)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($entryID))
    {
        LogError ("Invalid or empty entry ID [{0}] in PublicFolderHasBeenExported." -f @($entryID))
        $Script:ReturnObject.Good2Go = $false
    }

    return $alreadyExported
    }

    return $false
}

function PublicFolderHasBeenExported
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.String]
        $entryID
    )

    $alreadyExported = $false
    $header = $null
    $fs = $null

    if(-not [String]::IsNullOrEmpty($entryID) -and ($entryID.Length -gt 44))
    {
        $haveFileStream = $false
        $sw = [System.Diagnostics.Stopwatch]::new()
        $sw.Start()
        $fs = $null
        $sr = $null

        do
        {
            try
            {
                $fs = [System.IO.FileStream]::new($Script:ListOfExportedPublicFoldersFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $haveFileStream = ($null -ne $fs)
            }
            catch
            {
                if($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    LogError ("Failed to open a file stream to {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                } `
                else # NOT ($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    # Wait a bit and try again.

                    Start-Sleep -Milliseconds 10
                }
            }
        } while($Script:ReturnObject.Good2Go -and (-not $haveFileStream))
        $sw.Stop()

        if($haveFileStream)
        {
            try
            {
                $sr = [System.IO.StreamReader]::new($fs)

                try
                {
                    $headerText = $sr.ReadLine()
                    $headerText = $headerText.Replace("`"", "")
                    $header = $headerText -split "`t"

                    while((-not $alreadyExported) -and (-not $sr.EndOfStream))
                    {
                        try
                        {
                            $lineText = $sr.ReadLine()

                            try
                            {
                                $lineData = $lineText | ConvertFrom-CSV -Delimiter "`t" -Header $header -ErrorAction Stop
                                $alreadyExported = ((-not [String]::IsNullOrEmpty($lineData.EntryID)) -and ($lineData.EntryID.Length -gt 44) -and ($lineData.EntryID.Substring(44) -eq $entryID.SubString(44)) -and $lineData.Success)
                            }
                            catch
                            {
                                LogException ("Failed to convert export data line {0} to object." -f @($lineText))
                                $Script:ReturnObject.Good2Go = $false
                            }
                        }
                        catch
                        {
                            LogException ("Failed to read export data line from {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                            $Script:ReturnObject.Good2Go = $false
                        }
                    }
                }
                catch
                {
                    LogException ("Failed to read export data header from {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                }
            }
            catch
            {
                LogException "Failed to create stream reader from file stream."
                $Script:ReturnObject.Good2Go = $false
            }
            finally
            {
                if($null -ne $sr)
                {
                    $sr.Close()
                } `
                else # NOT ($null -ne $sr)
                {
                    # Nothing
                }
            }

            $fs.Close()
        } `
        else # NOT ($haveFileStream)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($entryID))
    {
        LogError ("Invalid or empty entry ID [{0}] in PublicFolderHasBeenExported." -f @($entryID))
        $Script:ReturnObject.Good2Go = $false
    }

    return $alreadyExported
}

function ResetScriptObjects
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $PFEntryID
    )

    if($null -eq $Script:PublicFolderItems)
    {
        $Script:PublicFolderItems = [System.Collections.Generic.List[System.Object]]::new()
    } `
    else # NOT ($null -eq $Script:PublicFolderItems)
    {
        $Script:PublicFolderItems.Clear()
    }

    if($null -eq $Script:ImportResults)
    {
        $Script:ImportResults = [System.Collections.Generic.List[System.Object]]::new()
    } `
    else # NOT ($null -eq $Script:ImportResults)
    {
        $Script:ImportResults.Clear()
    }

    if($null -eq $Script:ItemsByConversation)
    {
        $Script:ItemsByConversation = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()
    } `
    else # NOT ($null -eq $Script:ItemsByConversation)
    {
        $Script:ItemsByConversation.Clear()
    }

    $Script:ReturnObject = [PSCustomObject]@{
        Good2Go = $true                   # So long as everything goes smooth, this will remain $true
        LogFile = [String]::Empty
        WorkFolder = [String]::Empty
        PublicFolder = [PSCustomObject]@{
            Name = [String]::Empty
            EntryID = $PFEntryID
            ItemCount = 0
            Type = [String]::Empty
        }
        ProjectWise = [PSCustomObject]@{
            ImportFolder = [String]::Empty
        }
        Process = [PSCustomObject]@{
            ID = [System.Diagnostics.Process]::GetCurrentProcess().Id
            Start = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff")
            End = [String]::Empty
            Status = [String]::Empty
        }
        ExportedItems = [PSCustomObject]@{
            Count = 0
            Size = 0
        }
        ImportedItems = [PSCustomObject]@{
            Count = 0
            Size = 0
        }
    }
    $Script:pfObjsFilename = [String]::Empty
    $Script:importResultsFilename = [String]::Empty

    if($null -ne $Script:UniqueImportFileNames)
    {
        $Script:UniqueImportFileNames.Clear()
    } `
    else # NOT ($null -ne $Script:UniqueImportFileName)
    {
        $Script:UniqueImportFileNames = [System.Collections.Generic.List[System.String]]::new()
    }
}

function FixFileOrPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $fileOrPath,

        [Parameter(Mandatory = $false, Position = 1)]
        [Switch]
        $IsNotPath
    )

    if(-not [String]::IsNullOrEmpty($fileOrPath))
    {
        $fileOrPath = $fileOrPath.Trim()
        if(-not [String]::IsNullOrEmpty($fileOrPath))
        {
            if(-not $IsNotPath.IsPresent)
            {
                $pieces = $fileOrPath.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)
            } `
            else # NOT (-not $IsNotPath.IsPresent)
            {
                $pieces = @($fileOrPath)
            }

            $a = 0
            while($a -lt $pieces.Length)
            {
                do
                {
                    $x = $pieces[$a].IndexofAny($Script:BadFilenameChars)
                    if($x -ge 0)
                    {
                        $pieces[$a] = $pieces[$a].Remove($x, 1)
                    } `
                    else
                    {
                        # Nothing
                    }
                } while($x -ge 0)

                $a++
            }

            $fileOrPath = $pieces -join [System.IO.Path]::DirectorySeparatorChar
            if(-not [String]::IsNullOrEmpty($fileOrPath))
            {
                $fileOrPath = $fileOrPath -replace "%2F", "_"
            } `
            else # NOT (-not [String]::IsNullOrEmpty($path))
            {
                # Nothing.
            }
        }
    } `
    else
    {
        # Nothing, can't replace invalid characters in an empty string...
    }

    return $fileOrPath
}

function FixEntryID
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $entryIDtoFix
    )

    $fixedEntryID = [String]::Empty
    if(-not [String]::IsNullOrEmpty($Script:EntryIDPrefix))
    {
        if(-not [String]::IsNullOrEmpty($entryIDtoFix))
        {
            $fixedEntryID = "{0}{1}" -f @($Script:EntryIDPrefix, $entryIDtoFix.Substring(44))
        } `
        else
        {
            LogError "Null entry ID set to FixEntryID"
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else
    {
        LogError "`$Script:EntryIDPrefix must be set prior to calling FixEntryID."
        $Script:ReturnObject.Good2Go = $false
    }

    return $fixedEntryID
}

function ExportPublicFolderItemsAsIcs
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $publicFolder
    )

    $calExporter = $null
    try
    {
        $calExporter = $publicFolder.GetCalendarExporter()
    }
    catch
    {
        LogError ("Failed to create calendar exported.")
        $Script:ReturnObject.Good2Go = $false
    }

    if($null -ne $calExporter)
    {
        $exportedToICS = $false
        $fName = FixFileOrPath -fileOrPath $publicFolder.Name -IsNotPath
        $fileName = "{0}\{1}.ics" -f @($Script:WorkingFolder, $fName)

        LogInfo ("`tExporting {0} as ICS file." -f @($publicFolder.Name))
        try
        {
            $calExporter.SaveAsICal($fileName)
            $exportedToICS = $true
        }
        catch
        {
            LogError ("Failed to export {0} to ICS file: {1}" -f @($publicFolder.Name, $fileName))
            $Script:ReturnObject.Good2Go = $false
        }

        if($exportedToICS)
        {
            $icsFI = $null
            try
            {
                $icsFI = [System.IO.FileInfo]::new($fileName)
            }
            catch
            {
                LogError ("Failed to read file information for {0}" -f @($fileName))
                $Script:ReturnObject.Good2Go = $false
            }

            if($null -ne $icsFI)
            {
                if($icsFI.Exists)
                {
                    $Script:ReturnObject.ExportedItems.Count++
                    $Script:ReturnObject.ExportedItems.Size += $icsFI.Length
                    $Script:ReturnObject.ExportedItems.Count = 1
                } `
                else # NOT ($icsFI.Exists)
                {
                    LogError ("Calendar export file {0} for {1} does not seem to exist." -f @($fileName, $publicFolder.Name))
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else # NOT ($null -ne $icsFI)
            {
                # Nothing.
            }
        } `
        else # NOT ($exportedToICS)
        {
            # Nothing.
        }
    } `
    else
    {
        # Nothing, already logged an error
    }
}

function GetItemFromOutlookByEntryID
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $entryID
    )

    $item = $null
    if(-not [String]::IsNullOrEmpty($entryID))
    {
        $itemRetries = 0
        do
        {
            $itemRetries++
            try
            {
                $item = $null
                $item = $Script:OutlookNamespace.GetItemFromID($entryID)
            }
            catch
            {
                $item = $null
            }

            if($null -ne $item)
            {
                $entryIDRetries = 0
                while(($entryIDRetries -lt $Script:MaxItemGetRetries) -and ([String]::IsNullOrEmpty($item.EntryID)))
                {
                    $entryIDRetries++
                    if($entryIDRetries -eq $Script:MaxItemGetRetries)
                    {
                        LogError ("Failed to get a valid EntryID from item (using entryID = [{0}]) after {1} retries." -f @($entryID, $Script:MaxItemGetRetries))
                    } `
                    else # NOT ($entryIDRetries -eq $Script:MaxItemGetRetries)
                    {
                        Start-Sleep -Milliseconds $Script:ItemGetDelay
                    }
                }
            } `
            else # NOT ($null -ne $item)
            {
                if($itemRetries -eq $Script:MaxItemGetRetries)
                {
                    LogError ("Failed to retrieve item with entryID: {0} after {1} retries" -f @($entryID, $Script:MaxItemGetRetries))
                } `
                else # NOT ($tries -eq $Script:MaxRetries)
                {
                    LogInfo ("Retrying ({0}) GetItemFromID({1})" -f @($itemRetries, $entryID))
                    Start-Sleep -Milliseconds $Script:ItemGetDelay
                }
            }
        }  while((($null -eq $item) -or [String]::IsNullOrEmpty($item.EntryID)) -and ($itemRetries -lt $Script:MaxItemGetRetries))
    } `
    else # NOT (-not [String]::IsNullOrEmpty($entryID))
    {
        LogError "Null/Empty entryID in GetItemFromOutlookByEntryID."
    }

    return $item
}

function UpdatePublicFolderObjectStatus
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $pfObj,

        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $status
    )

    if(-not [String]::IsNullOrEmpty($status))
    {
        if(-not [String]::IsNullOrEmpty($pfObj.Status))
        {
            $pfObj.Status = "{0} | {1}" -f @($pfObj.Status, $status)
        } `
        else
        {
            $pfObj.Status = $status
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($status))
    {
        # Nothing.
    }
}

function NewPublicFolderObjectFromItem
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $item,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $fileIndex
    )

    if($null -ne $item)
    {
        $pfObj = [PSCustomObject]@{
            PublicFolderPath = $Script:ExportedPublicFolderPath
            EntryID = $item.EntryID
            Status = [String]::Empty
            LastModificationTime = $item.LastModificationTime
            CreationTime = $item.CreationTime
            Subject = $item.Subject
            SaveType = [Microsoft.Office.Interop.Outlook.olSaveAsType]::olMSG
            TempFileIndex = $fileIndex
            TempFileName = "{0}\File_{1:D5}.msg" -f @($Script:WorkingFolder, $fileIndex)
            FileName = [String]::Empty
            ImportedFileName = [String]::Empty
            SortTime = $item.CreationTime
            Saved = $false
            ConversationID = "NO_CONVERSATION"
            ConversationIndex = $item.ConversationIndex
            SenderName = $item.SenderName
            Saved2Temp = $false
            Renamed = $false
            Imported = $false
            Deleted = $false
            Good2Go = $true
        }

        # For different save types as I find them...
        switch($item.MessageClass)
        {
            "IPM.Contact" {
                $pfObj.SaveType = [Microsoft.Office.Interop.Outlook.olSaveAsType]::olVCard
                $pfObj.TempFileName = "{0}\File_{1:D5}.vcf" -f @($Script:WorkingFolder, $fileIndex)
            }
        }

        # If the item has no creation time (WTF!!) then use LastModificationTime
        if($null -eq $pfObj.SortTime)
        {
            $pfObj.SortTime = $pfObj.LastModificationTime
        } `
        else # NOT ($null -eq $convObj.SortTime)
        {
            # Nothing.
        }

        if([String]::IsNullOrEmpty($pfObj.Subject))
        {
            $pfObj.Subject = "NO_SUBJECT"
        } `
        else # NOT ([String]::IsNullOrEmpty($pfObj.Subject))
        {
            $pfObj.Subject = FixFileOrPath -fileOrPath $pfObj.Subject -IsNotPath
        }

        if(-not [String]::IsNullOrEmpty($pfObj.SenderName))
        {
            $pfObj.SenderName = FixFileOrPath -fileOrPath $pfObj.SenderName -IsNotPath
        } `
        else # NOT (-not [String]::IsNullOrEmpty($pfObj.SenderName))
        {
            $pfObj.SenderName = [String]::Empty
        }

        try
        {
            if(-not [String]::IsNullOrEmpty($item.ConversationID))
            {
                $pfObj.ConversationID = $item.ConversationID
            } `
            else # NOT (-not [String]::IsNullOrEmpty($item.ConversationID))
            {
                # Nothing, already initialized
            }
        }
        catch
        {
            $pfObj.ConversationID = "NO_CONVERSATION"
        }
    } `
    else
    {
        LogError "Null item in NewConversationObjectFromItem."
    }

    return $pfObj
}

function SavePublicFolderItemToTempFile
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $pfObj,

        [Parameter(Mandatory = $true, Position = 1)]
        [Object]
        $item
    )

    $tries = 0
    do
    {
        $tries++
        try
        {
            $item.SaveAs($pfObj.TempFileName, $pfObj.SaveType)
            $pfObj.Saved2Temp = $true
        }
        catch
        {
            if($tries -eq $Script:MaxSaveRetries)
            {
                LogError ("Failed to save: {0} EntryID: [{1}] to {2} ({3})" -f @($pfObj.Subject, $pfObj.EntryID, $pfObj.TempFileName, $pfObj.SaveType.ToString()))
                $pfObj.Good2Go = $false
                UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Failed to save item to temp file."
            } `
            else # NOT ($tries -eq $Script:MaxRetries)
            {
                Start-Sleep -Milliseconds $Script:SaveDelayInMS
            }
        }
    } while((-not $pfObj.Saved2Temp) -and ($tries -lt $Script:MaxSaveRetries))
}

function UpdateTempFileStats
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $pfObj,

        [Parameter(Mandatory = $true, Position = 1)]
        [Object]
        $item
    )

    if($pfObj.Saved2Temp)
    {
        try
        {
            $fi = [System.IO.FileInfo]::new($pfObj.TempFileName)
            if($fi.Exists)
            {
                $Script:ReturnObject.ExportedItems.Count++
                $Script:ReturnObject.ExportedItems.Size += $fi.Length
            } `
            else
            {
                LogError ("Failed to verify {0}/{1} was saved to {2}" -f @($pfObj.Subject, $pfObj.EntryID, $pfObj.TempFileName))
                $pfObj.Good2Go = $false
                UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Failed to verify temp save."
            }
        }
        catch
        {
            # Nothing, no big deal if I don't get the file size.
        }

        # Set the creation time on the saved file.
        if($null -ne $pfObj.CreationTime)
        {
            try
            {
                [System.IO.File]::SetCreationTime($pfObj.TempFileName, $pfObj.CreationTime)
            }
            catch
            {
                # Nothing, just trapping the exception.
            }
        } `
        else
        {
            # Nothing, can't set the creation time if I don't have one.
        }

        # If the item has a .LastModificationTime, then set the last write time on the file.
        #   Also, if there was no .CreationTime, then use .LastModificationTime as the date to sort conversation messages
        if($null -ne $pfObj.LastModificationTime)
        {
            try
            {
                [System.IO.File]::SetLastWriteTime($pfObj.TempFileName, $pfObj.LastModificationTime)
            }
            catch
            {
                # Nothing, just trapping the exception.
            }
        } `
        else
        {
            # Nothing, can't set the last modifiy time without one...
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function SavePublicFolderItemsToLocalFolder
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $publicFolder
    )

    $Script:ReturnObject.ExportedItems.Count = 0
    $Script:ReturnObject.ExportedItems.Size = 0

    # For faster and more reliable access to the data I need, get a table for the folder items.
    $table = $null
    try
    {
        $table = $publicFolder.GetTable()
        $Script:ReturnObject.Good2Go = ($null -ne $table)
    }
    catch
    {
        LogException ("Failed to get item table for folder: {0} ({1})" -f @($Script:ExportedPublicFolderPath, $publicFolder.EntryID))
        $Script:ReturnObject.Good2Go = $false
    }

    if($Script:ReturnObject.Good2Go)
    {
        $rowCount = $table.GetRowCount()
        $sw = [System.Diagnostics.Stopwatch]::new()
        $sw.Start()

        $table.MoveToStart()
        $activity = "Collecting Item data for {0}..." -f @($Script:ExportedPublicFolderPath)
        $rowNumber = 0
        while(-not $table.EndOfTable)
        {
            $elapsedTicks = $sw.ElapsedTicks
            $ticksPerItem = $elapsedTicks / ($Script:ReturnObject.ExportedItems.Count + 1)
            $totalETATicks = $ticksPerItem * $rowCount
            $remainingETATicks = $totalETATicks - $elapsedTicks
            $etaTS = [TimeSpan]::new($remainingETATicks)
            $etaDT = [DateTime]::Now.Add($etaTS)

            $percentComplete = ($Script:ReturnObject.ExportedItems.Count + 1) / $rowCount
            $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @(($Script:ReturnObject.ExportedItems.Count + 1), $rowCount, $percentComplete, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))
            Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($percentComplete * 100.0)

            $row = $table.GetNextRow()
            $rowNumber++
            if($null -ne $row)
            {
                $entryID = [String]::Empty
                try
                {
                    $entryID = $row["EntryID"]
                }
                catch
                {
                    LogException ("Failed to get row entry ID.")
                    $entryID = [String]::Empty      # Ensure the following IF statement falls through to the else on exeption
                    $Script:ReturnObject.Good2Go = $false
                }

                if(-not [String]::IsNullOrEmpty($entryID))
                {
                    $item = GetItemFromOutlookByEntryID -entryID $entryID

                    if($null -ne $item)
                    {
                        if(-not [String]::IsNullOrEmpty($item.EntryID))
                        {
                            $pfObj = NewPublicFolderObjectFromItem -item $item -fileIndex $Script:PublicFolderItems.Count

                            if($null -ne $pfObj)
                            {
                                $Script:PublicFolderItems.Add($pfObj)

                                # Create a new list of public folder objects for $pfObj.ConversationID if one doesn't already exist.
                                #   NOTE:  $pfObj will always have a .ConversationID since NewPublicFolderObjectFromItem ensure it is set.
                                if(-not $Script:ItemsByConversation.ContainsKey($pfObj.ConversationID))
                                {
                                    $Script:ItemsByConversation.Add($pfObj.ConversationID, [System.Collections.Generic.List[System.Object]]::new())
                                } `
                                else
                                {
                                    # Nothing, $Script:ItemsByConversation already has a conversation list for this conversation.
                                }
                                # Add $pfObj to $Script:ItemsByConversation[$pfObj.ConversationID]
                                $i = $Script:ItemsByConversation[$pfObj.ConversationID].BinarySearch($pfObj, $Script:PFObjectConversationIndexComparer)
                                if($i -lt 0)
                                {
                                    $i = -bnot $i
                                }
                                $Script:ItemsByConversation[$pfObj.ConversationID].Insert($i, $pfObj)

#                                $Script:ItemsByConversation[$pfObj.ConversationID].Add($pfObj)

                                SavePublicFolderItemToTempFile -pfObj $pfObj -item $item

                                if($pfObj.Saved2Temp)
                                {
                                    UpdateTempFileStats -pfObj $pfObj -item $item
                                } `
                                else # NOT ($pfObj.Saved2Temp)
                                {
                                    LogWarning ("Not updating file information for unsaved item: {0}" -f @($pfObj.TempFileName))
                                }
                            } `
                            else # NOT ($null -ne $pfObj)
                            {
                                LogError ("Null public folder object returned from NewPublicFolderObjectFromItem for entry ID: {0}" -f @($item.EntryID))
                            }
                        } `
                        else # NOT (-not [String]::IsNullOrEmpty($item.EntryID))
                        {
                            LogError ("Item with null .EntryID returned from NewPublicFolderObjectFromItem for public folder {0} [{1}] and row entryID: {2}" -f @($Script:ExportedPublicFolderPath, $publicFolder.EntryID, $entryID))
                            $Script:ReturnObject.Good2Go = $false
                        }
                    } `
                    else # NOT ($null -ne $item)
                    {
                        LogError ("Failed to get item from Outlook for public folder {0} [{1}] row entryID: {2}" -f @($Script:ExportedPublicFolderPath, $publicFolder.EntryID, $entryID))
                        $Script:ReturnObject.Good2Go = $false
                    }
                } `
                else # NOT (-not [String]::IsNullOrEmpty($entryID))
                {
                    LogError ("Null entry ID for row number: {0}" -f @($rowNumber))
                }
            } `
            else # NOT ($null -ne $row)
            {
                if(-not $table.EndOfTable)
                {
                    LogError ("Null row prior to end to table.  Row number: {0}" -f @($rowNumber))
                    $Script:ReturnObject.Good2Go = $false
                } `
                else # NOT (-not $table.EndOfTable)
                {
                    # Nothing, at the end of the table.
                }
            }
        }
        $sw.Stop()
        Write-Progress -Id 1 -Activity $activity -Completed

        LogInfo ("Exported {0} items in {1}." -f @($Script:ReturnObject.ExportedItems.Count, $sw.Elapsed.ToString()))
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        LogError ("No item table available for public folder: {0} ({1})" -f @($Script:ExportedPublicFolderPath, $publicFolder.EntryID))
    }
}

function SetSubjectForPWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $prefix,

        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [String]
        $senderName,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]
        $subject,

        [Parameter(Mandatory = $true, Position = 3)]
        [String]
        $extension,

        [Parameter(Mandatory = $false, Position = 4)]
        [Int32]
        $idxNum = -1
    )

    $subjLength = $subject.Length

    if([String]::IsNullOrEmpty($senderName))
    {
        # This deals with $senderName -eq $null
        $senderName = [String]::Empty
    } `
    else # NOT ([String]::IsNullOrEmpty($senderName))
    {
        # Nothing.
    }

    if([String]::IsNullOrEmpty($prefix))
    {
        # This deals with $senderName -eq $null
        $prefix = [String]::Empty
    } `
    else # NOT ([String]::IsNullOrEmpty($senderName))
    {
        # Nothing.
    }

<#
    if($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4} ({5}).{6}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $idxNum, $extension)
    } `
    else # NOT ($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4}.{5}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $extension)
    }
#>

if($idxNum -gt -1)
{
    $pwPath = "{0}{1}{2} ({3}).{4}" -f @($prefix, $senderName, $subject, $idxNum, $extension)
} `
else # NOT ($idxNum -gt -1)
{
    $pwPath = "{0}{1}{2}.{3}" -f @($prefix, $senderName, $subject, $extension)
}

#    if($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    if($pwPath.Length -gt 120)
    {
        $subjCharactersToRemove = $pwPath.Length - 120
        if($subjCharactersToRemove -gt 0)
        {
            $subjLength -= $subjCharactersToRemove
            if($subjLength -lt 0)
            {
                $subjLength = 0
            } `
            else # NOT ($subjLength -lt 0)
            {
                # Nothing.
            }
        } `
        else # NOT ($subjCharactersToRemove -gt 0)
        {
            LogError ("Unable to create a viable ProjectWise path for {0}." -f @($pwPath))
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    {
        # Nothing.
    }

    return $subject.Substring(0, $subjLength)
}

function MakeMessagePath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Int32]
        $conversationIdx,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $conversationCount,

        [Parameter(Mandatory = $true, Position = 2)]
        [Int32]
        $itemIdx,

        [Parameter(Mandatory = $true, Position = 3)]
        [Int32]
        $itemCount,

        [Parameter(Mandatory = $true, Position = 4)]
        [Object]
        $pfObj,

        [Parameter(Mandatory = $true, Position = 5)]
        [bool]
        $isPartOfConversation
    )
    <#
        .SYNOPSIS
        Creates a file name from the parameters provided.

        .DESCRIPTION
        Creates a well formed file name using the paramaters.

        If $conversationCount is greater than 1, the file name will contain "Conv X".  Where X is left padded with spaces to ensure all numbers align and sort correctly.
        If $itemCount is greater than 1, the file name will contain "Msg X of Y".  Where X and Y are left padded with spaces to ensure all numbers align and sort correctly.
        All invalid characters in $subject will be replaced with "_".  Additionally, spaces will be trimmed from the start and end of the subject.  If $subject is null or empty "NO_SUBJECT" will be used.
        Finally, file name will begin with the full path of $Script:WorkingFolder.

        See the examples below.

        .PARAMETER conversationIdx
        The nth conversation in the folder (1 based)

        .PARAMETER conversationCount
        The number of conversations

        .PARAMETER itemIdx
        The nth item of the conversation (0 based)

        .PARAMETER itemCount
        The number of items in the conversation

        .PARAMETER pfObj
        Data take from the mail item we are working with.  See NewConversationObjectFromItem

        .INPUTS
        None.  You can't pipe objects to MakeMessagePath.

        .OUTPUTS
        [String] A well formed file name

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 6 -itemIdx 3 -itemCount 12 -subject "Final call for reports"
        C:\TEMP\Conv 1 of 6 | Msg  4 of 12 | Final call for reports.msg"

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 1 -itemIdx 0 -itemCount 212 -subject "Final call for reports"
        C:\TEMP\Msg   1 of 212 | Final call for reports.msg"

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 1 -itemIdx 0 -itemCount 1 -subject "Final call for reports"
        C:\TEMP\Final call for reports.msg"
    #>

    # Already fixed up .SenderName when we made $pfObj
    $senderName = $pfObj.SenderName
    if(-not [String]::IsNullOrEmpty($senderName))
    {
        $senderName = "{0} {1} " -f @($senderName, [char] 9474)
    } `
    else # NOT (-not [String]::IsNullOrEmpty($pfObj.SenderName))
    {
        # Nothing
    }

    $prefix = [String]::Empty
    if($isPartOfConversation)
    {
        $conversationCntLength = $conversationCount.ToString().Length
        $itemCountLength = $itemCount.ToString().Length

        if($conversationCount -gt 1)
        {
            $prefix = $Script:ConversationPrefix -f @($conversationCntLength, [char] 9474)   # [char] 9474 is a vertical line character.  However, putting the character itself in the script causes PS some issues.
            $prefix = $prefix -f @($conversationIdx)
        }

        $prefix = "{0}{1}" -f @($prefix, ($Script:MessagePrefix -f @($itemCountLength, [char] 9474)))
        $prefix = $prefix -f @(($itemIdx + 1), $itemCount)
    } `
    else # NOT ($isPartOfConversation)
    {
        # Nothing, no conversation, no prefix.
    }

    # Add different extensions as needed...
    $extension = "msg"
    if($pfObj.SaveType -eq [Microsoft.Office.Interop.Outlook.olSaveAsType]::olVCard)
    {
        $extension = "vcf"
    } `
    else
    {
        # Nothing, stick with msg
    }

    # Already fixed up .Subject when we created $pfObj
    $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $pfObj.Subject -extension $extension
    $fileName = "{0}\{1}{2}{3}.{4}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $extension)
    $i = $Script:UniqueImportFileNames.BinarySearch($fileName)

    # Append (x) to the file name if a file is already tagged to be named $fileName
    $idxNum = 1

    # If $i -ge 0, then the perspective file name has already been used.
    while($i -ge 0)
    {
        $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $pfObj.Subject -idxNum $idxNum -extension $extension
        $fileName = "{0}\{1}{2}{3} ({4}).{5}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $idxNum, $extension)
        $i = $Script:UniqueImportFileNames.BinarySearch($fileName)
        $idxNum++
    }

    if($i -lt 0)
    {
        $Script:UniqueImportFileNames.Insert(-bnot $i, $fileName)
    } `
    else # NOT ($i -lt 0)
    {
        LogError ("Unable to create a unique file name for: {0}")
        $pfObj.Good2Go = $false
        UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Unable to create a unique file name"
        $fileName = [String]::Empty
    }

    <#   OLD WAY
    while(@($Script:ItemsByConversation.Values | Where-Object { $_.FileName -eq $fileName }).Length -gt 0)
    {
        $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $originalSubject -idxNum $idxNum -extension $extension
        $fileName = "{0}\{1}{2}{3} ({4}).{5}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $idxNum, $extension)
        $idxNum++
    }
    #>

    return $fileName
}

function SetPublicFolderConversationObjectsFileNames
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.Generic.List[System.Object]]
        $pfObjs,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $conversationIdx,

        [Parameter(Mandatory = $true, Position = 2)]
        [Int32]
        $conversationCount
    )

    if($null -ne $pfObjs)
    {
        if($pfObjs.Count -gt 0)
        {
            $uniqueConversationIDs = @($pfObjs | Select-Object -Unique -ExpandProperty ConversationID)

            # Make sure all pfObjs have the same .ConversationID
            if($uniqueConversationIDs.Length -eq 1)
            {
                $isPartOfConversation = $pfObjs[0].ConversationID -ne "NO_CONVERSATION"
                $c = 0
                while($c -lt $pfObjs.Count)
                {
                    $newFileName = MakeMessagePath -conversationIdx $conversationIdx -conversationCount $conversationCount -itemIdx $c -itemCount $pfObjs.Count -pfObj $pfObjs[$c] -isPartOfConversation $isPartOfConversation

                    if(-not [String]::IsNullOrEmpty($newFileName))
                    {
                        $pfObjs[$c].FileName = $newFileName
                    } `
                    else # NOT (-not [String]::IsNullOrEmpty($newFileName))
                    {
                        LogError ("Null/empty file name created for: {0}/{1}" -f @($pfObjs[$c].EntryID, $pfObjs[$c].Subject))
                        $pfObjs[$c].Good2Go = $false
                        UpdatePublicFolderObjectStatus -pfObj $pfObjs[$c] -status "Null file name created."
                    }

                    $c++
                }
            } `
            else # NOT (@($pfObjs | Where-Object { $_.ConversationID -ne $pfObjs[0].ConversationID }).Length -eq 0)
            {
                $Script:ReturnObject.Good2Go = $false
                LogError ("Mismatched conversation IDs in SetMessageFileNames.  Conversation IDs: {0}" -f @(($uniqueConversationIDs -join ", ")))
            }
        } `
        else # NOT ($pfObjs.Length -gt 0)
        {
            LogWarning ("No public folder objects to set file names.")
        }
    } `
    else # NOT ($null -ne $pfObjs)
    {
        LogError ("Null message list in SaveMessages.")
        $Script:ReturnObject.Good2Go = $false
    }
}

function SetPublicFolderObjectFileNames
{
    if($Script:ReturnObject.Good2Go)
    {
        if($null -ne $Script:ItemsByConversation)
        {
            if($Script:ReturnObject.ExportedItems.Count -gt 0)
            {
                if($Script:ItemsByConversation.Count -gt 0)
                {
                    LogInfo ("Calculating actual file names...")
                    # Now rename all the files using conversation number, message number, item sender and subject.
                    $uniqueConversationIDs = @(@($Script:ItemsByConversation.Keys) | Where-Object { $_ -ne "NO_CONVERSATION" })
                    $conversationCount = $uniqueConversationIDs.Length
                    LogInfo ("Unique conversations: {0}" -f @($conversationCount))

                    <#
                        When renaming the message files, do so by conversation in creation time (or last modified time if creation time isn't available) order.

                        The idea here is to have Conv 1 = the oldest conversation, even if some of its messages are newer than others.
                    #>

                    # Create a dictionary of conversation IDs by SortTime.  Exclude messages which are not part of a conversation
                    #   Key = creation/last mod date/time (.SortTime) of the first message in the conversation.
                    #   Value = List of all the conversation IDs whose first conversation message has the same .SortTime
                    $conversationIDsBySortTime = [System.Collections.Generic.SortedDictionary[DateTime, System.Collections.Generic.List[String]]]::new()

                    $a = 0
                    while($a -lt $uniqueConversationIDs.Length)
                    {
                        # Find the oldest message in the conversation which has .ConversationID -eq $uniqueConversationIDs[$a]
                        #    $Script:ItemsByConversation[$uniqueConversationIDs[$a]] is guaranteed to always have at least 1 item in the list, or we'd not have had $uniqueConversationIDs[$a] as a key use...
                        #    Also, since we are building $Script:ItemsByConversation[$uniqueConversationIDs[$a]] in .ConversationIndex order, [0] will always be the first.
                        $firstConversationItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]][0]
#                            $firstConversationItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]] | Sort-Object -Property SortTime | Select-Object -First 1
                        if(-not $conversationIDsBySortTime.ContainsKey($firstConversationItem.SortTime))
                        {
                            $conversationIDsBySortTime.Add($firstConversationItem.SortTime, [System.Collections.Generic.List[String]]::new())
                        } `
                        else
                        {
                            # Nothing
                        }

                        # $uniqueConversationIDs is already sorted since it's based on the keys from $Script:ItemsByConversation, so adding it will result in a sorted list.
                        #  Since we are looping through $uniqueConversationIDs, $uniqueConversationIDs[$a] will only ever get added to 1 list.
                        $conversationIDsBySortTime[$firstConversationItem.SortTime].Add($uniqueConversationIDs[$a])

                        $a++
                    }
                    <#
                        After the above code, we might have a conversation date which matches a message which is NOT part of a conversation.  However, we will not have any .ConversationIDs in
                           $conversationIDsBySortTime which are "NO_CONVERSATION"

                        Therefore, when I use $conversationIDsBySortTime.Keys ($conversationDates) as a loop counter, I will never end up in a situation where:

                            $Script:ItemsByConversation[$conversationIDsBySortTime[$conversationDates[$a]][$b]] results in an item with "NO_CONVERSATION" as its .ConversationID.

                        Furthermore, since the above is true, when I rename the items which do NOT have .ConversationID -eq "NO_CONVERSATION", it's safe to assume every item is
                           part of a conversation, so for every conversation ID in $conversationIDsBySortTime is a new conversation, so increment $conversationIdx every time.
                    #>

                    # If there are messages which are not part of a conversation, rename them first.
                    if($Script:ItemsByConversation.ContainsKey("NO_CONVERSATION"))
                    {
                        # Since these messages are not part of a conversation, $conversationIdx and $conversationCount don't mean anything.
                        SetPublicFolderConversationObjectsFileNames -pfObjs $Script:ItemsByConversation["NO_CONVERSATION"] -conversationIdx 0 -conversationCount 0
                    } `
                    else # NOT ($Script:ItemsByConversation.ContainsKey("NO_CONVERSATION"))
                    {
                        # Nothing.
                    }

                    if($Script:ReturnObject.Good2Go)
                    {
                        # Loop through the conversations, oldest to newest...
                        $conversationDates = @($conversationIDsBySortTime.Keys)
                        # $a in the loop index for all the various .SortTime values found in the first message of each conversation.  It's not a representation
                        #     of the conversation number.  Multiple conversations' first messages could share the same .SortTime.
                        $a = 0

                        # Unlike $a, $conversationIdx is the conversation number for a particular list of messages.
                        $conversationIdx = 1

                        while($a -lt $conversationDates.Length)
                        {
                            # Process all the conversations where the first message in the conversation has a .SortTime -eq $conversationDates[$a]
                            $b = 0
                            while($b -lt $conversationIDsBySortTime[$conversationDates[$a]].Count)
                            {
                                # Process all the messages that are part of conversation ID: $conversationIDsBySortTime[$conversationDates[$a]][$b]
                                $conversationMessages = $Script:ItemsByConversation[$conversationIDsBySortTime[$conversationDates[$a]][$b]]

                                SetPublicFolderConversationObjectsFileNames -pfObjs $conversationMessages -conversationIdx $conversationIdx -conversationCount $conversationCount

                                # See above (and good luck understanding) why incrementing $conversationIdx each time is safe.
                                $conversationIdx++

                                $b++
                            }
                            $a++
                        }
                    } `
                    else # NOT ($Script:ReturnObject.Good2Go)
                    {
                        # Nothing, already logged an error.
                    }
                } `
                else # NOT ($Script:ItemsByConversation.Count -gt 0)
                {
                    LogError "No item conversations in RenameLocalFiles."
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else # NOT ($Script:ReturnObject.ExportedItems.Count -gt 0)
            {
                # Nothing saved to the local disk..
            }
        } `
        else # NOT ($null -ne $Script:ItemsByConversation)
        {
            LogError "No items by conversation in RenameLocalFiles."
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}

function RenameLocalFiles
{
    if($Script:ReturnObject.Good2Go)
    {
        if($null -ne $Script:PublicFolderItems)
        {
            LogInfo "Renaming temporary files..."
            $a = 0
            while($a -lt $Script:PublicFolderItems.Count)
            {
                $pfObj = $Script:PublicFolderItems[$a]

                if($pfObj.Good2Go)
                {
                    if($pfObj.Saved2Temp)
                    {
                        if(-not [String]::IsNullOrEmpty($pfObj.FileName))
                        {
                            try
                            {
                                $oldFI = [System.IO.FileInfo]::new($pfObj.TempFileName)
                                if($oldFI.Exists)
                                {
                                    try
                                    {
                                        [System.IO.File]::Move($pfObj.TempFileName, $pfObj.FileName)

                                        try
                                        {
                                            $newFI = [System.IO.FileInfo]::new($pfObj.FileName)
                                            if($newFI.Exists)
                                            {
                                                $pfObj.Renamed = $true
                                                # LogInfo ("Renamed {0} to {1}" -f @($oldFI.Name, $newFI.Name))    # This is very chatty
                                            } `
                                            else # NOT ($newFI.Exists)
                                            {
                                                LogError ("Renamed message file {0} does not exist.." -f @($pfObj.FileName))
                                                $pfObj.Good2Go = $false
                                                UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Failed to verify rename."
                                            }
                                        }
                                        catch
                                        {
                                            LogError ("Failed to get file information for {0}." -f @($newFileName))
                                            $Script:ReturnObject.Good2Go = $false
                                        }
                                    }
                                    catch
                                    {
                                        LogError ("Failed to rename {0} to {1}." -f @($pfObj.TempFileName, $newFileName))
                                        $Script:ReturnObject.Good2Go = $false
                                    }
                                } `
                                else # NOT ($oldFI.Exists)
                                {
                                    LogError ("Message file {0} does not exist.." -f @($pfObj.TempFileName))
                                    $Script:ReturnObject.Good2Go = $false
                                }
                            }
                            catch
                            {
                                LogError ("Failed to get file information for {0}." -f @($pfObj.TempFileName))
                                $Script:ReturnObject.Good2Go = $false
                            }
                        } `
                        else # NOT (-not [String]::IsNullOrEmpty($newFileName))
                        {
                            LogError ("Null/empty file name created for: {0}/{1}" -f @($pfObj.EntryID, $pfObj.Subject))
                            $pfObj.Good2Go = $false
                            UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Null/empty file name"
                        }
                    } `
                    else # NOT ($pfObj.Good2Go)
                    {
                        # Nothing, would have already logged an error
                    }
                } `
                else # NOT ($pfObj.Saved2Temp)
                {
                    # Nothing, would have already logged an error
                }

                $a++
            }
        } `
        else # NOT ($null -ne $Script:PublicFolderItems)
        {
            $Script:ReturnObject.Good2Go = $false
            LogError ("`$Script:PublicFolderItems is null in RenameLocalFiles")
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}

function SavePFObjectsAndImportResults
{
    if([System.IO.Directory]::Exists($Script:ResultsFolder))
    {
        if([String]::IsNullOrEmpty($Script:pfObjsFileName) -or [String]::IsNullOrEmpty($Script:importResultsFilename))
        {
            do
            {
                $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
                $Script:pfObjsFilename = "{0}\{1}-{2}-PFObjects.json" -f @($Script:ResultsFolder, $Script:ReturnObject.PublicFolder.EntryID, $ts)
                $Script:importResultsFilename = "{0}\{1}-{2}-ImportResults.json" -f @($Script:ResultsFolder, $Script:ReturnObject.PublicFolder.EntryID, $ts)

                if(($resultsExist = ([System.IO.File]::Exists($Script:pfObjsFilename) -or [System.IO.File]::Exists($Script:importResultsFilename))))
                {
                    Start-Sleep -Seconds 1
                } `
                else # NOT ([System.IO.File]::Exists($Script:pfObjsFilename) -or [System.IO.File]::Exists($Script:importResultsFilename))
                {
                    # Nothing.
                }
            } while($resultsExist)
        } `
        else # NOT ([String]::IsNullOrEmpty($Script:pfObjsFileName) -or [String]::IsNullOrEmpty($Script:importResultsFilename))
        {
            # Nothing.
        }

        if(($null -ne $Script:PublicFolderItems) -and ($Script:PublicFolderItems.Count -gt 0))
        {
            LogInfo "Saving PFObjs..."
            try
            {
                $Script:PublicFolderItems | ConvertTo-Json -ErrorAction Stop | Set-Content -Path $Script:pfObjsFilename -Force -ErrorAction Stop
            }
            catch
            {
                LogWarning ("Unable to save pfObjects to file: {0}" -f @($Script:pfObjsFilename))
            }
        } `
        else # NOT (($null -ne $Script:PublicFolderItems) -and ($Script:PublicFolderItems.Count -gt 0))
        {
            # Nothing.
        }

        if(($null -ne $Script:ImportResults) -and ($Script:ImportResults.Count -gt 0))
        {
            LogInfo "Saving ImportResults..."
            try
            {
                $Script:ImportResults | ConvertTo-Json -ErrorAction Stop | Set-Content -Path $Script:importResultsFilename -Force -ErrorAction Stop
            }
            catch
            {
                LogWarning ("Unable to save import results to file: {0}" -f @($Script:importResultsFilename))
            }
        } `
        else # NOT (($null -ne $Script:ImportResults) -and ($Script:ImportResults.Count -gt 0))
        {
            # Nothing.
        }
    } `
    else # NOT ([System.IO.Directory]::Exists($Script:BaseWorkingFolder))
    {
        # Nothing.
    }
}

function ExportPublicFolderItemsAsFiles
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Object]
        $publicFolder
    )

    <#
        Accessing $publicFolder.Items is a slow process.... So I want enumerate .Items only once.

        I want to name files using the following rules:
            If a message is part of a conversation, that is, it has a .ConversationID and there are multiple messages in the conversation, then the file name will be:
                Conv X | Msg Y of Z | SenderName | Subject
            All messages which have no .ConversationID will be considered a part of "NO_CONVERSATION"
        However, until all items in the folder are enumerated, I won't have all the conversation data.  To prevent looping through .Items multiple times I'll:
            1. Collect the relevant data from each item
            2. Save the item to the local drive using a temporary name "FILE_xxxxx.msg" and record the name along with the collected data
        Once all required data is collected, I'll rename the temporary files based on conversations and message subject.
    #>
    LogInfo ("`tExporting {0} as individual files." -f @($publicFolder.Name))

    # First, save all the items in the folder to disk using a temporary name and create a dictionary of conversations.
    SavePublicFolderItemsToLocalFolder -publicFolder $publicFolder
    SavePFObjectsAndImportResults

    SetPublicFolderObjectFileNames
    SavePFObjectsAndImportResults

    # Now that all the conversation data has been collected, the file names have been set, it's time to rename all the message files according to conversation/message number.
    RenameLocalFiles
    SavePFObjectsAndImportResults
}

function SetWorkingFolder
{
    if($Script:ReturnObject.Good2Go)
    {
        # Validate working folder...
        if([String]::IsNullOrEmpty($Script:BaseWorkingFolder))
        {
            $Script:WorkingFolder = [System.IO.Path]::GetTempPath()
        } `
        else
        {
            $Script:WorkingFolder = $Script:BaseWorkingFolder
        }

        try
        {
            $tmpFolder = [System.IO.DirectoryInfo]::new($Script:WorkingFolder)
        }
        catch
        {
            LogError ("Unable to use {0} as a temporary working folder." -f @($Script:WorkingFolder))
            $Script:ReturnObject.Good2Go = $false
        }

        if($Script:ReturnObject.Good2Go)
        {
            # The following code creates a unique folder under $Script:WorkingFolder based on the current date/time.  If a folder with the purposed name
            #    already exists, the script sleeps a bit to allow some time to pass, and tries again.  Once a folder name without an existing folder is found,
            #    the new folder is created.
            do
            {
                $testWorkFolder = "{0}\PFWork-{1}" -f @($tmpFolder.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar), [DateTime]::Now.ToString("yyyyMMddHHmmss"))
                $workFolderExists = $false

                try
                {
                    $workFolderExists = [System.IO.Directory]::Exists($testWorkFolder)
                }
                catch
                {
                    LogError ("Unable to determine if work folder: {0} exists." -f @($testWorkFolder))
                    $Script:ReturnObject.Good2Go = $false
                }

                if($Script:ReturnObject.Good2Go)
                {
                    if($workFolderExists)
                    {
                        Start-Sleep -Milliseconds 333
                    } `
                    else
                    {
                        # Nothing, the preposed working folder does not exist.
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }
            } while($Script:ReturnObject.Good2Go -and $workFolderExists)

            if($Script:ReturnObject.Good2Go)
            {
                # Create the temporary working folder...
                try
                {
                    $null = [System.IO.Directory]::CreateDirectory($testWorkFolder)
                    $Script:WorkingFolder = $testWorkFolder
                    LogInfo ("Created temporary working folder: {0}" -f @($Script:WorkingFolder))
                }
                catch
                {
                    LogError ("Failed to create temporary work folder: {0}" -f @($testWorkFolder))
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else # NOT ($Script:ReturnObject.Good2Go)
            {
                # Nothing, already logged an error
            }
        } `
        else # NOT ($Script:ReturnObject.Good2Go)
        {
            # Nothing, already logged an error
        }
    } `
    else
    {
        # Nothing, already displayed a message.
    }
}

function ExportPublicFolderToDisk
{
    $Script:ReturnObject.PublicFolder.EntryID = FixEntryID -entryIDtoFix $Script:PFEntryID
    $Script:ReturnObject.ExportedItems.Count = 0

    $publicFolder = $null
    try
    {
        $publicFolder = $Script:OutlookNamespace.GetFolderFromID($Script:ReturnObject.PublicFolder.EntryID)
    }
    catch
    {
        LogError ("Public folder entry ID: {0} not found." -f @($Script:ReturnObject.PublicFolder.EntryID))
        $Script:ReturnObject.Good2Go = $false
    }

    if($null -ne $publicFolder)
    {
        # Make sure the public folder has not been deleted.
        if($publicFolder.FolderPath -notmatch "DUMPSTER_ROOT")
        {
            # Remove the leading "\\Public Folders - xxx@ddd.com\All Public Folders" from the folder path.
            $Script:ExportedPublicFolderPath = FixFileOrPath -fileOrPath $publicFolder.FolderPath.Replace($Script:topPublicFolder.FolderPath, "").Trim([System.IO.Path]::DirectorySeparatorChar)
            $Script:ReturnObject.PublicFolder.Name = $Script:ExportedPublicFolderPath.Replace("\Outlook Public Folders\", "")

            $Script:ReturnObject.PublicFolder.ItemCount = $publicFolder.Items.Count

            if($Script:ReturnObject.PublicFolder.ItemCount -gt 0)
            {
                LogInfo ("Exporting Public Folder: {0}" -f @($Script:ExportedPublicFolderPath))

                # Create a temporary working folder for this public folder export.
                SetWorkingFolder

                if($Script:ReturnObject.Good2Go)
                {
                    $Script:ReturnObject.PublicFolder.Type = ($publicFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType]).ToString()

                    if(($publicFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType]) -eq [Microsoft.Office.Interop.Outlook.OlItemType]::olAppointmentItem)
                    {
                        ExportPublicFolderItemsAsIcs -publicFolder $publicFolder
                    } `
                    else
                    {
                        ExportPublicFolderItemsAsFiles -publicFolder $publicFolder
                    }
                } `
                else # NOT ($Script:ReturnObject.Good2Go)
                {
                    # Nothing, already logged an error.
                }
            } `
            else # NOT ($Script:ReturnObject.PublicFolder.ItemCount -gt 0)
            {
                LogInfo ("Not exporting empty public folder: {0}" -f @($Script:ExportedPublicFolderPath))
                $Script:ReturnObject.Process.Status = "Empty"
            }
        } `
        else
        {
            LogInfo ("Public folder entry ID: {0} has been deleted.  Not exporting." -f @($Script:PFEntryID))
            $Script:ReturnObject.Process.Status = "Public folder deleted."
        }
    } `
    else
    {
        # Nothing, already logged an error
    }
}

function VerifyCreatePWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $path,

        [Parameter(Mandatory = $false, Position = 1)]
        [Switch]
        $Create
    )

    $pwFolderExists = $true

    if(-not [String]::IsNullOrEmpty($path))
    {
        LogInfo ("Verifying ProjectWise path: {0}" -f @($path))

        if($Create.IsPresent)
        {
            $sw = [System.Diagnostics.Stopwatch]::new()
            $sw.Start()
            $haveLock = $false
            do
            {
                try
                {
                    # Create a lock file so no other process tries to verify/create this path while I am.
                    $fLock = [System.IO.File]::Open("\\boifs1\itxchange\klbtest\PWCreateLock.lck", [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                    $haveLock = $true
                }
                catch
                {
                    # Failed to acquire the lock.  Assume another process has the lock file
                    # Sleep a bit to allow the other process to complete its work.
                    Start-Sleep -Milliseconds 10
                }
            } while((-not $haveLock) -and ($sw.ElapsedMilliseconds -lt $Script:MaxFileStreamRetryPeriodMS))
            $sw.Stop()
        } `
        else # NOT ($Create.IsPresent)
        {
            $haveLock = $true     # Not really, but since we aren't creating anything, we don't need it...but the code below need it to be $true
        }

        if($haveLock)
        {
            if($Create.IsPresent)
            {
                # Write a simple log to the lock file.
                $pathStr = "{0}`r`n" -f @($path)
                $uniEncoding = [System.Text.UnicodeEncoding]::new()
                $textLength = $uniEncoding.GetByteCount($pathStr)
                $null = $fLock.Seek(0, [System.IO.SeekOrigin]::End)
                $fLock.Write($uniEncoding.GetBytes($pathStr), 0, $textLength)
            } `
            else # NOT ($Create.IsPresent)
            {
                # Nothing.
            }

            $subFolders = $path.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)

            if($subFolders.Length -gt 0)
            {
                $testPWFolderPath = "\{0}" -f @($Script:ProjectWiseBaseFolder.Name)
                $subFolderIdx = 0
                do
                {
                    $testPWFolderPath = "{0}\{1}" -f @($testPWFolderPath, $subFolders[$subFolderIdx])
                    try
                    {
                        # Verify the ProjectWise folder exists...
                        $pwFolder = Get-PWFolders -FolderPath $testPWFolderPath -JustOne -ErrorAction Stop -WarningAction SilentlyContinue
                        $pwFolderExists = ($null -ne $pwFolder)
                    }
                    catch
                    {
                        $pwFolderExists = $false
                    }

                    if(-not $pwFolderExists)
                    {
                        if($Create.IsPresent)
                        {
                            try
                            {
                                $pwFolder = New-PWFolder -FolderPath $testPWFolderPath -ErrorAction Stop
                                $pwFolderExists = ($null -ne $pwFolder)
                                if($pwFolderExists)
                                {
                                    LogInfo ("Created ProjectWise folder: {0}" -f @($testPWFolderPath))
                                } `
                                else
                                {
                                    LogWarning ("Failed to create ProjectWise folder: {0}" -f @($testPWFolderPath))
                                }
                            }
                            catch
                            {
                                $pwFolderExists = $false
                            }

                            if(-not $pwFolderExists)
                            {
                                LogError ("Unable to create ProjectWise folder: {0}" -f @($testPWFolderPath))
                                $Script:ReturnObject.Good2Go = $false
                            } `
                            else
                            {
                                # Nothing, all is well.
                            }
                        } `
                        else # NOT ($Create.IsPresent)
                        {
                            # Nothing.
                        }
                    } `
                    else
                    {
                        # Nothing, continue down the subfolders...
                    }

                    $subFolderIdx++
                } while($Script:ReturnObject.Good2Go -and $pwFolderExists -and ($subFolderIdx -lt $subFolders.Length))
                $Script:ReturnObject.Good2Go = $Script:ReturnObject.Good2Go -and ((-not $Create.IsPresent) -or ($Create.IsPresent -and $pwFolderExists))

                if($Create.IsPresent -and $Script:ReturnObject.Good2Go -and $pwFolderExists)
                {
                    $Script:ReturnObject.ProjectWise.ImportFolder = $testPWFolderPath
                } `
                else # NOT ($Script:ReturnObject.Good2Go)
                {
                    # Nothing, already logged an error.
                }
            } `
            else
            {
                LogError ("Splitting [{0}] on '{1}' resulted in no sub folders." -f @($path, [System.IO.Path]::DirectorySeparatorChar))
                $Script:ReturnObject.Good2Go = $false
            }

            if($Create.IsPresent)
            {
                # Finally, we can't forget to release the lock so others get their chance.
                $fLock.Close()
            } `
            else # NOT ($Create.IsPresent)
            {
                # Nothing.
            }
        } `
        else # NOT ($haveLock)
        {
            LogError ("Failed to acqure PWCreateLock after 30 seconds.")
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else
    {
        LogError "Null/empty path set to VerifyCreatePWPath."
        $Script:ReturnObject.Good2Go = $false
    }

    return $pwFolderExists
}

function RemoveUselessFolder
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $path
    )

    $filesInFolder = @(Get-ChildItem -Path $path -ErrorAction Stop | Where-Object { $_.Extension -ne ".json"})

    # If there is nothing left in the folder, then delete $importFolder
    if($filesInFolder.Length -eq 0)
    {
        LogInfo ("Removing 'useless' folder: {0}" -f @($path))
        try
        {
            [System.IO.Directory]::Delete($path, $true)
        }
        catch
        {
            LogWarning ("Failed to delete empty 'useless' folder: {0}." -f @($path))
        }
    } `
    else # NOT ($filesInFolder.Length -eq 0)
    {
        LogWarning ("'Useless' folder: {0} is no empty" -f @($path))
    }
}

function ImportFolderToProjectWise
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $importFolder
    )

    if($Script:ReturnObject.Good2Go)
    {
        # Make sure we are still connected to ProjectWise
        ConnectToProjectWise
        $importFolderDI = $null
        try
        {
            $importFolderDI = [System.IO.DirectoryInfo]::new($importFolder)
        }
        catch
        {
            LogError ("Unable to validate import folder: {0}" -f @($importFolder))
            $Script:ReturnObject.Good2Go = $false
        }

        if(($null -ne $importFolderDI) -and $importFolderDI.Exists)
        {
            LogInfo ("`tImporting {0} to ProjectWise..." -f @($importFolder))
            # First import the files into ProjectWise...
            $result = ReTryCatch -callee "Import-PWDocuments" -funcParameters @{InputFolder = $importFolder; ProjectWiseFolder = $Script:ReturnObject.ProjectWise.ImportFolder; MultiThreaded = $true; ExcludeSourceDirectoryFromTargetPath = $true; Overwrite = $true}
            $Script:ReturnObject.Good2Go = $result.Good2Go

            if($Script:ReturnObject.Good2Go)
            {
                $importedFiles = $result.ReturnValue
                LogInfo ("Removing {0} imported files..." -f @($importedFiles.Length))

                $filesInImportFolder = $null
                try
                {
                    $filesInImportFolder = @(Get-ChildItem -Path $importFolder -ErrorAction Stop | Where-Object { $_.Extension -ne ".json" })
                }
                catch
                {
                    LogError ("Failed to retrieve files in import folder: {0}." -f @($importFolder))
                }

                # Process the list of files that were successfully imported into ProjectWise
                $importedFiles.ForEach({
                    $i = $_

                    $Script:ImportResults.Add($i)

                    # Delete the file from local storage...
                    if($null -ne $filesInImportFolder)
                    {
                        $importedFile = $filesInImportFolder | Where-Object { $_.Name -eq $i.FileName }

                        # If the file name is too long, PW truncates it and appends a random string... so let's get a bit tricky on locating the file.
                        if($null -eq $importedFile)
                        {
                            # First, let's get all files with a matching size....
                            $testFilesBySize = @($filesInImportFolder | Where-Object { $_.Length -eq $i.FileSize })

                            if($testFilesBySize.Length -gt 0)
                            {
                                # Ok, now let's compare the file name with the imported file name, shortening the file name by 1 until we find matches...

                                # ProjectWise replaces my [char]9474 characters with [char]166 ... so reverse that...
                                $testFileName = [System.IO.Path]::GetFileNameWithoutExtension($i.FileName).Replace([char]166, [char]9474)
                                $testFilesBySizeAndName = @()
                                while((-not [String]::IsNullOrEmpty($testFileName)) -and ($testFilesBySizeAndName.Length -eq 0))
                                {
                                    $testFilesBySizeAndName = @($testFilesBySize | Where-Object { $_.BaseName.StartsWith($testFileName) })

                                    # If we didn't find the file, then shorten the test file name some more...
                                    if($testFilesBySizeAndName.Length -eq 0)
                                    {
                                        # Only try to shorten the test file name if it's longer than 1 character...
                                        if($testFileName.Length -gt 1)
                                        {
                                            $testFileName = $testFileName.SubString(0, $testFileName.Length - 1)
                                        } `
                                        else # NOT ($testFileName.Length -gt 1)
                                        {
                                            $testFileName = [String]::Empty
                                        }
                                    } `
                                    else # NOT ($testFilesBySizeAndName.Length -eq 0)
                                    {
                                        # Nothing.
                                    }
                                }

                                if($testFilesBySizeAndName.Length -eq 1)
                                {
                                    $importedFile = $testFilesBySizeAndName[0]
                                } `
                                else # NOT ($testFilesBySizeAndName.Length -eq 1)
                                {
                                    LogWarning ("Unable to find a single file matching: {0} (Size: {1}) [1]" -f @($i.FileName, $i.FileSize))
                                }
                            } `
                            else # NOT ($testFiles.Length -gt 0)
                            {
                                LogWarning ("Unable to locate any imported file with size: {0}" -f @($i.FileSize))
                            }
                        } `
                        else # NOT ($null -eq $importedFile)
                        {
                            # Nothing... found the file we are looking for.
                        }

                        if($null -ne $importedFile)
                        {
                            $pfObj = $Script:PublicFolderItems | Where-Object { $_.FileName.EndsWith($importedFile.Name) }
                            if($null -ne $pfObj)
                            {
                                $pfObj.Imported = $true
                                $pfObj.ImportedFileName = $i.FileName    # The name ProjectWise assigned the file.  Normally this will match, but if the path is too long, it might be altered.
                            } `
                            else
                            {
                                LogWarning ("Unable to find a public folder item matching: {0}" -f @($importedFile.Name))
                            }

                            try
                            {
                                $importedFile.Delete()
                                if($null -ne $pfObj)
                                {
                                    $pfObj.Deleted = $true
                                } `
                                else # NOT ($null -ne $pfObj)
                                {
                                    # Nothing.
                                }
                            }
                            catch
                            {
                                # For now, just trap the exception.
                            }
                        } `
                        else
                        {
                            LogWarning ("Extra file imported??? {0}" -f @($_.FileName))
                        }
                    } `
                    else # NOT ($null -ne $filesInImportFolder)
                    {
                        # Nothing.
                    }

                    $Script:ReturnObject.ImportedItems.Count++
                    $Script:ReturnObject.ImportedItems.Size += $i.FileSize
                })

                # After deleting all the imported files, see if there is anything "useful" left in the folder and if not, remove it.
                RemoveUselessFolder -path $importFolder
            } `
            else
            {
                LogError ("Failed to import {0} files to ProjectWise" -f @($Script:ExportedPublicFolderPath))
            }
        } `
        else # NOT (($null -ne $importFolderDI) -and $importFolderDI.Exists)
        {
            # Nothing.
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function CreateIntermediateTempFolder
{
    $importFolderName = "{0}\ImportToPW-{1}" -f @($Script:WorkingFolder, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
    try
    {
        [System.IO.Directory]::CreateDirectory($importFolderName) | Out-Null
        LogInfo ("Using intermediate temp folder for import: {0}" -f @($importFolderName))
    }
    catch
    {
        LogError ("Failed to create temporary import folder: {0}" -f @($importFolderName))
        $Script:ReturnObject.Good2Go = $false
    }

    return $importFolderName
}

function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KB","MB","GB","TB","PB","EB","ZB","YB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}

function ImportFilesToProjectWise
{
    if($Script:ReturnObject.Good2Go)
    {
        if($Script:ReturnObject.ExportedItems.Count -gt 0)
        {
            if($null -ne $Script:PublicFolderItems)
            {
                if($Script:PublicFolderItems.Count -gt 0)
                {
                    $exportedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
                    $a = 0
                    while($a -lt $Script:PublicFolderItems.Count)
                    {
                        $pfObj = $Script:PublicFolderItems[$a]
                        if($pfObj.Good2Go)
                        {
                            if($pfObj.Saved2Temp)
                            {
                                if($pfObj.Renamed)
                                {
                                    try
                                    {
                                        $fi = [System.IO.FileInfo]::new($pfObj.FileName)
                                    }
                                    catch
                                    {
                                        LogError ("{0} not found." -f @($pfObj.FileName))
                                        $pfObj.Good2Go = $false
                                        UpdatePublicFolderObjectStatus -pfObj $pfObj "File not found during import"
                                        $fi = $null
                                    }

                                    if($null -ne $fi)
                                    {
                                        $exportedFiles.Add($fi)
                                    } `
                                    else # NOT ($null -ne $fi)
                                    {
                                        # Nothing.
                                    }
                                } `
                                else # NOT ($pfObj.Renamed)
                                {
                                    # Nothing.
                                }
                            } `
                            else # NOT ($pfObj.Saved2Temp)
                            {
                                # Nothing.
                            }
                        } `
                        else # NOT ($pfObj.Good2Go)
                        {
                            # Nothing.
                        }

                        $a++
                    }
                } `
                else # NOT ($Script:PublicFolderItems.Count -gt 0)
                {
                    # Nothing.
                }
            } `
            else # NOT ($null -ne $Script:PublicFolderItems)
            {
                # Nothing.
            }
<#
            $exportedFiles = @()


            try
            {
                $exportedFiles = @(Get-ChildItem -Path $Script:WorkingFolder -File -ErrorAction Stop)
            }
            catch
            {
                LogError ("Failed to retrieve files to import into ProjectWise from {0}." -f @($Script:WorkingFolder))
                $Script:ReturnObject.Good2Go = $false
            }
#>
            if($Script:ReturnObject.Good2Go)
            {
                if($exportedFiles.Count -gt 0)
                {
                    LogInfo ("Found {0} items to import into ProjectWise." -f @($exportedFiles.Count))

                    $pwFolderPath = $Script:ExportedPublicFolderPath

                    # Verify the existence of the corresponding folder structure in ProjectWise, creating any missing folders.
                    if((VerifyCreatePWPath -path $pwFolderPath -Create))
                    {
                        if($Script:ReturnObject.Good2Go)
                        {
                            LogInfo ("Importing items into ProjectWise folder: {0}" -f @($Script:ReturnObject.ProjectWise.ImportFolder))

#                            # If there are too many files to import at once, let's break them into chunks.
#                            if($exportedFiles.Length -gt $Script:MaxFilesPerImport)
#                            {
                                $importFolderName = CreateIntermediateTempFolder
                                if($Script:ReturnObject.Good2Go)
                                {
                                    $a = 0
                                    while($Script:ReturnObject.Good2Go -and ($a -lt $exportedFiles.Count))
                                    {
                                        $newFileName = "{0}\{1}" -f @($importFolderName, $exportedFiles[$a].Name)
                                        try
                                        {
                                            [System.IO.File]::Move($exportedFiles[$a].FullName, $newFileName)
                                        }
                                        catch
                                        {
                                            LogError ("Failed to move {0} to {1}." -f @($exportedFiles[$a].FullName, $newFileName))
                                            $Script:ReturnObject.Good2Go = $false
                                        }

                                        $a++

                                        # After moving $Script:MaxFilesPerImport files (or the last file) into the ImportToPW folder:
                                        #    1. Import the files in ImportToPW into ProjectWise
                                        #    2. Delete all the files in ImportToPW
                                        if($Script:ReturnObject.Good2Go -and (($a % $Script:MaxFilesPerImport) -eq 0) -or ($a -eq $exportedFiles.Count))
                                        {
                                            ImportFolderToProjectWise -importFolder $importFolderName

                                            if($a -lt $exportedFiles.Count)
                                            {
                                                # After importing the folder, if there are more files to import, create another temporary folder
                                                $importFolderName = CreateIntermediateTempFolder    # while loop will check $Script:ReturnObject.Good2Go
                                            } `
                                            else # NOT ($a -lt $exportedFiles.Count)
                                            {
                                                # Nothing.
                                            }
                                        } `
                                        else
                                        {
                                            # Nothing, keep going until an error occured, we put 1000 items in the import folder, or we get to the end...
                                        }
                                    }
                                } `
                                else # NOT ($Script:ReturnObject.Good2Go)
                                {
                                    # Nothing.
                                }
#                            } `
#                            else
#                            {
#                                ImportFolderToProjectWise -importFolder $Script:WorkingFolder
#                            }

                            if($Script:ReturnObject.Good2Go)
                            {
                                LogInfo ("Imported {0} items totalling {1}" -f @($Script:ReturnObject.ImportedItems.Count, (Format-StorageNumber $Script:ReturnObject.ImportedItems.Size)))
                            } `
                            else
                            {
                                # Nothing, already logged an error.
                            }
                        } `
                        else
                        {
                            # Nothing, already displayed a message.
                        }
                    } `
                    else # NOT (VerifyCreatePWPath -path $pwFolderPath -Create)
                    {
                        # Nothing.
                    }
                } `
                else
                {
                    LogError ("No files found in {0} to import into ProjectWise." -f @($Script:WorkingFolder))
                    $Script:ReturnObject.Good2Go = $false
                }
            } `
            else
            {
                # Nothing, already displayed an error
            }
        } `
        else # NOT ($Script:ReturnObject.ExportedItems.Count -gt 0)
        {
            LogInfo "No files exported from public folder.  Skipping import to ProjectWise."
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}

function TransferPublicFolderToProjectWise
{
    ExportPublicFolderToDisk

    if($Script:ReturnObject.Good2Go)
    {
        if(-not $Script:LocalOnly.IsPresent)
        {
            if($Script:ReturnObject.ExportedItems.Count -gt 0)
            {
                ImportFilesToProjectWise
            } `
            else
            {
                LogInfo "No items exported, skipping ProjectWise import."
            }

            if([System.IO.Directory]::Exists($Script:WorkingFolder))
            {
                # After deleting all the imported files, see if there is anything "useful" left in the folder and if not, remove it.
                RemoveUselessFolder -path $Script:WorkingFolder
            } `
            else # NOT ([System.IO.Directory]::Exists($Script:WorkingFolder))
            {
                # Nothing.
            }
        } `
        else
        {
            LogInfo "Skipping import to ProjectWise."
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function UpdateListOfExportedPublicFolders
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object]
        $exportData
    )

    if($null -ne $exportData)
    {
        $haveFileStream = $false
        $sw = [System.Diagnostics.Stopwatch]::new()
        $sw.Start()
        $fs = $null

        do
        {
            try
            {
                $fs = [System.IO.FileStream]::new($Script:ListOfExportedPublicFoldersFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $haveFileStream = ($null -ne $fs)
            }
            catch
            {
                if($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    LogError ("Failed to open a file stream to {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                } `
                else # NOT ($sw.ElapsedMilliseconds -ge $Script:MaxFileStreamRetryPeriodMS)
                {
                    # Wait a bit and try again.

                    Start-Sleep -Milliseconds 10
                }
            }
        } while($Script:ReturnObject.Good2Go -and (-not $haveFileStream))
        $sw.Stop()

        if($haveFileStream)
        {
            # Assume we have to write the header line to the export file.
            $startLine = 0

            # If the file is longer than 0 bytes, then assume the header has already been written...
            if($fs.Length -gt 0)
            {
                $startLine++
            } `
            else # NOT ($fs.Length -gt 0)
            {
                # Nothing.
            }

            $sWriter = $null

            try
            {
                $sWriter = [System.IO.StreamWriter]::new($fs)
            }
            catch
            {
                LogException "Failed to create stream reader from file stream."
                $Script:ReturnObject.Good2Go = $false
            }

            if($null -ne $sWriter)
            {
                try
                {
                    $exportCSV = @($exportData | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation -ErrorAction Stop)

                    $a = $startLine
                    while($Script:ReturnObject.Good2Go -and ($a -lt $exportCSV.Length))
                    {
                        try
                        {
                            $sWriter.WriteLine($exportCSV[$a])
                        }
                        catch
                        {
                            LogException ("Failed to add: {0} to {1}." -f @($exportCSV[$a], $Script:ListOfExportedPublicFoldersFile))
                            $Script:ReturnObject.Good2Go = $false
                        }
                        $a++
                    }
                }
                catch
                {
                    LogException ("Failed to read export data header from {0}." -f @($Script:ListOfExportedPublicFoldersFile))
                    $Script:ReturnObject.Good2Go = $false
                }

                $sWriter.Close()
            } `
            else # NOT ($null -ne $sWriter)
            {
                # Nothing.
            }

            $fs.Close()
        } `
        else # NOT ($haveFileStream)
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $publicFolder)
    {
        LogError "Null export data in UpdateListOfExportedPublicFolder."
        $Script:ReturnObject.Good2Go = $false
    }
}

<#
    FinishExport save key data to files.  It really has nothing to do with the actual export/import process.
#>
function FinishExport
{
    SavePFObjectsAndImportResults

    if($Script:ReturnObject.Good2Go)
    {
        if([String]::IsNullOrEmpty($Script:ReturnObject.Process.Status))
        {
            $Script:ReturnObject.Process.Status = "Success"
        } `
        else # NOT ([String]::IsNullOrEmpty($Script:ReturnObject.Process.Status))
        {
            # Nothing.
        }
    } `
    else
    {
        if([String]::IsNullOrEmpty($Script:ReturnObject.Process.Status))
        {
            $Script:ReturnObject.Process.Status = "Failed"
        } `
        else # NOT ([String]::IsNullOrEmpty($Script:ReturnObject.Process.Status))
        {
            # Nothing.
        }
    }

    $Script:ReturnObject.PublicFolder.Name = $Script:ExportedPublicFolderPath.Replace("\Outlook Public Folders\", "")
    $Script:ReturnObject.Process.End = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff")

    $d = [PSCustomObject]@{
        Success = $Script:ReturnObject.Good2Go
        ExportStarted = $Script:ReturnObject.Process.Start
        ExportEnded = $Script:ReturnObject.Process.End
        ExportStatus = $Script:ReturnObject.Process.Status
        EntryID = $Script:ReturnObject.PublicFolder.EntryID
        PFName = $Script:ReturnObject.PublicFolder.Name
        PFType = $Script:ReturnObject.PublicFolder.Type
        ItemCount = $Script:ReturnObject.PublicFolder.ItemCount
        ExportCount = $Script:ReturnObject.ExportedItems.Count
        ExportSize = $Script:ReturnObject.ExportedItems.Size
        ImportCount = $Script:ReturnObject.ImportedItems.Count
        ImportSize = $Script:ReturnObject.ImportedItems.Size
    }

    UpdateListOfExportedPublicFolders -exportData $d
    # $d | Export-CSV -Delimiter "`t" -NoTypeInformation -Append -Path "C:\TEMP\T2\ListOfExportedPublicFolders.csv" -ErrorAction Stop
}

function ExportPublicFolder
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object]
        $publicFolderIdentity
    )

    if(-not (PublicFolderHasBeenExported -entryID $publicFolderIdentity.EntryID))
    {
        if(-not (PublicFolderActivelyBeingExported -entryID $publicFolderIdentity.EntryID))
        {

        } `
        else # NOT (PublicFolderActivelyBeingExported -entryID $publicFolderIdentity.EntryID)
        {
            # Nothing.
        }
        $Script:PFEntryID = $publicFolderIdentity.EntryId
        # Reset $Script:ReturnObject back to factory defaults
        ResetScriptObjects -PFEntryID $publicFolderIdentity.EntryId

        if($Script:ReturnObject.Good2Go)
        {
            # Proceed with transferring items from public folders to ProjectWise...
            LogInfo ("Starting export of public folder: {0} ({1})" -f @($publicFolderIdentity.Identity, $publicFolderIdentity.EntryId))

            # Export the public folder to the local disk then import it into ProjectWise
            TransferPublicFolderToProjectWise

            # Do 'Stuff' with the results
            FinishExport
        } `
        else
        {
            # Nothing, already logged an error.
        }
    } `
    else # NOT (-not (PublicFolderHasBeenExported -entryID $publicFolderIdentity.EntryID))
    {
        LogInfo ("Public folder {0} [{1}] has already been successfully exported." -f @($publicFolderIdentity.Identity, $publicFolderIdentity.EntryID))
    }
}

function CleanUp()
{
    LogInfo ("Cleaning up after ourself...")
    # If we are connected to ProjectWise, then disconnect
    try
    {
        $null = Get-PWCurrentDSSession -ErrorAction Stop

        try
        {
            Undo-PWLogin -ErrorAction Stop | Out-Null
            LogInfo "Disconnected from ProjectWise"
        }
        catch
        {
            LogWarning ("Failed to logout of ProjectWise.")
            # Do not set $Script:ReturnObject.Good2Go to $false since this is not a fatal error.
        }
    }
    catch
    {
        # Nothing... not connected
    }

    try
    {
        if($null -ne $Script:OutlookNamespace)
        {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Script:OutlookNamespace) | Out-Null
            LogInfo "Released Outlook MAPI namespace object"
        } `
        else
        {
            # Nothing...
        }
    } catch { }

    try
    {
        if($null -ne $Script:OutlookApp)
        {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Script:OutlookApp) | Out-Null
            LogInfo "Released Outlook application object"
        } `
        else
        {
            # Nothing...
        }
    } catch { }
}

function main
{
    if([System.IO.Directory]::Exists($Script:BaseWorkingFolder))
    {
        if(-not [System.IO.Directory]::Exists($Script:ResultsFolder))
        {
            try
            {
                [System.IO.Directory]::CreateDirectory($Script:ResultsFolder)
            }
            catch
            {
                LogException ("Unable to create folder {0}." -f @($Script:ResultsFolder))
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else # NOT (-not [System.IO.Directory]::Exists($Script:ResultsFolder))
        {
            # Nothing.
        }

        if($Script:ReturnObject.Good2Go)
        {
            try
            {
                # Always make sure $pfList is an Array...
                $pfList = @(Import-CSV -Path $Script:publicFolderListFile -Delimiter "`t" -ErrorAction Stop)
            }
            catch
            {
                LogError ("Failed to load list of public folder to transfer from: {0}." -f @($publicFolderListFile))
                $Script:ReturnObject.Good2Go = $false
            }

            if($Script:ReturnObject.Good2Go)
            {
                LogInfo ("Processing {0} public folder entries." -f @($pfList.Length))

                InitializeExporter

                if($Script:ReturnObject.Good2Go)
                {
                    # Proceed with transferring items from public folders to ProjectWise...
                    $pfListIdx = 0
                    # Don't stop the remaining exports if something went wrong with one.  ExportPublicFolder will reset $Script:ReturnObject.Good2Go each time it runs.
                    while($pfListIdx -lt $pfList.Length)
                    {
                        $percentComplete = ($pfListIdx / $pfList.Length)
                        $status = "{0,7:P2} Complete | Exported: {1} | Remaining: {2}" -f @($percentComplete, $pfListIdx, ($pfList.Length - $pfListIdx))
                        Write-Progress -Id 0 -Activity "Xfering PFs to PW..." -Status $status -PercentComplete ($percentComplete * 100.0)

                        ExportPublicFolder -publicFolderIdentity $pfList[$pfListIdx]
                        $pfListIdx++
                    }
                } `
                else
                {
                    # Nothing, already logged an error.
                }

                CleanUp
            } `
            else # NOT ($Script:ReturnObject.Good2Go)
            {
                # Nothing.
            }
        } `
        else # NOT ($Script:ReturnObject.Good2Go)
        {
            # Nothing.
        }
    } `
    else # NOT ([System.IO.Directory]::Exists($Script:BaseWorkingFolder))
    {
        LogException ("Base working folder: {0} does not exist.  Please create and retry." -f @($Script:BaseWorkingFolder))
        $Script:ReturnObject.Good2Go = $false
    }
}

main
