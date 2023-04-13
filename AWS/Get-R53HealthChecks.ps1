$r53healthChecks = (aws route53 list-health-checks | ConvertFrom-Json).HealthChecks

$a = 0
$r53HCs = @()
while($a -lt $r53healthChecks.Length)
{
    Write-Host ("Processing Route53 Health Check ID: {0}" -f @($r53healthChecks[$a].Id))

    $d = "" | Select-Object Name, HealthCheck, Observations, Status
    $d.HealthCheck = $r53healthChecks[$a]
    $d.Name = (((aws route53 list-tags-for-resource --resource-type healthcheck --resource-id $r53healthChecks[$a].Id | ConvertFrom-Json).ResourceTagSet).Tags | Where-Object { $_.Key -eq "Name" }).Value

    Write-Host ("`tName: {0}" -f @($d.Name))

    if($d.HealthCheck.HealthCheckConfig.Type -ne "CALCULATED")
    {
        $d.Observations = (aws route53 get-health-check-status --health-check-id $r53healthChecks[$a].Id | ConvertFrom-Json).HealthCheckObservations
        $d.Status = "Unhealthy"

        if(($d.Observations | Select-Object -ExpandProperty StatusReport | Where-Object { $_.Status -match "Success" }).Length -ge $d.HealthCheck.HealthCheckConfig.FailureThreshold)
        {
            $d.Status = "Healthy"
        }
        Write-Host ("`tStatus: {0}" -f @($d.Status))
    }
    else
    {
        Write-Host ("`tStatus: CALCULATED")
    }

    $r53HCs += $d
    $a++
}

$a = 0
while($a -lt $r53HCs.Length)
{
    if($r53HCs[$a].HealthCheck.HealthCheckConfig.Type -eq "CALCULATED")
    {
        $childHCs = @($r53HCs | Where-Object { $_.HealthCheck.Id -in $r53HCs[$a].HealthCheck.HealthCheckConfig.ChildHealthChecks })
        if(@($childHCs | Where-Object { $_.Status -eq "Healthy" }).Length -ge $r53HCs[$a].HealthCheck.HealthCheckConfig.HealthThreshold)
        {
            $r53HCs[$a].Status = "Healthy"
        }
        Write-Host ("{0}: {1}" -f @($r53HCs[$a].Name, $r53HCs[$a].Status))
    }

    $a++
}
