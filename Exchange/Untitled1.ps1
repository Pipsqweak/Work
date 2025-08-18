
<#
 
   Build Exchange Public Folder Identification files...

#>
Connect-ExchangeOnline
$pf = Get-PublicFolder -Identity "\" -Recurse -ResultSize "Unlimited"
$pfIds = @($pf | Select-Object -Unique -ExpandProperty Identity | Sort-Object)

$maxThreads = 10   # How many processes will be ran to update permissions?

# $pfIds = Get-Content -Path "C:\Users\kbriney-adm\Documents\PFPerms\All-PFIdentities-Combined.txt"

# Build a dictionary of $maxThreads ID lists, and initialize them to empty lists.
$idDict = [System.Collections.Generic.SortedDictionary[[int],[System.Collections.Generic.List[System.String]]]]::new()
$a = 0
while($a -lt $maxThreads)
{
    $idDict.Add($a, [System.Collections.Generic.List[System.String]]::new())
    $a++
}
# Shortcut for all the keys in the dictionary.
$idxKeys = @($idDict.Keys)

# Track the dictionary idx of each list containing a given ID
$foundIdxs = [System.Collections.Generic.List[int]]::new()

# Build the dictionary balancing the number of IDs in each list.
$a = 0
while($a -lt $pfIds.Length)
{
    $lowCountIdx = -1    # Track the dictionary key for the smallest list of IDs (count wise) 
    
    # Make sure an individual ID is not in any other list.  Seems redundant, but I had some oddness
    #   where the same ID was saved to multiple ID list files.  So I got anal about it.
    $b = 0
    $foundIdxs.Clear()
    while($b -lt $idxKeys.Length)
    {
        $idx = $idxKeys[$b]    # Shortcut for the key of the list we are looking at.

        # Set $lowCountIdx if needed.
        if(($lowCountIdx -eq -1) -or ($idDict[$idx].Count -lt $idDict[$lowCountIdx].Count))
        {
            $lowCountIdx = $idx
        }

        # If $pfIds[$a] is already in a list, add the list's idx to $foundIdxs...
        if($idDict[$idx].BinarySearch($pfIds[$a]) -ge 0)
        {
            $i = $foundIdxs.BinarySearch($idx)
            if($i -lt 0)
            {
                $foundIdxs.Insert(-bnot $i, $idx)
            }
        }

        $b++
    }

    # If the ID was not found in any of the lists, then
    if($foundIdxs.Count -eq 0)
    {
        $idx = 0
        if($lowCountIdx -gt -1)
        {
            $idx = $lowCountIdx
        }
        if(-not $idDict.ContainsKey($idx))
        {
            $idDict.Add($idx, [System.Collections.Generic.List[System.String]]::new())
        }
        $i = $idDict[$idx].BinarySearch($pfIds[$a])
        if($i -lt 0)
        {
            $idDict[$idx].Insert(-bnot $i, $pfIds[$a])
        }
        else
        {
            Write-Host ("WTH!!  {0} already exists in `$idDict[{1}]" -f @($pfIds[$a], $idx))
        }
    }
    else
    {
        Write-Host ("{0} found in idxs: {1}" -f @($pfIds[$a], ($foundIdx -join ", ")))
    }

    $a++
}

$idxKeys = @($idDict.Keys)
$a = 0
while($a -lt $idxKeys.Length)
{
    $idx = $idxKeys[$a]
    $savePath = "C:\Users\kbriney-adm\Documents\PFPerms\All-PFIdentities-{0}.txt" -f @($idx)
    $idDict[$idx] | Set-Content -path $savePath

    $a++
}
    


$chkIdentities = [System.Collections.Generic.List[System.String]]::new()
$idFiles = Get-ChildItem -Path "C:\Users\kbriney-adm\Documents\PFPerms" -Filter "All-PFIdentities??.txt"

$a = 0
while($a -lt $idFiles.Length)
{
    $tmpIDs = Get-Content -Path $idFiles[$a].FullName
    $b = 0
    while($b -lt $tmpIDs.Length)
    {
        $i = $chkIdentities.BinarySearch($tmpIDs[$b])
        if($i -lt 0)
        {
            if(-not $dups.ContainsKey($idFiles[$a].Name))
            {
                
            }
            $chkIdentities.Insert(-bnot $i, $tmpIDs[$b])
        }
        else
        {
            Write-Host ("Dup: {0}/{1}" -f @($idFiles[$a].Name, $tmpIDs[$b]))
        }
        $b++
    }
    $a++
}




