
$notImported = [System.Collections.Generic.List[System.Object]]::new()
$importedFileNames = [System.Collections.Generic.List[String]]::new()


$a = 0
while($a -lt $exportedFiles.Count)
{
    $found = @($ImportResults | Where-Object { $_.FileName -ceq $exportedFiles[$a].Name })
    if($found.Length -gt 1)
    {
        Write-Host ("{0} : {1}" -f @($found.Length, $exportedFiles[$a].Name))
    }
    $a++
}

$a = 0
while($a -lt $ImportResults.Count)
{
    $i = $importedFileNames.BinarySearch($ImportResults[$a].FileName)
    if($i -lt 0)
    {
        $importedFileNames.Insert(-bnot $i, $ImportResults[$a].FileName)
    }
    $a++
}


$a = 0
while($a -lt $exportedFiles.Count)
{
    $i = $importedFileNames.BinarySearch($exportedFiles[$a].Name)
    if($i -lt 0)
    {
        $notImported.Add($exportedFiles[$a])
    }
    $a++
}
