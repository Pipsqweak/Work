# ConnectTo cDot
# Source in most of C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\TempTest\IPAMDNS\FixDNSPTR.ps1

GetIPAMData

$selectStatement = "SELECT id,loc FROM locations ORDER BY id;"
$ipamLocationsDT = $Global:ipamDB.GetDataTable($selectStatement)
$Global:ipamLocations = [System.Collections.Generic.SortedDictionary[System.Int32,System.String]]::new()

$ipamLocationsDT.Rows.ForEach({
    $row = $_
    if ((-not [String]::IsNullOrEmpty($row.loc)) -and (-not $Global:ipamLocations.ContainsKey($row.id)))
    {
        $Global:ipamLocations.Add($row.id, $row.loc)
    } `
    else # NOT (-not $Global:ipamLocations.ContainsKey()
    {
        # Nothing.
    }
})

$currentCIFSCOnnections = @(Get-NcCifsConnection -Controller $yyc01CDOT)
$locationCount = [System.Collections.Generic.SortedDictionary[System.String, System.Int32]]::new()

$a = 0
while($a -lt $currentCIFSCOnnections.Length)
{
    $workstationIP = $currentCIFSCOnnections[$a].WorkstationIp.ToString()
    if (-not [String]::IsNullOrEmpty($workstationIP))
    {
        $workstationLocationID = @(IPAMSubnetsForAddress -ipStr $workstationIP) | Foreach-Object { $_.Row.loc } | Select-Object -First 1
        if ($null -ne $workstationLocationID)
        {
            if ($Global:ipamLocations.ContainsKey($workstationLocationID))
            {
                $d = [PSCustomObject]@{
                    SourceIP = $workstationIP
                    Location = $Global:ipamLocations[$workstationLocationID]
                }

                $d
            } `
            else # NOT ($Global:ipamLocations.ContainsKey($workstationLocationID))
            {
                # Nothing.
            }
        } `
        else # NOT ($null -ne $workstationLocationID)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($workstationIP))
    {
        # Nothing.
    }

    $a++
}

$workstationLocationID = @(IPAMSubnetsForAddress -ipStr "8.8.8.8") | Foreach-Object { $_.Row.loc } | Select-Object -First 1

$currentCIFSCOnnections[10]
