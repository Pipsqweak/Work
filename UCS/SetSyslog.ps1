$ucs = $yyc01UCS
$transactionCommitted = $false

try
{
    $Error.Clear()
    Start-UcsTransaction -Ucs $ucs -ErrorAction Stop

    try
    {
        $svcEP = Get-UcsSvcEp -Ucs $ucs -ErrorAction Stop
        try
        {
            $ucsSyslog = Get-UcsSyslog -SvcEp $svcEP -Ucs $ucs -ErrorAction Stop

            try
            {
                [void] (Add-UcsManagedObject -Ucs $ucs -Parent $ucsSyslog -ModifyPresent -ClassId "CommSyslogClient" -PropertyMap @{Hostname="syslog.powereng.com"; AdminState="enabled"; Name="primary"; ForwardingFacility="local0"; Severity="information"; } -ErrorAction Stop)
                try
                {
                    [void] (Add-UcsManagedObject -Ucs $ucs -Parent $ucsSyslog -ModifyPresent -ClassId "CommSyslogSource" -PropertyMap @{Audits="enabled"; Events="enabled"; } -ErrorAction Stop)

                    try
                    {
                        [void] (Complete-UcsTransaction -Ucs $ucs -ErrorAction Stop)
                        $transactionCommitted = $true
                    }
                    catch
                    {
                        Write-Host ("Failed to commit syslog settings to: {0}." -f @($ucs.Name))
                    }
                }
                catch
                {
                    Write-Host ("Failed to set syslogging for audits and events for: {0}." -f @($ucs.Name))
                }
            }
            catch
            {
                Write-Host ("Failed to set syslog settings for: {0}." -f @($ucs.Name))
            }
        }
        catch
        {
            Write-Host ("Failed to get syslog settings from: {0}." -f @($ucs.Name))
        }
    }
    catch
    {
        Write-Host ("Failed to get service endpoint from: {0}." -f @($ucs.Name))
    }
}
catch
{
    Write-Host ("Failed to start UCS transaction on {0}." -f @($ucs.Name))
}

if(-not $transactionCommitted)
{
    try
    {
        Undo-UcsTransaction -Ucs $ucs -ErrorAction Stop
    }
    catch
    {
        Write-Host ("Failed to rollback UCS transaction on {0}." -f @($ucs.Name))
    }
}



$ucsSyslog = Get-UcsSyslogClient -Ucs $cdcUCS02 -Name "primary"

$ucsSyslog = Get-UcsSyslog -Ucs $cdcUCS02


$ucsSysLogSrc = Get-UcsSyslogSource -Ucs $cdcUCS02 -Syslog $ucsSyslog[0]
