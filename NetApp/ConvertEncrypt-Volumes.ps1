ConnectTo cdc,cdot
ConnectTo ddc,cdot

$controllerEncryptionComplete = [System.Collections.Generic.SortedDictionary[[System.String],[System.Boolean]]]::new()
$controllers = @($cdot['CDC-CDOTCLST01'], $cdot['BDC-CDOTCLST01'])


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

do
{
    foreach($cntrlr in $controllers)
    {
        $cntrlrName = @($cntrlr.Name -split '\.')[0].ToUpper()
        if(-not $controllerEncryptionComplete.ContainsKey($cntrlrName))
        {
            $controllerEncryptionComplete.Add($cntrlrName, $false)
        }

        if(-not $controllerEncryptionComplete[$cntrlrName])
        {
            # Get the conversion operations in progress...
            $encryptionConversions = @(Get-NcVolumeEncryptionConversion -Controller $cntrlr)

            # If there are no conversions in progress...
            if ($encryptionConversions.Length -eq 0)
            {
                # Get an array of the volumes that are eligible for conversion, sorted by least used space...
                $eligibleVolumes = @(Get-NCVol -Controller $cntrlr | Where-Object { ($_.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock" ) -and (-not $_.VolumeStateAttributes.IsNodeRoot) -and (-not $_.VolumeStateAttributes.IsVserverRoot) -and (-not $_.Encrypt) } | Sort-Object @{E={$_.TotalSize - $_.Available};Descending=$false})

                # If there is at least 1 volume left to convert...
                if ($eligibleVolumes.Length -gt 0)
                {
                    try
                    {
                        Start-NcVolumeEncryptionConversion -Controller $eligibleVolumes[0].NcController -VserverContext $eligibleVolumes[0].VServer -Volume $eligibleVolumes[0].Name -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Host -NoNewline ("`r`nEncryption conversion started for {0}:{1}:{2} ({3} used)" -f @($cntrlrName, $eligibleVolumes[0].Vserver, $eligibleVolumes[0].Name, (Format-StorageNumber ($eligibleVolumes[0].TotalSize - $eligibleVolumes[0].Available))))
                        # If there was only 1 volume left to convert, then this controller is done since we just launched the process to convert the final volume
                        $controllerEncryptionComplete[$cntrlrName] = $eligibleVolumes.Length -le 1
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("`r`nEncryption conversion failed for {0}:{1}:{2}" -f @($cntrlrName, $eligibleVolumes[0].Vserver, $eligibleVolumes[0].Name))
                        $controllerEncryptionComplete[$cntrlrName] = $true # Had an error, so stop
                    }
                } `
                else # NOT ($eligibleVolumes.Length -gt 0)
                {
                    # No volumes found to encrypt
                    $controllerEncryptionComplete[$cntrlrName] = $true
                }
            } `
            else # NOT ($encryptionConversions.Length -eq 0)
            {
                # Nothing, there is a conversion running, so don't start another one...
            }
        }
    }

    # If any controller has more volumes to encrypt, then pause for station identification.
    if (@($controllerEncryptionComplete.Values | Where-Object { -not $_ }).Length -gt 0)
    {
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 10
    } `
    else # NOT (@($controllerEncryptionComplete.Values | Where-Object { -not $_ }).Length -gt 0)
    {
        # Nothing.
    }

    # Keep going until all volumes are converted.
} while(@($controllerEncryptionComplete.Values | Where-Object { -not $_ }).Length -gt 0)
