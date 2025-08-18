# 1. Source the following:
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb0100000078d925fc3ed0ce40a9a7699b00acc6ad0000000002000000000010660000000100002000000056e0e6f1a4b6cda767ad1e3d4dc6a07779df5593207d9e782a981dcbfe242e85000000000e8000000002000020000000f79655a6d7f7343dd6f522e27cbc198024162fdfb1cb1d4e125f04d9a535d6df20000000d7a7ed174fc6193a0a4e0f0403bf61e96a91f5b11b29c67510eb3dc8b0fc8742400000009f4a47b887d5cc82d74786f95cf9aaaacf28f11bb6f60e382533d192f8c3c7e6d46e4d7ef0576d5f32407701b01af35a92e8556d9d2adabce0f740f3219691c5"
# $PEntryID = "000000009598E9A20E04F041B38518182890A2D501006C95E27D1ACA634AA1AADC20796388DD00000049C5460000"     # Divisions\Operations\Information Technology\Help Desk\Meeting Notes
# $PEntryID = "000000009598E9A20E04F041B38518182890A2D501001296C725372D7F4B86B758A22EA3141B000000004A950000"     # IT Calendar
# $PFEntryID = "000000001A447390AA6611CD9BC800AA002FC45A03001953B16A689BCD4AA8FC82955DB27CB100000014FC8D0000"    # Divisions\Operations\Information Technology\RestoreTest"
# $PFEntryID = "000000009598E9A20E04F041B38518182890A2D501001296C725372D7F4B86B758A22EA3141B000000004A960000"   # Divisions\Operations\Information Technology\IT Contacts
# $PFEntryID = "000000009598E9A20E04F041B38518182890A2D50100572FF007A7D6B64CA96E5CFE8E1CC1A40000000D5E0C0000"     # Divisions\ENV\Environmental Anaheim\115244 BARREN RIDGE TECHNICAL REPORTS
$PFEntryID = "000000009598E9A20E04F041B38518182890A2D501001296C725372D7F4B86B758A22EA3141B000000004A980000"      # Divisions\Operations\Information Technology\Networking\Documents
$ProjectWiseBaseFolderName = "Outlook Public Folders"
$LogFolder = "C:\TEMP\t2"
$WorkingFolder = "C:\TEMP\t2"
#$LocalOnly = [Switch]::new($true)

# 2. Source in Export-PublicFolder


# 3 - Initialize
InitializeExporter



# For Export-PublicFolderSTA.ps1
$publicFolderListFile = "C:\Temp\t2\Lists\test2.csv"
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb0100000078d925fc3ed0ce40a9a7699b00acc6ad0000000002000000000010660000000100002000000056e0e6f1a4b6cda767ad1e3d4dc6a07779df5593207d9e782a981dcbfe242e85000000000e8000000002000020000000f79655a6d7f7343dd6f522e27cbc198024162fdfb1cb1d4e125f04d9a535d6df20000000d7a7ed174fc6193a0a4e0f0403bf61e96a91f5b11b29c67510eb3dc8b0fc8742400000009f4a47b887d5cc82d74786f95cf9aaaacf28f11bb6f60e382533d192f8c3c7e6d46e4d7ef0576d5f32407701b01af35a92e8556d9d2adabce0f740f3219691c5"
$ProjectWiseBaseFolderName = "Outlook Public Folders"
$LogFolder = "C:\TEMP\t2"
$BaseWorkingFolder = "C:\TEMP\t2"





# MakeMessagePath
# $isPartOfConversation,
# $conversationIdx
# $conversationCount
$itemIdx = $b
$itemCount = $coll.Length
$subject = $coll[$b].Subject

$folderDefaultTypes = [System.Collections.Generic.List[System.String]]::new()

function TryAdd($pfFolderType)
{
    $fType = ($pfFolderType -as [Microsoft.Office.Interop.Outlook.OlItemType]).ToString()
    $idx = $folderDefaultTypes.BinarySearch($fType)
    if($idx -lt 0)
    {
        $folderDefaultTypes.Insert(-bnot $idx, $fType)
        Write-Host $fType
    }
}

function GetPFDefaultItemType($pfFolder)
{
    Write-Host ("{0}: {1}" -f @($pfFolder.FolderPath, ($pfFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType]).ToString()))
    TryAdd $pfFolder.DefaultItemType
    
    $folderFolders = $pfFolder.Folders
    $folder = $folderFolders.GetFirst()
    while($null -ne $folder)
    {
        GetPFDefaultItemType $folder
        $folder = $folderFolders.GetNext()
    }
}  

switch($publicFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType])
{
    { [Microsoft.Office.Interop.Outlook.OlItemType]::olAppointmentItem } {
        Write-Host "Works"
    }

    default { Write-Host ("{0} is {1}" -f @($_, $_.GetType().FullName)) }
}
