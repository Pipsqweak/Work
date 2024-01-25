<#
   I need to build a series of .zip files, but I don't want any single .zip file to exceed $mapZipSize bytes.

   Get an array of [System.IO.FileInfo] for all the files that need to be added to the .zip files.
   
   Place each of the [FileInfo] objects into 1 of 2 sorted lists.
        Files  > $maxZipSize -> $largeFiles   -- these will be treated special
        Files <= $maxZipSize -> $listOfFiles

   Now all the files in $listOfFiles need to be archived

   Since the "art" of archiving files cannot be easily predicted, I'm going to get creative.
   
      I'll build a sublist of files from $listOfFiles where the sum of the length of the sublist of files
          is -le to the remaining space in the archive ($zipSpaceLeft).
          
      I'll add the sublist of files to the archive and see how much space is left.  ($maxZipSize - archive size)
      
      I'll then repeat the process of adding more files to the archive and rechecking the archive's size until:
          1. There are no more files to archive
          2. No files remaining in $listOfFiles that will fit in the remaining archive space.

      If no files are found that can fit into the archive, I'll start a new archive and repeat the process.


   To break it down further:

   While there are files left to archive:
      Archive files

   Archive files:
        
       Build a sublist of files to add to a single .zip archive.
   
       This is done by keeping track of how much space remains in the .zip archive ($zipSpaceLeft) as it is being built.
   
       At first the archive will not exist, so $zipSpaceLeft = $maxZipSize

       Search $listOfFiles for a file that is -le $zipSpaceLeft...

       The search will either.

           1. Yield a file that will fit in $zipSpaceLeft
       
                Add the located file to the sublist of files to add to the next .zip archive
                Subtract its length from from $zipSpaceLeft
                Remove it from the over all list of files to be archived.


           2. No file that will fit in $zipSpaceLeft

#>
 class ObjComparer3:System.Collections.Generic.IComparer[System.Object]
 {
     [System.Object] $x
     [System.Object] $y

     [int] Compare($x,$y) {
         return $x.Length.CompareTo($y)
     }
 }

$comparer = [ObjComparer3]::new()
# $l1.BinarySearch("Ben", $comparer)
 
$pwNumber = "144176"
$baseFolder = "E:\TMP\LHTMP"
$folderToAdd = "{0}\{1}" -f @($baseFolder, $pwNumber)
$maxZipSize = 8GB
$files = @(Get-ChildItem -Path $folderToAdd -Recurse -Attributes !Directory+!System)
$fileListName = "{0}\zipFileList.txt" -f @($baseFolder)

$listOfFiles = [System.Collections.Generic.List[System.Object]]::new()
$largeFiles = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $files.Length)
{
    $listToAddTo = $null
    
    # If the current file is larger than the max zip size...
    if($files[$a].Length -gt $maxZipSize)
    {
        # ... add it to the large file list...
        $listToAddTo = $largeFiles
    }
    else
    {
        # ... add the file to the regular list of files...
        $listToAddTo = $listOfFiles
    }
    
    if($null -ne $listToAddTo)
    {
        $i = $listToAddTo.BinarySearch($files[$a].Length, $comparer)
        if($i -lt 0)
        {
            $i = -bnot $i
        }
        $listToAddTo.Insert($i, $files[$a])
    }
    else
    {
        Write-Host -ForegroundColor Red ("Unable to determine which list to add: {0} to." -f @($files[$a].FullName))
    }

    $a++
}



$a = 0
$zipCounter = 1
while($listOfFiles.Count -gt 0)
{
    $zipFileName = "{0}\{1}-{2,3:D3}.7z" -f @($baseFolder, $pwNumber, $zipCounter)
    if(-not (Test-Path -Path $zipFileName))
    {
        $zipFileSize = 0
    }
    else
    {
        $zipFileSize = (Get-ChildItem -Path $zipFileName).Length
    }

    $zipSpaceLeft = $maxZipSize - $zipFileSize
    $fileList = @()
    $continueMakingFileList = ($listOfFiles.Count -gt 0)

    while($continueMakingFileList) 
    {
        # If we get to this point, then there are more files in $listOfFiles that need to be archived.

        $i = $listOfFiles.BinarySearch($zipSpaceLeft, $comparer)
        if($i -lt 0)
        {
            # BinarySearch returns -lt 0 if the value is not found.
            #   The returned value is the bitwise complement index of the next larger number.
            #   Get the index of the next larger file.
            $i = -bnot $i

            # Since I need a file that is -le to $zipSpaceLeft, decrement $i until
            #   I get to a file that will fit, or until we reach the bottom of the list.
            while(($i -gt 0) -and ($listOfFiles[$i].Length -gt $zipSpaceLeft))
            {
                $i--
            }
        }

        # Did we get a file to add to the archive?
        if(($i -ge 0) -and ($i -lt $listOfFiles.Count))
        {
            # Yes, add the file to the list of files to add to the zip archive
            $fileList += $listOfFiles[$i].FullName.Replace(("{0}\" -f @($baseFolder)), "")

            # Reduce the estimated space left by the length of the file we just added.
            $zipSpaceLeft -= $listOfFiles[$i].Length

            # Remove the file from further consideration.
            $listOfFiles.RemoveAt($i)
        }
        else
        {
            # No, there was no file found that will fit in the zip archive

            # Are there any files in the list of files to add to the archive?
            if($fileList.Length -gt 0)
            {
                # Yes, so run 7-zip to add the files to the archive and start a new list.
                

                # NOTE: RUN 7-Zip here...
                

                $continueMakingFileList = $false
            }
            else
            {
                # No files found to add to the archive
                
                if($listOfFiles.Count -gt 0)
                {
                    # No files found to add to the archive, yet there are still files in the list of files to archive.
                }
            }


            if($fileList.Length -eq 0)
            {
                Write-Host ("File: {0} ({1}) too big for {2} sized zip file." -f @($listOfFiles[$i].FullName, (ConvertTo-FormattedNumber $listOfFiles[$i].Length DataSize "0.00"), (ConvertTo-FormattedNumber $maxZipSize DataSize "0.00")))
                $listOfFiles.RemoveAt($i)
            }
            $continueMakingFileList = ($listOfFiles.Count -gt 0)
        }

                if(($fileList.Length -eq 0) -and ($listOfFiles[$i].Length -gt $maxZipSize))
                {
                    Write-Host ("File: {0} ({1}) too big for {2} sized zip file." -f @($listOfFiles[$i].FullName, (ConvertTo-FormattedNumber $listOfFiles[$i].Length DataSize "0.00"), (ConvertTo-FormattedNumber $maxZipSize DataSize "0.00")))
                    $listOfFiles.RemoveAt($i)
                }

                # Are there files to add to the .zip file?
                if($fileList.Length -gt 0)
                {
                    Set-Content -Path $fileListName -Value ($fileList -join "`r`n") -Encoding Ascii -Force
                    $zipCommandArgs = @(
                        "a",                                # Add files to archive
                        ("-i@{0}" -f @($fileListName)),     # ...from list of files
                        $zipFileName                        # name of archive file
                    )

                    & $sevenZipPath $zipCommandArgs        
                }
                else   # No, but it might be because adding the next file to the .zip file would over-flow it...
                {
                    # Are there files left to add to a .zip file?
                    if($listOfFiles.Count -gt 0)
                    {
                        # Yes, start a new zip file...
                        $zipCounter++
                    }
                }
            }
        }
    }

    while(($a -lt $files.Length) -and (($fileSizeSum + $files[$a].Length) -lt $zipSpaceLeft))
    {
        $fileSizeSum += $files[$a].Length
        $fileList += $files[$a].FullName.Replace(("{0}\" -f @($baseFolder)), "")
        $a++
    }

    if(($a -lt $files.Length) -and ($fileList.Length -eq 0))
    {
        if($files[$a].Length -gt $maxZipSize)
        {
            Write-Host ("File: {0} ({1}) too big for {2} sized zip file." -f @($files[$a].FullName, (ConvertTo-FormattedNumber $files[$a].Length DataSize "0.00"), (ConvertTo-FormattedNumber $maxZipSize DataSize "0.00")))
            $a++
        }
    }
    else
    {
        # Are there files to add to the .zip file?
        if($fileList.Length -gt 0)
        {
            Set-Content -Path $fileListName -Value ($fileList -join "`r`n") -Encoding Ascii -Force
            $zipCommandArgs = @(
                "a",                                # Add files to archive
                ("-i@{0}" -f @($fileListName)),     # ...from list of files
                $zipFileName                        # name of archive file
            )

            & $sevenZipPath $zipCommandArgs

        
        }
        else   # No, but it might be because adding the next file to the .zip file would over-flow it...
        {
            # Are there files left to add to a .zip file?
            if($a -lt $files.Length)
            {
                # Yes, start a new zip file...
                $zipCounter++
            }
        }
    }
}