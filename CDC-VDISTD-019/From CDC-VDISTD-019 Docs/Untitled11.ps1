
$Script:ImportResults = [System.Collections.Generic.List[System.Object]]::new()

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
                    } `
                    else # NOT ($null -ne $filesInImportFolder)
                    {
                        # Nothing.
                    }

                    $Script:ReturnObject.ImportedItems.Count++
                    $Script:ReturnObject.ImportedItems.Size += $i.FileSize
                })

                # After deleting all the imported files, see if there is anything "useful" left in the folder and if not, remove it.
                # RemoveUselessFolder -path $importFolder
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
