
$Script:MaximumProjectWisePathLength = 231

function SetSubjectForPWPath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [String]
        $prefix,

        [Parameter(Mandatory = $true, Position = 1)]
        [String]
        $senderName,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]
        $subject,

        [Parameter(Mandatory = $true, Position = 3)]
        [String]
        $extension,

        [Parameter(Mandatory = $false, Position = 4)]
        [Int32]
        $idxNum = -1
    )

    if($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4} ({5}).{6}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $idxNum, $extension)
    } `
    else # NOT ($idxNum -gt -1)
    {
        $pwPath = "{0}\{1}\{2}{3}{4}.{5}" -f @($Script:ProjectWiseBaseFolderName, $Script:ExportedPublicFolderPath, $prefix, $senderName, $subject, $extension)
    }
    if($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    {
        $subjCharactersToRemove = $pwPath.Length - $Script:MaximumProjectWisePathLength
        if($subjCharactersToRemove -gt 0)
        {
            $subject = $subject.SubString(0, $subject.Length - $subjCharactersToRemove)
        } `
        else # NOT ($subjCharactersToRemove -gt 0)
        {
            LogError ("Unable to create a viable ProjectWise path for {0}." -f @($pwPath))
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($pwPath.Length -gt $Script:MaximumProjectWisePathLength)
    {
        # Nothing.
    }

    return $subject
}

$publicFolder = $OutlookNamespace.GetFolderFromID("000000001A447390AA6611CD9BC800AA002FC45A030012225CC57BF01F4EA8CCA87A792FF35F0000C13B89D70000")

$itemList = [System.Collections.Generic.List[System.Object]]::new()
$table = $publicFolder.GetTable()
$table.MoveToStart()
$a = 0
while(-not $table.EndOfTable)
{
    $a++
    if(($a % 10) -eq 0)
    {
        Write-Host $a
    }
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

            $retries = 0
            $itemList.Add($d)
            do
            {
                $retries++
                try
                {
                    $item = $null
                    $item = $OutlookNamespace.GetItemFromID($entryID)
                }
                catch
                {
                    $item = $null
                    Write-Host ("Failed to get item with entry ID: " -f @($entryID))
                }

                if(($null -eq $item) -or ([String]::IsNullOrEmpty($item.EntryID)))
                {
                    Write-Host ("Retry {0} for {1}" -f @($retries, $entryID))
                }                
            } while(($retries -lt 5) -and (($null -eq $item) -or ([String]::IsNullOrEmpty($item.EntryID))))

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
        }
    }
    else
    {
        Write-Host ("Null Row")
    }
}


$uniqueItemEntryIDs = [System.Collections.Generic.List[String]]::new()
$uniqueTableEntryIDs = [System.Collections.Generic.List[String]]::new()

$a = 0
while($a -lt $itemList.Count)
{
    $i = $uniqueItemEntryIDs.BinarySearch($itemList[$a].ItemEntryID)
    if($i -lt 0)
    {
        $uniqueItemEntryIDs.Insert(-bnot $i, $itemList[$a].ItemEntryID)
    }
    
    $i = $uniqueTableEntryIDs.BinarySearch($itemList[$a].TableEntryID)
    if($i -lt 0)
    {
        $uniqueTableEntryIDs.Insert(-bnot $i, $itemList[$a].TableEntryID)
    }

    $a++
}

Write-Host ("Unique Item Entry IDs:  {0}" -f @($uniqueItemEntryIDs.Count))
Write-Host ("Unique Table Entry IDs: {0}" -f @($uniqueTableEntryIDs.Count))

