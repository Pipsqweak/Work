$failed = Get-Content -Path "C:\Users\kbriney-adm\Documents\PFPerms\Failed_Run_2.txt"
$a = 0
while($a -lt $failed.Length)
{
    $pfIdentity = $failed[$a]
    Write-Host -NoNewline -ForegroundColor Gray ("Checking {0}..." -f @($pfIdentity))
    try
    {
        $pf = Get-PublicFolder -Identity $pfIdentity -ErrorAction Stop
        if($null -ne $pf)
        {
            try
            {
                $pfPerms = Get-PublicFolderClientPermission -Identity $pf -ErrorAction Stop
                if(@($pfPerms | Where-Object { $_.User -match "CVEXBackupAccount1651078337" }).Length -gt 0)
                {
                    Write-Host -NoNewline -ForegroundColor Green "Perms ok"
                }
                else
                {
                    Write-Host -NoNewline -ForegroundColor Red "Perms not ok"
                }
            }
            catch
            {
                Write-Host -NoNewline -ForegroundColor Red ("Could not get public folder permissions")
            }
        }
    }
    catch
    {
        Write-Host -NoNewline -ForegroundColor Red ("Could not get public folder object")
    }
    Write-Host
    $a++
}