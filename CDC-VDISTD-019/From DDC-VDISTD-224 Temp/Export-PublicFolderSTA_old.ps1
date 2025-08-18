<#
    This script will export a public folder to a local folder then upload the local folder to ProjectWise.

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

    [Parameter(Mandatory = $false, Position = 6)]
    [AllowEmptyString()]
    [String]
    $LogFolder,

    [Parameter(Mandatory = $false, Position = 7)]
    [AllowEmptyString()]
    [String]
    $BaseWorkingFolder
)

# Import the ProjectWise powershell module.
Import-Module -Name PWPS_DAB -Force -DisableNameChecking

$Script:LogFileNamePrefix = "ExportPF"

. C:\Users\kbriney\Documents\LogFunctions.ps1
. C:\Users\kbriney\Documents\RetryCatch.ps1

$Script:ListOfExportedPublicFoldersFile = "\\boifs1\ITxchange\klbtest\ListOfExportedPublicFolders.csv"

$Script:DoDebugging = $true

# Maximum length of a ProjectWise path
$Script:MaximumProjectWisePathLength = 201

# Maximum number of time to try to get an item from Exchange.
$Script:MaxItemGetRetries = 5

# How long to delay between attempt to retrieve an item from Exchange.
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
    LogFile = [String]::Empty
    WorkFolder = [String]::Empty
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

$Script:WorkingFolderCreated = $false

$Script:OutlookApp = $null
$Script:OutlookNamespace = $null

# Folder which regex match any of the included strings will be ignored.
$Script:IgnoredFolders = @("All Public Folders\\ExchsyncSecurityFolder","All Public Folders\\Internet Newsgroups")

# Characters which are illegal in file names
$Script:BadFilenameChars = [System.IO.Path]::GetInvalidFileNameChars()

# Character which are illegal in paths.
$Script:BadPathChars = [System.IO.Path]::GetInvalidPathChars()

$Script:topPublicFolder = $null
$Script:ExportedPublicFolderPath = [String]::Empty

$Script:ProjectWiseBaseFolder = $null

# Move out of function...
$Script:ConversationPrefix = "Conv {{0,{0}}} {1} "
$Script:MessagePrefix = "Msg {{0,{0}}} of {{1,{0}}} {1} "

# Dictionary of public folder items by entryID
$Script:PublicFolderItems = $null

# Dictionary of lists of public folder items by conversation ID
$Script:ItemsByConversation = $null

# Maximum number of files to import at once to ProjectWise
$Script:MaxFilesPerImport = 1000

# This is the .EntryID of the public folder where other public folders which have been exported will be moved to so the script doesn't process them again.  (NOT IMPLEMENTED)
$Script:RootExportedPublicFolderEntryID = "000000009598E9A20E04F041B38518182890A2D5010012225CC57BF01F4EA8CCA87A792FF35F000800ECECE90000"

$Script:EntryIDPrefix = [String]::Empty
<#
    Seems the .EntryID of an object is dependent on the user looking at the object.
        Since I export the list of folders via ExchangeOnline powershell cmdlets (to avoid timeouts),
        I have to "fix" .EntryID for each object accessed via my normal Outlook user credentials.

        For any given .EntryID, the first 44 characters always match, so I'll get the .EntryID for the top level
        public folder and use it's .EntryID (first 44 characters) to create the .EntryID I need for this script.

        Example:

        Exported using ExchangeOnline cmdlets using POWERENG\kbriney-adm account
            .EntryID =    "000000009598E9A20E04F041B38518182890A2D50100A3DF33FCC9BD1644BD14FCA330AA978500002C9DB2BF0000"
            .FolderPath = "\Divisions\ENV\Environmental Boise\142963 TSCHACHE LANE WETLAND DELIN"

        If try to .GetFolderFromID using the EntryID, the call fails.

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
        $Script:PublicFolderItems = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()
    } `
    else # NOT ($null -eq $Script:PublicFolderItems)
    {
        $Script:PublicFolderItems.Clear()
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
}

function InitializeExporter
{
    LogInfo "Initializing public folder exporter..."

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

function ResetOutlook
{
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Script:OutlookNamespace) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Script:OutlookApp) | Out-Null

    $Script:OutlookApp = [System.Activator]::CreateInstance([Type]::GetTypeFromProgID("Outlook.Application"))
    $Script:OutlookNamespace = $Script:OutlookApp.GetNameSpace("MAPI")
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
                    $Script:WorkingFolderCreated = $true
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

function RemoveWorkingFolder
{
    # Clean up the working folder...
    if($Script:WorkingFolderCreated -and (-not [String]::IsNullOrEmpty($Script:WorkingFolder)))
    {
        $di = [System.IO.DirectoryInfo]::new($Script:WorkingFolder)
        if($di.Exists)
        {
            try
            {
                # Delete the working folder and all files therein.
                [System.IO.Directory]::Delete($Script:WorkingFolder, $true)
                LogInfo ("Removed working folder/files: {0}" -f @($Script:WorkingFolder))
                $Script:WorkingFolderCreated = $false    # I mean, we did just un-create the working folder after all.
            }
            catch
            {
                LogError ("Failed to remove all or part of working folder: {0}" -f @($Script:WorkingFolder))
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else # NOT ($di.Exists)
        {
            # Nothing.
        }
    } `
    else
    {
        # Nothing, must not have gotten far enough to create a working folder...
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

<#
    FixFileName replaces any invalid characters in a file name with '_'
#>
function FixFileName
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $filename
    )

    if(-not [String]::IsNullOrEmpty($filename))
    {
        $filename = $filename.Trim()
        do
        {
            $x = $filename.IndexofAny($Script:BadFilenameChars)
            if($x -ge 0)
            {
                $filename = $filename.Remove($x, 1)
            } `
            else
            {
                # Nothing
            }
        } while($x -ge 0)
    } `
    else
    {
        # Nothing, can't replace invalid characters in an empty string...
    }

    return $filename
}


function FixPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $path
    )

    if(-not [String]::IsNullOrEmpty($path))
    {
        do
        {
            $x = $path.IndexofAny($Script:BadPathChars)
            if($x -ge 0)
            {
                $path = $path.Remove($x, 1)
            } `
            else
            {
                # Nothing
            }
        } while($x -ge 0)
    } `
    else
    {
        # Nothing, can't replace invalid characters in an empty string...
    }

    return $path
}

function SetSubjectForPWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $prefix,

        [Parameter(Mandatory = $true, Position = 1)]
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

    if($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4} ({5}).{6}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $idxNum, $extension)
    } `
    else # NOT ($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4}.{5}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $extension)
    }
    if($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    {
        $subjCharactersToRemove = $pwPath.Length - $Script:MaximumProjectWisePathLength
        if($subjCharactersToRemove -gt 0)
        {
            $subject = $subject.SubString(0, $subject.Length - $subjCharactersToRemove)
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

    return $subject
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

    $originalSubject = FixFileName $pfObj.Subject
    $senderName = FixFileName $pfObj.SenderName
    if(-not [String]::IsNullOrEmpty($senderName))
    {
        $senderName = "{0} {1} " -f @($senderName, [char] 9474)
    } `
    else # NOT (-not [String]::IsNullOrEmpty($senderName))
    {
        # Nothing.
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

    $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $originalSubject -extension $extension

    $fileName = "{0}\{1}{2}{3}.{4}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $extension)

    # Append (x) to the file name if a file is already tagged to be named $fileName
    $idxNum = 1
    while(@($Script:ItemsByConversation.Values | Where-Object { $_.FileName -eq $fileName }).Length -gt 0)
    {
        $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $originalSubject -idxNum $idxNum -extension $extension
        $fileName = "{0}\{1}{2}{3} ({4}).{5}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $idxNum, $extension)
        $idxNum++
    }

    return $fileName
}

function NewPublicFolderObjectFromEntryID
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $entryID,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $fileIndex
    )

    $convObj = [PSCustomObject]@{
        PublicFolderPath = $Script:ExportedPublicFolderPath
        RowEntryID = $entryID       #  It seems when an item is retrieved via .GetItemFromID, the entryID of the returned item does not match the value used to retrieve it.
        EntryID = $entryID
        Status = [String]::Empty
        LastModificationTime = $null
        CreationTime = $null
        Subject = $null
        SaveType = [Microsoft.Office.Interop.Outlook.olSaveAsType]::olMSG
        TempFileIndex = $fileIndex
        TempFileName = "{0}\File_{1:D5}.msg" -f @($Script:WorkingFolder, $fileIndex)
        FileName = [String]::Empty
        SortTime = $null
        Saved = $false
        ConversationID = "NO_CONVERSATION"
        ConversationIndex = $null
        SenderName = $null
        Saved2Temp = $false
        Renamed = $false
        Imported = $false
        Good2Go = $true
    }

    return $convObj
}

function UpdatePublicFolderObjectFromItem
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

    if($null -ne $pfObj)
    {
        if($null -ne $item)
        {
            $pfObj.EntryID = $item.EntryID   # Since the entryID used to get the item is different than what is returned, I'll update .EntryID here.
            $pfObj.LastModificationTime = $item.LastModificationTime
            $pfObj.CreationTime = $item.CreationTime
            $pfObj.Subject = $item.Subject
            $pfObj.SortTime = $item.CreationTime
            $pfObj.ConversationIndex = $item.ConversationIndex
            $pfObj.SenderName = $item.SenderName

            # For different save types as I find them...
            switch($item.MessageClass)
            {
                "IPM.Contact" {
                    $pfObj.SaveType = [Microsoft.Office.Interop.Outlook.olSaveAsType]::olVCard
                    $pfObj.TempFileName = "{0}\File_{1:D5}.vcf" -f @($Script:WorkingFolder, $pfObj.TempFileIndex)
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
                # Nothing.
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
            $pfObj.Good2Go = $false
            UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Null item in NewConversationObjectFromItem"
        }
    } `
    else # NOT ($null -ne $convObj)
    {
        LogError "Null conversation object in UpdateConversationObjectFromItem"
    }
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
        $tries = 0
        do
        {
            $tries++
            try
            {
                $item = $Script:OutlookNamespace.GetItemFromID($entryID)
            }
            catch
            {
                if($tries -eq $Script:MaxItemGetRetries)
                {
                    LogError ("Failed to retrieve item with entryID: {0}" -f @($entryID))
                    $Script:ReturnObject.Good2Go = $false
                } `
                else # NOT ($tries -eq $Script:MaxRetries)
                {
                    LogInfo ("Retrying ({0}) GetItemFromID({1})" -f @($tries, $entryID))
                    Start-Sleep -Milliseconds $Script:ItemGetDelay
                }
            }
        }  while(($null -eq $item) -and ($tries -lt $Script:MaxItemGetRetries))
    } `
    else # NOT (-not [String]::IsNullOrEmpty($entryID))
    {
        LogError "Null/Empty entry ID in GetItemFromOutlookByEntryID."
    }

    return $item
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
        while($Script:ReturnObject.Good2Go -and (-not $table.EndOfTable))
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
                    if(-not $Script:PublicFolderItems.ContainsKey($entryID))
                    {
                        $pfObj = NewPublicFolderObjectFromEntryID -entryID $entryID -fileIndex $Script:PublicFolderItems.Count
                        if($null -ne $pfObj)
                        {
                            $Script:PublicFolderItems.Add($entryID, $pfObj)

                            $item = GetItemFromOutlookByEntryID -entryID $entryID
                            if($null -ne $item)
                            {
                                UpdatePublicFolderObjectFromItem -pfObj $Script:PublicFolderItems[$entryID] -item $item

                                # Create a new list of public folder objects for $Script:PublicFolderItems[$entryID].ConversationID if one doesn't already exist.
                                if(-not $Script:ItemsByConversation.ContainsKey($Script:PublicFolderItems[$entryID].ConversationID))
                                {
                                    $Script:ItemsByConversation.Add($Script:PublicFolderItems[$entryID].ConversationID, [System.Collections.Generic.List[System.Object]]::new())
                                } `
                                else
                                {
                                    # Nothing, $Script:ItemsByConversation already has a conversation list for this conversation.
                                }
                                # Add $Script:PublicFolderItems[$entryID] to $Script:ItemsByConversation[$Script:PublicFolderItems[$entryID].ConversationID]
                                $Script:ItemsByConversation[$Script:PublicFolderItems[$entryID].ConversationID].Add($Script:PublicFolderItems[$entryID])

                                SavePublicFolderItemToTempFile -pfObj $Script:PublicFolderItems[$entryID] -item $item

                                # Even if -not $Script:PublicFolderItems[$entryID].Good2Go, still try to set the file stats just incase we can manually fix something.
                                UpdateTempFileStats -pfObj $Script:PublicFolderItems[$entryID] -item $item
                            } `
                            else # NOT ($null -ne $item)
                            {
                                $Script:PublicFolderItems[$entryID].Good2Go = $false
                                UpdatePublicFolderObjectStatus -pfObj $Script:PublicFolderItems[$entryID] -status "No item returned from Outlook"
                            }
                        } `
                        else # NOT ($null -ne $pfObj)
                        {
                            LogError ("Null public folder object returned from NewPublicFolderObjectFromEntryID of entry ID: {0}" -f @($entryID))
                        }
                    } `
                    else # NOT (-not $Script:PublicFolderItems.ContainsKey($entryID))
                    {
                        LogError("Duplicate entry ID: {0} in SavePublicFolderItemsToLocalFolder" -f @($entryID))
                        $Script:PublicFolderItems[$entryID].Good2Go = $false
                        UpdatePublicFolderObjectStatus -pfObj $Script:PublicFolderItems[$entryID] -status "Duplicate entry ID"
                    }
                } `
                else # NOT (-not [String]::IsNullOrEmpty($entryID))
                {
                    # Nothing, already logged an exception
                }
            } `
            else # NOT ($null -ne $row)
            {
                if(-not $table.EndOfTable)
                {
                    LogError ("Null row prior to end to table.")
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

        if($Script:ReturnObject.Good2Go)
        {
            LogInfo ("Exported {0} items in {1}." -f @($Script:ReturnObject.ExportedItems.Count, $sw.Elapsed.ToString()))
        } `
        else # NOT ($Script:ReturnObject.Good2Go)
        {
            # Nothing.
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        LogError ("No item table available for folder: {0} ({1})" -f @($Script:ExportedPublicFolderPath, $publicFolder.EntryID))
        $Script:ReturnObject.Good2Go = $false
    }
}

function SetPublicFolderConversationObjectsFileNames
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object[]]
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
        if($pfObjs.Length -gt 0)
        {
            $uniqueConversationIDs = @($pfObjs | Select-Object -Unique -ExpandProperty ConversationID)

            # Make sure all pfObjs have the same .ConversationID
            if($uniqueConversationIDs.Length -eq 1)
            {
                $isPartOfConversation = $pfObjs[0].ConversationID -ne "NO_CONVERSATION"
                $c = 0
                while($c -lt $pfObjs.Length)
                {
                    $newFileName = MakeMessagePath -conversationIdx $conversationIdx -conversationCount $conversationCount -itemIdx $c -itemCount $pfObjs.Length -pfObj $pfObjs[$c] -isPartOfConversation $isPartOfConversation

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

function RenameMessages
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Object[]]
        $messages,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $conversationIdx,

        [Parameter(Mandatory = $true, Position = 2)]
        [Int32]
        $conversationCount
    )

    if($null -ne $messages)
    {
        if($messages.Length -gt 0)
        {
            $isPartOfConversation = $messages[0].ConversationID -ne "NO_CONVERSATION"
            $c = 0
            while($c -lt $messages.Length)
            {
                $newFileName = MakeMessagePath -itemsByConversation $Script:ItemsByConversation -conversationIdx $conversationIdx -conversationCount $conversationCount -itemIdx $c -itemCount $messages.Length -item $messages[$c] -isPartOfConversation $isPartOfConversation

                if($Script:ReturnObject.Good2Go)
                {
                    if(-not [String]::IsNullOrEmpty($newFileName))
                    {
                        try
                        {
                            $oldFI = [System.IO.FileInfo]::new($messages[$c].TempFileName)
                            if($oldFI.Exists)
                            {
                                try
                                {
                                    [System.IO.File]::Move($messages[$c].TempFileName, $newFileName)

                                    try
                                    {
                                        $newFI = [System.IO.FileInfo]::new($newFileName)
                                        if($newFI.Exists)
                                        {
                                            LogInfo ("Renamed {0} to {1}" -f @($oldFI.Name, $newFI.Name))
                                        } `
                                        else # NOT ($newFI.Exists)
                                        {
                                            LogError ("Renamed message file {0} does not exist.." -f @($newFileName))
                                            $Script:ReturnObject.Good2Go = $false
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
                                    LogError ("Failed to rename {0} to {1}." -f @($messages[$c].TempFileName, $newFileName))
                                    $Script:ReturnObject.Good2Go = $false
                                }
                            } `
                            else # NOT ($oldFI.Exists)
                            {
                                LogError ("Message file {0} does not exist.." -f @($messages[$c].TempFileName))
                                $Script:ReturnObject.Good2Go = $false
                            }
                        }
                        catch
                        {
                            LogError ("Failed to get file information for {0}." -f @($messages[$c].TempFileName))
                            $Script:ReturnObject.Good2Go = $false
                        }
                    } `
                    else # NOT (-not [String]::IsNullOrEmpty($newFileName))
                    {
                        LogError ("Null/empty file name created for: {0}/{1}" -f @($messages[$c].EntryID, $messages[$c].Subject))
                        $Script:ReturnObject.Good2Go = $false
                    }
                } `
                else # NOT ($Script:ReturnObject.Good2Go)
                {
                    # Nothing, already logged an error
                }

                $c++
            }
        } `
        else # NOT ($messages.Length -gt 0)
        {
            # Nothing, no messages to save...
        }
    } `
    else # NOT ($null -ne $messages)
    {
        LogError ("Null message list in SaveMessages.")
        $Script:ReturnObject.Good2Go = $false
    }
}

<#
    Set the .FileName property for all public folder object prior to actually renaming them.

    This is so I can save the information about a particular object if something goes wrong in the entire process.
#>
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
                    # Now rename all the files using conversation number, message number, item sender and subject.
                    $uniqueConversationIDs = @($Script:ItemsByConversation.Keys)
                    $conversationCount = @($uniqueConversationIDs | Where-Object { $_ -ne "NO_CONVERSATION" }).Length
                    LogInfo ("Unique conversations: {0}" -f @($conversationCount))

                    <#
                        When renaming the message files, do so by conversation in creation time (or last modified time if creation time isn't available) order.

                        The idea here is to have Conv 1 = the oldest conversation, even if some of its messages are newer than others.
                    #>

                    # Create a dictionary of conversation ID by sort time.  Exclude messages which are not part of a conversation
                    #   Key = creation/last mod date time of the oldest message in the conversation.
                    #   Value = List of all the conversation IDs with the same sort time.
                    $conversationIDsBySortTime = [System.Collections.Generic.SortedDictionary[DateTime, System.Collections.Generic.List[String]]]::new()

                    $a = 0
                    while($a -lt $uniqueConversationIDs.Length)
                    {
                        # Only consider messages which are part of conversations.
                        if($uniqueConversationIDs[$a] -ne "NO_CONVERSATION")
                        {
                            # Find the oldest message in the conversation which has .ConversationID -eq $uniqueConversationIDs[$a]
                            #    $Script:ItemsByConversation[$uniqueConversationIDs[$a]] is guaranteed to always have at least 1 item in the list, or we'd not have had $uniqueConversationIDs[$a] as a key use...
                            $oldestItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]] | Sort-Object -Property SortTime | Select-Object -First 1
                            if(-not $conversationIDsBySortTime.ContainsKey($oldestItem.SortTime))
                            {
                                $conversationIDsBySortTime.Add($oldestItem.SortTime, [System.Collections.Generic.List[String]]::new())
                            } `
                            else
                            {
                                # Nothing
                            }

                            # $uniqueConversationIDs is already sorted since it's based on the keys from $Script:ItemsByConversation, so adding it will result in a sorted list.
                            $conversationIDsBySortTime[$oldestItem.SortTime].Add($uniqueConversationIDs[$a])
                        } `
                        else # NOT ($uniqueConversationIDs[$a] -ne "NO_CONVERSATION")
                        {
                            # Nothing.
                        }
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
                    if($uniqueConversationIDs -contains "NO_CONVERSATION")
                    {
                        # Process all the messages which are not part of a conversation
                        $conversationMessages = @($Script:ItemsByConversation["NO_CONVERSATION"] | Sort-Object ConversationIndex)

                        # Since these messages are not part of a conversation, $conversationIdx and $conversationCount don't mean anything.
                        SetPublicFolderConversationObjectsFileNames -pfObjs $conversationMessages -conversationIdx 0 -conversationCount 0
                    } `
                    else # NOT ($uniqueConversationIDs -contains "NO_CONVERSATION")
                    {
                        # Nothing.
                    }

                    if($Script:ReturnObject.Good2Go)
                    {
                        # Loop through the conversations, oldest to newest...
                        $conversationDates = @($conversationIDsBySortTime.Keys)
                        $conversationIdx = 1
                        $a = 0

                        while($a -lt $conversationDates.Length)
                        {
                            # Process all the conversations with SortTime -eq $conversationDates[$a]
                            $b = 0
                            while($b -lt $conversationIDsBySortTime[$conversationDates[$a]].Count)
                            {
                                # Process all the messages that are part of conversation ID: $conversationIDsBySortTime[$conversationDates[$a]][$b]
                                $conversationMessages = @($Script:ItemsByConversation[$conversationIDsBySortTime[$conversationDates[$a]][$b]] | Sort-Object ConversationIndex)

                                SetPublicFolderConversationObjectsFileNames -pfObjs $conversationMessages -conversationIdx $conversationIdx -conversationCount $conversationCount

                                # See above (and good luck understanding) which incrementing $conversationIdx each time is safe.
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
            $publicFolderItemKeys = @($Script:PublicFolderItems.Keys)
            $a = 0
            while($a -lt $publicFolderItemKeys.Length)
            {
                $pfObj = $Script:PublicFolderItems[$publicFolderItemKeys[$a]]

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
                                                LogInfo ("Renamed {0} to {1}" -f @($oldFI.Name, $newFI.Name))
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
                Conv X | Msg Y of Z | Subject
            All messages which have no .ConversationID will be considered a part of "NO_CONVERSATION"
        However, until all items in the folder are enumerated, I won't have all the conversation data.  To prevent looping through .Items multiple times I'll:
            1. Collect the relevant data from each item
            2. Save the item to the local drive using a temporary name "FILE_xxxxx.msg" and record the name along with the collected data
        Once all required data is collected, I'll rename the temporary files based on conversations and message subject.
    #>
    LogInfo ("`tExporting {0} as individual files." -f @($publicFolder.Name))

    # First, save all the items in the folder to disk using a temporary name and create a dictionary of conversations.
    SavePublicFolderItemsToLocalFolder -publicFolder $publicFolder

    SetPublicFolderObjectFileNames

    # Now that all the conversation data has been collected, the file names have been set, it's time to rename all the message files according to conversation/message number.
    RenameLocalFiles
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
        $fName = FixFileName -filename $publicFolder.Name
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
            $Script:ExportedPublicFolderPath = $publicFolder.FolderPath.Replace($Script:topPublicFolder.FolderPath, "").Trim([System.IO.Path]::DirectorySeparatorChar)
            $Script:ReturnObject.PublicFolder.Name = $Script:ExportedPublicFolderPath.Replace("\Outlook Public Folders\", "")

            $Script:ReturnObject.PublicFolder.ItemCount = $publicFolder.Items.Count

            if($Script:ReturnObject.PublicFolder.ItemCount -gt 0)
            {
                LogInfo ("Exporting Public Folder: {0}" -f @($Script:ExportedPublicFolderPath))

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
        $path
    )

    if(-not [String]::IsNullOrEmpty($path))
    {
        LogInfo ("Verifying ProjectWise path: {0}" -f @($path))

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

        if($haveLock)
        {
            # Write a simple log to the lock file.
            $pathStr = "{0}`r`n" -f @($path)
            $uniEncoding = [System.Text.UnicodeEncoding]::new()
            $textLength = $uniEncoding.GetByteCount($pathStr)
            $null = $fLock.Seek(0, [System.IO.SeekOrigin]::End)
            $fLock.Write($uniEncoding.GetBytes($pathStr), 0, $textLength)

            $subFolders = $path.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)

            if($subFolders.Length -gt 0)
            {
                $testPWFolderPath = "\{0}" -f @($Script:ProjectWiseBaseFolder.Name)
                $pwFolderExists = $true
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
                    }
                    $subFolderIdx++
                } while($Script:ReturnObject.Good2Go -and $pwFolderExists -and ($subFolderIdx -lt $subFolders.Length))
                $Script:ReturnObject.Good2Go = $Script:ReturnObject.Good2Go -and $pwFolderExists

                if($Script:ReturnObject.Good2Go)
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

            # Finally, we can't forget to release the lock so others get their chance.
            $fLock.Close()
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
        # First import the files into ProjectWise...
        $result = ReTryCatch -callee "Import-PWDocuments" -funcParameters @{InputFolder = $importFolder; ProjectWiseFolder = $Script:ReturnObject.ProjectWise.ImportFolder; MultiThreaded = $true; ExcludeSourceDirectoryFromTargetPath = $true; Overwrite = $true}
        $Script:ReturnObject.Good2Go = $result.Good2Go

        if($Script:ReturnObject.Good2Go)
        {
            $importedFiles = $result.ReturnValue
            $pfObjs = @($Script:PublicFolderItems.Values)


                # Temporary....
                try
                {
                    $pfObjs | ConvertTo-Json -ErrorAction Stop | Set-Content -Path ("{0}\PFObjects.json" -f @($Script:WorkingFolder))
                }
                catch
                {
                    # Nothing, this is what we want to happen.
                }
                try
                {
                    $importedFiles | ConvertTo-Json -ErrorAction Stop | Set-Content -Path ("{0}\ImportResults.json" -f @($Script:WorkingFolder))
                }
                catch
                {
                    # Nothing, this is what we want to happen.
                }

            $filesInImportFolder = $null
            try
            {
                $filesInImportFolder = @(Get-ChildItem -Path $importFolder -ErrorAction Stop)
            }
            catch
            {
                LogError ("Failed to retrieve files in import folder: {0}." -f @($importFolder))
            }

            # Process the list of files that were successfully imported into ProjectWise
            $importedFiles.ForEach({
                $i = $_

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
                            while(($testFileName.Length -gt 0) -and ($testFilesBySizeAndName.Length -eq 0))
                            {
                                $testFilesBySizeAndName = @($testFilesBySize | Where-Object { $_.BaseName.StartsWith($testFileName) })
                                if($testFilesBySizeAndName.Length -eq 0)
                                {
                                    $testFileName = $testFileName.SubString(0, $testFileName.Length - 1)
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
                                LogWarning ("Unable to find a file matching: {0} (Size: {1}) [1]" -f @($i.FileName, $i.FileSize))
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
                        try
                        {
                            $importedFile.Delete()
                        }
                        catch
                        {
                            # For now, just trap the exception.
                        }

                        $pfObj = $pfObjs | Where-Object { $_.FileName.EndsWith($importedFile.Name) }
                        if($null -ne $pfObj)
                        {
                            $pfObj.Imported = $true   # Set this just in case the removal below fails.
                            try
                            {
                                $null = $Script:PublicFolderItems.Remove($pfObj.RowEntryID)
                            }
                            catch
                            {
                                # Nothing, just trapping the exception.
                            }
                        } `
                        else
                        {
                            LogWarning ("Unable to find a public folder item matching: {0}" -f @($importedFile.Name))
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

            # After deleting all the imported files, see if there is anything left in the folder...
            try
            {
                $filesInImportFolder = @(Get-ChildItem -Path $importFolder -ErrorAction Stop | Where-Object { $_.Extension -ne ".json"})

                # If there is nothing left in the folder, then delete $importFolder
                if($filesInImportFolder.Length -eq 0)
                {
                    try
                    {
                        [System.IO.Directory]::Delete($importFolder, $true)
                    }
                    catch
                    {
                        LogWarning ("Failed to delete empty import folder: {0}." -f @($importFolder))
                    }
                } `
                else # NOT ($filesInImportFolder.Length -eq 0)
                {
                    # Nothing.
                }
            }
            catch
            {
                LogError ("Failed to retrieve files in import folder: {0}." -f @($importFolder))
            }
        } `
        else
        {
            LogError ("Failed to import {0} files to ProjectWise" -f @($Script:ExportedPublicFolderPath))
        }
    } `
    else
    {
        # Nothing, already logged an error.
    }
}

function ImportFilesToProjectWise
{
    if($Script:ReturnObject.Good2Go)
    {
        if($Script:ReturnObject.ExportedItems.Count -gt 0)
        {
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

            if($Script:ReturnObject.Good2Go)
            {
                if($exportedFiles.Length -gt 0)
                {
                    LogInfo ("Found {0} items to import into ProjectWise." -f @($exportedFiles.Length))

                    # Make sure $Script:ExportedPublicFolderPath only contains valid characters
                    $pwFolderPath = FixPath -path $Script:ExportedPublicFolderPath

                    # Verify the existence of the corresponding folder structure in ProjectWise, creating any missing folders.
                    VerifyCreatePWPath -path $pwFolderPath

                    if($Script:ReturnObject.Good2Go)
                    {
                        LogInfo ("Importing items into ProjectWise folder: {0}" -f @($Script:ReturnObject.ProjectWise.ImportFolder))

                        # If there are too many files to import at once, let's break them into chunks.
                        if($exportedFiles.Length -gt $Script:MaxFilesPerImport)
                        {
                            # Create a temporary folder under the working folder so we can import chunks of $Script:MaxFilesPerImport files at a time.
                            $importFolderName = "{0}\ImportToPW-{1}" -f @($Script:WorkingFolder, [DateTime]::Now.ToString("yyyyMMddHHmmss"))

                            try
                            {
                                [System.IO.Directory]::CreateDirectory($importFolderName) | Out-Null
                            }
                            catch
                            {
                                LogError ("Failed to create temporary import folder: {0}" -f @($importFolderName))
                                $Script:ReturnObject.Good2Go = $false
                            }

                            $a = 0
                            while($Script:ReturnObject.Good2Go -and ($a -lt $exportedFiles.Length))
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
                                if($Script:ReturnObject.Good2Go -and (($a % $Script:MaxFilesPerImport) -eq 0) -or ($a -eq $exportedFiles.Length))
                                {
                                    ImportFolderToProjectWise -importFolder $importFolderName

                                    # After importing the folder, create another temporary folder
                                    $importFolderName = "{0}\ImportToPW-{1}" -f @($Script:WorkingFolder, [DateTime]::Now.ToString("yyyyMMddHHmmss"))
                                } `
                                else
                                {
                                    # Nothing, keep going until an error occured, we put 1000 items in the import folder, or we get to the end...
                                }
                            }
                        } `
                        else
                        {
                            ImportFolderToProjectWise -importFolder $Script:WorkingFolder
                        }

                        if($Script:ReturnObject.Good2Go)
                        {
                            LogInfo ("Imported {0} items totalling {1}" -f @($Script:ReturnObject.ImportedItems.Count, (Format-StorageNumber $Script:ReturnObject.ImportedItems.Size)))
                        } `
                        else
                        {
                            # Nothing, already logged an error.
                        }

                        if([System.IO.Directory]::Exists($Script:WorkingFolder))
                        {
                            try
                            {
                                $remainingFiles = @(Get-ChildItem -Path $Script:WorkingFolder -Recurse -File -ErrorAction Stop)
                                if($remainingFiles.Length -eq 0)
                                {
                                    try
                                    {
                                        @($Script:PublicFolderItems.Values) | ConvertTo-Json -ErrorAction Stop | Set-Content -Path ("{0}\PFObjects.json" -f @($Script:WorkingFolder))
                                    }
                                    catch
                                    {
                                        # Nothing, this is what we want to happen.
                                    }
                                } `
                                else # NOT ($remainingFilesAndFolders.Length -eq 0)
                                {
                                    # Nothing.
                                }
                            }
                            catch
                            {
                                LogException ("Failed to determine if there was anything left in working folder: {0}." -f @($Script:WorkingFolder))
                            }
                        } `
                        else # NOT ([System.IO.Directory]::Exists($Script:WorkingFolder))
                        {
                            # Nothing.
                        }
                    } `
                    else
                    {
                        # Nothing, already displayed a message.
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

function ProcessReturnObject
{
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
    $Script:ReturnObject.LogFile = $Script:LogFileName
    $Script:ReturnObject.WorkFolder = $Script:WorkingFolder
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

<#
    This is a hot mess since I'm adapting what used to be a script meant to export a single public folder into a script to export a list of public folders, so bear with me.
#>
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
        $Script:PFEntryID = $publicFolderIdentity.EntryId
        # Reset $Script:ReturnObject back to factory defaults
        ResetScriptObjects -PFEntryID $publicFolderIdentity.EntryId

        if($Script:ReturnObject.Good2Go)
        {
            # Proceed with transferring items from public folders to ProjectWise...
            LogInfo ("Starting export of public folder: {0} ({1})" -f @($publicFolderIdentity.Identity, $publicFolderIdentity.EntryId))

            # Create a temporary working folder for this public folder export.
            SetWorkingFolder

            # Export the public folder to the local disk then import it into ProjectWise
            TransferPublicFolderToProjectWise

            # Do 'Stuff' with the results of TransferPublicFolderToProjectWise
            ProcessReturnObject

            # Remove the temporary working folder so the next export can start fresh.
            # RemoveWorkingFolder
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

function main
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
}

main
