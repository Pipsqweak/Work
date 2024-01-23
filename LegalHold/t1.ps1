$copyData = Import-Csv -Path ".\LegalHold\Jobs\20231211-UEC.csv" -Delimiter "`t"

$copyDictionary = [System.Collections.Generic.SortedDictionary[[String],[System.Collections.Generic.List[System.IO.FileSystemInfo]]]]::new()
$doesNotExists = [System.Collections.Generic.List[String]]::new()

$copyDictionary = [System.Collections.Generic.SortedDictionary[[String],[System.Collections.Generic.List[System.IO.FileSystemInfo]]]]::new([System.StringComparer]::OrdinalIgnoreCase)


$sb = [System.Text.StringBuilder]::new()
$copySize = 0
$i = 0
while($i -lt $copyData.Length)
{
    $source = $copyData[$i].Source
    $srcSplit = $source.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $source = "\\?\UNC\{0}" -f @(($srcSplit -join '\'))

    $destination = $copyData[$i].Destination
    $dstSplit = $destination.Split(@('\'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $destination = "\\?\UNC\{0}" -f @(($dstSplit -join '\'))

    if([System.IO.Directory]::Exists($source))
    {
        [void] $sb.AppendLine(("Checking {0}...`r`n`tDST: {1}" -f @($source, $destination)))
        try
        {
            $subFolders = [System.IO.Directory]::GetDirectories($source, "*", [System.IO.SearchOption]::AllDirectories)
            if($subFolders.Length -gt 0)
            {
                [void] $sb.AppendLine(("`t{0} nested folders." -f @($subFolders.Length)))
            }

            try
            {
                $ff = [System.IO.Directory]::GetFiles($source, "*", [System.IO.SearchOption]::AllDirectories)
                # $ff = @(Get-ChildItem -Path $copyData[$i].Source -Recurse -ErrorAction Stop)
                [void] $sb.AppendLine(("`tAdding {0} files to copy dictionary." -f @($ff.Length)))
                $j = 0
                while($j -lt $ff.Length)
                {
                    $fi = [System.IO.FileInfo]::new($ff[$j])

                    $copySize += $fi.Length
                    $destinationPath = "{0}\{1}" -f @($destination, $fi.Name)

                    $ffList = $null
                    if(-not $copyDictionary.ContainsKey($destinationPath))
                    {
                        $ffList = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()
                        $copyDictionary.Add($destinationPath, $ffList)
                    } `
                    else
                    {
                        $ffList = $copyDictionary[$destinationPath]
                    }

                    $ffList.Add($fi)
                    [void] $sb.AppendLine(("`tSRC:{0}" -f @($fi.FullName)))

                    if($ffList.Count -eq 2)
                    {
                        [void] $sb.AppendLine(("`tDuplicate destination: {0}" -f @($destinationPath)))
                    }

                    $j++
                }
            }
            catch
            {
                [void] $sb.AppendLine(("`r`nERROR: Failed to get files and folders from {0}." -f @($source)))
            }
        }
        catch
        {
            [void] $sb.AppendLine(("`r`nERROR: Failed to get subdirectories for {0}." -f @($source)))
        }
    } `
    else
    {
        [void] $sb.AppendLine(("ERROR: {0} does not exist." -f @($source)))
        $o = $doesNotExists.BinarySearch($source)
        if($o -lt 0)
        {
            $doesNotExists.Insert(-bnot $o, $source)
        }
    }

    $i++
}

$sb.ToString() | Set-Clipboard


$copyDestinations = @($copyDictionary.Keys)
$copyData = [System.Collections.Generic.List[Object]]::new()
[void] $sb.Clear()
$a = 0
while($a -lt $copyDestinations.Length)
{
    $fi = [System.IO.FileInfo]::new($copyDestinations[$a])

    $proceedWithCopy = $false
    if(-not [System.IO.Directory]::Exists($fi.DirectoryName))
    {
        try
        {
            [void] $sb.AppendLine(("Creating destination folder: {0}" -f @($fi.DirectoryName)))
            [void] [System.IO.Directory]::CreateDirectory($fi.DirectoryName)

            $proceedWithCopy = $true
        }
        catch
        {
            [void] $sb.AppendLine("`tERROR: Failed to create folder")
        }
    } `
    else
    {
        $proceedWithCopy = $true
    }

    if($proceedWithCopy)
    {
        $srcFiles = $copyDictionary[$copyDestinations[$a]] | Sort-Object -Descending CreationTime
        $b = 0
        while($b -lt $copyDictionary[$copyDestinations[$a]].Count)
        {
            $d = "" | Select-Object Source,Destination
            $d.Source = $srcFiles[$b].FullName
            $srcFI = [System.IO.FileInfo]::new($d.Source)

            if($b -gt 0)
            {
                $d.Destination = "{0}\{1}_{2:D3}{3}" -f @($fi.DirectoryName, $srcFI.BaseName, $b, $srcFI.Extension)
            } `
            else
            {
                $d.Destination = $copyDestinations[$a]
            }
            [void] $sb.AppendLine(("Copying {0} to {1}" -f ($d.Source, $d.Destination)))
            $copyData.Add($d)
            <#
                try
                {
                    [System.IO.File]::Copy($srcFiles[$b].FullName, $dst, $true)
                }
                catch
                {
                    [void] $sb.AppendLine(("ERROR: Failed to copy {0} to {1}" -f @($srcFiles[$b].FullName, $dst)))
                }
            #>
            $b++
        }
    }
    $a++
}

$sb.ToString() | Set-Clipboard

$copyData | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard


$copyData | Foreach-Object -ThrottleLimit 32 -Parallel {
    $src = $_.Source
    $dst = $_.Destination

    if(-not [System.IO.File]::Exists($dst))
    {
        if([System.IO.File]::Exists($src))
        {
            try
            {
                [System.IO.File]::Copy($src, $dst, $true)
            }
            catch
            {
                Write-Host ("ERROR: Failed to copy {0} to {1}" -f @($src, $dst))
            }
        } `
        else
        {
            Write-Host ("ERROR: Missing source: {0}" -f @($src))
        }
    }
}

$sourceSize = 0
$destinationSize = 0
$copyData | ForEach-Object {
    $dstFI = [System.IO.FileInfo]::new($_.Destination)
    $srcFI = [System.IO.FileInfo]::new($_.Source)

    if(-not $dstFI.Exists)
    {
        Write-Host ("Missing destination: {0}" -f @($dstFI.FullName))
    }
    else
    {
        if(-not $srcFI.Exists)
        {
            Write-Host ("Missing source: {0}" -f @($srcFI.FullName))
        }
        else
        {
            $sourceSize += $srcFI.Length
            $destinationSize += $dstFI.Length
        }
     }
}
