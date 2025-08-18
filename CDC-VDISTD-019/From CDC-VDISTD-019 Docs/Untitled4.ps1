$convKeys = @($Script:ItemsByConversation.Keys)
$pfObjsMaster = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $convKeys.Length)
{
    $b = 0
    while($b -lt $Script:ItemsByConversation[$convKeys[$a]].Count)
    {
        $pfObjsMaster.Add($Script:ItemsByConversation[$convKeys[$a]][$b])
        $b++
    }
    $a++
}

