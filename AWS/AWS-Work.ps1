$awsCLI = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

$hostedZones = (& $awsCLI route53 list-hosted-zones) | ConvertFrom-Json
$allARecords = [System.Collections.Generic.List[System.Object]]::new()
$allPTRRecords = [System.Collections.Generic.List[System.Object]]::new()
$allCNAMERecords = [System.Collections.Generic.List[System.Object]]::new()

<# vv Search for IP address vv #>
$a = 0
while($a -lt $hostedZones.HostedZones.Count)
{
    $zoneID = $hostedZones.HostedZones[$a].Id
    $awsRRs = (& $awsCLI route53 list-resource-record-sets --hosted-zone-id $zoneID) | ConvertFrom-Json
    $aRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "A" })
    $ptrRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "PTR" })
    $cnameRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "CNAME" })

    $aRecords.ForEach({ $allARecords.Add($_) })
    $ptrRecords.ForEach({ $allPTRRecords.Add($_) })
    $cnameRecords.ForEach({ $allCNAMERecords.Add($_) })

    $a++
}
$ipStr = "151.122.137.53"
$ipStrOctets = $ipStr.Split('.')
[Array]::Reverse($ipStrOctets)
$ptrSearch = "{0}.in-addr.arpa." -f @(($ipStrOctets -join '.'))

$matchingARecords = [System.Collections.Generic.List[System.Object]]::new()
$matchingCNameRecords = [System.Collections.Generic.List[System.Object]]::new()
$matchingPTRRecords = [System.Collections.Generic.List[System.Object]]::new()
$matchingRecords = [System.Collections.Generic.List[System.Object]]::new()

$allARecords.Where({ $_.ResourceRecords.Where({ $_.Value -match $ipStr })}).ForEach({ $matchingARecords.Add($_)})
$matchingARecords.ToArray().ForEach({ $n = $_.Name; $allCNAMERecords.Where({ $_.ResourceRecords.Where({ $_.Value -eq $n }) }) }).Foreach({ $matchingCNameRecords.Add($_) })
$matchingARecords.ToArray().ForEach({ $n = $_.Name; $allPTRRecords.Where({ $_.ResourceRecords.Where({ $_.Value -eq $n })}) }).Foreach({ $matchingPTRRecords.Add($_) })
$allPTRRecords.Where({ ($_.Name -eq $ptrSearch) -and (@($matchingPTRRecords.Where({ $_.Name -eq $ptrSearch })).Length -eq 0) }).Foreach({ $matchingPTRRecords.Add($_) })

$matchingARecords.ToArray().ForEach({ $matchingRecords.Add($_) })
$matchingCNameRecords.ToArray().ForEach({ $matchingRecords.Add($_) })
$matchingPTRRecords.ToArray().ForEach({ $matchingRecords.Add($_) })

$matchingRecords

<# ^^ Search for IP Address ^^ #>


$zoneID = ($hostedZones.HostedZones | Where-Object { $_.Name -eq "powereng.com." }).Id.Replace("/hostedzone/", "")

$awsRRs = (& $awsCLI route53 list-resource-record-sets --hosted-zone-id $zoneID) | ConvertFrom-Json
$aRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "A" })

$zoneID = ($hostedZones.HostedZones | Where-Object { $_.Name -eq "122.151.in-addr.arpa." }).Id.Replace("/hostedzone/", "")
$awsRRs = (& $awsCLI route53 list-resource-record-sets --hosted-zone-id $zoneID) | ConvertFrom-Json
$ptrRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "PTR" })



function FindPTRForHost($hStr)
{
    $a = @($ptrRecords | Where-Object { $_.ResourceRecords | Where-Object { $_ -match $hStr } })

    if(-not ($a -is [Array]))
    {
        return @( , $a)
    }
    else
    {
        return $a
    }
}

function FindAForHost($hStr)
{
    $a = @($aRecords | Where-Object { $_.ResourceRecords | Where-Object { $_ -match $hStr } })

    if(-not ($a -is [Array]))
    {
        return @( , $a)
    }
    else
    {
        return $a
    }
}

function GetPTRIP($ptrRec)
{
    $ptrIP = [String]::Empty

    if($ptrRec.Name -match "(\d+)\.(\d+)\.(\d+)\.(\d+)\..*")
    {
        $ptrIP = "{0}.{1}.{2}.{3}" -f $Matches[4..1]
    }

    return $ptrIP
}




$breakLoop = $false
$a = 0
while((-not $breakLoop) -and ($a -lt $aRecords.Length))
{
    $aRec = $aRecords[$a]

    $b = 0
    while($b -lt $aRec.ResourceRecords.Count)
    {
        if($aRec.ResourceRecords[$b].Value -match "^(151)\.(122)\.(\d+)\.(\d+)")
        {
            Write-Host ("{0}: {1} || {2}: {3}" -f $($a, $aRec.Name, $b, $aRec.ResourceRecords[$b].Value))

            $ptrName = "^{0}.in-addr.arpa.`$" -f @($Matches[4..1] -join ".")
            $ptrRecs = @($ptrRecords | Where-Object { $_.Name -match $ptrName })

            if($ptrRecs.Length -gt 0)
            {
                $c = 0
                while($c -lt $ptrRecs.Length)
                {
                    $d = 0
                    while($d -lt $ptrRecs[$c].ResourceRecords.Count)
                    {
                        if($ptrRecs[$c].ResourceRecords[$d].Value -eq $aRec.Name)
                        {
                            Write-Host ("`t{0} : {1}" -f @($ptrRecs[$c].Name, $ptrRecs[$c].ResourceRecords[$d].Value))
                        }
                        else
                        {
                            Write-Host -ForegroundColor Green ("`t{0} : {1}" -f @($ptrRecs[$c].Name, $ptrRecs[$c].ResourceRecords[$d].Value))
                        }
                        $d++
                    }
                    $c++
                }
            }
            elseif($ptrRecs.Length -eq 0)
            {
                Write-Host -ForegroundColor Red ("`tNo PTR record found ({0})" -f @($ptrName))
            }
        }
        $b++
    }
    $a++
}






$createRecord = $false
$breakLoop = $false
$a = 0
while((-not $breakLoop) -and ($a -lt $aRecords.Length))
{
    $aRec = $aRecords[$a]
    $ptrRecs = FindPTRForHost $aRec.Name

    if($ptrRecs.Length -eq 1)
    {
        #$ptrIP = GetPTRIP $ptrRecs[0]
        #Write-Host ("{0}: {1}: {2}" -f @($a, $aRec.Name, $ptrIP))
    }
    elseif($ptrRecs.Length -eq 0)
    {
        #Write-Host ("{0}: {1}" -f @($a, $aRec.Name))
        $b = 0
        while((-not $breakLoop) -and ($b -lt $aRec.ResourceRecords.Count))
        {
            if($aRec.ResourceRecords[$b].Value -match "^(\d+)\.(\d+)\.(\d+)\.(\d+)")
            {
                if(($Matches[1] -eq "151") -and ($Matches[2] -eq "122"))
                {
                    $ptrName = $Matches[4..1] -join "."
                    if(@($ptrRecords | Where-Object { $_.Name -match $ptrName }).Length -eq 0)
                    {
                        Write-Host ("New Record: {0} : {1}" -f @($aRec.Name, $aRec.ResourceRecords[$b].Value))
                        $arr = $aRec.ResourceRecords[$b].Value -split "\."
                        [Array]::Reverse($arr)
                        $ptrName = $arr[0..1] -join "."

                        if($createRecord)
                        {
                            [Microsoft.VisualBasic.Interaction]::AppActivate("Route 53 Management Console")
                            Start-Sleep -Milliseconds 250
                            $wsh.SendKeys($ptrName)
                            $wsh.SendKeys("{TAB}")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys("P")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys("{TAB}")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys("{TAB}")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys("1200")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys("{TAB}")
                            Start-Sleep -Milliseconds 50
                            $wsh.SendKeys($aRec.Name)

                            $keyPress = WaitForKeyPress
                            $breakLoop = ($keyPress.Key -eq [System.ConsoleKey]::X)
                        }
                    }
                }
            }
            $b++
        }
    }

    $a++
}

function WaitForKeyPress
{
    while([Console]::KeyAvailable -eq $false)
    {
        Start-Sleep -Milliseconds 250
    }
    $o = [Console]::ReadKey($true)

    return $o
}


if($ptrRecords[0].Name -match "(\d+)\.(\d+)\.(\d+)\.(\d+)\..*")
{
    $ptrIP = "{0}.{1}.{2}.{3}" -f $Matches[4..1]
}

$aRecords | Select-Object -ExpandProperty ResourceRecords | Select-Object -ExpandProperty Value

aws route53 list-resource-record-sets --hosted-zone-id

[void] [System.Reflection.Assembly]::LoadWithPartialName("'Microsoft.VisualBasic")
[Microsoft.VisualBasic.Interaction]::AppActivate("Route 53 Management Console")

$wsh = New-Object -ComObject WScript.Shell


Start-Sleep -Seconds 5

[Microsoft.VisualBasic.Interaction]::AppActivate("Route 53 Management Console")
Start-Sleep -Milliseconds 250
$wsh.SendKeys($ptrName)
$wsh.SendKeys("{TAB}")
Start-Sleep -Milliseconds 50
$wsh.SendKeys("P")
Start-Sleep -Milliseconds 50
$wsh.SendKeys("{TAB}")
Start-Sleep -Milliseconds 50
$wsh.SendKeys("{TAB}")
Start-Sleep -Milliseconds 50
$wsh.SendKeys("1200")
Start-Sleep -Milliseconds 50
$wsh.SendKeys("$aRec.Name")


$keepGoing = $true
$alive = @()
for($o3 = 0; ($keepGoing) -and ($o3 -lt 256); $o3++)
{
    for($o4 = 1; ($keepGoing) -and ($o4 -lt 255); $o4++)
    {
        $compName = "151.122.{0}.{1}" -f @($o3, $o4)
        $r = Test-Connection -ComputerName $compName -Quiet -Count 1
        if($r)
        {
            $alive += $compName
            Write-Host -NoNewline ("{0}, " -f @($compName))
        }
        # $keepGoing = $false
    }
}


function NewResourceRecordSet($hostName, $recType, $recTTL, $recValue)
{
    $change = "" | Select-Object Action, ResourceRecordSet
    $change.Action = "CREATE"
    $change.ResourceRecordSet = "" | Select-Object Name, Type, TTL, ResourceRecords

    $change.ResourceRecordSet.Name = $hostName
    $change.ResourceRecordSet.Type = $recType
    $change.ResourceRecordSet.TTL = $recTTL
    $change.ResourceRecordSet.ResourceRecords = @()

    $resourceRecord = "" | Select-Object Value
    $resourceRecord.Value = $recValue
    $change.ResourceRecordSet.ResourceRecords += $resourceRecord

    return $change
}


$r = "" | Select-Object Changes

$r.Changes = @()

$change = "" | Select-Object Action, ResourceRecordSet
$change.Action = "CREATE"
$change.ResourceRecordSet = "" | Select-Object Name, Type, TTL, ResourceRecords

$change.ResourceRecordSet.Name = "hostname"
$change.ResourceRecordSet.Type = "A"
$change.ResourceRecordSet.TTL = 3600
$change.ResourceRecordSet.ResourceRecords = @()

$resourceRecord = "" | Select-Object Value
$resourceRecord.Value = "address"
$change.ResourceRecordSet.ResourceRecords += $resourceRecord
$r.Changes += $change


$awsCLI = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

$hostedZones = (& $awsCLI route53 list-hosted-zones) | ConvertFrom-Json

$aZoneID = ($hostedZones.HostedZones | Where-Object { $_.Name -eq "powereng.com." }).Id.Replace("/hostedzone/", "")

$awsRRs = (& $awsCLI route53 list-resource-record-sets --hosted-zone-id $aZoneID) | ConvertFrom-Json
$aRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "A" })

$ptrZoneID = ($hostedZones.HostedZones | Where-Object { $_.Name -eq "122.151.in-addr.arpa." }).Id.Replace("/hostedzone/", "")
$awsRRs = (& $awsCLI route53 list-resource-record-sets --hosted-zone-id $ptrZoneID) | ConvertFrom-Json
$ptrRecords = @($awsRRs.ResourceRecordSets | Where-Object { $_.Type -eq "PTR" })

$missing = Import-Csv -Path C:\Tmp\AWS\missing.csv

$a = 0
$aRecordChanges = "" | Select-Object Changes
$ptrRecordChanges = "" | Select-Object Changes

$aRecordChanges.Changes = @()
$ptrRecordChanges.Changes = @()

while($a -lt $missing.Length)
{
    $aRecs = @($aRecords | Where-Object { $_.Name -match $missing[$a].HostName })
    if($aRecs.Length -eq 0)
    {
        # Add A Record
        $rr = NewResourceRecordSet $missing[$a].HostName "A" 3600 $missing[$a].Address
        $aRecordChanges.Changes += $rr
    }

    $octets = $missing[$a].Address -split "\."
    [Array]::Reverse($octets)
    $ptrName = "{0}.in-addr.arpa" -f ($octets -join ".")


    $ptrRecs = @($ptrRecords | Where-Object { $_.Name -match $ptrName })
    if($ptrRecs.Length -eq 0)
    {
        # Add PTR Record
        $rr = NewResourceRecordSet $ptrName "PTR" 1200 $missing[$a].HostName
        $ptrRecordChanges.Changes += $rr
    }
    $a++
}

if($aRecordChanges.Changes.Length -gt 0)
{
    $aRecJSONFile = "c:\tmp\AWS\adda.json"
    $aRecordChanges | ConvertTo-Json -Depth 10 | Set-Content -Path $aRecJSONFile
    Write-Host ("aws route53 change-resource-record-sets --hosted-zone-id {0} --change-batch file://{1}" -f @($aZoneID, $aRecJSONFile))
}

if($ptrRecordChanges.Changes.Length -gt 0)
{
    $ptrRecJSONFile = "C:\Tmp\AWS\addptr.json"
    $ptrRecordChanges | ConvertTo-Json -Depth 10 | Set-Content -Path $ptrRecJSONFile
    Write-Host ("aws route53 change-resource-record-sets --hosted-zone-id {0} --change-batch file://{1}" -f @($ptrZoneID, $ptrRecJSONFile))
}
