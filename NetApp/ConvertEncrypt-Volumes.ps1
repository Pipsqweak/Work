<#
if(($null -eq $cdot) -or (($null -ne $cdot) -and (-not ($cdot.ContainsKey('CDC-CDOTCLST01')))))
{
    Write-Verbose ("Connecting to CDC CDOT...")
    ConnectTo cdc,cdot,prod
}
#>

if(($null -eq $cdot) -or (-not ($cdot.ContainsKey('BDC-CDOTCLST01'))))
{
    Write-Verbose ("Connecting to DDC CDOT...")
    ConnectTo ddc,cdot,prod
}

$controllerVolumeDataRefreshed = [System.Collections.Generic.SortedDictionary[[System.String],[System.Boolean]]]::new()
# $controllers = @($cdot['CDC-CDOTCLST01'], $cdot['BDC-CDOTCLST01'])
$controllers = @($cdot['BDC-CDOTCLST01'])
$controllerEncryptionProgress = [System.Collections.Generic.SortedDictionary[[System.String],[System.Object]]]::new()


$d = "" | Select-Object ParentId, Id, PercentComplete, Activity, Status, StartTime, ETC
$d.ParentId = -1
$d.Id = 0
$d.PercentComplete = 0
$d.Activity = "Overall Volume encryption"
$d.Status = "0% Complete"
$d.StartTime = $null
$d.ETC = "N/A"

$controllerEncryptionProgress.Add("OVERALL", $d)

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

function UnixTimeStampToDateTime($unixTimeStamp)
{
    # Unix timestamp is seconds past epoch
    $dateTime = [DateTime]::new(1970, 1, 1, 0, 0, 0, 0, [DateTimeKind]::Utc)
    $dateTime = $dateTime.AddSeconds($unixTimeStamp).ToLocalTime()

    return $dateTime
}

function UpdateVolumeCounts
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [NetApp.Ontapi.Filer.C.NcController[]]
        $controllers
    )
    $Global:totalEncryptableVolumes = 0
    $Global:totalUnencryptedEncryptableVolumes = 0

    $controllers | Foreach-Object {
        $cntrlrName = @($_.Name -split '\.')[0].ToUpper()

        if ($Global:encryptableVolumesByController.ContainsKey($cntrlrName))
        {
            $Global:totalEncryptableVolumes += $Global:encryptableVolumesByController[$cntrlrName].Length
        } `
        else # NOT ($Global:encryptableVolumesByController.ContainsKey($cntrlrName))
        {
            # Nothing.
        }

        if ($Global:unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName))
        {
            $Global:totalUnencryptedEncryptableVolumes += $Global:unencryptedEncryptableVolumesByController[$cntrlrName].Length
        } `
        else # NOT ($Global:encryptableVolumesByController.ContainsKey($cntrlrName))
        {
            # Nothing.
        }
    }
}

function GetVolumeData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [NetApp.Ontapi.Filer.C.NcController]
        $cntrlr
    )

    $volsToIgnore = @("BDCDR-SVMA01:SMDV_vol_BDC_SVMA01_vol_SMB_Env_GIS_01")

    $cntrlrName = @($cntrlr.Name -split '\.')[0].ToUpper()
    $encryptableVolumes = @(Get-NCVol -Controller $cntrlr | Where-Object { ($_.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock" ) -and (-not $_.VolumeStateAttributes.IsNodeRoot) -and (-not $_.VolumeStateAttributes.IsVserverRoot) -and (("{0}:{1}" -f @($_.VServer, $_.Name)) -notin $volsToIgnore) })

    if ($Global:encryptableVolumesByController.ContainsKey($cntrlrName))
    {
        $Global:encryptableVolumesByController[$cntrlrName] = $encryptableVolumes
    } `
    else # NOT ($Global:encryptableVolumesByController.ContainsKey($cntrlrName))
    {
        $Global:encryptableVolumesByController.Add($cntrlrName, $encryptableVolumes)
    }

    $unencryptedEncryptableVolumes = @($Global:encryptableVolumesByController[$cntrlrName] | Where-Object { -not $_.Encrypt } | Sort-Object @{E={$_.VolumeSpaceAttributes.SizeUsed}; Descending=$false})

    if ($Global:unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName))
    {
        $Global:unencryptedEncryptableVolumesByController[$cntrlrName] = $unencryptedEncryptableVolumes
    } `
    else # NOT ($Global:unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName))
    {
        $Global:unencryptedEncryptableVolumesByController.Add($cntrlrName, $unencryptedEncryptableVolumes)
    }

    if (-not $Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName))
    {
        $Global:controllerVolumeDataRefreshed.Add($cntrlrName, $true)
    } `
    else # NOT (-not $Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName))
    {
        $Global:controllerVolumeDataRefreshed[$cntrlrName] = $true
    }
}

# Start with good volume data...
$Global:encryptableVolumesByController = [System.Collections.Generic.SortedDictionary[[System.String],[System.Object]]]::new()
$Global:unencryptedEncryptableVolumesByController = [System.Collections.Generic.SortedDictionary[[System.String],[System.Object]]]::new()

Write-Verbose ("Refreshing volume data...")
$controllers | Foreach-Object { Write-Verbose ("`t{0}..." -f @($_.Name)); [void] (GetVolumeData $_) }
UpdateVolumeCounts $controllers

do
{
    $controllers | Foreach-Object {
        $cntrlrName = @($_.Name -split '\.')[0].ToUpper()
        if (-not $Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName))
        {
            $Global:controllerVolumeDataRefreshed.Add($cntrlrName, $false)
        } `
        else # NOT (-not $Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName))
        {
            $Global:controllerVolumeDataRefreshed[$cntrlrName] = $false
        }
    }

    UpdateVolumeCounts $controllers

    if ($totalEncryptableVolumes -gt 0)
    {
        $controllerEncryptionProgress["OVERALL"].PercentComplete = [double] ("{0:N2}" -f ((($totalEncryptableVolumes - $totalUnencryptedEncryptableVolumes) / $totalEncryptableVolumes) * 100))
    } `
    else # NOT ($totalEncryptableVolumes -gt 0)
    {
        $controllerEncryptionProgress["OVERALL"].PercentComplete = 0
    }

    Write-Verbose ("Top of outer loop, totalUnencryptedEncryptableVolumes: {0}" -f @($totalUnencryptedEncryptableVolumes))
    # If there are any unencrypted volumes left...
    if ($totalUnencryptedEncryptableVolumes -gt 0)
    {
        $controllerEncryptionProgress["OVERALL"].Status = "{0}% Complete ({1} of {2} Encryptable volumes encrypted or being converted)" -f @($controllerEncryptionProgress["OVERALL"].PercentComplete, ($totalEncryptableVolumes - $totalUnencryptedEncryptableVolumes), $totalEncryptableVolumes)
#        Write-Progress -ParentId $controllerEncryptionProgress["OVERALL"].ParentId -Id $controllerEncryptionProgress["OVERALL"].Id -Activity $controllerEncryptionProgress["OVERALL"].Activity -Status $controllerEncryptionProgress["OVERALL"].Status -PercentComplete $controllerEncryptionProgress["OVERALL"].PercentComplete

        $a = 0
        while($a -lt $controllers.Length)
        {
            $cntrlr = $controllers[$a]

            $cntrlrName = @($cntrlr.Name -split '\.')[0].ToUpper()

            # If there appears to be no more $unencryptedEncryptableVolumes, then refresh the volume data to make sure...
            if ((-not $unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName)) -or ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -eq 0))
            {
                Write-Host ("Refreshing volume data for {0}..." -f @($cntrlrName))

                GetVolumeData $cntrlr
                UpdateVolumeCounts $controllers
            } `
            else # NOT ((-not $unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName)) -or ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -eq 0))
            {
                # Nothing.
            }

            # If there are more $unencryptedEncryptableVolumes, press on...
            if($unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName) -and ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -gt 0))
            {
                # If there is no progress tracker for this controller, then create one.
                if(-not $controllerEncryptionProgress.ContainsKey($cntrlrName))
                {
                    $d = "" | Select-Object Volume,ParentId, Id, PercentComplete, Activity, Status, StartTime, ETC
                    $d.Volume = $null
                    $d.ParentId = 0
                    $d.Id = $a + 1
                    $d.PercentComplete = 0
                    $d.Activity = "N/A"
                    $d.Status = "N/A"
                    $d.StartTime = $null
                    $d.ETC = "N/A"

                    $controllerEncryptionProgress.Add($cntrlrName, $d)
                } `
                else # NOT ((-not $controllerEncryptionProgress.ContainsKey($cntrlrName)))
                {
                    # Nothing
                }

                # Get the conversion operations in progress for this controller...
                $encryptionConversions = @(Get-NcVolumeEncryptionConversion -Controller $cntrlr)

                Write-Verbose ("Encryptions conversions for {0}: {1}." -f @($cntrlrName, $encryptionConversions.Length))

                # If there are no conversions in progress...
                if ($encryptionConversions.Length -eq 0)
                {
                    # If there is an encryption progress trackers for this controller, then mark it complete since we didn't find any active encryption processes for it.
                    if ($controllerEncryptionProgress.ContainsKey($cntrlrName))
                    {
                        $ended = [DateTime]::Now
                        if ($null -ne $controllerEncryptionProgress[$cntrlrName].Volume)
                        {
                            if ($null -ne $controllerEncryptionProgress[$cntrlrName].StartTime)
                            {
                                $started = $controllerEncryptionProgress[$cntrlrName].StartTime.ToString("yyyy-MM-dd hh:mm:ss")
                                $elapsed = ($ended - $controllerEncryptionProgress[$cntrlrName].StartTime).ToString("dd\.hh\:mm\:ss")
                                Write-Host ("{0}:{1}:{2} Started: {3} / Completed - {4} / Elapsed: {5}" -f @((($controllerEncryptionProgress[$cntrlrName].Volume.NCController.Name -split '\.')[0].ToUpper()), $controllerEncryptionProgress[$cntrlrName].Volume.Vserver, $controllerEncryptionProgress[$cntrlrName].Volume.Name, $started, $ended.ToString("yyyy-MM-dd hh:mm:ss"), $elapsed))
                            } `
                            else # NOT ($null -ne )
                            {
                                Write-Host ("{0}:{1}:{2} Completed - {3}" -f @((($controllerEncryptionProgress[$cntrlrName].Volume.NCController.Name -split '\.')[0].ToUpper()), $controllerEncryptionProgress[$cntrlrName].Volume.Vserver, $controllerEncryptionProgress[$cntrlrName].Volume.Name, $ended.ToString("yyyy-MM-dd hh:mm:ss")))
                            }
                        } `
                        else # NOT ($null -ne $controllerEncryptionProgress[$cntrlrName].Volume)
                        {
                            # Nothing.
                        }

                        # Remove the completed progress data...
                        [void] $controllerEncryptionProgress.Remove($cntrlrName)
                    } `
                    else # NOT ($controllerEncryptionProgress.ContainsKey($cntrlrName))
                    {
                        # Nothing.
                    }

                    # If the volume data for this controller was not just refreshed, then refresh it.
                    if ($Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName) -and (-not $Global:controllerVolumeDataRefreshed[$cntrlrName]))
                    {
                        # Retrieve volume data for this controller.  Refresh the data since we want to ensure we have accurate information before trying to convert/encrypt another volume.
                        Write-Host ("Refreshing volume data for {0}..." -f @($cntrlrName))

                        GetVolumeData $cntrlr
                        UpdateVolumeCounts $controllers
                    } `
                    else # NOT (-not $Global:controllerVolumeDataRefreshed.ContainsKey($cntrlrName))
                    {
                        # Nothing
                    }

                    # Might have just refreshed volume data for this controller so make sure there are volumes left to encrypt.
                    if ($unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName) -and ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -gt 0))
                    {
                        $nextVolumeToEncrypt = $unencryptedEncryptableVolumesByController[$cntrlrName][0]
                        try
                        {
                            Write-Verbose ("Encryption conversion started for {0}:{1}:{2} ({3} used)" -f @($cntrlrName, $nextVolumeToEncrypt.Vserver, $nextVolumeToEncrypt.Name, (Format-StorageNumber ($nextVolumeToEncrypt.TotalSize - $nextVolumeToEncrypt.Available))))
                            Start-NcVolumeEncryptionConversion -Controller $nextVolumeToEncrypt.NcController -VserverContext $nextVolumeToEncrypt.VServer -Volume $nextVolumeToEncrypt.Name -Confirm:$false -ErrorAction Stop | Out-Null
                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red ("Encryption conversion failed for {0}:{1}:{2}" -f @($nextVolumeToEncrypt.NcController.Name, $nextVolumeToEncrypt.VServer, $nextVolumeToEncrypt.Name))
                        }
                    } `
                    else # NOT ($unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName) -and ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -gt 0))
                    {
                        # Nothing.
                    }
                } `
                else # NOT ($encryptionConversions.Length -eq 0)
                {
                    $v = $unencryptedEncryptableVolumesByController[$cntrlrName] | Where-Object { ($_.NCController.Name -eq $encryptionConversions[0].NcController.Name) -and ($_.Vserver -eq $encryptionConversions[0].Vserver) -and ($_.Name -eq $encryptionConversions[0].Volume) }
                    if($null -ne $v)
                    {
                        $controllerEncryptionProgress[$cntrlrName].Volume = $v
                        $controllerEncryptionProgress[$cntrlrName].Activity = "{0}:{1}:{2} ({3} [Used: {4}])" -f @(($encryptionConversions[0].NCController.Name -split '\.')[0].ToUpper(), $encryptionConversions[0].Vserver, $encryptionConversions[0].Volume, (Format-StorageNumber $v.TotalSize), (Format-StorageNumber $v.VolumeSpaceAttributes.SizeUsed))
                    }
                    else
                    {
                        $controllerEncryptionProgress[$cntrlrName].Activity = "{0}:{1}:{2}" -f @(($encryptionConversions[0].NCController.Name -split '\.')[0].ToUpper(), $encryptionConversions[0].Vserver, $encryptionConversions[0].Volume)
                    }

                    if ($null -eq $controllerEncryptionProgress[$cntrlrName].StartTime)
                    {
                        $controllerEncryptionProgress[$cntrlrName].StartTime = UnixTimeStampToDateTime $encryptionConversions[0].StartTime
                    } `
                    else # NOT ($null -eq $controllerEncryptionProgress[$cntrlrName].StartTime)
                    {
                        # Nothing.
                    }

                    if($encryptionConversions[0].PercentageCompleted -match "^(\d+)")
                    {
                        $controllerEncryptionProgress[$cntrlrName].PercentComplete = [int] $Matches[1]
                    }
                    else
                    {
                        # Nothing  -- just leave .PercentComplete the way it is...
                    }
                }
            } `
            else # NOT (($unencryptedEncryptableVolumesByController.ContainsKey($cntrlrName) -and ($unencryptedEncryptableVolumesByController[$cntrlrName].Length -gt 0)))
            {
                # If there is an encryption progress tracker for this controller, then remove it
                if ($controllerEncryptionProgress.ContainsKey($cntrlrName))
                {
                    $controllerEncryptionProgress.Remove($cntrlrName)
                } `
                else # NOT ($controllerEncryptionProgress.ContainsKey($cntrlrName))
                {
                    # Nothing.
                }
            }

            $a++
        }

        # If any controller has more volumes to encrypt, then pause for station identification.
        if ($totalUnencryptedEncryptableVolumes -gt 0)
        {
            # Adjust the maximum width of the progress bar based on the console window width
            $PSStyle.Progress.MaxWidth = (Get-Host).UI.RawUI.WindowSize.Width
            foreach($progress in @($controllerEncryptionProgress.Values | Sort-Object ParentId, Id))
            {
                $progress.ETC = "N/A"
                if ($null -ne $progress.StartTime)
                {
                    $elapsed = [DateTime]::Now - $progress.StartTime
                    $elapsedPerMS = $elapsed.TotalMilliseconds / [double]($progress.PercentComplete)
    #                Write-Host ("{0}" -f @($elapsedPerMS))

                    try
                    {
                        if(($elapsedPerMS * 100) -gt [System.Int32]::MaxValue)
                        {
                            # Less accurate, but should not throw an exception...
                            $etcTS = [TimeSpan]::new(0,0,0,($elapsedPerMS / 10), 0)
                        }
                        else
                        {
                            $etcTS = [TimeSpan]::new(0,0,0,0,($elapsedPerMS * 100))
                        }

                        $etc = $progress.StartTime + $etcTS
                        $progress.ETC = $etc.ToString("yyyy-MM-dd HH\:mm\:ss")
                    }
                    catch
                    {

                    }

                    if ($progress.ParentId -ne -1)
                    {
                        $progress.Status = "{0}% Complete (Elapsed: {1}, ETC: {2})" -f @($progress.PercentComplete, $elapsed.ToString("dd\.hh\:mm\:ss\.ff"), $progress.ETC)
                    } `
                    else # NOT ($progress.ParentId -ne -1)
                    {
                        $progress.Status = "{0}% Complete ({1} of {2} Volumes encrypted or being converted)" -f @($progress.PercentComplete, ($encryptableVolumes.Length - $eligibleVolumes.Length), $encryptableVolumes.Length)
                    }
                } `
                else # NOT ($null -ne $progress.StartTime)
                {
                    $progress.Status = "{0}% Complete ({1} of {2} Encryptable volumes encrypted or being converted)" -f @($progress.PercentComplete, ($totalEncryptableVolumes - $totalUnencryptedEncryptableVolumes), $totalEncryptableVolumes)
                }
    #Write-Host ("Write-Progress -ParentId {0} -Id {1} -Activity {2} -Status {3} -PercentComplete {4}" -f @($progress.ParentId, $progress.Id , $progress.Activity, $progress.Status, $progress.PercentComplete))
                Write-Progress -ParentId $progress.ParentId -Id $progress.Id -Activity $progress.Activity -Status $progress.Status -PercentComplete $progress.PercentComplete

            }
        } `
        else # NOT ($totalUnencryptedEncryptableVolumes -gt 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($totalUnencryptedEncryptableVolumes -gt 0)
    {
        # Nothing.
    }

    if ($totalUnencryptedEncryptableVolumes -gt 0)
    {
        # If we just refreshed volume data from a controller, then we'll use the time it took to collect the data as the pause, otherwise, let's take a break
        if (@(@($controllerVolumeDataRefreshed.Values) | Where-Object { $_ }).Length -eq 0)
        {
            Start-Sleep -Seconds 10
        } `
        else # NOT (-not $volumeDataRefreshed)
        {
            # Nothing.
        }
    } `
    else # NOT ($totalUnencryptedEncryptableVolumes -gt 0)
    {
        # Nothing.
    }

    # Keep going until all volumes are converted.
} while($totalUnencryptedEncryptableVolumes -gt 0)
