
$combinedResultsFileName = "PreSDWANCombined.csv"
$combinedSearchPhrase  = "Before SDWAN conversion"


$combinedResultsFileName = "PostSDWANCombined.csv"
$combinedSearchPhrase  = "Post SDWAN conversion"

$combinedResultsFile = "\\cdcfs1\Reference\PerfTest\Results\{0}" -f @($combinedResultsFileName)

$resultFiles = @(Get-ChildItem -Path "\\cdcfs1\Reference\PerfTest\Results" -Filter "*.csv")

$combinedResults = [System.Collections.Generic.List[System.Object]]::new()
$combinedFiles = [System.Collections.Generic.List[System.String]]::new()

$a = 0
while($a -lt $resultFiles.Length)
{
    $results = Import-CSV -Path $resultFiles[$a].FullName -Delimiter "`t"
    $included = $false

    $b = 0
    while($b -lt $results.Length)
    {
        if($results[$b].Description -eq $combinedSearchPhrase)
        {
            $combinedResults.Add($results[$b])
            $included = $true
        }
        $b++
    }

    if($included)
    {
        Write-Host -NoNewline ("{0}" -f @($resultFiles[$a].FullName))
        # Do not add $combinedResultsFileName to the list of combined files, or it will be removed just after it is recreated...
        if($resultFiles[$a].Name -notmatch $combinedResultsFileName)
        {
            $combinedFiles.Add($resultFiles[$a].FullName)
            Write-Host -NoNewline (" to be deleted")
        }
        else
        {
        }

        Write-Host ""
    }

    $a++
}

try
{
    $combinedResults | Sort-Object Office | Export-CSV -Path $combinedResultsFile -Delimiter "`t" -NoTypeInformation -Force -Confirm:$false -ErrorAction Stop
    $combinedFiles | Foreach-Object { Remove-Item -Path $_ -Force -Confirm:$false -ErrorAction Stop }
}
catch
{

}
