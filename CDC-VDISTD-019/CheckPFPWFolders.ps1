[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String]
    $publicFolderListFile
)

Import-Module -Name PWPS_DAB -Force -DisableNameChecking

. C:\Users\kbriney\Documents\LogFunctions.ps1

$Script:topPublicFolder = $null
$Script:OutlookNApp = $null
$Script:OutlookNamespace = $null
$Script:EntryIDPrefix = $null
$Script:PWServerFQDN = "cdc-pwdint02.powereng.com"
$Script:PWDatasourceName = "pw_prod_dmsclosed"
$Script:PWUserName = "_powershell"
$Script:ProjectWiseBaseFolderName = "Outlook Public Folders"
$Script:BadFilePathChars = @([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()) | Select-Object -Unique
$Script:BadFilenameChars = [System.IO.Path]::GetInvalidFileNameChars()
$Script:DoDebugging = $true
$Script:ListOfExportedPublicFoldersFile = "\\boifs1\ITxchange\klbtest\ListOfExportedPublicFolders.csv"


if($env:COMPUTERNAME -eq "CDC-VDISTD-019")
{
    $Script:PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb0100000078d925fc3ed0ce40a9a7699b00acc6ad0000000002000000000010660000000100002000000056e0e6f1a4b6cda767ad1e3d4dc6a07779df5593207d9e782a981dcbfe242e85000000000e8000000002000020000000f79655a6d7f7343dd6f522e27cbc198024162fdfb1cb1d4e125f04d9a535d6df20000000d7a7ed174fc6193a0a4e0f0403bf61e96a91f5b11b29c67510eb3dc8b0fc8742400000009f4a47b887d5cc82d74786f95cf9aaaacf28f11bb6f60e382533d192f8c3c7e6d46e4d7ef0576d5f32407701b01af35a92e8556d9d2adabce0f740f3219691c5"
} `
else # NOT ($env:COMPUTERNAME -ne "CDC-VDISTD-019")
{
    $Script:PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721"
}

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

function VerifyCreatePWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $path,

        [Parameter(Mandatory = $false, Position = 1)]
        [Switch]
        $Create
    )

    $pwFolderExists = $true

    if($null -ne $path)
    {
#        LogInfo ("Verifying ProjectWise path: {0}" -f @($path))

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
#Write-Host ("Tested: {0} | Exists: {1} | idx: {2}" -f @($testPWFolderPath, $pwFolderExists, $subFolderIdx))
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
#Write-Host ("{0} of {1}" -f @($subFolderIdx, $subFolders.Length))
                } while($Script:ReturnObject.Good2Go -and $pwFolderExists -and ($subFolderIdx -lt $subFolders.Length))
                $Script:ReturnObject.Good2Go = $Script:ReturnObject.Good2Go -and ((-not $Create.IsPresent) -or ($Create.IsPresent -and $pwFolderExists))

                if($Script:ReturnObject.Good2Go -and $pwFolderExists)
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
            LogError ("Failed to acquire PWCreateLock after 30 seconds.")
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else
    {
        LogError "Null/empty path sent to VerifyCreatePWPath."
        $Script:ReturnObject.Good2Go = $false
    }

    return $pwFolderExists
}

InitializeExporter

$pfList = Import-CSV -Delimiter "`t" -Path $publicFolderListFile

$notImported = [System.Collections.Generic.List[System.Object]]::new()
$notExported = [System.Collections.Generic.List[System.Object]]::new()
$suspectFolders = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($Script:ReturnObject.Good2Go -and ($a -lt $pfList.Length))
{
    Write-Host -NoNewline ("Checking: {0}" -f @($pfList[$a].Identity))

    $pfEntryID = FixEntryID -entryIDtoFix $pfList[$a].EntryID

    $retries = 0
    $publicFolder = $null

    while(($null -eq $publicFolder) -and ($retries -lt 3))
    {
        $retries++
        try
        {
            $publicFolder = $Script:OutlookNamespace.GetFolderFromID($pfEntryID)
        }
        catch
        {
            $publicFolder = $null
        }

        if($null -eq $publicFolder)
        {
            if($retries -eq 3)
            {
                Write-Host -ForegroundColor Red ("Failed to retrieve public folder: {0}" -f @($pfList[$a].Identity))
            } `
            else
            {
                Start-Sleep -Milliseconds 500
            }
        }
    }

    if($null -ne $publicFolder)
    {
        if(-not (PublicFolderHasBeenExported -entryID $pfList[$a].EntryID))
        {
            Write-Host -ForegroundColor Red "`tNot Exported"
            $notExported.Add($pfList[$a])
        } `
        else
        {
            Write-Host -ForegroundColor Green "`tExported"
        }

        $itemCount = $publicFolder.Items.Count
        Write-Host ("`tPF Items: {0}" -f @($itemCount))

        if(($publicFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType]) -eq [Microsoft.Office.Interop.Outlook.OlItemType]::olAppointmentItem)
        {
            $itemCount = 1       # Calendars always export as a single .ics file.
        } `
        else
        {
            # Nothing
        }

        $publicFolderPath = FixFileOrPath -fileOrPath $publicFolder.FolderPath.Replace($Script:topPublicFolder.FolderPath, "").Trim([System.IO.Path]::DirectorySeparatorChar)
        $result = $null

        $pwPathExists = VerifyCreatePWPath -path $publicFolderPath
        if($pwPathExists)
        {
            $pwFolder = "\{0}{1}" -f @($Script:ProjectWiseBaseFolderName, $pfList[$a].Identity)

            $result = Get-PWFolderDocumentSize -InputFolder $pwFolder

            if($null -ne $result)
            {
                Write-Host ("`tPW documents: {0}" -f @($result.NumberOfContainedDocuments))

                if($result.NumberOfContainedDocuments -gt 0)
                {
                    if($result.NumberOfContainedDocuments -ne $itemCount)
                    {
                        Write-Host -ForegroundColor Red ("`tSuspect folder")

                        $d = "" | Select-Object Identity, EntryID, PWDocCount, PFItemCount
                        $d.Identity = $pfList[$a].Identity
                        $d.EntryID = $pfList[$a].EntryID
                        $d.PWDocCount = $result.NumberOfContainedDocuments
                        $d.PFItemCount = $itemCount
                        $suspectFolders.Add($d)
                    } `
                    else # NOT ($result.NumberOfContainedDocuments -ne $itemCount)
                    {
                        Write-Host -ForegroundColor Green ("`tPW Document Count = PF Item Count")
                    }
                } `
                else # NOT ($result.NumberOfContainedDocuments -gt 0)
                {
                    if($itemCount -gt 0)
                    {
                        Write-Host -ForegroundColor Yellow "`tNot Imported"
                        $notImported.Add($pfList[$a])
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Green "`tEmpty PF"
                    }
                }

            }
            else
            {
                Write-Host "`tPW documents: Folder Not found.  Then how did it verify??"
                if($itemCount -gt 0)
                {
                    Write-Host -ForegroundColor Yellow "`tNot Imported"
                    $notImported.Add($pfList[$a])
                } `
                else
                {
                    Write-Host -ForegroundColor Green "`tEmpty PF"
                }
            }
        } `
        else # NOT ($pwPathExists)
        {
            Write-Host "`tPW documents: Folder Not found"
        }
    } `
    else # NOT ($null -ne $publicFolder)
    {
        # Nothing.
    }

    if(-not $Script:ReturnObject.Good2Go)
    {
        Write-Host "Script broke"
    } `
    else # NOT (-not $Script:ReturnObject.Good2Go)
    {
        # Nothing.
    }
    $a++
}

Write-Host ("Not Imported: {0}" -f @($notImported.Count))
Write-Host ("Not Exported: {0}" -f @($notExported.Count))
Write-Host ("Suspect Folders (remember to save): {0}" -f @($suspectFolders.Count))
