$a = 0
while($a -lt $pfObjsMaster.Count)
{
    if($pfObjsMaster[$a].Saved2Temp)
    {
        $newFN = $newFileNames[$pfObjsMaster[$a].TempFileIndex]
        if(-not [String]::IsNullOrEmpty($newFN))
        {
            try
            {
                $fi = [System.IO.FileInfo]::new($pfObjsMaster[$a].TempFileName)
                if($fi.Exists)
                {
                    try
                    {
                        $nFI = [System.IO.FileInfo]::new($newFN)
                        if(-not $nFI.Exists)
                        {
                            try
                            {
                                $fi.MoveTo($newFN)
                                if($null -ne $pfObjsMaster[$a].CreationTime)
                                {
                                    try
                                    {
                                        $fi.CreationTime = $pfObjsMaster[$a].CreationTime
                                    }
                                    catch
                                    {
                                        Write-Host ("Failed on {0}, .CreationTime." -f @($a))
                                    }
                                }

                                if($null -ne $pfObjsMaster[$a].LastModificationTime)
                                {
                                    try
                                    {
                                        $fi.LastWriteTime = $pfObjsMaster[$a].LastModificationTime
                                    }
                                    catch
                                    {
                                        Write-Host ("Failed on {0}, .LastWriteTime." -f @($a))
                                    }
                                }
                            }
                            catch
                            {
                                Write-Host ("Failed on {0}, .MoveTo." -f @($a))
                            }
                        }
                    }
                    catch
                    {
                        Write-Host ("Failed on {0}, new file name check." -f @($a))
                    }
                }
            }
            catch
            {
                Write-Host ("Failed on {0}, old file name check." -f @($a))
            }
        }
    }

    $a++
}
