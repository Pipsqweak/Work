function AddLongUNCPath($str) { $retval = $str; if($str -notmatch "^\\\\\?\\unc\\") { $retval = $str -replace "^\\\\","\\?\UNC\" } return $retval }

function RemoveLongUNCPath($str) { return ($str -replace "^\\\\\?\\UNC\\","\\") }

function NewDictionaryLeaf($dict, $key, $translation = [String]::Empty, $cifsServer = [String]::Empty, $fs1Alias = [String]::Empty)
{
    if(-not $dict.ContainsKey($key))
    {
            #Write-Host ("{0}" -f @($key))
        $dict.Add($key, [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
            <#
            if(-not [String]::IsNullOrEmpty($translation))
            {
                Write-Host ("->{0}" -f @($translation))
            }
            #>
        $dict[$key].Add("CIFSServer", $cifsServer)
        $dict[$key].Add("FS1Alias", $fs1Alias)
        $dict[$key].Add("Translation", $translation)
        $dict[$key].Add("Children", [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
    }

    return @( , $dict[$key]["Children"])
}

<#
    BuildTranslationDictionaryFromCSV reads the contents of a CSV file previously created with ExportNCCIFSSharesToCSV then creates a dictionary used to translate
#>
function BuildTranslationDictionaryFromCSV
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $translationCSVPath,

        [Parameter(Mandatory=$false,Position=1)]
        [String]
        $forServer = [String]::Empty
    )

    try
    {
        $allCifsShares = Import-CSV -Delimiter "`t" -Path $translationCSVPath

        $Global:pathTranslationDictionary = [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $uniqueCifsServers = @($allCifsShares | Select-Object -Unique -ExpandProperty CifsServer)

        $uniqueCifsServers = @($allCifsShares | Select-Object -Unique CifsServer, FS1Alias)

        if(-not [String]::IsNullOrEmpty($forServer))
        {
            $uniqueCifsServers = @($uniqueCifsServers | Where-Object { ($_.CifsServer -eq $forServer) -or (($_.FS1Alias -eq $forServer)) })
        }
        $a = 0
        while($a -lt $uniqueCifsServers.Length)
        {
            $translationDictionary = $Global:pathTranslationDictionary

            $translationDictionary = NewDictionaryLeaf -dict $translationDictionary -key $uniqueCifsServers[$a].CifsServer -cifsServer $uniqueCifsServers[$a].CifsServer -fs1Alias $uniqueCifsServers[$a].FS1Alias
            $cifsServerShares = [System.Collections.Generic.List[Object]]::new()
            @($allCifsShares | Where-Object { ($_.CifsServer -eq $uniqueCifsServers[$a].CifsServer) -or ($_.FS1Alias -eq $uniqueCifsServers[$a].FS1Alias) } | Sort-Object Path) | ForEach-Object { $cifsServerShares.Add($_) }

            $shareNum = 0
            while($shareNum -lt $cifsServerShares.Count)
            {
                $parentCifsShare = $cifsServerShares[$shareNum]
                $childShares = @($cifsServerShares | Where-Object { ($_.Path -ne $parentCifsShare.Path) -and $_.Path.StartsWith($parentCifsShare.Path) })
                if($childShares.Length -gt 0)
                {
                    $translationDictionary = NewDictionaryLeaf -dict $translationDictionary -key $parentCifsShare.ShareName -cifsServer $uniqueCifsServers[$a].CifsServer -fs1Alias $uniqueCifsServers[$a].FS1Alias
                    $parentTranslationDictionary = $translationDictionary
                    [void] $cifsServerShares.Remove($parentCifsShare)
                    $b = 0
                    while($b -lt $childShares.Length)
                    {
                        $translationDictionary = $parentTranslationDictionary
                        $subFolders = ($childShares[$b].Path -replace $parentCifsShare.Path, "").Split(@('/'), [System.StringSplitOptions]::RemoveEmptyEntries)
                        $c = 0
                        while($c -lt $subFolders.Length)
                        {
                            if(-not $translationDictionary.ContainsKey($subFolders[$c]))
                            {
                                if($c -eq ($subFolders.Length - 1))
                                {
                                    # Write-Host ("`t`t[{0}] -> {1}" -f @($subFolders[$c], ("{0}\{1}" -f @($childShares[$b].CifsServer, $childShares[$b].ShareName))))
                                    $translationDictionary = NewDictionaryLeaf -dict $translationDictionary -key $subFolders[$c] -translation ("{0}\{1}" -f @($childShares[$b].CifsServer, $childShares[$b].ShareName)) -cifsServer $uniqueCifsServers[$a].CifsServer -fs1Alias $uniqueCifsServers[$a].FS1Alias
                                }
                                else
                                {
                                    # Write-Host ("`t`tadding child key: {0}" -f @($subFolders[$c]))
                                    $translationDictionary = NewDictionaryLeaf -dict $translationDictionary -key $subFolders[$c] -cifsServer $uniqueCifsServers[$a].CifsServer -fs1Alias $uniqueCifsServers[$a].FS1Alias
                                }
                            }
                            else
                            {
                                $translationDictionary = $translationDictionary[$subFolders[$c]]["Children"]
                            }

                            $c++
                        }
                        [void] $cifsServerShares.Remove($childShares[$b])

                        $b++
                    }
                }
                $shareNum++
            }
            $a++
        }
    }
    catch
    {
        # [Log]::Error("CIFS server shares file {0} not found." -f @($translationCSVPath))
    }
}

function TranslatePath($pathToTranslate)
{
    $tDict = $Global:pathTranslationDictionary
    $tPath = RemoveLongUNCPath $pathToTranslate
    $d = "" | Select-Object TranslatedPath, DirectShare

    $d.TranslatedPath = $pathToTranslate

    $pathParts = $tPath.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)

    $a = 0
    while(($a -lt $pathParts.Length) -and $tDict.ContainsKey($pathParts[$a]) -and ($tDict[$pathParts[$a]]["Children"].Keys.Count -gt 0))
    {
        if(@($tDict.Keys | Where-Object { $_ -eq $pathParts[$a] }).Length -eq 1)
        {
            $pathParts[$a] = @($tDict.Keys | Where-Object { $_ -eq $pathParts[$a] })[0]
            $d.DirectShare = "\\{0}" -f @(($pathParts[0..1] -join "\"))
        }

        # If there is a translation at this point, let's capture it...
        if(-not [String]::IsNullOrEmpty($tDict[$pathParts[$a]]["Translation"]))
        {
            $d.DirectShare = "\\{0}" -f @($tDict[$pathParts[$a]]["Translation"])
            $d.TranslatedPath = $pathToTranslate -replace [Regex]::Escape(($pathParts[0..$a] -join "\")), $tDict[$pathParts[$a]]["Translation"]
        }
        #Write-Host ("{0}) {1} : [{2}]" -f @($a, $pathParts[$a], $tDict[$pathParts[$a]]["Translation"]))
        $tDict = $tDict[$pathParts[$a]]["Children"]
        $a++
    }

    if(($a -lt $pathParts.Length) -and ($tDict.ContainsKey($pathParts[$a])) -and (-not [String]::IsNullOrEmpty($tDict[$pathParts[$a]]["Translation"])))
    {
        $d.DirectShare = "\\{0}" -f @($tDict[$pathParts[$a]]["Translation"])
        $d.TranslatedPath = $pathToTranslate -replace [Regex]::Escape(($pathParts[0..$a] -join "\")), $tDict[$pathParts[$a]]["Translation"]
    }

    if($pathToTranslate -match "^\\\\\?\\unc\\")
    {
        $d.DirectShare = AddLongUNCPath $d.DirectShare
    }

    if(($null -ne $pathParts) -and ($pathParts.Length -gt 0) -and (-not [String]::IsNullOrEmpty($pathParts[0])) -and $Global:pathTranslationDictionary.ContainsKey($pathParts[0]) -and (-not [String]::IsNullOrEmpty($Global:pathTranslationDictionary[$pathParts[0]].CIFSServer)) -and (-not [String]::IsNullOrEmpty($Global:pathTranslationDictionary[$pathParts[0]].FS1Alias)))
    {
        $d.DirectShare = [regex]::Replace($d.DirectShare, ("\\{0}\\" -f @($Global:pathTranslationDictionary[$pathParts[0]].CIFSServer)), ("\{0}\" -f @($Global:pathTranslationDictionary[$pathParts[0]].FS1Alias)))
        $d.TranslatedPath = [regex]::Replace($d.TranslatedPath, ("\\{0}\\" -f @($Global:pathTranslationDictionary[$pathParts[0]].CIFSServer)), ("\{0}\" -f @($Global:pathTranslationDictionary[$pathParts[0]].FS1Alias)))
    }

    return $d
}

function TestTranslation($testPath)
{
    $Global:translationSW.Start()
    $Global:translationsAttempted++
    $translation = TranslatePath $testPath
    $Global:translationSW.Stop()

    return $translation
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

function GetPathOwners($sharePath)
{
    $ownerList = $null
    $retries = 0
    do
    {
        $di = [System.IO.DirectoryInfo]::new($sharePath)
        if(-not $di.Exists)
        {
            Start-Sleep -Milliseconds 200
            $retries++
        }
    } until(($retries -eq 3) -or ($di.Exists))

    if($di.Exists)
    {
        # Get all groups with FullControl or Modify access -- these I'll call owners since they have the ability to create new files and folder and delete old ones.
        #   Also filter out "FS-FileServices-ADM"
        $acl = $di.GetAccessControl()
        $fcAccessRules = @($acl.Access | Where-Object { (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl) -and (($_.AccessControlType -band [System.Security.AccessControl.AccessControlType]::Allow) -eq [System.Security.AccessControl.AccessControlType]::Allow) -and ($_.IdentityReference.Value -notmatch "FS-FileServices-ADM") })

        # For Modify Rules...
        $modifyAccessRules = @($acl.Access | Where-Object { (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -ne [System.Security.AccessControl.FileSystemRights]::FullControl) -and (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) -eq [System.Security.AccessControl.FileSystemRights]::Modify) -and (($_.AccessControlType -band [System.Security.AccessControl.AccessControlType]::Allow) -eq [System.Security.AccessControl.AccessControlType]::Allow) -and ($_.IdentityReference.Value -notmatch "FS-FileServices-ADM") })

        if(($fcAccessRules.Length -eq 0) -and ($modifyAccessRules.Length -eq 0))
        {
            Write-Host ("No FC or RW group for {0}." -f @($di.FullName))
        }
        else
        {
            # Remember, $accessRules is an array of arrays!
            #   $accessRules.Length is a thing...and
            #   $accessRules[0].Length is also a thing...
            $accessRules = @($fcAccessRules, $modifyAccessRules)
            $ownerList = [System.Collections.Generic.List[System.String]]::new()

            $b = 0
            while($b -lt $accessRules.Length)
            {
                $c = 0
                while($c -lt $accessRules[$b].Length)
                {
                    $ownerList.Add($accessRules[$b][$c].IdentityReference.Value)
                    $acctParts = $accessRules[$b][$c].IdentityReference.Value -split "\\"
                    $acctName = $acctParts[$acctParts.Length - 1]

                    if($acctName -eq "everyone")
                    {
                        Write-Host $di.FullName
                        Write-Host ("*************** ALERT!!! ************")
                        Write-Host ("Found Everyone in FC or RW Access Rule")
                    }

                    $c++
                }
                $b++
            }
        }
    }

    # ensure the ownerlist is returned as a list and not an array.
    return @(, $ownerList)
}

function ShowStats
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $saveToPath = [String]::Empty
    )

    $shareKeys = @($Global:sizeByAgeDict.Keys)

    $statData = [System.Collections.Generic.List[Object]]::new()
    $t = "" | Select-Object ShareName, Directories, Files, TotalSize, LT1Count, LT1Size, GE1Count, GE1Size, GE2Count, GE2Size, GE3Count, GE3Size, GE4Count, GE4Size, GE5Count, GE5Size, GE6Count, GE6Size, GE7Count, GE7Size, GE8Count, GE8Size, GE9Count, GE9Size, GE10Count, GE10Size
    $t.ShareName = "Total"
    $a = 0
    while($a -lt $shareKeys.Length)
    {
        $key = $shareKeys[$a]
        $d = "" | Select-Object ShareName, Directories, Files, TotalSize, LT1Count, LT1Size, GE1Count, GE1Size, GE2Count, GE2Size, GE3Count, GE3Size, GE4Count, GE4Size, GE5Count, GE5Size, GE6Count, GE6Size, GE7Count, GE7Size, GE8Count, GE8Size, GE9Count, GE9Size, GE10Count, GE10Size
        $d.ShareName = RemoveLongUNCPath $key
        $d.Directories = $Global:sizeByAgeDict[$key].Directories
        $t.Directories += $d.Directories
        $d.Files = $Global:sizeByAgeDict[$key].Files
        $t.Files += $d.Files
        $d.TotalSize = $Global:sizeByAgeDict[$key].TotalSize
        $t.TotalSize += $d.TotalSize
        $fileAgeKeyIdx = [ShareStats]::FileAgeKeys.Count - 1
        $d.LT1Count =  $Global:sizeByAgeDict[$key].Files - $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.LT1Count += $d.LT1Count
        $d.LT1Size = $Global:sizeByAgeDict[$key].TotalSize - $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Size
        $t.LT1Size += $d.LT1Size

        $d.GE1Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE1Count += $d.GE1Count
        $d.GE1Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE1Size += $d.GE1Size

        $d.GE2Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE2Count += $d.GE2Count
        $d.GE2Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE2Size += $d.GE2Size

        $d.GE3Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE3Count += $d.GE3Count
        $d.GE3Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE3Size += $d.GE3Size

        $d.GE4Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE4Count += $d.GE4Count
        $d.GE4Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE4Size += $d.GE4Size

        $d.GE5Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE5Count += $d.GE5Count
        $d.GE5Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE5Size += $d.GE5Size

        $d.GE6Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE6Count += $d.GE6Count
        $d.GE6Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE6Size += $d.GE6Size

        $d.GE7Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE7Count += $d.GE7Count
        $d.GE7Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE7Size += $d.GE7Size

        $d.GE8Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE8Count += $d.GE8Count
        $d.GE8Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE8Size += $d.GE8Size

        $d.GE9Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE9Count += $d.GE9Count
        $d.GE9Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE9Size += $d.GE9Size

        $d.GE10Count = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx]].Count
        $t.GE10Count += $d.GE10Count
        $d.GE10Size = $Global:sizeByAgeDict[$key].FilesByAge[[ShareStats]::FileAgeKeys[$fileAgeKeyIdx--]].Size
        $t.GE10Size += $d.GE10Size
        $statData.Add($d)

        $a++
    }

    if(-not [String]::IsNullOrEmpty($saveToPath))
    {
        try
        {
            $statData | Export-Csv -NoTypeInformation -Delimiter "`t" -Path $saveToPath
        }
        catch
        {

        }
    }
    else
    {
        $cbd = $statData | ConvertTo-Csv -NoTypeInformation -Delimiter "`t"
        $cbd[1..($cbd.Length - 1)] | Set-Clipboard
        $t | Format-Table -AutoSize -Property *
        Write-Host "Stats copied to clipboard"
    }
}

function ShowOwners
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $saveToPath = [String]::Empty
    )

    $shareKeys = @($Global:sizeByAgeDict.Keys)

    $statData = [System.Collections.Generic.List[Object]]::new()
    $a = 0
    while($a -lt $shareKeys.Length)
    {
        $key = $shareKeys[$a]
        $d = "" | Select-Object ShareName, Owners
        $d.ShareName = RemoveLongUNCPath $key
        $d.Owners = $Global:sizeByAgeDict[$key].Owners -join ", "
        $statData.Add($d)

        $a++
    }

    if(-not [String]::IsNullOrEmpty($saveToPath))
    {
        try
        {
            $statData | Export-Csv -NoTypeInformation -Delimiter "`t" -Path $saveToPath
        }
        catch
        {

        }
    }
    else
    {
        $cbd = $statData | ConvertTo-Csv -NoTypeInformation -Delimiter "`t"
        $cbd[1..($cbd.Length - 1)] | Set-Clipboard
        $cbd | Format-Table -AutoSize -Property *
        Write-Host "Owners copied to clipboard"
    }
}

function CaptureExplicitACLRules($fsi)
{
    $abandonedRuleFound = $false
    if($null -ne $fsi)
    {
        try
        {
            $fsiACL = $fsi.GetAccessControl()
            $explicitRules = @($fsiACL.Access | Where-Object { -not $_.IsInherited })

            $a = 0
            while($a -lt $explicitRules.Length)
            {
                $kk = "" | Select-Object Path, FileSystemRights,AccessControlType,IdentityReference,InheritanceFlags,PropagationFlags
                $kk.Path = $fsi.FullName
                $kk.FileSystemRights = $fsiACL.Access[$a].FileSystemRights.ToString()
                $kk.AccessControlType = $fsiACL.Access[$a].AccessControlType.ToString()
                $kk.IdentityReference = $fsiACL.Access[$a].IdentityReference.ToString()
                $kk.InheritanceFlags = $fsiACL.Access[$a].InheritanceFlags.ToString()
                $kk.PropagationFlags = $fsiACL.Access[$a].PropagationFlags.ToString()

                $Global:explicitACLRules.Add($kk)

                if((-not $abandonedRuleFound) -and ($kk.IdentityReference -match "^S-1-5"))
                {
                    Write-Host ("Abandoned ACL rule on {0}." -f @($kk.Path))
                    $abandonedRuleFound = $true
                }

                $a++
            }
        }
        catch
        {

        }
    }
    else
    {
        Write-Host ("Null `$fsi sent to CaptureExplicitACLRules")
    }
}

function DumpExplicitACLs()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $saveToPath = [String]::Empty
    )

    if($Global:explicitACLRules.Count -gt 0)
    {
        $Global:explicitACLRules | Export-Csv -NoTypeInformation -Delimiter "`t" -Path $saveToPath -Force
    }
    else
    {
        Write-Host "No explicit ACL rules found."
    }
}

function DumpExceptions()
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [String]
        $saveToPath = [String]::Empty
    )

    if($Global:directoryExceptions.Count -gt 0)
    {
        $Global:directoryExceptions | Export-Csv -NoTypeInformation -Delimiter "`t" -Path $saveToPath -Force
    }
    else
    {
        Write-Host "No explicit ACL rules found."
    }
}

function ListDirectory
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [System.Object]
        $di,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $folderToSaveTo,

        [Parameter(Mandatory=$true,Position=2)]
        [String]
        $serverName
    )

    if($null -ne $di)
    {
        if($di -is [System.IO.DirectoryInfo])
        {
            $pathTranslation = TestTranslation $di.FullName
            CaptureExplicitACLRules $di

            if(-not $Global:sizeByAgeDict.ContainsKey($pathTranslation.DirectShare))
            {
                $owners = GetPathOwners $pathTranslation.DirectShare

                $Global:sizeByAgeDict.Add($pathTranslation.DirectShare, [ShareStats]::new($owners))
            }
            $Global:sizeByAgeDict[$pathTranslation.DirectShare].Directories++

            $diDirectories = $null
            try
            {
                $diDirectories = @($di.GetDirectories() | Where-Object { $_.Name -notmatch "~snapshot" })
            }
            catch
            {
                $formatstring = "{5}`r`n{0} : {1}`n{2}`n" +
                "    + CategoryInfo          : {3}`n" +
                "    + FullyQualifiedErrorId : {4}`n"
                $fields = $_.InvocationInfo.MyCommand.Name,
                        $_.ErrorDetails.Message,
                        $_.InvocationInfo.PositionMessage,
                        $_.CategoryInfo.ToString(),
                        $_.FullyQualifiedErrorId,
                        $di.FullName

                $formatstring -f $fields
                Write-Host -Foreground Red -Background Black ($formatstring -f $fields)

                $Global:directoryExceptions.Add($di.FullName)
            }

            if($null -ne $diDirectories)
            {
                $diDirectories | ForEach-Object {
                    ListDirectory -di $_ -folderToSaveTo $folderToSaveTo -serverName $serverName
                }

                $diFiles = $null
                try
                {
                    $diFiles = $di.GetFiles()
                }
                catch
                {
                    $formatstring = "{5}`r`n{0} : {1}`n{2}`n" +
                    "    + CategoryInfo          : {3}`n" +
                    "    + FullyQualifiedErrorId : {4}`n"
                    $fields = $_.InvocationInfo.MyCommand.Name,
                            $_.ErrorDetails.Message,
                            $_.InvocationInfo.PositionMessage,
                            $_.CategoryInfo.ToString(),
                            $_.FullyQualifiedErrorId,
                            $di.FullName

                    $formatstring -f $fields
                    Write-Host -Foreground Red -Background Black ($formatstring -f $fields)

                    $Global:directoryExceptions.Add($di.FullName)
                }

                if($null -ne $diFiles)
                {
                    $Global:sizeByAgeDict[$pathTranslation.DirectShare].Files += $diFiles.Length
                    $diFiles | ForEach-Object {
                        $fi = $_
                        CaptureExplicitACLRules $fi
                        $Global:sizeByAgeDict[$pathTranslation.DirectShare].TotalSize += $fi.Length
                        foreach($ageKey in [ShareStats]::FileAgeKeys)
                        {
                            if($fi.LastWriteTime -le $ageKey)
                            {
                                $Global:sizeByAgeDict[$pathTranslation.DirectShare].FilesByAge[$ageKey].Count++
                                $Global:sizeByAgeDict[$pathTranslation.DirectShare].FilesByAge[$ageKey].Size += $fi.Length
                            }
                        }

                        # [void] (AddFSIToDB $db $_ $false)
                        if([Console]::KeyAvailable)
                        {
                            $fileTranslation = TranslatePath $fi.FullName
                            $keyPressed = [Console]::ReadKey($false)
                            $keyRead = $keyPressed.Key

                            Write-Host ("`r`n{0}`r`nTranslated: {1}`t{2}`t{3}" -f @($_.FullName, $fileTranslation.TranslatedPath, (Format-StorageNumber $_.Length), $_.CreationTime.ToString("yyyyMMdd hh:mm:ss")))
                            if(($null -ne $Global:sizeByAgeDict[$pathTranslation.DirectShare].Owners) -and ($Global:sizeByAgeDict[$pathTranslation.DirectShare].Owners.Count -gt 0))
                            {
                                Write-Host ("`tOwners:")
                                $Global:sizeByAgeDict[$pathTranslation.DirectShare].Owners | ForEach-Object { Write-Host ("`t`t{0}" -f @($_)) }
                            }

                            if($keyRead -eq [System.ConsoleKey]::X)
                            {
                                ShowExplicitACLs
                            }
                            elseif ($keyRead -eq [System.ConsoleKey]::S)
                            {
                                Write-Host ("`r`n{0}`t{1}`t{2}" -f @($_.FullName, (Format-StorageNumber $_.Length), $_.CreationTime.ToString("yyyyMMdd hh:mm:ss")))
                                ShowStats
                            }
                            elseif ($keyRead -eq [System.ConsoleKey]::C)
                            {
                                CopyStats
                            }
                            elseif($keyRead -eq [System.ConsoleKey]::O)
                            {
                                ShowOwners
                            }
                            elseif($keyRead -eq [System.ConsoleKey]::E)
                            {
                                if($Global:directoryExceptions.Count -gt 0)
                                {
                                    Write-Host ("`r`nExceptions:")
                                    Write-Host ("`t{0}" -f @(($Global:directoryExceptions -join "`r`n`t")))
                                }
                            }
                            elseif($keyRead -eq [System.ConsoleKey]::Z)
                            {
                                SaveData -folderToSaveTo $folderToSaveTo -cifsServer $serverName
                            }
                        }
                    }
                }
            }
        } `
        elseif($di -is [String])
        {
            $di = [System.IO.DirectoryInfo]::new($di)
            if($di.Exists)
            {
                ListDirectory -di $di -folderToSaveTo $folderToSaveTo -serverName $serverName
            }
        }
    } `
    else
    {
        return
    }
}

class ShareAgeStat
{
    [UInt64] $Count = 0
    [UInt64] $Size = 0
}

class ShareStats
{
    static [DateTime] $dNow
    static [System.Collections.Generic.List[DateTime]] $FileAgeKeys = $null
    [UInt64] $Directories = 0
    [UInt64] $Files = 0
    [UInt64] $TotalSize = 0
    [System.Collections.Generic.Dictionary[[DateTime],[Object]]] $FilesByAge = [System.Collections.Generic.Dictionary[[DateTime],[ShareAgeStat]]]::new()
    [System.Collections.Generic.List[System.Object]] $Owners = [System.Collections.Generic.List[System.Object]]::new()

    static [void] InitFileAgeKeys()
    {
        if($null -eq [ShareStats]::FileAgeKeys)
        {
            [ShareStats]::dNow = [DateTime]::Parse([DateTime]::Now.ToString("MM/dd/yyyy"))
            [ShareStats]::FileAgeKeys = [System.Collections.Generic.List[DateTime]]::new()
            @(-10..-1) | ForEach-Object { [ShareStats]::FileAgeKeys.Add([ShareStats]::dNow.AddYears($_)) }
        }
    }

    ShareStats([System.Collections.Generic.List[System.String]] $pathOwners)
    {
        if($null -ne [ShareStats]::FileAgeKeys)
        {
            [ShareStats]::InitFileAgeKeys()
        }
        foreach($key in [ShareStats]::FileAgeKeys)
        {
            $this.FilesByAge.Add($key, [ShareAgeStat]::new())
        }
        if($null -ne $pathOwners)
        {
            $pathOwners | Foreach-Object { $this.Owners.Add($_) }
        }
    }
}

function InitShareAgeDictionary
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $shareName
    )

    if(-not $Global:sizeByAgeDict.ContainsKey($shareName))
    {
        $Global:sizeByAgeDict.Add($shareName, [System.Collections.Generic.Dictionary[[String],[Object]]]::new())
        $Global:sizeByAgeDict[$shareName] = [System.Collections.Generic.Dictionary[[String],[Object]]]::new()
        $Global:sizeByAgeDict[$shareName].Add("Directories", 0)
        $Global:sizeByAgeDict[$shareName].Add("Files", 0)
        $Global:sizeByAgeDict[$shareName].Add("TotalSize", 0)
        $Global:sizeByAgeDict[$shareName].Add("FilesByAge", [System.Collections.Generic.Dictionary[[DateTime],[Object]]]::new())

        $Global:sizeByAgeDict[$shareName].Add("SizeByAge", [System.Collections.Generic.Dictionary[[DateTime],[UInt64]]]::new())
        [ShareStats]::FileAgeKeys | ForEach-Object {
            $Global:sizeByAgeDict[$shareName]["FilesByAge"].Add($_, [System.Collections.Generic.Dictionary[[String],[UInt64]]]::new())
            $Global:sizeByAgeDict[$shareName]["FilesByAge"][$_].Add("Count", 0)
            $Global:sizeByAgeDict[$shareName]["FilesByAge"][$_].Add("Size", 0)
        }
    }
}

<#

**************** Saved the explicit ACLs, but not file age or owner data. ****************

#>

function CreateSavePath($folderToSaveTo,$cifsServer)
{
    $serverFolder = "{0}\{1}" -f @($folderToSaveTo, $cifsServer)
    if(-not [System.IO.Directory]::Exists($serverFolder))
    {
        New-Item -Path $folderToSaveTo -Name $cifsServer -ItemType Directory | Out-Null
    }

    return $serverFolder
}

function SaveData($folderToSaveTo,$cifsServer)
{
    try
    {
        $serverFolder = CreateSavePath -folderToSaveTo $folderToSaveTo -cifsServer $cifsServer

        $explicitACLRulesSavePath = "{0}\explicitRules.csv" -f @($serverFolder)
        DumpExplicitACLs -saveToPath $explicitACLRulesSavePath

        $ownerFile = "{0}\owners.csv" -f @($serverFolder)
        ShowOwners -saveToPath $ownerFile

        $fileAgeDataFile = "{0}\fileAgeData.csv" -f @($serverFolder)
        ShowStats -saveToPath $fileAgeDataFile

        $exceptionsDataFile = "{0}\exceptions.csv" -f @($serverFolder)
        DumpExceptions -saveToPath $exceptionsDataFile
    }
    catch
    {

    }
}

function LD
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $translationCSVPath,

        [Parameter(Mandatory=$true,Position=2)]
        [String]
        $folderToSaveTo,

        [Parameter(Mandatory=$true,Position=3)]
        [String]
        $di
    )

    $Global:outputData = "" | Select-Object cifsServer,shareName,owners,explicitRules,stats,exceptions
    $Global:outputData.exceptions = "" | Select-Object directory,file

    $Global:outputData.exceptions.directory = [System.Collections.Generic.List[System.String]]::new()
    $Global:outputData.exceptions.file = [System.Collections.Generic.List[System.String]]::new()


    [ShareStats]::InitFileAgeKeys()
    $Global:sizeByAgeDict = [System.Collections.Generic.SortedDictionary[[String], [ShareStats]]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $Global:directoryExceptions = [System.Collections.Generic.List[System.String]]::new()
    $Global:fileExceptions = [System.Collections.Generic.List[System.String]]::new()

    $Global:translationSW = [System.Diagnostics.Stopwatch]::new()
    $Global:translationsAttempted = 0
    $Global:translationsFailed = [System.Collections.Generic.List[String]]::new()

    $Global:explicitACLRules = [System.Collections.Generic.List[System.Object]]::new()

    $tDI = RemoveLongUNCPath $di
    $diParts = $tDI.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $serverName = $diParts[0]
    $shareName = $diParts[1]

    # "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\Data"
    CreateSavePath -folderToSaveTo $folderToSaveTo -cifsServer $serverName

    $oldTitle = $host.UI.RawUI.WindowTitle
    BuildTranslationDictionaryFromCSV -translationCSVPath $translationCSVPath -forServer $serverName
        # "\\cdc-ntapmgmt01\c$\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\AllCifsShares-20231213.csv" $serverName

    $host.ui.RawUI.WindowTitle = $di.ToLower()
    ListDirectory -di $di -folderToSaveTo $folderToSaveTo -serverName $serverName
    if($Global:directoryExceptions.Count -gt 0)
    {
        Write-Host ("`r`nDirectory Exceptions:")
        Write-Host ("`t{0}" -f @(($Global:directoryExceptions -join "`r`n`t")))
    }

    if($Global:fileExceptions.Count -gt 0)
    {
        Write-Host ("`r`nFile Exceptions:")
        Write-Host ("`t{0}" -f @(($Global:fileExceptions -join "`r`n`t")))
    }
    ShowStats
    $host.UI.RawUI.WindowTitle = $oldTitle
    SaveData -folderToSaveTo $folderToSaveTo -cifsServer $serverName
}


# LD "\\?\UNC\boifs1\shares$"

function teststuff
{
    $a = 0
    while($a -lt $allCifsShares.Count)
    {
        if($allCifsShares[$a].UNCPath -notmatch "shares\$")
        {
            $retries = 0
            do
            {
                $di = [System.IO.DirectoryInfo]::new((RemoveLongUNCPath $allCifsShares[$a].UNCPath))
                if(-not $di.Exists)
                {
                    Start-Sleep -Milliseconds 200
                    $retries++
                }
            } until(($retries -eq 3) -or ($di.Exists))

            if($di.Exists)
            {
                # Get all groups with FullControl or Modify access -- these I'll call owners since they have the ability to create new files and folder and delete old ones.
                $acl = $di.GetAccessControl()
                $fcAccessRules = @($acl.Access | Where-Object { (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -eq [System.Security.AccessControl.FileSystemRights]::FullControl) -and (($_.AccessControlType -band [System.Security.AccessControl.AccessControlType]::Allow) -eq [System.Security.AccessControl.AccessControlType]::Allow) -and ($_.IdentityReference.Value -notmatch "FS-FileServices-ADM") })

                # For Modify Rules...
                $modifyAccessRules = @($acl.Access | Where-Object { (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -ne [System.Security.AccessControl.FileSystemRights]::FullControl) -and (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) -eq [System.Security.AccessControl.FileSystemRights]::Modify) -and (($_.AccessControlType -band [System.Security.AccessControl.AccessControlType]::Allow) -eq [System.Security.AccessControl.AccessControlType]::Allow) -and ($_.IdentityReference.Value -notmatch "FS-FileServices-ADM") })

                if(($fcAccessRules.Length -eq 0) -and ($modifyAccessRules.Length -eq 0))
                {
                    Write-Host ("No FC or RW group for {0}." -f @($di.FullName))
                }
                else
                {
                    # Remember, $accessRules is an array of arrays!
                    #   $accessRules.Length is a thing...and
                    #   $accessRules[0].Length is also a thing...
                    $accessRules = @($fcAccessRules, $modifyAccessRules)
                    $usersFound = $false
                    Write-Host $di.FullName
                    $b = 0
                    while((-not $usersFound) -and ($b -lt $accessRules.Length))
                    {
                        $c = 0
                        while($c -lt $accessRules[$b].Length)
                        {
                            $acctParts = $accessRules[$b][$c].IdentityReference.Value -split "\\"
                            $acctName = $acctParts[$acctParts.Length - 1]

                            if(-not ($acctName -eq "everyone"))
                            {
                                try
                                {
                                    $adGroup = @(Get-ADGroup -Identity $acctName -Properties Members -ErrorAction Stop)
                                    $d = 0
                                    while($d -lt $adGroup.Members.Count)
                                    {
                                        if(-not $usersFound)
                                        {
                                            Write-Host ("`t{0}:{1}" -f @($accessRules[$b][$c].FileSystemRights, $accessRules[$b][$c].IdentityReference.Value))
                                        }
                                        $usersFound = $true
                                        Write-Host ("`t`t{0}" -f $($adGroup.Members[$d]))
                                        $d++
                                    }
                                }
                                catch
                                {
                                }
                            }
                            else
                            {
                                Write-Host $di.FullName
                                Write-Host ("*************** ALERT!!! ************")
                                Write-Host ("Found Everyone in FC or RW Access Rule")
                            }

                            $c++
                        }
                        $b++
                    }
                }
            }
        }
        $a++
    }
}

function ExportNCCIFSSharesToCSV($csvPath)
{
    $dnsServer = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "loopback" } | Select-Object -ExpandProperty ServerAddresses)[0]
    $cifsServerAliases = Get-DnsServerResourceRecord -RRType CName -ZoneName "powereng.com" -ComputerName $dnsServer | Where-Object { $_.HostName -match "fs1$" } | Select-Object @{N='Alias';E={$_.HostName.ToLower()}},@{N='AliasFor';E={$_.RecordData.HostNameAlias.ToLower().Replace(".powereng.com.","")}}

    $allCifsShares = [System.Collections.Generic.List[Object]]::new()

    # Get all volumes that do not match:
    #   1. CifsServer contains "DR-"
    #   2. ShareName is: c$, ipc$, or admin$
    # @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object { $allCifsShares.Add($_) }
    @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object {
        $share = $_
        $shareACLs = @(Get-NcCifsShareAcl -Controller $share.NCController -VserverContext $share.VServer -Share $share.ShareName)

        # Favor shares with a no_access ACL so we don't include secondary shares without the no_access ACL
        if(@($shareACLs | Where-Object { $_.Permission -eq "no_access" }).Length -ge 1)
        {
            # Further limit the shares to avoid duplicates.
            if(@($allCifsShares | Where-Object { ($_.NCController.Name -eq $share.NcController.Name) -and ($_.VServer -eq $share.VServer) -and ($_.Volume -eq $share.Volume) -and ($_.Path -eq $share.Path) } ).Length -eq 0)
            {
                $allCifsShares.Add($_)
            }
        }
    }
    #@(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") } | Foreach-Object { $x = "" | Select-Object CifsServer,ShareName,Path; $x.CifsServer = $_.CifsServer; $x.ShareName = $_.ShareName; $x.Path = $_.Path; $x } | Sort-Object CifsServer,Path,ShareName)
    # $allCifsShares | Export-Csv -Path $csvPath -Delimiter "`t" -NoTypeInformation


    # Now, filter out all the shares that are hosted on data protection destination volumes...
    $cifsShareVolumes = [System.Collections.Generic.List[Object]]::new()
    $indexesToRemove = [System.Collections.Generic.List[int]]::new()

    # List of CIFS servers that have shares not hosted on DR destination volumes (excluding Shares$)
    $cifsServersWithNonDRShareVols = [System.Collections.Generic.List[String]]::new()

    foreach($cifsShare in $allCifsShares)
    {
        if(-not [String]::IsNullOrEmpty($cifsShare.Volume))
        {
            try
            {
                $vol = $cifsShareVolumes | Where-Object { ($_.NCController.name -eq $cifsShare.NcController.Name) -and ($_.VServer -eq $cifsShare.Vserver) -and ($_.Name -eq $cifsShare.Volume) }
                if($null -eq $vol)
                {
                    # Write-Host ("Getting {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
                    $vol = Get-NCVol -Controller $cifsShare.NcController -Vserver $cifsShare.Vserver -Name $cifsShare.Volume -ErrorAction Stop
                    $cifsShareVolumes.Add($vol)
                }

                if($null -ne $vol)
                {
                    if($vol.VolumeMirrorAttributes.IsDataProtectionMirror)
                    {
                        $idx = $allCifsShares.IndexOf($cifsShare)
                        if($idx -gt -1)
                        {
                            $i = $indexesToRemove.BinarySearch($idx)
                            if($i -lt 0)
                            {
                                $indexesToRemove.Insert(-bnot $i, $idx)
                            }
                        }
                    }
                    else
                    {
                        if($cifsShare.ShareName -ne "Shares$")
                        {
                            $i = $cifsServersWithNonDRShareVols.BinarySearch($cifsShare.CifsServer)
                            if($i -lt 0)
                            {
                                $cifsServersWithNonDRShareVols.Insert(-bnot $i, $cifsShare.CifsServer)
                            }
                        }
                    }
                }
                else
                {
                    Write-Host ("No volume found for: {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
                }
            }
            catch
            {
                Write-Host ("Failed to get {0}://{1}/{2}" -f @($cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
            }
        }
    }

    $drShares = @($allCifsShares | Where-Object { $_.CifsServer -notin $cifsServersWithNonDRShareVols } | Sort-Object CifsServer)

    # Remove any remaining shares (typically Shares$) on CIFS servers which only host DR volume shares from $allCifsShares
    foreach($cifsShare in $drShares)
    {
        $idx = $allCifsShares.IndexOf($cifsShare)
        if($idx -gt -1)
        {
            $i = $indexesToRemove.BinarySearch($idx)
            if($i -lt 0)
            {
                $indexesToRemove.Insert(-bnot $i, $idx)
            }
        }
    }

    $a = $indexesToRemove.Count - 1
    while($a -ge 0)
    {
        $idx = $indexesToRemove[$a]
        if(($idx -ge 0) -and ($idx -lt $allCifsShares.Count))
        {
            $cifsShare = $allCifsShares[$idx]
            # Write-Host ("Removing CIFS share on DP volume: \\{0}\{1} ==> {2}://{3}/{4}" -f @($cifsShare.CifsServer, $cifsShare.ShareName, $cifsShare.NcController.Name, $cifsShare.Vserver, $cifsShare.Volume))
            [void] $allCifsShares.RemoveAt($idx)
        }
        $a--
    }

    @(foreach($cifsShare in $allCifsShares)
    {
        $fs1Alias = $cifsServerAliases | where-object { ($_.AliasFor -match $cifsShare.CifsServer) -or ($_.Alias -match $cifsShare.CifsServer) } | Select-Object -First 1 -ExpandProperty Alias
        if($null -ne $fs1Alias)
        {
            $cifsShare | Select-Object @{N='Cluster'; E={$_.NCController.Name}}, VServer, CifsServer, @{N='FS1Alias';E={ $fs1Alias }}, ShareName, Path, @{N='UNCPath';E={"\\?\UNC\{0}\{1}" -f @($fs1Alias, $_.ShareName) }}
        }
        else
        {
            Write-Host ("No FS1 alias for {0}:{1}:{2}" -f @($cifsShare.CifsServer, $cifsShare.ShareName, $cifsShare.Path))
        }
    }) | Export-CSV -Force -Delimiter "`t" -NoTypeInformation -Path $csvPath
}

function ExportData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $data
    )


}

function MergeFileAgeData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $dataFolder,

        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object[]]
        $fileAgeDataFiles
    )

    $combinedFileAgeData = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $fileAgeDataFiles.Length)
    {
        try
        {
            $fad = Import-CSV -Path $fileAgeDataFiles[$a].FullName -Delimiter "`t"
            $fad.ForEach({$combinedFileAgeData.Add($_)})
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to read file age data from: {0}." -f @($fileAgeDataFiles[$a].FullName))
        }

        $a++
    }
    $savePath = "{0}\CombinedFileAgeData.csv" -f @(($dataFolder.TrimEnd("\")))
    try
    {
        $combinedFileAgeData | Sort-Object ShareName | Export-Csv -Delimiter "`t" -NoTypeInformation -Path $savePath -Force -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to save combined file age data to: {0}." -f @($savePath))
    }
}

function MergeFileOwnerData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $dataFolder,

        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object[]]
        $fileOwnerDataFiles
    )

    $combinedFileOwnerData = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $fileOwnerDataFiles.Length)
    {
        try
        {
            $fod = Import-CSV -Path $fileOwnerDataFiles[$a].FullName -Delimiter "`t"
            $fod.ForEach({$combinedFileOwnerData.Add($_)})
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to read file owner data from: {0}." -f @($fileOwnerDataFiles[$a].FullName))
        }

        $a++
    }
    $savePath = "{0}\CombinedFileOwnerData.csv" -f @(($dataFolder.TrimEnd("\")))
    try
    {
        $combinedFileOwnerData | Sort-Object ShareName | Export-Csv -Delimiter "`t" -NoTypeInformation -Path $savePath -Force -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to save combined file owner data to: {0}." -f @($savePath))
    }
}

function MergeFileExplicitACLData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $dataFolder,

        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object[]]
        $fileExplicitACLDataFiles
    )

    $combinedFileExplicitACLData = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $fileExplicitACLDataFiles.Length)
    {
        try
        {
            $fod = Import-CSV -Path $fileExplicitACLDataFiles[$a].FullName -Delimiter "`t"
            $fod.ForEach({$combinedFileExplicitACLData.Add($_)})
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to read file explicit ACL data from: {0}." -f @($fileExplicitACLDataFiles[$a].FullName))
        }

        $a++
    }
    $savePath = "{0}\CombinedFileExplicitACLData.csv" -f @(($dataFolder.TrimEnd("\")))
    try
    {
        $combinedFileExplicitACLData | Sort-Object Path | Export-Csv -Delimiter "`t" -NoTypeInformation -Path $savePath -Force -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to save combined file explicit ACL data to: {0}." -f @($savePath))
    }
}

function CombineFileAgeData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [System.Object]
        $dataFolder
    )

    try
    {
        $files = @(Get-ChildItem -Path $dataFolder -Recurse -File -ErrorAction Stop)
        $fileAgeDataFiles = @($files | Where-Object { $_.Name -eq "fileAgeData.csv" })
        MergeFileAgeData -dataFolder $dataFolder -fileAgeDataFiles $fileAgeDataFiles

        $fileOwnerDataFiles = @($files | Where-Object { $_.Name -eq "owners.csv" })
        MergeFileOwnerData -dataFolder $dataFolder -fileOwnerDataFiles $fileOwnerDataFiles

        $fileExplicitACLDataFiles = @($files | Where-Object { $_.Name -eq "explicitRules.csv" })
        MergeFileExplicitACLData -dataFolder $dataFolder -fileExplicitACLDataFiles $fileExplicitACLDataFiles
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to retrieve file age work data files from: {0}." -f @($dataFolder))
    }
}

function TestClipboardCapture
{
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")

    $procs = @(Get-Process)

    $proc = $procs | Where-Object { $_.MainWindowTitle -eq "\\?\unc\opk-smb01\shares$"}

    if($null -ne $proc)
    {
        [Microsoft.VisualBasic.Interaction]::AppActivate($proc.MainWindowTitle)
        Start-Sleep -Seconds 5
        [System.Windows.Forms.SendKeys]::SendWait("SSS")
    }

    Set-Clipboard $null
    $sb = [System.Text.StringBuilder]::new()
    [void] $sb.Clear()
    $clip = [String]::Empty
    while($true)
    {
        $clip = [String]::Empty
        $clip = Get-Clipboard
        if(-not [String]::IsNullOrEmpty($clip))
        {
            foreach($s in $clip)
            {
                Write-Host $s
                [void] $sb.AppendLine($s)
            }
            Set-Clipboard $null
        }
        Start-Sleep -Seconds 1
    }
}

# SIG # Begin signature block
# MIIPMgYJKoZIhvcNAQcCoIIPIzCCDx8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU9w8jyXy2mu9SgF+CQqHiZ+6L
# dlGgggyXMIIF3zCCBMegAwIBAgITFQAAAALU9Lz04Hi9mwAAAAAAAjANBgkqhkiG
# 9w0BAQ0FADBGMRMwEQYKCZImiZPyLGQBGRYDY29tMRgwFgYKCZImiZPyLGQBGRYI
# cG93ZXJlbmcxFTATBgNVBAMTDFBFSSBSb290IENBMjAeFw0xNTA4MTIyMDQ2MDVa
# Fw0zNTA4MTIyMDA4MDVaME0xEzARBgoJkiaJk/IsZAEZFgNjb20xGDAWBgoJkiaJ
# k/IsZAEZFghwb3dlcmVuZzEcMBoGA1UEAxMTUEVJIFN1Ym9yZGluYXRlIENBMjCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKVLzra7Ww5Nmy+NM14MdRZW
# wEhw09fhAIC6jDl90IGt1D0zvB9xrM1XTrSfEWgCNnveOnNSvXBSHjfWYd7KAs8N
# EDLyIjWluCB66bdi/xY2fascuYJvy2ZmA6Voh005/nRS7lPGq6yfZEjc6LXfiaHS
# Wo+kbrFw/ICoq79kEIympaHeO7TYFOcHoP7T/nfWvD0OrJZLrou9m53qQzZXduBV
# pYwfI91CsGR1DpXKwcgC4yPqLdaP9GmWjYYddT6jQTGD/aCIfYo/29z2vXVafaHx
# 90i8OIF7frlhOL39P3GhxIlDk7espdSKxHWF6772N0XXc7NVaq+Jdw7vtpG02yMC
# AwEAAaOCAr0wggK5MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBQFk+663K25
# Xljs+Tik5+qrsUUojTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8E
# BAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBSwdElPGrGwpa46Uu+0
# SWDcXSTY9TCCAQ8GA1UdHwSCAQYwggECMIH/oIH8oIH5hoG6bGRhcDovLy9DTj1Q
# RUklMjBSb290JTIwQ0EyLENOPUJPSS1SQ0EwMixDTj1DRFAsQ049UHVibGljJTIw
# S2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1w
# b3dlcmVuZyxEQz1jb20/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29i
# amVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50hjpodHRwOi8vY2VydHMyLnBv
# d2VyZW5nLmNvbS9DZXJ0RW5yb2xsL1BFSSUyMFJvb3QlMjBDQTIuY3JsMIIBFwYI
# KwYBBQUHAQEEggEJMIIBBTCBsAYIKwYBBQUHMAKGgaNsZGFwOi8vL0NOPVBFSSUy
# MFJvb3QlMjBDQTIsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENO
# PVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9cG93ZXJlbmcsREM9Y29tP2NB
# Q2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9y
# aXR5MFAGCCsGAQUFBzAChkRodHRwOi8vY2VydHMyLnBvd2VyZW5nLmNvbS9DZXJ0
# RW5yb2xsL0JPSS1SQ0EwMl9QRUklMjBSb290JTIwQ0EyLmNydDANBgkqhkiG9w0B
# AQ0FAAOCAQEAcpv1ZhjtPnt9puHEI7ex1y8Y5l9KFw9/H0d05h104MDMGuD07HDG
# lQfgvSrmghZP86z2WsssNFbUisjr+aQlCtK8kTdfO/lf3agg/GJBPnzqxiJxIlb9
# Y1v0JT4gJf9sZMsXNiiYwatYGecK8DR2UbWDFUMjcIF7MaECWNedh/aWMb4cah2i
# sNP7FbCftZmP4LJ5VynBGTHb3P6DxYG2YzRxpSFeIlDP1aAABoFuKDGIK72izBG2
# QyeB1W2e7/sjFRiSLbyw2GuSuzHm0o4w3PkHQ0H1yiv50jiX02Sl30J/uP4bNAQF
# kC2U3Ov3RefYTwqj4uLKMmkNEqmpxLoySDCCBrAwggWYoAMCAQICE2YAABLaelh+
# 7dzdJlYAAAAAEtowDQYJKoZIhvcNAQENBQAwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyMB4XDTE2MDMyNDEzNTQzOVoXDTI2MDMyMjEzNTQzOVowgbAxCzAJ
# BgNVBAYTAlVTMQ4wDAYDVQQIEwVJZGFobzEPMA0GA1UEBxMGSGFpbGV5MR0wGwYD
# VQQKExRQT1dFUiBFbmdpbmVlcnMgSW5jLjEWMBQGA1UECxMNT3BlcmF0aW9ucyBJ
# VDFJMEcGA1UEAxNAUE9XRVIgRW5naW5lZXJzIEluZm9ybWF0aW9uIFRlY2hub2xv
# Z3kgSW5mcmFzdHJ1Y3R1cmUgRGVwYXJ0bWVudDCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBANo3WBVO5y8uBMYMzLPqdqDkyMcQoJVQR7yPHPKOh/0DeNoZ
# yVM0qXwdV6sZGaotW0+UR2DzyyMvmwxl5zqIIBEvIwjtHFLU/tAEOWamTf9vMwn+
# LxbUVysZ/RCKkv+V56dOnhtYE3vg+NxRBfEZKViQMXHq6FbmpL1LZcDKlYq1t3RO
# gYhbEHYjG5tEJftg11rznA379+K9yWkybUYEEVCavYNQGp/WHlroK9jMg8RtXIaQ
# pI7O/5CLFondPga3eqEU6fjbE3uDsY2ex7Q1+YnjFhvKt7GkosZo+1yWPeykOPra
# TGxqnig+7c8hKHO+ibV9/xfX8q/iWzlLAPQhMZUCAwEAAaOCAyMwggMfMD4GCSsG
# AQQBgjcVBwQxMC8GJysGAQQBgjcVCIHNilODqvxmhZmNOoHT7HuB1rU5gSGC5vp+
# hMywSwIBZAIBCjATBgNVHSUEDDAKBggrBgEFBQcDAzALBgNVHQ8EBAMCB4AwGwYJ
# KwYBBAGCNxUKBA4wDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUY/0hsMlcQdPeIB7Z
# eh3nuq3RuZ8wHwYDVR0jBBgwFoAUBZPuutytuV5Y7Pk4pOfqq7FFKI0wggEjBgNV
# HR8EggEaMIIBFjCCARKgggEOoIIBCoaBwWxkYXA6Ly8vQ049UEVJJTIwU3Vib3Jk
# aW5hdGUlMjBDQTIsQ049Qk9JLVNDQTAyLENOPUNEUCxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0
# Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGRGh0dHA6Ly9CT0ktU0NBMDIucG93
# ZXJlbmcuY29tL0NlcnRFbnJvbGwvUEVJJTIwU3Vib3JkaW5hdGUlMjBDQTIuY3Js
# MIIBNQYIKwYBBQUHAQEEggEnMIIBIzCBtwYIKwYBBQUHMAKGgapsZGFwOi8vL0NO
# PVBFSSUyMFN1Ym9yZGluYXRlJTIwQ0EyLENOPUFJQSxDTj1QdWJsaWMlMjBLZXkl
# MjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPXBvd2Vy
# ZW5nLERDPWNvbT9jQUNlcnRpZmljYXRlP2Jhc2U/b2JqZWN0Q2xhc3M9Y2VydGlm
# aWNhdGlvbkF1dGhvcml0eTBnBggrBgEFBQcwAoZbaHR0cDovL0JPSS1TQ0EwMi5w
# b3dlcmVuZy5jb20vQ2VydEVucm9sbC9CT0ktU0NBMDIucG93ZXJlbmcuY29tX1BF
# SSUyMFN1Ym9yZGluYXRlJTIwQ0EyLmNydDANBgkqhkiG9w0BAQ0FAAOCAQEAcMQQ
# HArQMPorMDdTv0PIeU80NpxlZm6ZjMLHJIWtyKWNRmuG1Oc+Ti762snW05yq5aEY
# kwmmWtm/00ukV4z/DhYrlCuxbmKeQP4kIZoVo4/7K7HrdG0u6QN4SmG9rTJGCuXz
# EXlKZIeHiwgD2EsNa7varVK3jX8CEik1jJh8II0VIbBzvetAMm1QGUCk9/WtllYG
# 76CLyPasgcfFsOlMeRWoHKNw/oV4AvMab0yuQCDJ9uNG3dU+6jGoxDz+ksAKl9OO
# u+zBNs+EOR/TWBD0JfE9hdChCzrbyG6JPIQdOsBoqo822QoIGc8emp4MTeDnCTTh
# ojIQLkYA7bMGDxIxHjGCAgUwggIBAgEBMGQwTTETMBEGCgmSJomT8ixkARkWA2Nv
# bTEYMBYGCgmSJomT8ixkARkWCHBvd2VyZW5nMRwwGgYDVQQDExNQRUkgU3Vib3Jk
# aW5hdGUgQ0EyAhNmAAAS2npYfu3c3SZWAAAAABLaMAkGBSsOAwIaBQCgeDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQN
# AiTrx1dpFaimFvHl0sVrTwIEVjANBgkqhkiG9w0BAQEFAASCAQCuJXasZmIfATWd
# GA6qzV+yRWTvIEqYaxN51q31VCMLavkIVr//5ncxAtopa9MuGh8SzHTpZlhRO1ED
# XcgVcn0w+xSHlbflIseEeldyrinNEOWqE8EBy8cdPNVsOoom2Axu2MRD7YmmyDNW
# XVQCyv5MIclytctwubKYXvi8nvtrsx5AOOoRTjp/M7EHFG3tcvBYhDIVl75mzcwO
# QUSiJpOxXx27dSQdehRDE42aHOVpRyBUlXJYtWuewHJBdD2RAXjhJCcBAG0ohjbt
# +b1Y/3fv2ZeZv8THn1C/lFTs1HaJS62mU3N/WJFLajyMCrXpXSWDpIdVLh+mpS0c
# CGGxPMt+
# SIG # End signature block
