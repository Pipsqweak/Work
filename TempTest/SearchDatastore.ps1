$datastores = @(Get-Datastore -Server $vCenter | Sort-Object Type, Name)
$uniqueDatastores = @()
$a = 0
while($a -lt $datastores.Length)
{
    if($datastores[$a].Type -eq "VMFS")
    {
        $uniqueDatastores += $datastores[$a]
    }
    else
    {
        if(@($uniqueDatastores | Where-Object { ($_.RemoteHost -eq $datastores[$a].RemoteHost) -and ($_.RemotePath -eq $datastores[$a].RemotePath)}).Length -eq 0)
        {
            $uniqueDatastores += $datastores[$a]
        }
    }
    $a++
}

$fileQueryFlags = [VMware.Vim.FileQueryFlags]::new()
$fileQueryFlags.FileSize = $true
$fileQueryFlags.FileType = $true
$fileQueryFlags.Modification = $true

$searchSpec = [VMware.Vim.HostDatastoreBrowserSearchSpec]::new()
$searchSpec.details = $fileQueryFlags
$searchSpec.sortFoldersFirst = $true
$searchSpec.MatchPattern = "*.vmdk"

$vmdkFiles = @()
$unusedVMDKs = @()

$a = 0
while($a -lt $uniqueDatastores.Length)
{
    $dsView = $uniqueDatastores[$a] | Get-View
    $dsBrowser = Get-View -Server $vCenter $dsView.browser

    $rootPath = "[{0}]" -f @($dsView.summary.Name)

    Write-Host ("Searching {0}..." -f @($rootPath))
    # Used to filter out folders/files that start with a '.'
    $folderMatchStr = "\[{0}\] \." -f @($dsView.summary.Name)

    $searchResult = $dsBrowser.SearchDatastoreSubFolders($rootPath, $searchSpec)
    $noSnaps = $searchResult | Where-Object { $_.FolderPath -notmatch $folderMatchStr }

    foreach ($folder in $noSnaps)
    {
        foreach ($fileResult in $folder.File)
        {
            $file = "" | Select-Object Datastore, Name, Size, Modified, FullPath, Used
            $file.Datastore = $dsView.summary.Name
            $file.Name = $fileResult.Path
            $file.Size = $fileResult.Filesize
            $file.Modified = $fileResult.Modification
            $file.FullPath = $folder.FolderPath + $file.Name
            $file.Used = $true

            $used = " "
            $usedVMDKs = @($diskBackingData | Where-Object { $_.BackingFile -eq $file.FullPath })
            if($usedVMDKs.Length -eq 0)
            {
                $file.Used = $false
                $unusedVMDKs += $file
                $used = "*"
            }
            Write-Host ("{0}{1}`t{2}`t{3}`t{4}`t{5}" -f @($used,$file.Datastore,$file.Name, $file.Size, $file.Modified, $file.FullPath))
            $vmdkFiles += $file
        }
    }

    $a++
}


# $groups = @($vmdkFiles | Where-Object { -not $_.Used }) | Group-Object -Property Datastore
$groups = $unusedVMDKs | Group-Object -Property Datastore

$a = 0
while($a -lt $groups.Count)
{
    $grpSum = ($groups[$a].Group | Measure-Object -Property Size -Sum).Sum
    Write-Host ("{0}: {1:N2}GB" -f @($groups[$a].Name, ($grpSum / 1gb)))
    $a++
}
