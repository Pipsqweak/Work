class FileInfoComparer2:System.Collections.Generic.IComparer[System.IO.FileInfo]
{
    [int] Compare([System.IO.FileInfo] $x, [System.IO.FileInfo] $y) {
        return $x.LastWriteTime.CompareTo($y.LastWriteTime)
    }
}

class PFObjectComparerByConversationIndex:System.Collections.Generic.IComparer[System.Object]
{
    [int] Compare([System.Object] $pfObj1, [System.Object] $pfObj2) {
        $retVal = 0
        if(($null -eq $pfObj1) -and ($null -eq $pfObj2))
        {
            $retVal = 0
        } `
        elseif($null -eq $pfObj1)
        {
            $retVal = -1
        } `
        elseif($null -eq $pfObj2)
        {
            $retVal = 1;
        } `
        else
        {
            if(($null -eq $pfObj1.ConversationIndex) -and ($null -eq $pfObj2.ConversationIndex))
            {
                $retVal = 0
            } `
            elseif($null -eq $pfObj1.ConversationIndex)
            {
                $retVal = -1
            } `
            elseif($null -eq $pfObj2.ConversationIndex)
            {
                $retVal = 1;
            } `
            else
            {
                $retval = $pfObj1.ConversationIndex.CompareTo($pfObj2.ConversationIndex)
            }
        }

        return $retval
    }
}

$Script:PFObjectConversationIndexComparer = [PFObjectComparerByConversationIndex]::new()

# 1271 ---------------------
$Script:ItemsByConversation[$pfObj.ConversationID].Add($pfObj)

    $i = $Script:ItemsByConversation[$pfObj.ConversationID].BinarySearch($pfObj, $Script:PFObjectConversationIndexComparer)
    if($i -lt 0)
    {
        $i = -bnot $i
    }
    $Script:ItemsByConversation[$pfObj.ConversationID].Insert($i, $pfObj)

# 1672      ---------------------------
$oldestItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]] | Sort-Object -Property SortTime | Select-Object -First 1

    $oldestItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]][0]



$listToAddTo = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

$comparer = [FileInfoComparer2]::new()

$a = 0
while($a -lt $files.Length)
{
    $i = $listToAddTo.BinarySearch($files[$a], $comparer)
    if($i -lt 0)
    {
        $listToAddTo.Insert(-bnot $i, $files[$a])
    }

    $a++
}


$a = 0
$notProcessed = [System.Collections.Generic.List[System.Object]]::new()
while($a -lt $pfListFiles.Length)
{
    $pfList = @(Import-CSV -Delimiter "`t" -Path $pfListFiles[$a].FullName)
    $notProcessed.Clear()
    $b = 0
    while($b -lt $pfList.Length)
    {
        if(-not (PublicFolderHasBeenExported -entryID $pfList[$b].EntryID))
        {
            $notProcessed.Add($pfList[$b])
        }
        $b++
    }

    if($notProcessed.Count -gt 0)
    {
        $notProcessed | Export-CSV -Delimiter "`t" -Path ("C:\Temp\t2\Lists\20250225\Updated\{0}-upd.csv" -f @($pfListFiles[$a].BaseName))
    }
    $a++
}
