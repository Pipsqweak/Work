$done = [System.Collections.Generic.List[System.String]]::new()
$completed = @(Import-CSV -Delimiter "`t" -Path "\\boifs1\ITxchange\klbtest\ListOfExportedPublicFolders.csv")
@(Get-Content -Path "C:\Temp\T2\Lists\20250225\03done.txt").ForEach({ $done.Add($_) })
$done.Sort()

$pfItems = [System.Collections.Generic.List[System.Object]]::new()

@(Import-CSV -Path "C:\Temp\T2\Lists\20250225\PFList_03.CSV" -Delimiter "`t").ForEach({
    Write-Host -NoNewline ("Searching for {0}" -f @($_.EntryID))
    $i = $done.BinarySearch($_.EntryID)
    if($i -lt 0)
    {
        Write-Host -ForegroundColor Red " Not done"
        $pfItems.Add($_)
    } `
    else
    {
        Write-Host -ForegroundColor Green " Done"
    }
})

$pfItems | Export-CSV -NoTypeInformation -Delimiter "`t" -Path "C:\Temp\t2\Lists\20250225\PFList_03a.CSV"
