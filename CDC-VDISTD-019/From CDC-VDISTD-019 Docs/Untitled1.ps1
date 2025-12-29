$publicFolderListFile =  "\\ddc-vdistd-224\temp$\t2\Lists\20250331\PFList_04.csv"
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb0100000078d925fc3ed0ce40a9a7699b00acc6ad0000000002000000000010660000000100002000000056e0e6f1a4b6cda767ad1e3d4dc6a07779df5593207d9e782a981dcbfe242e85000000000e8000000002000020000000f79655a6d7f7343dd6f522e27cbc198024162fdfb1cb1d4e125f04d9a535d6df20000000d7a7ed174fc6193a0a4e0f0403bf61e96a91f5b11b29c67510eb3dc8b0fc8742400000009f4a47b887d5cc82d74786f95cf9aaaacf28f11bb6f60e382533d192f8c3c7e6d46e4d7ef0576d5f32407701b01af35a92e8556d9d2adabce0f740f3219691c5"
$ProjectWiseBaseFolderName = "Outlook Public Folders"
$LogFolder = "C:\Temp\T2"
$BaseWorkingFolder = "C:\Temp\T2"
[switch] $CheckPF2PW = $true


$p = "cleartext_password"
$ss = ConvertTo-SecureString -String $p -AsPlainText -Force | ConvertFrom-SecureString

# $ss = encrypted password



InitializeExporter
SetEntryIDPrefix


$Script:OutlookApp = [System.Activator]::CreateInstance([Type]::GetTypeFromProgID("Outlook.Application"))
$Script:OutlookNamespace = $Script:OutlookApp.GetNameSpace("MAPI")



$pfObjs = Get-Content -Path "\\boifs1\itxchange\KLBTest\PFExportResults\000000001A447390AA6611CD9BC800AA002FC45A030012225CC57BF01F4EA8CCA87A792FF35F00000A50CAFE0000-20250331-174012-PFObjects.json" | ConvertFrom-Json
$sw = [System.Diagnostics.Stopwatch]::new()


$start = 0 # [int] ($pfObjs.Length / 2)
$end = 10867 # $pfObjs.Length

$a = $start
$itemCount = $end - $start
$activity = "Downloading items {0} to {1} ({2})..." -f @($start, $end, $itemCount)
$sw.Start()

$a = 0
while($a -lt $itemCount)
{
    $elapsedTicks = $sw.ElapsedTicks
    $ticksPerItem = $elapsedTicks / ($a + 1)
    $totalETATicks = $ticksPerItem * $itemCount
    $remainingETATicks = $totalETATicks - $elapsedTicks
    $etaTS = [TimeSpan]::new($remainingETATicks)
    $etaDT = [DateTime]::Now.Add($etaTS)

    $percentComplete = ($a + 1) / $itemCount
    $status = "{0} of {1} | {2,7:P2} Complete | Elapsed: {3} | Est Remaining: {4} | ETC: {5}" -f @(($a + 1), $itemCount, $percentComplete, $sw.Elapsed.ToString(), $etaTS.ToString(), $etaDT.ToString("HH:mm:ss.fffff"))
    Write-Progress -Id 1 -Activity $activity -Status $status -PercentComplete ($percentComplete * 100.0)

    $idx = $a + $start
    $pfObjs[$idx].TempFileName = $pfObjs[$idx].TempFileName.Replace("20250331170749","20250401170946")
    if(-not [System.IO.File]::Exists($pfObjs[$idx].TempFileName))
    {
        $item = GetItemFromOutlookByEntryID -entryID $pfObjs[$idx].EntryID
        if($null -ne $item)
        {
            try
            {
                $item.SaveAs($pfObjs[$idx].TempFileName, $pfObjs[$idx].SaveType)
                $pfObjs[$idx].Saved2Temp = $true
            }
            catch
            {
            }
        }
    }
    $a++
}