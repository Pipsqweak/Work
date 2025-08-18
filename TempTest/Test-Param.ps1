[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $MyName,

    [Parameter()]
    [Switch]
    $Simulated
)

function t1()
{
    Write-Host ("T1: {0}" -f @($MyName))

    if($Simulated)
    {
        Write-Host "T1: Simulated"
    }
}

Write-Host ("Global: {0}" -f @($MyName))
t1

if($Simulated)
{
    Write-Host "Simulated"
}


$d = "" | Select-Object VM,Datacenters

$d.Datacenters = "" | Select-Object

<#

    Sound Alarm every X minutes if AD account locks reach Y $alarmThreshold

    $alarmThreshold = 5
    $alarmFrequencyMinutes = 15
    if((Search-ADAccount -LockedOut).Count -ge $alarmThreshold)
    {
        if(($null -eq $lastAlarm) -or (([DateTime]::Now - $lastAlarm).TotalMinutes -gt $alarmFrequencyMinutes))
        {
            Sound-Alarm
            $lastAlarm = [DateTime]::Now
        }
    }
    elseif(($null -ne $lastAlarm) -and ([DateTime]::Now - $lastAlarm).TotalMinutes -gt $alarmFrequencyMinutes)
    {
        $lastAlarm = $null
    }
#>
