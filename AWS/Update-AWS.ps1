
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
