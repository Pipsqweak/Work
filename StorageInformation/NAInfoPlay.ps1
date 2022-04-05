     
        
$naInfos = [System.Collections.Generic.List[NANodeInformation8]]::new()

$a = 0
while($a -lt $smNodeNames.Length)
{
    $node = $smNodes[$smNodeNames[$a]]
    Write-Host ("Processing {0}..." -f @($node.Name))
    $ni = [NANodeInformation8]::new($node)
    $naInfos.Add($ni)

    $a++
}