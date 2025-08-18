
$allGroupMembers = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
$controllers = @($cdot.Values)
while($a -lt $controllers.Length)
{
    $svms = @(Get-NcVserver -Controller $controllers[$a] | Where-Object { $_.VserverType -eq "data" })
    $b = 0
    while($b -lt $svms.Length)
    {
        try
        {
            $grpMbrs = @(Get-NcCifsLocalGroupMember -Controller $controllers[$a] -Vserver $svms[$b] -Name "BUILTIN\Administrators" -ErrorAction Stop)
            if ($grpMbrs.Length -gt 0)
            {
                $fsADM = @($grpMbrs | Where-Object { $_.Member -match "FS-FileServices-ADM" })
                if ($fsADM.Length -eq 0)
                {
                    try
                    {
                        Add-NcCifsLocalGroupMember -Controller $controllers[$a] -VserverContext $svms[$b] -Name "BUILTIN\Administrators" -Member "POWERENG\FS-FileServices-ADM" -ErrorAction Stop | Out-Null
                        Write-Host ("Added POWERENG\FS-FileServices-ADM to {0}\{1}:BUILTIN\Administrators  A:{2}, B:{3}" -f @($controllers[$a].Name, $svms[$b].Vserver, $a, $b))
                    }
                    catch
                    {
                        Write-Host -ForegroundColor Red ("ERROR: Failed to add POWERENG\FS-FileServices-ADM to {0}\{1}:BUILTIN\Administrators  A:{2}, B:{3}" -f @($controllers[$a].Name, $svms[$b].Vserver, $a, $b))
                    }
                } `
                else # NOT ($fsADM.Length -eq 0)
                {
                    # Nothing.
                }
            } `
            else # NOT ($grpMbrs.Length -gt 0)
            {
                # Nothing.
            }
        }
        catch
        {
            Write-Host -ForegroundColor Red ("Failed to get {0}\{1}:BUILTIN\Administrators" -f @($controllers[$a].Name, $svms[$b].Vserver))
        }
        <#
        $grpMbrs.ForEach({
            $allGroupMembers.Add($_)
        })
        #>
        $b++
    }
    $a++
}
