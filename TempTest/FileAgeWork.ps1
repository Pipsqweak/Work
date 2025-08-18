
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


[UInt64] $totalFiles = 0
[UInt64] $totalDirectories = 1
[UInt64] $totalSize = 0

$sizeByAge = [System.Collections.Generic.Dictionary[[DateTime],[UInt64]]]::new()
$dNow = [DateTime]::Parse([DateTime]::Now.ToString("MM/dd/yyyy"))
@(-10..-1) | ForEach-Object { $sizeByAge.Add(($dNow.AddYears($_)), 0)}
$fileAgeKeys = @($sizeByAge.Keys)

$directoryExceptions = [System.Collections.Generic.List[System.String]]::new()
$fileExceptions = [System.Collections.Generic.List[System.String]]::new()

$explicitACLRules = [System.Collections.Generic.List[System.Object]]::new()

function ShowStats()
{
    Write-Host ("Directories: {0}" -f @($Global:totalDirectories))
    Write-Host ("Files: {0}" -f @($Global:totalFiles))
    Write-Host ("Total size: {0}" -f @((Format-StorageNumber $Global:totalSize)))
    $pcnt = 0
    if($Global:totalSize -gt 0)
    {
        $pcnt = $Global:sizeOver5Years / $Global:totalSize
    }
    Write-Host ("Older than X year(s):")
    foreach($ageKey in $Global:fileAgeKeys)
    {
        $pcnt = 0
        if($Global:totalSize -gt 0)
        {
            $pcnt = $Global:sizeByAge[$ageKey] / $Global:totalSize
        }
        $age = 10 - $Global:fileAgeKeys.IndexOf($ageKey)
        Write-Host ("`t{0,2}: {1,11} [{2,6:P2}]" -f @($age, (Format-StorageNumber $Global:sizeByAge[$ageKey]), $pcnt))
    }
}

function CaptureExplicitACLRules($fsi)
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

            $a++
        }
    }
    catch
    {

    }
}

function DumpExplicitACLs()
{
    $Global:explicitACLRules | Export-Csv -NoTypeInformation -Delimiter "`t" -Path $Global:explicitACLRulesSavePath -Force
}

function ListDirectory($di)
{
    if($null -ne $di)
    {
        if($di -is [System.IO.DirectoryInfo])
        {
            CaptureExplicitACLRules $di
            $Global:totalDirectories++
            #Write-Host $di.FullName
            try
            {
                $diDirectories = @($di.GetDirectories() | Where-Object { $_.Name -notmatch "~snapshot" })
                # $Global:totalDirectories += $diDirectories.Length
                $diDirectories | ForEach-Object {
                    ListDirectory $_
                }

                try
                {
                    $diFiles = $di.GetFiles()
                    $Global:totalFiles += $diFiles.Length
                    $diFiles | ForEach-Object {
                        $fi = $_

                        CaptureExplicitACLRules $fi

                        $Global:totalSize += $fi.Length
                        foreach($ageKey in $Global:fileAgeKeys)
                        {
                            if($fi.LastWriteTime -lt $ageKey)
                            {
                                $Global:sizeByAge[$ageKey] += $fi.Length
                            }
                        }

                        # [void] (AddFSIToDB $db $_ $false)
                        if([Console]::KeyAvailable)
                        {
                            $keyRead = [Console]::ReadKey($false).Key
                            if($keyRead -eq [System.ConsoleKey]::A)
                            {
                                DumpExplicitACLs
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
                        }
                    }
                }
                catch
                {
                    $Global:fileExceptions.Add($di.FullName)
                }
            }
            catch
            {
                $Global:directoryExceptions.Add($di.FullName)
            }

            # Write-Host
        } `
        elseif($di -is [String])
        {
            $di = [System.IO.DirectoryInfo]::new($di)
            if($di.Exists)
            {
                ListDirectory $di
            }
        }
    } `
    else
    {
        return
    }
}

function LD($di)
{
    [UInt64] $Global:totalFiles = 0
    [UInt64] $Global:totalDirectories = 1
    [UInt64] $Global:totalSize = 0
    [String] $Global:shareName = $di.Replace("\\?\UNC\", "\\")

    $Global:sizeByAge = [System.Collections.Generic.Dictionary[[DateTime],[UInt64]]]::new()
    $dNow = [DateTime]::Parse([DateTime]::Now.ToString("MM/dd/yyyy"))
    @(-10..-1) | ForEach-Object { $Global:sizeByAge.Add(($dNow.AddYears($_)), 0)}
    $Global:fileAgeKeys = @($Global:sizeByAge.Keys)
    $Global:directoryExceptions = [System.Collections.Generic.List[System.String]]::new()
    $Global:fileExceptions = [System.Collections.Generic.List[System.String]]::new()
    $Global:explicitACLRules = [System.Collections.Generic.List[System.Object]]::new()

    $pathParts = $Global:shareName.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $Global:explicitACLRulesSavePath = "{0}\{1}_{2}.csv" -f @($env:TEMP, $pathParts[0], $pathParts[1])
    ListDirectory $di
    ShowStats
}


function CopyStats()
{
    $jj = "" | Select-Object @{N='Share';E={$Global:shareName}}, @{N='Directories'; E={$Global:totalDirectories}}, @{N='Files';E={$Global:totalFiles}}, @{N='TotalSize';E={$Global:totalSize}},
        @{N='yr1size';E={$Global:sizeByAge[$Global:fileAgeKeys[9]]}},
        @{N='yr2size';E={$Global:sizeByAge[$Global:fileAgeKeys[8]]}},
        @{N='yr3size';E={$Global:sizeByAge[$Global:fileAgeKeys[7]]}},
        @{N='yr4size';E={$Global:sizeByAge[$Global:fileAgeKeys[6]]}},
        @{N='yr5size';E={$Global:sizeByAge[$Global:fileAgeKeys[5]]}},
        @{N='yr6size';E={$Global:sizeByAge[$Global:fileAgeKeys[4]]}},
        @{N='yr7size';E={$Global:sizeByAge[$Global:fileAgeKeys[3]]}},
        @{N='yr8size';E={$Global:sizeByAge[$Global:fileAgeKeys[2]]}},
        @{N='yr9size';E={$Global:sizeByAge[$Global:fileAgeKeys[1]]}},
        @{N='yr10size';E={$Global:sizeByAge[$Global:fileAgeKeys[0]]}}
    $jj | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
}
