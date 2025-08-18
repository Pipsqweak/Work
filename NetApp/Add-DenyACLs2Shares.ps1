ConnectTo cdot

@(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Foreach-Object {
    $s = $_
    $shareACLs = Get-NcCifsShareAcl -Controller $s.NcController -VserverContext $s.Vserver  -Share $s.ShareName

    if(@($shareACLs | Where-Object { <# ($_.UserOrGroup -eq "POWERENG\FS-AllShares-XD") -and #> ($_.Permission -eq "no_access") }).Length -eq 0)
    {
        Write-Host ("{0}`t{1}`t{2}`tAdding POWERENG\FS-AllShares-XD no_access" -f@($s.NcController.Name, $s.Vserver, $s.ShareName))

        try
        {
            Add-NcCifsShareAcl -Controller $s.NcController -VserverContext $s.Vserver -Share $s.ShareName -UserOrGroup "POWERENG\FS-AllShares-XD" -Permission "no_access" -ErrorAction Stop | Out-Null
        }
        catch
        {
            Write-Host -ForegroundColor Red ("`tFailed adding no_access rule to: {0}`t{1}`t{2}." -f@($s.NcController.Name, $s.Vserver, $s.ShareName))
        }
    }
    else
    {
        # Write-Host ("{0}`t{1}`t{2}`tAlready has POWERENG\FS-AllShares-XD no_access" -f@($s.NcController.Name, $s.Vserver, $s.ShareName))
    }
}
