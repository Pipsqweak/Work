$shares = Get-NcCifsShare -Controller @($cdot.Values) | Sort-Object CifsServer, ShareName
$a = 0
while($a -lt $shares.Length)
{
    $shareToModify = $shares[$a]
    if($shareToModify.ShareName -notin @("c`$","ipc`$","admin`$","Shares`$"))
    {
        try
        {
            $cifsShare = Get-NcCifsShare -Controller $shareToModify.NcController -CifsServer $shareToModify.CifsServer -Name $shareToModify.ShareName
            if($null -ne $cifsShare)
            {
                $shareProperties = $cifsShare.ShareProperties
                if($shareProperties -notcontains "show_previous_versions")
                {
                    Write-Host -ForegroundColor Green -NoNewline ("Fixing \\{0}\{1}..." -f @($shareToModify.CifsServer, $shareToModify.ShareName))
                    $shareProperties += "show_previous_versions"
                    try
                    {
                        $modifiedShare = Set-NcCifsShare -Controller $cifsShare.NcController -Name $cifsShare.ShareName -ShareProperties $shareProperties -ErrorAction Stop
                        if($null -ne $modifiedShare)
                        {
                            if($modifiedShare.ShareProperties -contains "show_previous_versions")
                            {
                                Write-Host -ForegroundColor Green "success"
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Red "Error: Failed to set share properties."
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Red "Error: Unable to verify changed share properties."
                        }
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red "Exception: Failed to set share properties"
                    }
                }
            }
        }
        catch
        {
            Write-Host ("`r`nException: Failed to retrieve CIFS share for: \\{0}\{1}`r`n" -f @($shareToModify.CifsServer, $shareToModify.ShareName))
        }
    }
    $a++
}

$shareToModify = $shares | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -eq "Test_03")}
if($shareToModify.ShareProperties -notcontains "show_previous_versions")
{
    Set-NcCifsShare -Controller $shareToModify.NcController -Name $shareToModify.ShareName -ShareProperties $shareProperties
}

$sharePropertyData = @(
    $shares.ForEach({
        $d = "" | Select-Object CifsServer, Name, Path, Browsable, ChangeNotify, OpLocks, ShowSnaphots, ShowPreviousVersions

        $d.CifsServer = $_.CifsServer
        $d.Name = $_.ShareName
        $d.Path = $_.Path
        $d.Browsable = $_.ShareProperties -contains "browsable"
        $d.ChangeNotify = $_.ShareProperties -contains "changenotify"
        $d.OpLocks = $_.ShareProperties -contains "oplocks"
        $d.ShowSnaphots = $_.ShareProperties -contains "showsnapshot"
        $d.ShowPreviousVersions = $_.ShareProperties -contains "show_previous_versions"

        $d
    })
) | ConvertTo-CSV -NoTypeInformation -Delimiter "`t" | Set-Clipboard
