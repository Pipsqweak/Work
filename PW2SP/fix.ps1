function FixDocLibPermissions
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $projectName1
    )

    $docLib = Get-PnPList -Identity $Script:connData.ConnectionInformation.SharePointDocumentLibraries[$projectName1].RealName -Includes RoleAssignments
    if($null -ne $docLib)
    {
        Get-PnPProperty -ClientObject $docLib -Property HasUniqueRoleAssignments,RoleAssignments

        if(-not $docLib.HasUniqueRoleAssignments)
        {
            Set-PnpList -Identity $docLib.Title -BreakRoleInheritance
            Set-PnpListPermission -Identity $docLib.Title -Group "SP-Government Services Owners" -AddRole "Full Control"
        } `
        else
        {
            Write-Host ("{0} is already fixed." -f @($docLib.Title))
        }
    }
}

function FixAllDocLibPermissions
{
    BuildDocumentLibraryDictionary
    $a = 0
    $docLibNames = @($Script:connData.ConnectionInformation.SharePointDocumentLibraries.Keys)
    while($a -lt $docLibNames.Length)
    {
        if($docLibNames[$a] -notin @("Active Projects","Inactive Projects","PW Admin Standards","Test"))
        {
            # $projectName1 = $docLibNames[$a]
            FixDocLibPermissions -projectName1 $docLibNames[$a]
        }
        $a++
    }
}


function SelectNewest
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowNull()]
        [String] $projName,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [AllowNull()]
        [System.IO.FileInfo] $reportFile,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [ALlowNull()]
        [System.IO.FileInfo] $prodFile,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=2)]
        [ALlowNull()]
        [String] $projPath,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=3)]
        [String] $fileType
    )

    $retval = $false
    if($null -ne $reportFile)
    {
        $destFilePath = "E:\PW2SPProd\{0}\{1}" -f @($projPath, $reportFile.Name)
        if($null -ne $prodFile)
        {
            if($reportFile.LastWriteTime -gt $prodFile.LastWriteTime)
            {
                Write-Host ("Report: {0}, Prod: {1}" -f @($reportFile.LastWriteTime, $prodFile.LastWriteTime))
                Write-Host ("`tCopying {0} to {1}" -f @($reportFile.FullName, $destFilePath))
                $reportFile.CopyTo($destFilePath)

                $retval = [System.IO.File]::Exists($destFilePath)
            } `
            else
            {
                #Write-Host ("`tProd is same or newer.")
                $retval = $true
            }
        } `
        else
        {
            Write-Host ("Copying {0} to {1} (Prod does not exist)" -f @($reportFile.FullName, $destFilePath))
            $reportFile.CopyTo($destFilePath)
            $retval = [System.IO.File]::Exists($destFilePath)
        }
    } `
    else
    {
        if($null -eq $prodFile)
        {
            Write-Host -ForegroundColor Red ("No {0} file for {1}" -f @($fileType, $projName))
        } `
        else
        {
            #Write-Host ("Leaving Prod export file in place.")
            $retval = $true
        }
    }

    return $retval
}

function UpdateProjectList
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $projectName1,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $uploadReady,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=2)]
        [Switch] $checked,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=3)]
        [Switch] $redoUpload,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=4)]
        [Switch] $clearUploadReady,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=5)]
        [Switch] $rediscover,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=6)]
        [Switch] $override,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=7)]
        [Switch] $verified,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=8)]
        [Switch] $removeProject,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=9)]
        [Switch] $recheck
    )

    $mutex = [System.Threading.Mutex]::new($false, "SPProjectListtMutex")
    $myProject = $null
    $projectListFile = "E:\PW2SPReport\projectList.csv"

    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile

        $myProject = $projList.Where({ $_.projectName -eq $projectName1 }) | Select-Object -First 1
        $saveChanges = $false

        if($null -ne $myProject)
        {
            if($uploadReady.IsPresent)
            {
                if(($override.IsPresent) -or ($myProject.reportPhase -eq "complete"))
                {
                    if([String]::IsNullOrEmpty($myProject.uploadStatus))
                    {
                        $latestPWDataReportExportFile = Get-ChildItem -File -Filter ("{0}_*_PWData.json" -f @($myProject.projectName)) -Path ("E:\PW2SPReport\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
                        $latestPWDataProdExportFile = Get-ChildItem -File -Filter ("{0}_*_PWData.json" -f @($myProject.projectName)) -Path ("E:\PW2SPProd\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
                        $pwDataFileReady = SelectNewest -projName $myProject.projectName -reportFile $latestPWDataReportExportFile -prodFile $latestPWDataProdExportFile -projPath $myProject.pwProjectPath -fileType "PWData"

                        $latestViablePathReportExportFile = Get-ChildItem -File -Filter ("{0}_*_viablepaths.json" -f @($myProject.projectName)) -Path ("E:\PW2SPReport\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
                        $latestViablePathProdExportFile = Get-ChildItem -File -Filter ("{0}_*_viablepaths.json" -f @($myProject.projectName)) -Path ("E:\PW2SPProd\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
                        $viablePathFileReady = SelectNewest -projName $myProject.projectName -reportFile $latestViablePathReportExportFile -prodFile $latestViablePathProdExportFile -projPath $myProject.pwProjectPath -fileType "ViablePaths"

                        if($viablePathFileReady -and $pwDataFileReady)
                        {
                            $myProject.uploadStatus = "readyToUpload"
                            $saveChanges = $true
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Yellow ("Not marking {0} ready for upload." -f @($myProject.projectName))
                        }
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Yellow ("Project upload status is {0}.  Not changing." -f @($myProject.uploadStatus))
                    }
                } `
                else
                {
                    Write-Host ("{0} reporting phase not complete." -f @($myProject.projectName))
                    Write-Host -ForegroundColor Yellow ("Not marking {0} ready for upload." -f @($myProject.projectName))
                }
            } `
            elseif($checked.IsPresent)
            {
                if(($override.IsPresent) -or ($myProject.uploadStatus -eq "complete"))
                {
                    $myProject.reportPhase = "complete"
                    $myProject.uploadStatus = "complete"
                    $myProject.checked = "true"
                    $myProject.verified = "false"
                    $saveChanges = $true
                } `
                else
                {
                    Write-Host ("{0} upload phase not complete." -f @($myProject.projectName))
                    Write-Host -ForegroundColor Yellow ("Not marking {0} 'checked'." -f @($myProject.projectName))
                }
            } `
            elseif($redoUpload.IsPresent)
            {
                if($override.IsPresent -or ($myProject.reportPhase -eq "complete"))
                {
                    if($override.IsPresent -or ($myProject.uploadStatus -in @("complete","started")))
                    {
                        $myProject.reportPhase = "completed"
                        $myProject.uploadStatus = "redoUpload"
                        $myProject.checked = ""
                        $myProject.verified = "false"
                        $myProject.verifyCounter = 0
                        $saveChanges = $true
                    } `
                    else
                    {
                        Write-Host ("{0} upload phase not started/complete." -f @($myProject.projectName))
                        Write-Host -ForegroundColor Yellow ("Not marking {0} redo upload." -f @($myProject.projectName))
                    }
                } `
                else
                {
                    Write-Host ("{0} reporting phase not complete." -f @($myProject.projectName))
                    Write-Host -ForegroundColor Yellow ("Not marking {0} ready for upload." -f @($myProject.projectName))
                }
            } `
            elseif($clearUploadReady.IsPresent)
            {
                $myProject.uploadStatus = ""
                $myProject.checked = ""
                $myProject.verified = "false"
                $saveChanges = $true
            } `
            elseif($rediscover.IsPresent)
            {
#                Write-Host ("clearUploadReady requested.")
                $myProject.reportPhase = ""
                $myProject.uploadStatus = ""
                $myProject.verified = "false"
                $saveChanges = $true
            } `
            elseif($verified.IsPresent)
            {
                $myProject.reportPhase = "complete"
                $myProject.uploadStatus = "complete"
                $myProject.checked = "true"
                $myProject.verified = "true"
                $saveChanges = $true
            } `
            elseif($removeProject.IsPresent)
            {
                $projList = @($projList.Where({ $_.projectName -ne $myProject.projectName }))
                Write-Host -ForegroundColor Yellow ("Removed project {0}." -f @($myProject.projectName))
                $saveChanges = $true
            } `
            elseif($recheck.IsPresent)
            {
                $myProject.reportPhase = "complete"
                $myProject.uploadStatus = "complete"
                $myProject.checked = $false
                $myProject.verified = $false
                $myProject.verifyCounter = 0
                $saveChanges = $true
            }

            if($saveChanges)
            {
                $projList | Export-CSV -Delimiter "`t" -Path $projectListFile -Force
            }
        } `
        else
        {
            Write-Host -ForegroundColor Yellow ("{0} not found." -f @($projectName1))
        }
    }
    finally   # No matter what happens, make sure to release the mutex...
    {
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }

    $null = $mutex.Dispose()
}

function CheckPW2SP
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $projectName1
    )

    Write-Host ("PID: {0}" -f @($PID))
    $mutex = [System.Threading.Mutex]::new($false, "SPProjectListtMutex")
    $myProject = $null
    $projectListFile = "E:\PW2SPReport\projectList.csv"

    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile
    }
    finally   # No matter what happens, make sure to release the mutex...
    {
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }

    $myProject = $projList.Where({ $_.projectName -eq $projectName1 }) | Select-Object -First 1
    if($null -ne $myProject)
    {
        # $dbg = $Script:DoDebugging
        $Script:DoDebugging = $false
        $Script:connDataJSONFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\PW2SP\connDataProd.json"
        $Script:projectName = $myProject.projectName
        $Script:pwProjectPath = $myProject.pwProjectPath
        $Script:localPath = $myProject.localPath
        $docLibName = "Closed Projects"
        if($Script:pwProjectPath -match "Active")
        {
            $docLibName = "Shared Documents"
        }
        $sb = [System.Text.StringBuilder]::new()

        $null = BasicSPOLConnection

        try
        {
            $latestLogFile = Get-ChildItem -File -Filter ("{0}-*.log" -f @($Script:projectName)) -Path "E:\PW2SPProd\Logs" -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
            if($null -ne $latestViablePathsExportFile)
            {
                $logContent = Get-Content -Path $latestLogFile.FullName
                @($logContent -cmatch "WARNING:|ERROR:") | ForEach-Object {
                    [void] $sb.AppendLine($_)
                }
                if($sb.Length -gt 0)
                {
                    [void] $sb.AppendLine("`r`n")
                    Write-Host ("Warnings and/or errors logged")
                }
            } `
            else
            {
                # Nothing, no viable path export to load.
            }
        }
        catch
        {
            $Error.Clear()
            # Not viable path export to load.
        }

        # Might want to consider looking at E:\PW2SPProd vs E:\PW2SPReport
        Write-Host "Loading latest ProjectWise data export file..."
        $pwData = LoadLatestPWData
        Write-Host "Loading latest viable path export file..."
        $viablePathsDict = LoadLatestViablePaths

        Write-Host "Parsing export data...."
        $pwFolders = [System.Collections.Generic.List[Object]]::new()
        $pwDocs = [System.Collections.Generic.List[Object]]::new()
        $uniqueFPs = [System.Collections.Generic.List[String]]::new()
        $extraDocs = [System.Collections.Generic.List[Object]]::new()

        $pwKeys = @($pwData.ProjectWiseObjects.Keys)
        $a = 0
        $pwKeys.ForEach({
            $p = $pwData.ProjectWiseObjects[$_]
            if($p.MyType -eq "ProjectWiseFolder")
            {
                $pwFolders.Add($p)
            } `
            elseif($p.MyType -eq "ProjectWiseDocument")
            {
                $i = $uniqueFPs.BinarySearch($p.FullPath)
                if($i -lt 0)
                {
                    $pwDocs.Add($p)
                    $uniqueFPs.Insert(-bnot $i, $p.FullPath)
                } `
                else
                {
                    $extraDocs.Add($p)
                }
            } `
            else
            {
                Write-Host ("Unknown object type at index: {0}" -f @($a))
            }
            $a++
        })

        Write-Host ("PWFolders: {0}, PWDocs: {1}" -f @($pwFolders.Count, $pwDocs.Count))
        Write-Host ("Getting data from Sharepoint Online...(might be a bit...)")
        $fnf = Get-PnPFolderItem -FolderSiteRelativeUrl ("{0}/{1}" -f @($docLibName, $Script:projectName)) -Recursive
        Write-Host ("Sharepoint objects: {0}" -f @($fnf.Length))

        if($fnf.Length -gt 0)
        {
            $spFolders = [System.Collections.Generic.List[Object]]::new()
            $spFiles = [System.Collections.Generic.List[Object]]::new()
            $spPaths = [System.Collections.Generic.List[String]]::new()
            $spExtras = [System.Collections.Generic.List[String]]::new()

            $a = 0
            $fnf.ForEach({
                $spSplit = $_.ServerRelativeURL -split "/"
                $spPath = $spSplit[4..($spSplit.Length - 1)] -join "/"
                $i = $spPaths.BinarySearch($spPath)
                if($i -lt 0)
                {
                    $spPaths.Insert(-bnot $i, $spPath)
                }
                if($_ -is [Microsoft.SharePoint.Client.Folder])
                {
                    $spFolders.Add($_)
                } `
                elseif($_ -is [Microsoft.SharePoint.Client.File])
                {
                    $spFiles.Add($_)
                } `
                else
                {
                    Write-Host ("Unknown SP object type ({0}) at index {1}" -f @($_.GetType().FullName, $a))
                }
                $a++
            })

            $allSPPaths = [System.Collections.Generic.List[String]]::new()
            $spPaths | ForEach-Object {
                $allSPPaths.Add($_)
            }

            $missingDocPaths = [System.Collections.Generic.List[String]]::new()
            $vpPaths = [System.Collections.Generic.List[String]]::new()
            $extraVersions = [System.Collections.Generic.List[String]]::new()

            $vpKeys = @($viablePathsDict.Keys)
            $a = 0
            while($a -lt $vpKeys.Length)
            {
                $vpSplit = $viablePathsDict[$vpKeys[$a]].SPData.FolderName -split "/"
                if($vpSplit.Length -gt -1)
                {
                    $vpPath = $vpSplit[1..($vpSplit.Length - 1)] -join "/"
                    if(-not [String]::IsNullOrEmpty($viablePathsDict[$vpKeys[$a]].SPData.Filename))
                    {
                        $vpPath += "/" + $viablePathsDict[$vpKeys[$a]].SPData.Filename
                    }

                    # First, see if $vpPath is in the list of paths found on SharePoint
                    #   keep in mind, once I've seen $vpPath in $spPaths, I remove it so I'm left
                    #   with a list of extra stuff on SharePoint.
                    $i = $spPaths.BinarySearch($vpPath)
                    if($i -lt 0)
                    {
                        # Ok, $vpPath is not in $spPaths....HOWEVER, it might have been removed by a previous version of $vpPath.

                        # See if $vpPath is in the list of ALL paths on SharePoint...
                        $i = $allSPPaths.BinarySearch($vpPath)
                        if($i -lt 0)
                        {
                            # Ok, $vpPath is NOT on SharePoint ....

                            # So see if we've already collected the path in $missingDocPaths
                            $i = $missingDocPaths.BinarySearch($vpPath)
                            if($i -lt 0)
                            {
                                # This is a new $vpPath... if its at least a folder/file, then record it.
                                if(($vpPath -split "/").Length -gt 1)
                                {
                                    $missingDocPaths.Insert(-bnot $i, $vpPath)
                                } `
                                else
                                {
                                    # Skipp the document library and project folder.
                                }
                            } `
                            else
                            {
                                # Already recorded $vpPath as a missing path...
                            }
                        } `
                        else
                        {
                            # $vpPath is in $allSPPaths, so it's just another version of the file.
                            $i = $extraVersions.BinarySearch($vpPath)
                            if($i -lt 0)
                            {
                                $i = -bnot $i
                            }
                            $extraVersions.Insert($i, $vpPath)
                        }
                    } `
                    else
                    {
                        # $vpPath is in $spPaths, so remove it....
                        #     if I remove all the matching vp paths from spPaths, then what's left should be extras on the SP side.
                        $spPaths.RemoveAt($i)
                    }

                    $i = $vpPaths.BinarySearch($vpPath)
                    if($i -lt 0)
                    {
                        $vpPaths.Insert(-bnot $i, $vpPath)
                    }
                }
                $a++
            }

            if($missingDocPaths.Count -eq 0)
            {
                Write-Host -ForegroundColor Green "Nothing missing from Sharepoint"
            } `
            else
            {
                [void] $sb.AppendLine(("Missing {0} folders and/or files in Sharepoint:" -f @($missingDocPaths.Count)))
                $missingDocPaths | ForEach-Object {
                    [void] $sb.AppendLine(("`t{0}" -f @($_)))
                }
            }

            if($spPaths.Count -eq 0)
            {
                Write-Host -ForegroundColor Green "Nothing extra on SharePoint"
            } `
            else
            {
                [void] $sb.AppendLine(("Extra {0} folders and/or files in Sharepoint:" -f @($spPaths.Count)))
                $spPaths | ForEach-Object {
                    [void] $sb.AppendLine(("`t{0}" -f @($_)))
                }
            }


            if($sb.Length -gt 0)
            {
                Write-Host -ForegroundColor Yellow "Report copied to clipboard."
                $sb.ToString() | Set-Clipboard
            }

            if((($pwFolders.Count - 2) -eq $spFolders.Count) -and ($pwDocs.Count -eq $spFiles.Count) -and ($missingDocPaths.Count -eq 0) -and ($spPaths.Count -eq 0))
            {
                Write-Host -ForegroundColor Green ("Project {0} is good" -f @($projectName1))
                UpdateProjectList -projectName1 $myProject.projectName -checked -override
            } `
            else
            {
                Write-Host ("Folders:")
                Write-Host ("`tPW: {0}" -f @($pwFolders.Count))
                Write-Host ("`tSP: {0}" -f @($spFolders.Count))
                Write-Host ("Files:")
                Write-Host ("`tPW: {0}" -f @($pwDocs.Count))
                Write-Host ("`t`tOther version docs: {0}" -f @($extraDocs.Count))
                Write-Host ("`tSP: {0}" -f @($spFiles.Count))
                # UpdateProjectList -projectName1 $projectName1 -redoUpload
            }
            $missingDocPaths.Clear()
            $vpPaths.Clear()
            $extraVersions.Clear()
            $allSPPaths.Clear()
            $spFolders.Clear()
            $spFiles.Clear()
            $spPaths.Clear()
            $spExtras.Clear()
            $pwFolders.Clear()
            $pwDocs.Clear()
            $uniqueFPs.Clear()
            $extraDocs.Clear()
            $pwData.ProjectWiseObjects.Clear()
            $viablePathsDict.Clear()
            $pwData = $null
            $fnf = $null
        } `
        else
        {
            Write-Host -ForegroundColor Yellow "No sharepoint folders or files..."
        }
        #$Script:DoDebugging = $dbg
    } `
    else
    {
        Write-Host -ForegroundColor Red ("Project {0} not found in project list." -f @($projectName1))
    }
}

function GetProjectStatus
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $projectName1
    )

    Write-Host ("Checking project {0}..." -f @($projectName1))
    $mutex = [System.Threading.Mutex]::new($false, "SPProjectListtMutex")
    $myProject = $null
    $projectListFile = "E:\PW2SPReport\projectList.csv"

    try
    {
        $null = $mutex.WaitOne()   # Wait for any other thread in this block to complete, they block others...
        $projList = Import-csv -Delimiter "`t" -Path $projectListFile
        $myProject = $projList.Where({ $_.projectName -eq $projectName1 }) | Select-Object -First 1
    }
    finally
    {
        $null = $mutex.ReleaseMutex()  # All done, let others play...
    }

    try
    {
        $latestProjectReportLogFile = Get-ChildItem -File -Filter ("{0}-*.log" -f @($projectName1)) -Path "E:\PW2SPReport\Logs" -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        if($null -eq $latestProjectReportLogFile)
        {
            Write-Host ("Project discovery not attempted")
            $discoveryAttempted = $false
            $reportErrors = $false
        } `
        else
        {
            $discoveryAttempted = $true
            $logContent = Get-Content -Path $latestProjectReportLogFile.FullName -ErrorAction Stop
            $errorMsgs = @($logContent -match "ERROR:")
            $reportErrors = $errorMsgs.Length -gt 0
            if($errorMsgs.Length -gt 0)
            {
                Write-Host -ForegroundColor Red ("`tDiscovery errors:")
                $errorMsgs.ForEach({
                    Write-Host -ForegroundColor Red ("`t`t{0}" -f @($_))
                })
            }
        }
    }
    catch
    {
        # No report generated...
    }

    try
    {
        $latestProjectProdLogFile = Get-ChildItem -File -Filter ("{0}-*.log" -f @($projectName1)) -Path "E:\PW2SPProd\Logs" -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        if($null -eq $latestProjectProdLogFile)
        {
            $uploadAttempted = $false
            $uploadErrors = $false
        } `
        else
        {
            $uploadAttempted = $true
            $logContent = Get-Content -Path $latestProjectProdLogFile.FullName -ErrorAction Stop
            $errorMsgs = @($logContent -match "ERROR:")
            $uploadErrors = $errorMsgs.Length -gt 0
            if($errorMsgs.Length -gt 0)
            {
                Write-Host -ForegroundColor Red ("`tUpload errors:")
                $errorMsgs.ForEach({
                    Write-Host -ForegroundColor Red ("`t`t{0}" -f @($_))
                })
            }
        }
    }
    catch
    {
        # No upload attempted...
    }

    if($null -ne $myProject)
    {
        Write-Host ("`treport phase: {0}" -f @($myProject.reportPhase))
        Write-Host ("`tupload status: {0}" -f @($myProject.uploadStatus))
        Write-Host ("`tchecked? {0}" -f @($myProject.checked))

        if($myProject.reportPhase -eq "complete")
        {
            if(-not $uploadAttempted)
            {
                if([String]::IsNullOrEmpty($myProject.uploadStatus))
                {
                    Write-Host ("`t`tShould be 'readyToUpload'")
                } `
                elseif($myProject.uploadStatus -ne "readyToUpload")
                {
                }
            } `
            else
            {
            }
        }
    } `
    else
    {
        Write-Host -ForegroundColor Yellow ("`tnot in {0}" -f @($projectListFile))
    }
}

function InvestigateProject
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String] $projectName1,

        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=1)]
        [Switch] $sp
    )

    $projectListFile = "E:\PW2SPReport\projectList.csv"
    $projList = Import-csv -Delimiter "`t" -Path $projectListFile
    $myProject = $projList.Where({ $_.projectName -eq $projectName1 }) | Select-Object -First 1

    if($null -ne $myProject)
    {
        $latestPWDataProdExportFile = Get-ChildItem -File -Filter ("{0}_*_PWData.json" -f @($myProject.projectName)) -Path ("E:\PW2SPProd\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        $latestViablePathProdExportFile = Get-ChildItem -File -Filter ("{0}_*_viablepaths.json" -f @($myProject.projectName)) -Path ("E:\PW2SPProd\{0}" -f @($myProject.pwProjectPath)) -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1
        $latestLogFile = Get-ChildItem -File -Filter ("{0}-*.log" -f @($myProject.projectName)) -Path "E:\PW2SPProd\Logs" -ErrorAction SilentlyContinue | Sort-Object -Descending LastWriteTime | Select-Object -First 1

        if($null -ne $latestPWDataProdExportFile)
        {
            npp $latestPWDataProdExportFile.FullName
        }
        if($null -ne $latestViablePathProdExportFile)
        {
            npp $latestViablePathProdExportFile.FullName
        }
        if($null -ne $latestLogFile)
        {
            npp $latestLogFile.FullName
        }

        if($sp.IsPresent)
        {
            Start-Process ("microsoft-edge:https://powereng0.sharepoint.com/sites/SP-GovernmentServices-Projects/{0}" -f @($myProject.projectName))
        }
    }
}

function StorageReport
{

    BuildDocumentLibraryDictionary
    $docLibKeys = @(@($Script:connData.ConnectionInformation.SharePointDocumentLibraries.Keys).Where({ $_ -notin @("_Template Project Folder Structure","Active Projects","CAD-BIM Project testing","Form Templates","Inactive Projects","Library","Proposals - Archive","PW Admin Standards", "Test") }))
    $storageData = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0

    while($a -lt $docLibKeys.Length)
    {
        ShowProgress -progressID 1 -activity "Getting storage info" -counter $a -counterMax $docLibKeys.Length -statusSuffix $docLibKeys[$a]
        $storageInfo = Get-PnpFolderStorageMetric -List $docLibKeys[$a]
        $sd = [PSCustomObject]@{
            ProjectName = $docLibKeys[$a]
            StorageInfo = $storageInfo
        }
        $storageData.Add($sd)
        $a++
    }

    $storageData | Select-Object @{N='ProjectName'; E={$_.ProjectName}}, @{N='TotalSize';E={$_.StorageInfo.TotalSize}},@{N='TotalSizeA';E={ (Format-StorageNumber $_.StorageInfo.TotalSize) }}, @{N='FileCount';E={$_.StorageInfo.TotalFileCount}} | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | scb

}


CheckPW2SP -projectName1 "121847" -pwProjectPath1 "Archived Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"



# Redos
<#
CheckPW2SP -projectName1 "126210" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "129212" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "121894" -pwProjectPath1 "Archived Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "146340" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "153053" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "157826" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "167419" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "156870" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "156555" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "153866" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "153414" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "153400" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "153053" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "148840" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "144994" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "143111" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "135977" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "135643" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "132707" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "126134" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "124669" -pwProjectPath1 "Archived Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "121847" -pwProjectPath1 "Archived Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"
CheckPW2SP -projectName1 "158741" -pwProjectPath1 "Archive Projects" -localPath1 "E:\PW2SPProd" -docLibName "Closed Projects"



$bad = @($pwFolder.TreeDocuments | Where-Object { $_.FullPath -notmatch ("{0}$" -f @([RegEx]::Escape($_.FileName)))})

#>

$reportPath = "E:\PW2SPProd\StorageReport.csv"
$siteStorage = Get-PnPTenantSite -Identity ("{0}/sites/{1}" -f @($Script:connData.ConnectionInformation.SharePointRootURL, $Script:connData.ConnectionInformation.SharePointSiteName)) | Select-Object @{Name='StorageAvailable'; Expression={$_.StorageQuota - $_.StorageUsageCurrent}}, @{Name='StorageUsageCurrent'; Expression={$_.StorageUsageCurrent}}, @{Name='StorageQuota'; Expression={$_.StorageQuota}}, @{Name='% Used'; Expression={'{0:P2}' -f ($_.StorageUsageCurrent / $_.StorageQuota)}}



# Active Projects for 12/2
UpdateProjectList -projectName1 "0245025_0000" -uploadReady
UpdateProjectList -projectName1 "0246381_0001" -uploadReady
UpdateProjectList -projectName1 "0248121_0000" -uploadReady
UpdateProjectList -projectName1 "0248721_0000" -uploadReady
UpdateProjectList -projectName1 "0251994_0000" -uploadReady
UpdateProjectList -projectName1 "0252230_0000" -uploadReady
UpdateProjectList -projectName1 "0257862_0000" -uploadReady
UpdateProjectList -projectName1 "0262135_0000" -uploadReady
UpdateProjectList -projectName1 "0262136_0000" -uploadReady
UpdateProjectList -projectName1 "0262137_0000" -uploadReady
UpdateProjectList -projectName1 "0262155_0000" -uploadReady
UpdateProjectList -projectName1 "160863" -uploadReady
UpdateProjectList -projectName1 "179849" -uploadReady
UpdateProjectList -projectName1 "0257998_0000" -uploadReady
UpdateProjectList -projectName1 "0252242_0000" -uploadReady
UpdateProjectList -projectName1 "160075" -uploadReady

# Active Projects for 12/3
@("174417", "177797", "177830", "0239208_0000", "0245838_0000", "0246304_0000").ForEach({ UpdateProjectList -projectName1 $_ -rediscover })
@("167497", "174465", "0240582_0000", "158853").ForEach({ UpdateProjectList -projectName1 $_ -rediscover })

@("174417", "177797", "177830", "0239208_0000", "0245838_0000", "0246304_0000").ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })
@("167497", "174465", "0240582_0000", "158853").ForEach({ UpdateProjectList -projectName1 $_ -rediscover })

# Active Projects for 12/4
@("0246807_0000","0248017_0000","0249423_0000","0250641_0000","0251078_0000","0251270_0000","0253397_0000","0253785_0000","159867","0255544_0000").ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })
@("0246807_0000","0249423_0000","0250641_0000","0251078_0000","0251270_0000","0253397_0000","0253785_0000","0255544_0000").ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })
@("0248017_0000","159867").ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })

# Active Projects for 12/5
@(
    "174465","0241907_0001","0256018_0000","0256346_0000","0256903_0000","0257925_0000","0258794_0001", "0261227_0000","0261492_0000","0262671_0000","158349","153296",
    "0245666_0000","163779","176707","0257443_0000","0188265_00","0233676_00","0234427_00","0235215_00","0235440_00","0235574_00","0238813_0001","0242182_0001","0243748_0000","0243974_0000"
).ForEach({ UpdateProjectList -projectName1 $_ -rediscover })


$dec8ActiveProjects = @(
    "0244709_0000","0245137_0000","0245414_0000","0247511_0000","0248823_0000","0249372_0000",
    "0249386_0000","0249675_0000","0250605_0000","0252562_0000","0253099_0000","0253269_0000"
)

$dec8ActiveProjects.ForEach({ UpdateProjectList -projectName1 $_ -rediscover })
$dec8ActiveProjects.ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })


$dec9Projects = @("0254063_0000","0255376_0000","0256805_0000","0257387_0000","0258338_0000","0259198_0000","0259420_0000","0261262_0000","0261674_0000","0261744_0000","0262057_0000")
$dec9Projects.ForEach({ UpdateProjectList -projectName1 $_ -rediscover })
$dec9Projects.ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })

$dec10Projects = @("145725","160862","161546","162365","166424","169508","179956","0188265_00","0235437_00","0235565_0002","0240327_0000","0240535_0000","0250215_0000","0253290_0000","0256023_0000","0257518_0000","0262394_0000")
$dec10Projects.ForEach({ UpdateProjectList -projectName1 $_ -rediscover })

$dec10Projects2 = @("160862","169508")
$dec10Projects2.ForEach({ UpdateProjectList -projectName1 $_ -rediscover })

UpdateProjectList -projectName1 "161546" -uploadReady
@("0262394_0000","0256023_0000","0250215_0000","166424","145725","0253290_0000","0257518_0000","162365","179956","0240327_0000","160862","0240535_0000","169508","0235565_0002","0188265_00").ForEach({ UpdateProjectList -projectName1 $_ -uploadReady })



# Remove projects not in Brooke's List...
@(
    "164911", "170686", "156311", "159211", "160240", "163036", "159390", "158106", "166562", "158392", "151757", "158925",
    "165521", "153530", "167928", "167927", "162156", "141377", "163617", "153763", "172961", "159844", "165152", "150800",
    "159759", "156698", "146404", "158105", "157892", "158557", "156782", "157934", "165506", "163768", "158041", "157677",
    "173734", "159391", "152880", "162309", "165504", "167648", "144762", "148217", "160805", "167197", "151159", "149602",
    "170601", "154507", "137961", "164409", "162600", "163423", "142856", "162672", "146873", "162529", "160378", "162310",
    "155430", "150413", "162671", "149466", "154550", "130449", "155410", "157886", "144884", "169849", "162308", "156134",
    "147561", "150823", "150696", "155162", "151265", "151683", "155408", "155346", "146344", "159987", "162305", "157974",
    "156759", "156132", "146072", "156994", "169726", "156133", "157976", "140506", "159551", "154268", "152445", "155070",
    "164681", "147060", "146530", "162353", "153872", "157476", "153312"
).ForEach({ UpdateProjectList -projectName1 $_ -removeProject })
