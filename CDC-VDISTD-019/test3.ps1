[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [System.String]
    $name
)

Write-Host ("Script: {0}" -f @($PSCommandPath))
Write-Host ("Name: {0}" -f @($name))


Start-Sleep -Seconds 15

# Calendar exports
$logFiles = @(Get-ChildItem -Path "C:\Temp\PFExportLogs\CDC-VDISTD-025" -Filter "*.log")
$calendarRedos = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $logFiles.Length)
{
    $logText = Get-Content -Path $logFiles[$a].FullName
    if($logText[14].EndsWith(" as ICS file."))
    {
        $d = "" | Select-Object EntryID, Identity
        $d.EntryID = $logText[11].Substring(71)
        $d.Identity = $logText[12].Substring(53)

        $existingEntries = @($calendarRedos | Where-Object { $_.EntryID -eq $d.EntryID })
        if($existingEntries.Length -eq 0)
        {
            $calendarRedos.Add($d)
            $logFiles[$a].Delete()
        } `
        else # NOT ($existingEntries.Length -eq 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($logText[15].EndsWith(" as ICS file."))
    {
        # Nothing.
    }
    $a++
}


# Empty public folder:
$logFiles = @(Get-ChildItem -Path "C:\Temp\PFExportLogs" -Filter "*.log" -Recurse)
$a = 0
while ($a -lt $logFiles.Length)
{
    $logText = Get-Content -Path $logFiles[$a].FullName

    if($logText.Length -ge 13)
    {
        if((-not [String]::IsNullOrEmpty($logText[13])) -and ($logText[13].EndsWith("No items exported, skipping ProjectWise import.")))
        {
            Write-Host ("Removing 'empty' log: {0}" -f @($logFiles[$a].FullName))
            $logFiles[$a].Delete()
        } `
        else # NOT ($logText[13] -eq "No items exported, skipping ProjectWise import.")
        {
            # Nothing.
        }
    }
    $a++
}

# Delete logs:
#   for successful export/import
#   ERROR: Failed to attach to the Outlook Application namespace.  -- need to redo anyway
#   ERROR: No top level public folder found.  Try resetting Outlook then try again.  -- need to redo anyway
$redoErrorExp = @(
    "ERROR: Failed to attach to the Outlook Application namespace\.",
    "ERROR: No top level public folder found.  Try resetting Outlook then try again\."
)
$toDelete = [System.Collections.Generic.List[System.Object]]::new()
$logFiles = @(Get-ChildItem -Path "C:\Temp\PFExportLogs" -Filter "*.log" -Recurse)
$a = 0
while($a -lt $logFiles.Length)
{
    $needToDelete = $false
    $logText = Get-Content -Path $logFiles[$a].FullName

    $b = 0
    while((-not $needToDelete) -and ($b -lt $redoErrorExp.Length))
    {
        $needToDelete = @(@($wee -match $redoErrorExp[$b]).Length -ge 1)
        $b++
    }
    if(-not $needToDelete)
    {
        $wee = @($logText -match "WARNING|ERROR|EXCEPTION")
        if(($wee.Length -eq 0) `
            -or (@($wee -match "Unable to locate any imported file with size:\s+$").Length -ge 1))
        {
            $importLine = @($logText -match ": INFO: Imported (\d+) items totalling ")
            if($importLine.Length -eq 1)
            {
                if($importLine[0] -match ": INFO: Imported (\d+) items totalling ")
                {
                    $importCount = $Matches[1]
                    $exportLine = @($logText -match ": INFO: Exported (\d+) items in")
                    if($exportLine.Length -eq 1)
                    {
                        if($exportLine[0] -match ": INFO: Exported (\d+) items in")
                        {
                            $exportCount = $Matches[1]

                            if($importCount -eq $exportCount)
                            {
                                $needToDelete = $true
                                Write-Host ("Exported: {0} | Imported: {1} | {2}" -f @($exportCount, $importCount, $logFiles[$a].FullName))
                            }
                        }
                    }
                }
            }
        }
    }

    if($needToDelete)
    {
        $toDelete.Add($logFiles[$a])
        Write-Host ("Deleting: {0}" -f @($logFiles[$a].FullName))
        # $logFiles[$a].Delete()
    }
    $a++
}

"ERROR: Failed to attach to the Outlook Application namespace."
$a = 0
while($a -lt 10)
{
    $a++
}
