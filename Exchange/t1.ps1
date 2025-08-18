$NumberOfLists = 15

# Connect-ExchangeOnline
#Write-Host ("Getting complete list of public folders as of: {0}... (this takes a while)" -f @([DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")))
try
{
#    $publicFolders = @(Get-PublicFolders -Identity "\" -Recurse -ResultSize "Unlimited" -ErrorAction Stop | Sort-Object -Property Identity)
    if($publicFolders.Length -gt 0)
    {
        Write-Host ("Splitting public folders into {0} lists." -f @($NumberOfLists))
        # Split the public folders into lists...
        $pfLists = [System.Collections.Generic.List[System.Object][]]::new($NumberOfLists)
        $listNumber = 0
        $pfIdx = 0
        while($pfIdx -lt $publicFolders.Length)
        {
            if($listNumber -ge $NumberOfLists)
            {
                $listNumber = 0
            }

            if($null -eq $pfLists[$listNumber])
            {
                $pfLists[$listNumber] = [System.Collections.Generic.List[System.Object]]::new()
            }

            $d = [PSCustomObject]@{
                EntryId = $publicFolders[$pfIdx].EntryId
                Identity = $publicFolders[$pfIdx].Identity
            }

            $pfLists[$listNumber].Add($d)

            $listNumber++
            $pfIdx++
        }

        # Save the lists to files...
        Write-Host "Saving lists..."
        $listNumber = 0
        while($listNumber -lt $pfLists.Length)
        {
            $pfFileName = "PFList{0:D2}.CSV" -f @($listNumber+1)
            try
            {
                $pfLists[$listNumber] | Export-CSV -Path $pfFileName -Delimiter "`t" -NoTypeInformation -ErrorAction Stop
            }
            catch
            {
                Write-Host -ForegroundColor Red ("Failed to save list #{0}." -f @($listNumber + 1))
            }

            $listNumber++
        }
    } `
    else
    {
        Write-Host -ForegroundColor Yellow "No public folder located."
    }
}
catch
{

}
