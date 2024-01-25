
# Param:
$lhExcelWorkbook = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\LegalHold\Legal_hold_082023_forKen.xlsx"

# Param:
$discoveryFolderPath = "\\cdcfs1\Discovery\124186, 157684 Gateway\PW"

if(-not $discoveryFolderPath.StartsWith("\\?\UNC\"))
{
    $discoveryFolderPath = "\\?\UNC\{0}" -f @($discoveryFolderPath.TrimStart("\"))
}

function Format-StorageNumber([decimal] $n)
{
    $suffix = @("B","KiB","MiB","GiB","TiB","PiB","EiB","ZiB","YiB")
    $z = 0
    while(($z -lt 7) -and ($n -gt ([Math]::Pow(1024, ($z + 1)))))
    {
        $z++
    }

    return "{0,0:N2} {1}" -f @(($n / [Math]::Pow(1024, $z)), $suffix[$z])
}

try
{
    $excel = Open-ExcelPackage -Path $lhExcelWorkbook
}
catch
{
    Write-Error ("Failed to open Excel file: {0}." -f @($lhExcelWorkbook))
    return -1
}

# Get a list of the project numbers to process
$lhProjects = @($excel.Workbook.Worksheets | Select-Object -ExpandProperty Name)
$copyData = [System.Collections.Generic.List[System.Object]]::new()
$prefixes = @("d","dms")

$a = 0
while($a -lt $lhProjects.Length)
{
    # Read all the Excel data from this project...
    Write-Host ("Processing project #{0}..." -f @($lhProjects[$a]))
    $projectFileData = Import-Excel -ExcelPackage $excel -WorksheetName $lhProjects[$a] # -NoHeader -StartRow 2

    if($null -ne $projectFileData)
    {
        # Track unique source folders for the project
        $uniqueSourceFolders = [System.Collections.Generic.List[System.String]]::new()

        # Track missing source folders for the project
        $missing = [System.Collections.Generic.List[System.Object]]::new()

        # Track all the files I need to copy.
        $fileList = [System.Collections.Generic.SortedDictionary[[System.String], [System.Collections.Generic.List[System.Object]]]]::new()

        $totalFileCount = 0
        $totalFileSize = 0
        $pc = 0
        $e = 0
        while($e -lt $projectFileData.Count)
        {
            $pc = (($e + 1) / $projectFileData.Count) * 100.0
            if(($pc -ge 100.0) -and ($e -lt $projectFileData.Count))
            {
                $pc = "99.99"
            }
            $status = "{0:N0} of {1:N0} : {2:N2}% complete, {3:N0} files, Size: {4}, Unique file names: {5:N0}" -f @(($e + 1), $projectFileData.Count, $pc, $totalFileCount, (Format-StorageNumber $totalFileSize), $fileList.Count)
            Write-Progress -Activity "Scanning folders..." -Status $status -PercentComplete $pc
            $added = $false
            $b = 0
            while((-not $added) -and ($b -lt $prefixes.Length))
            {
                $folderPath = "\\?\UNC\{0}" -f @($projectFileData[$e].Path.TrimStart("\"))
                if($prefixes[$b] -eq "d")
                {
                    $testPath = "{0}\{1}{2,7:D7}" -f @($folderPath, $prefixes[$b], [int]($projectFileData[$e].'Folder Id'))
                }
                else
                {
                    $testPath = "{0}\{1}{2}" -f @($folderPath, $prefixes[$b], $projectFileData[$e].'Folder Id')
                }
                $i = $uniqueSourceFolders.BinarySearch($testPath)
                if($i -lt 0)
                {
                    try
                    {
                        $srcFiles = @(Get-ChildItem -LiteralPath $testPath -Recurse -ErrorAction Stop)
                        $l = 0
                        while($l -lt $srcFiles.Length)
                        {
                            # Don't add subfolders....
                            if(-not $srcFiles[$l].PSIsContainer)
                            {
                                $srcFN = $srcFiles[$l].Name.ToLower()
                                if(-not $fileList.ContainsKey($srcFN))
                                {
                                    $newFL = [System.Collections.Generic.List[System.Object]]::new()
                                    $fileList.Add($srcFN, $newFL)
                                }

                                $fileList[$srcFN].Add($srcFiles[$l])
                                $totalFileCount++
                                $totalFileSize += $srcFiles[$l].Length
                            }
                            $l++
                        }
                        $uniqueSourceFolders.Insert(-bnot $i, $testPath)
                        $added = $true
                    }
                    catch
                    {
                    }
                }
                else
                {
                    $added = $true
                }
                $b++
            }

            if(-not $added)
            {
                Write-Host -ForegroundColor Red ("`t`tNot found: Project:{0} Folder ID: {1}, Path: {2}" -f @($lhProjects[$a], $projectFileData[$e].Path, $projectFileData[$e].'Folder Id'))
                $missing.Add($projectFileData[$e])
            }

            $e++
        }

        if($missing.Count -eq 0)
        {
            Write-Host ("`tLocated {0,0:N0} files totaling {1}, {2} unique file names" -f @($totalFileCount, (Format-StorageNumber $totalFileSize), $fileList.Count))

            Write-Host ("`tBuilding file copy data...")

            # Enumerate the unique fileList ... i.e. by file name...
            $keys = @($fileList.Keys)
            $c = 0
            while($c -lt $keys.Length)
            {
                # Enumerate all the files for this file group ... i.e. all files with the name base file name.
                $groupFiles = $fileList[$keys[$c]]
                if($fileList[$keys[$c]].Count -gt 1)
                {
                    $groupFiles = $fileList[$keys[$c]] | Sort-Object -Descending LastWriteTime
                }

                $d = 0
                while($d -lt $groupFiles.Count)
                {
                    $z = "" | Select-Object ProjectNumber,SourceFile,DestinationFile
                    $z.ProjectNumber = $lhProjects[$a]

                    $z.SourceFile = $groupFiles[$d].FullName
                    if($d -eq 0)
                    {
                        $z.DestinationFile = "{0}\{1}\{2}" -f @($discoveryFolderPath, $lhProjects[$a], $groupFiles[$d].Name)
                    }
                    else
                    {
                        $z.DestinationFile = "{0}\{1}\{2}_{3,3:D3}{4}" -f @($discoveryFolderPath, $lhProjects[$a], $groupFiles[$d].BaseName, $d, $groupFiles[$d].Extension)
                    }

                    $copyData.Add($z)

                    $d++
                }
                $c++
            }
        }
        else
        {
            Write-Host -ForegroundColor Red "Unable to continue, missing folders"
        }
    }
    else
    {
        Write-Host -ForegroundColor Red ("No data read from sheet: {0}" -f @($lhProjects[$a]))
    }

    $a++
}

$results = [System.Collections.Generic.List[System.Object]]::new()

# After all files for all projects have been found, let's start the actual copy...
if($copyData.Count -gt 0)
{
    # Clear jobs
    Get-Job | Remove-Job
    $maxCopies = 50
    $jobs = [System.Collections.Generic.List[System.Management.Automation.Job]]::new()

    Write-Host "Copying files...`r`n`tSometimes it looks like it's stuck... just let it run, the jobs will eventually terminate and the copy will progress..."

    $e = 0
    while($e -lt $copyData.Count)
    {
        $d = $copyData[$e]
        $job = Start-Job -ScriptBlock { param($srcFile, $dstFile) Copy-Item -LiteralPath $srcFile -Destination $dstFile } -ArgumentList $d.SourceFile, $d.DestinationFile
#        $jobs.Add($job)

        $pc = (($e + 1) / $copyData.Count) * 100.0
        if(($pc -ge 100.0) -and ($e -lt $copyData.Count))
        {
            $pc = "99.99"
        }
        $status = "{0:N0} of {1:N0} : {2:N2}% complete" -f @(($e + 1), $copyData.Count, $pc)
        Write-Progress -Activity "Copying files..." -Status $status -PercentComplete $pc

        $runningJobs = @(Get-Job -State Running)
        do
        {
            if($runningJobs.Length -ge $maxCopies)
            {
                $status = "{0:N0} of {1:N0} : {2:N2}% complete (Waiting for open job...[{3}])" -f @(($e + 1), $copyData.Count, $pc, $runningJobs)
                Write-Progress -Activity "Copying files..." -Status $status -PercentComplete $pc
                if($runningJobs.Length -ge $maxCopies)
                {
                    Start-Sleep -Seconds 1
                }
            }
            $runningJobs = @(Get-Job -State Running)
        } while($runningJobs.Length -ge $maxCopies)

        $completeJobs = @(Get-Job -State Completed)
        if($completeJobs.Length -gt 0)
        {
            $subResults = @(Receive-Job $completeJobs -Wait -AutoRemoveJob)
            $k = 0
            while($k -lt $subResults.Length)
            {
                $results.Add($subResults[$k])
                $k++
            }
        }
        $e++
    }
}
else
{
    Write-Error -ForegroundColor Red "No copy data to act on.  There were likely missing directories.  Fix and rerun."
}


<#
    The following section is just for verification.  If you want to run it, just uncomment it.
#>


<##>
$pairsToRetest1 = [System.Collections.Generic.List[int]]::new()

$pairsToRetest = [System.Collections.Generic.List[int]]::new()
$reTest = $true
$reTestIdx = 0
$sb = [System.Text.StringBuilder]::new()
if(-not $reTest)
{
    $a = 0
}
else
{
    $a = $pairsToRetest[$reTestIdx]
}

while($a -lt $copyData.Count)
{
    $srcFile = $copyData[$a].SourceFile
    $srcFileInfo = $null
    $dstFile = $copyData[$a].DestinationFile
    $dstFileInfo = $null

    try
    {
        $srcFileInfo = Get-ChildItem -LiteralPath $srcFile -ErrorAction Stop
    }
    catch
    {
        $msg = "Missing source file: {0}:{0}" -f @($a,$srcFile)
        Write-Host -ForegroundColor Red $msg
        $sb.AppendLine($msg) | Out-Null
        if(($pairsToRetest.Count -eq 0) -or (($pairsToRetest.Count -lt 0) -and ($pairsToRetest[$pairsToRetest.Count - 1] -ne $a)))
        {
            $pairsToRetest.Add($a)
        }
    }

    try
    {
        $dstFileInfo = Get-ChildItem -LiteralPath $dstFile -ErrorAction Stop

        if($null -ne $srcFileInfo)
        {
            if($srcFileInfo.Length -ne $dstFileInfo.Length)
            {
                $msg = "{0}: File length mismatch.`r`n`tSRC: {1}: [{2}]`r`n`tDST: {3} [{4}]" -f @($a, $srcFile, $srcFileInfo.Length, $dstFile, $dstFileInfo.Length)
                Write-Host -ForegroundColor Red $msg
                $sb.AppendLine($msg) | Out-Null

                $msg = "`tLast Write: SRC: {0}, DST: {1}" -f @($srcFileInfo.LastWriteTime, $dstFileInfo.LastWriteTime)
                Write-Host -ForegroundColor Red $msg
                $sb.AppendLine($msg) | Out-Null

                if($srcFileInfo.LastWriteTime -gt $dstFileInfo.LastWriteTime)
                {
                    $msg = "`tSRC is newer"
                    Write-Host -ForegroundColor Green $msg
                    $sb.AppendLine($msg) | Out-Null
                }
                else
                {
                    if(($pairsToRetest.Count -eq 0) -or (($pairsToRetest.Count -lt 0) -and ($pairsToRetest[$pairsToRetest.Count - 1] -ne $a)))
                    {
                        $pairsToRetest.Add($a)
                    }
                }
            }
        }
        else
        {
            $msg = "{0}: Extra DST: {1} for {2}." -f @($a, $dstFile, $srcFile)
            Write-Host -ForegroundColor Red $msg
            $sb.AppendLine($msg) | Out-Null
        }
    }
    catch
    {
        if(($pairsToRetest.Count -eq 0) -or (($pairsToRetest.Count -lt 0) -and ($pairsToRetest[$pairsToRetest.Count - 1] -ne $a)))
        {
            $pairsToRetest.Add($a)
        }
        $msg = "{0}: Missing destination file: {1}" -f @($a, $dstFile)
        Write-Host -ForegroundColor Red $msg
        $sb.AppendLine($msg) | Out-Null

        if($null -ne $srcFileInfo)
        {
            $msg = "`tAttempting to copy {0} to {1}" -f @($srcFile, $dstFile)
            Write-Host -ForegroundColor Yellow $msg
            $sb.AppendLine($msg) | Out-Null

            try
            {
                Copy-Item -LiteralPath $srcFile -Destination $dstFile -ErrorAction Stop
            }
            catch
            {
                $msg = "`tFailed to copy"
                Write-Host -ForegroundColor Red $msg
                $sb.AppendLine($msg) | Out-Null
            }
        }
        else
        {
            # Nothing, already logged the src was missing...
        }
    }

    if(-not $reTest)
    {
        $a++
    }
    else
    {
        $reTestIdx++
        if($reTestIdx -lt $pairsToRetest.Count)
        {
            $a = $pairsToRetest[$reTestIdx]
        }
        else
        {
            $a = $copyData.Count
        }
    }

    $pc = ($a / $copyData.Count) * 100.0
    if(($pc -ge 100.0) -and ($a -lt $copyData.Count))
    {
        $pc = "99.99"
    }
    $status = "{0:N0} of {1:N0} : {2:N2}% complete" -f @($a, $copyData.Count, $pc)
    Write-Progress -Activity "Checking files..." -Status $status -PercentComplete $pc
}
<##>
