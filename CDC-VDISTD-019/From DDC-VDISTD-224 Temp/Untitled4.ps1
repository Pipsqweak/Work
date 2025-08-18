$publicFolder = $OutlookNamespace.GetFolderFromID("000000001A447390AA6611CD9BC800AA002FC45A030012225CC57BF01F4EA8CCA87A792FF35F0000C13B89D70000")

$itemList = [System.Collections.Generic.List[System.Object]]::new()
$table = $publicFolder.GetTable()
$table.MoveToStart()
$a = 0
while(-not $table.EndOfTable)
{
    $row = $table.GetNextRow()
    if($null -ne $row)
    {
        $entryID = $row["EntryID"]
        if(-not [String]::IsNullOrEmpty($entryID))
        {
            $d = [PSCustomObject]@{
                TableEntryID = $entryID
                ItemEntryID = [String]::Empty
            }

            $itemRetries = 0
            $itemList.Add($d)
            do
            {
                $itemRetries++
                try
                {
                    $item = $null
                    $item = $OutlookNamespace.GetItemFromID($entryID)

                    if($null -ne $item)
                    {
                        $entryIDRetries = 0
                        while(([String]::IsNullOrEmpty($item.EntryID)) -and ($entryIDRetries -lt 5))
                        {
                            $entryIDRetries++
                            Write-Host ("Retrying .EntryID...{0}" -f @($entryIDRetries))
                            Start-Sleep -Milliseconds 50
                        }
                    } `
                    else
                    {
                        # Nothing
                    }
                }
                catch
                {
                    $item = $null
                    Write-Host ("Exception getting item with entry ID: {0}" -f @($entryID))
                }

                if(($null -eq $item) -or ([String]::IsNullOrEmpty($item.EntryID)))
                {
                    Write-Host ("Retry {0} for {1}" -f @($itemRetries, $entryID))
                    if($null -eq $item)
                    {
                        Write-Host ("`tNull item")
                    }
                    else
                    {
                        Write-Host ("`tNull item.EntryID")
                    }
                    Start-Sleep -Milliseconds 250
                }                
            } while(($itemRetries -lt 5) -and (($null -eq $item) -or ([String]::IsNullOrEmpty($item.EntryID))))

            if($null -ne $item)
            {
                if(-not [String]::IsNullOrEmpty($item.EntryID))
                {
                    $d.ItemEntryID = $item.EntryID
                    if([String]::IsNullOrEmpty($d.ItemEntryID))
                    {
                        Write-Host ("Null item entry ID for row entry ID: {0}" -f @($entryID))
                    }
                }
            }
            else
            {
                Write-Host ("Null item for entry ID: {0}" -f @($entryID))
            }
        } `
        else
        {
            Write-Host ("Null entryID for row number: {0}" -f @($a))
        }
    }
    else
    {
        Write-Host ("Null Row")
    }

    $a++
    if(($a % 10) -eq 0)
    {
        Write-Host ("RowCount: {0}, Item Count: {1}" -f @($a, $itemList.Count))
    }
}
