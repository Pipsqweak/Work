[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNull()]
    [String]
    $TranslationCSV,

    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNull()]
    [String]
    $PathToScan,

    [Parameter(Mandatory=$true,Position=2)]
    [ValidateNotNull()]
    [String]
    $FolderToSaveTo
)

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
            # Just getting the date/time for the current date at 12:00am
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

function CreateSavePath($folderToSaveTo,$cifsServer)
{
    $serverFolder = "{0}\{1}" -f @($folderToSaveTo, $cifsServer)
    if(-not [System.IO.Directory]::Exists($serverFolder))
    {
        New-Item -Path $folderToSaveTo -Name $cifsServer -ItemType Directory | Out-Null
    }

    return $serverFolder
}

function AddLongUNCPath($str) { $retval = $str; if($str -notmatch "^\\\\\?\\unc\\") { $retval = $str -replace "^\\\\","\\?\UNC\" } return $retval }

function RemoveLongUNCPath($str) { return ($str -replace "^\\\\\?\\UNC\\","\\") }

function NewDictionaryLeaf($dict, $key, $translation = [String]::Empty, $cifsServer = [String]::Empty, $fs1Alias = [String]::Empty)
{
    if(-not $dict.ContainsKey($key))
    {
        $dict.Add($key, [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
        $dict[$key].Add("CIFSServer", $cifsServer)
        $dict[$key].Add("FS1Alias", $fs1Alias)
        $dict[$key].Add("Translation", $translation)
        $dict[$key].Add("Children", [System.Collections.Generic.SortedDictionary[[String],[Object]]]::new([System.StringComparer]::OrdinalIgnoreCase))
    }

    return @( , $dict[$key]["Children"])
}

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

function ShowExplicitACLs
{

    if($Global:explicitACLRules.Count -gt 0)
    {
        $Global:explicitACLRules | Format-Table -AutoSize
    }
    else
    {
        Write-Host "No explicit ACL rules found."
    }
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

$tDI = RemoveLongUNCPath $PathToScan
$diParts = $tDI.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
$serverName = $diParts[0]
$shareName = $diParts[1]

# "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\Data"
CreateSavePath -folderToSaveTo $FolderToSaveTo -cifsServer $serverName

$oldTitle = $host.UI.RawUI.WindowTitle
BuildTranslationDictionaryFromCSV -translationCSVPath $TranslationCSV -forServer $serverName
    # "\\cdc-ntapmgmt01\c$\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Dataclassification\AllCifsShares-20231213.csv" $serverName

$host.ui.RawUI.WindowTitle = $PathToScan.ToLower()
ListDirectory -di $PathToScan -folderToSaveTo $FolderToSaveTo -serverName $serverName
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
SaveData -folderToSaveTo $FolderToSaveTo -cifsServer $serverName
