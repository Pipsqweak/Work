
$jobFolder = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\LegalHold\Jobs\20250634"
# $dstBaseFolder = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\LegalHold\Test"
$dstBaseFolder = "\\cdcfs1\Discovery\172957_ENMAX\PW"

$jobFile = "172957_Main"

$dstFolder = "{0}\{1}" -f @($dstBaseFolder, $jobFile)
$dstFolderInfo = [System.IO.DirectoryInfo]::new($dstFolder)
if(-not $dstFolderInfo.Exists)
{
    try
    {
        New-Item -ItemType Directory -Path $dstBaseFolder -Name $jobFile | Out-Null
        $dstFolderInfo = [System.IO.DirectoryInfo]::new($dstFolder)
    }
    catch
    {
        Write-Host -ForegroundColor ("ERROR: Failed to create destination folder: {0}" -f @($dstFolder))
    }
}

if($dstFolderInfo.Exists)
{
    $sourceFilesFound = 0
    $sourceFilesSize = 0
    $jobFileListPath = "{0}\{1}.txt" -f @($jobFolder, $jobFile)
    $folderList = @(Get-Content -Path $jobFileListPath)
    $logFile = ("{0}\{1}.log" -f @($dstBaseFolder, $jobFile))
    $fnDict = [System.Collections.Generic.SortedDictionary[System.String,[System.Collections.Generic.List[System.Object]]]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $a = 0
    while($a -lt $folderList.Length)
    {
        $folderFiles = @(Get-ChildItem -Path $folderList[$a] -Recurse | Where-Object { -not $_.PSIsContainer} )
        $sourceFilesFound += $folderFiles.Length
        $b = 0
        while($b -lt $folderFiles.Length)
        {
            $fn = $folderFiles[$b].Name
            if(-not $fnDict.ContainsKey($fn))
            {
                $fnDict.Add($fn, [System.Collections.Generic.List[System.Object]]::new())
            }
            $fnDict[$fn].Add($folderFiles[$b])
            $sourceFilesSize += $folderFiles[$b].Length

            $b++
        }
        $a++
    }


    $sbLog = [System.Text.StringBuilder]::new()

    $uniqueFileNames = @($fnDict.Keys)
    Write-Host ("Found {0:N0} files." -f @($sourceFilesFound))
    Write-Host ("`tUnique file names: {0:N0}" -f @($uniqueFileNames.Length))
    Write-Host ("`tSize: {0:N0}`r`n" -f @($sourceFilesSize))

    $a = 0
    $copiedFileCount = 0
    $copiedSize = 0
    while($a -lt $uniqueFileNames.Length)
    {
        $tFiles = $fnDict[$uniqueFileNames[$a]] | Sort-Object -Property LastWriteTime
        $b = 0
        while($b -lt $tFiles.Count)
        {
            $srcFile = $tFiles[$b]
            $null = $sbLog.AppendLine(("{0}`t{1:N0}" -f @($srcFile.FullName, $srcFile.Length)))

            if($srcFile.Exists)
            {
                $dupSuffix = [String]::Empty
                if($b -gt 0)
                {
                    $dupSuffix = "_{0:D3}" -f @($b)
                }

                $dstFile = "{0}\{1}{2}{3}" -f @($dstFolder, $tFiles[$b].BaseName, $dupSuffix, $tFiles[$b].Extension)
                $dstFileInfo = [System.IO.FileInfo]::new($dstFile)

                if(-not $dstFileInfo.Exists)
                {
                    try
                    {
                        Copy-Item -Path $srcFile.FullName -Destination $dstFile -ErrorAction Stop
                        $copiedFileCount++
                        $copiedSize += $srcFile.Length
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to copy\r\n`tFrom: {0}`r`n`t  To: {1}" -f @($srcFile.FullName, $dstFile))
                        $null = $sbLog.AppendLine(("`tERROR: Failed to copy to: {0}" -f @($dstFile)))
                    }

        #            Write-Host ("copy {0} {1} :: {2}" -f @($srcFile, $dstFile, $tFiles[$b].LastWriteTime.ToString()))

                    $dstFileInfo = [System.IO.FileInfo]::new($dstFile)
                    if($dstFileInfo.Exists)
                    {
                        $dstFileInfo.CreationTime = $srcFile.CreationTime
                        $dstFileInfo.LastAccessTime = $srcFile.LastAccessTime
                        $dstFileInfo.LastWriteTime = $srcFile.LastWriteTime
                        $dstFileInfo.Attributes = $srcFile.Attributes
                        $null = $sbLog.AppendLine(("`tCopied to: {0}`t{1:N0}" -f @($dstFileInfo.FullName, $dstFileInfo.Length)))
                    }
                } `
                else
                {
                        $null = $sbLog.AppendLine(("`tERROR: {0} already exists" -f @($dstFile)))
                        Write-Host -ForegroundColor Red ("ERROR: {0} already exists" -f @($dstFile))
                }
            } `
            else
            {
                $null = $sbLog.AppendLine("`tERROR: Does not exist")
                Write-Host -ForegroundColor Red ("ERROR: {0} does not exist" -f @($srcFile.FullName))
            }
            $b++
        }

        $a++
    }
    $null = $sbLog.AppendLine(("`r`nTotal files copied: {0:N0}`r`nTotal Size: {1:N0}" -f @($copiedFileCount, $copiedSize)))

    Set-Content -Value $sbLog.ToString() -Path $logFile

    Write-Host ("Total files copied: {0:N0}`r`nTotal Size: {1:N0}" -f @($copiedFileCount, $copiedSize))
}




# Shared Mailboxes...
$sm = @(Get-ADUser -Filter * -Properties @("Name","CanonicalName","CN","Description","DisplayName","DistinguishedName","EmailAddress","legacyExchangeDN","mail","mailNickname","msExchUMDtmfMap","proxyAddresses","SamAccountName","targetAddress","textEncodedOrAddress","UserPrincipalName"))



$projectsToSearchFor = Get-Content -Path "E:\Tmp\fedsmsearch.txt"
$possibleMatches = [System.Collections.Generic.List[System.Object]]::new()
$propertiesToSearch = @("Name","CanonicalName","CN","Description","DisplayName","DistinguishedName","EmailAddress","legacyExchangeDN","mail","mailNickname","msExchUMDtmfMap","proxyAddresses","SamAccountName","targetAddress","textEncodedOrAddress","UserPrincipalName")
$userAccts = [System.Collections.Generic.List[System.Object]]::new()

# The most likely place to find a shared mailbox is in the shared mailboxes OU... so make sure I search there first.
@($sm | Where-Object { $_.DistinguishedName -match "OU=Shared Mailboxes,OU=PEI,DC=powereng,DC=com" } | Sort-Object -Property Name).ForEach({
    $userAccts.Add($_)
})
@($sm | Where-Object { $_.DistinguishedName -notmatch "OU=Shared Mailboxes,OU=PEI,DC=powereng,DC=com" } | Sort-Object -Property Name).ForEach({
    $userAccts.Add($_)
})

<#
$sm.ForEach({
    $userAccts.Add($_)
})
#>

$p = 0
while($p -lt $projectsToSearchFor.Length)
{
    Write-Host -NoNewline ("`r`nSearching for {0}..." -f @($projectsToSearchFor[$p]))
    $a = 0
    $idxToRemove = -1
    while(($idxToRemove -eq -1) -and ($a -lt $userAccts.Count))
    {
        # $properties = @($sm[$a] | Get-Member -MemberType Properties)
        $b = 0
        while(($idxToRemove -eq -1) -and ($b -lt $propertiesToSearch.Length))
        {
            $prop = $userAccts[$a].$($propertiesToSearch[$b])
            if($null -ne $prop)
            {
                foreach($propVal in $prop)
                {
                    $str = $propVal.ToString()
                    if((-not [String]::IsNullOrEmpty($str)) -and ($str -match $projectsToSearchFor[$p]))
                    {
                        $d = "" | Select-Object DistinguishedName,Property,PropertyValue,SearchValue
                        $d.DistinguishedName = $userAccts[$a].DistinguishedName
                        $d.Property = $propertiesToSearch[$b]
                        $d.SearchValue = $projectsToSearchFor[$p]
                        $d.PropertyValue = $str

                        $d | Export-Csv -Path "E:\Tmp\PossibleFedProjects.csv" -NoTypeInformation -Delimiter "," -Append
                        $possibleMatches.Add($d)
                        Write-Host -NoNewline "*"
                        $idxToRemove = $a
                        break
                    }
                }
            }
            $b++
        }

        if(($idxToRemove -gt -1) -and ($idxToRemove -lt $userAccts.Count))
        {
            $userAccts.RemoveAt($idxToRemove)
        }

        $a++
        if(($a % 1000) -eq 0)
        {
            Write-Host -NoNewline "."
        }
    }
    $p++
    Write-Host
}

$secondTry.ForEach({
    $st = $_
    Write-Host -NoNewline $st
    $kkk = @($sm | Where-Object { $_.Name -match $st })
    Write-Host ("`t{0}" -f @($kkk.Length))
    foreach($kk in $kkk)
    {
        $d = "" | Select-Object DistinguishedName,Property,PropertyValue,SearchValue
        $d.DistinguishedName = $kk.DistinguishedName
        $d.Property = "Name"
        $d.SearchValue = $st
        $d.PropertyValue = $kk.Name

        $d | Export-Csv -Path "E:\Tmp\PossibleFedProjects.csv" -NoTypeInformation -Delimiter "`t" -Append
        $d
    }
})
