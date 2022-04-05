$retentions = Import-Csv -Delimiter "`t" -Path 'C:\Users\kbriney-adm\PSScripts\Snaplock Report\retention.csv'

$a = 0
while($a -lt $retentions.Length)
{
    $b = $null
    Write-Host ("{0}:{1}:{2}" -f @($retentions[$a].Cluster, $retentions[$a].VServer, $retentions[$a].Volume))
    try
    {
        $b = Get-NcSnaplockVolAttr -Controller $cDot[$retentions[$a].Cluster] -VserverContext $retentions[$a].VServer -Volume $retentions[$a].Volume -ErrorAction Stop
    }
    catch
    {
        Write-Host "not found"
    }
    if($null -ne $b)
    {
        Write-Host -NoNewline ("`tCurrent retention {0}" -f @($b.MaximumRetentionPeriod))
        if($b.MaximumRetentionPeriod -ne $retentions[$a].Retention)
        {
            Write-Host ("`tChanging retention to {0}" -f @($retentions[$a].Retention))
            $c = $null
        <#
            try
            {
                $c = Set-NcSnaplockVolAttr -Controller $cDot[$retentions[$a].Cluster] -VserverContext $retentions[$a].VServer -Volume $retentions[$a].Volume -MaximumRetentionPeriod $retentions[$a].Retention -ErrorAction Stop
                if($c.MaximumRetentionPeriod -eq $retentions[$a].Retention)
                {
                    Write-Host ("`tRetention successfully changed")
                }
                else
                {
                    throw
                }
            }
            catch
            {
                Write-Host ("`tERROR: Failed to update retention.")
            }
        #>
        }
        else
        {
            Write-Host ("`tNo change")
        }
    }
    Write-Host

    $a++
}