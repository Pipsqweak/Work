[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
    [ValidateRange(1,20)]
    [Int32]
    $NumberOfLists,

    [Parameter(Mandatory=$true, Position=1)]
    [String]
    $exportFolder
)

Connect-ExchangeOnline
if([System.IO.Directory]::Exists($exportFolder))
{
    # Connect-ExchangeOnline
    Write-Host ("Getting complete list of public folders as of: {0}... (this takes a while)" -f @([DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")))
    try
    {
        $publicFolders = @(Get-PublicFolder -Identity "\" -Recurse -ResultSize "Unlimited" -ErrorAction Stop | Sort-Object -Property Identity)
        if($publicFolders.Length -gt 0)
        {
            # Split the public folders into lists...
            Write-Host ("Splitting public folders into {0} lists." -f @($NumberOfLists))
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
                $pfFileName = "{0}\PFList_{1:D2}.CSV" -f @($exportFolder, $listNumber+1)
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
            Write-Host -ForegroundColor Yellow "No public folders located."
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed to get a list of all public folders from Exchange online."
    }
} `
else
{
    Write-Host -ForegroundColor Red ("Export folder: {0} does not exist." -f @($exportFolder))
}
