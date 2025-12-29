$exported = Import-CSV -Path "E:\Tmp\2021-06-0328.csv" -Delimiter "`t"

$exportedPaths = [System.Collections.Generic.List[System.String]]::new()
$a = 0

while($a -lt $exported.Length)
{
    if($exported[$a].ItemType -eq "Item")
    {
        $pieces = $exported[$a].Path -split "/"
        $searchPath = "Proposals - Archive\{0}\{1}" -f @(($pieces[3..($pieces.Length - 1)] -join "\"), $exported[$a].Name)
        $i = $exportedPaths.BinarySearch($searchPath)
        if($i -lt 0)
        {
            $exportedPaths.Insert(-bnot $i, $searchPath)
        }
    }
    $a++
}

$missingPaths = [System.Collections.Generic.List[System.String]]::new()

$a = 0
while($a -lt $pwData.ProjectWiseObjects.Length)
{
    if(($pwData.ProjectWiseObjects[$a].MyType -eq "ProjectWiseDocument") -and (-not $pwData.ProjectWiseObjects[$a].IsSet))
    {
        $i = $exportedPaths.BinarySearch($pwData.ProjectWiseObjects[$a].FullPath)
        if($i -lt 0)
        {
            $missingPaths.Add($pwData.ProjectWiseObjects[$a].FullPath)
        }
    }
    $a++
}
