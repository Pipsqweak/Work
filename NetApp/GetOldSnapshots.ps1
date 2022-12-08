
$oldSnapshots = @()
$oldSnapshotDate = [DateTime]::Now.AddDays(-180)
foreach($clusterName in $cdot.Keys)
{
    $cluster = $cdot[$clusterName]
    $vServers = @(Get-NcVserver -Controller $cluster -ErrorAction Stop | Sort-Object )
    foreach($vServer in $vServers)
    {
        Write-Host ("Processing {0}:{1}..." -f @($clusterName, $vServer.VServerName))
        try
        {
            $vServerSnapshots = @(Get-NcSnapshot -Controller $cluster -Vserver $vServer.VServerName -ErrorAction Stop)
            Write-Host ("`t{0} total vServer snapshots" -f @($vServerSnapshots.Length))
            $oldvServerSnapshots = @($vServerSnapshots | Where-Object { $_.Created -lt $oldSnapshotDate })
            Write-Host ("`t{0} old vServer snapshots" -f @($oldvServerSnapshots.Length))
            $oldvServerSnapshots | Foreach-Object {
                Write-Host ("`t`t{0}, {1}, {2}, {3}, {4:0}" -f @($_.NcController.Name, $_.VServer, $_.Volume, $_.Created.ToString("yyyy-MM-dd hh:mm:ss"), ([DateTime]::Now - $_.Created).TotalDays))
                $oldSnapshots += $_
            }
        }
        catch
        {

        }
    }
    Write-Host
}

$oldSnapshots | Select-Object @{N="Created";E={$_.Created.ToString("yyyy-MM-dd hh:mm")}},@{N="Cluster";E={$_.NcController.Name}}, VServer, Volume, Name, CumulativeTotal, @{N="Age (in days)";E={[int](([DateTime]::Now - $_.Created).TotalDays)}}, @{N="DeleteCMD"; E={"snapshot delete -vserver {0} -snapshot {1} -force true -ignore-owners true" -f @($_.VServer, $_.Name)}} | Sort-Object Created | ConvertTo-Csv -NoTypeInformation -Delimiter "`t" | Set-Clipboard

# $oldSnapshots | Select-Object @{N="Created";E={$_.Created.ToString("yyyy-MM-dd hh:mm")}},@{N="Cluster";E={$_.NcController.Name}}, VServer, Volume, Name, CumulativeTotal, @{N="Age (in days)";E={[int](([DateTime]::Now - $_.Created).TotalDays)}}, @{N="DeleteCMD"; E={"snapshot delete -vserver {0} -snapshot {1} -force true -ignore-owners true" -f @($_.VServer, $_.Name)}} | Sort-Object Created | ConvertTo-Html | Set-Clipboard
