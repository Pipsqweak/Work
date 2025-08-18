# 1. Source the following:
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721"
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


# _powershell PW: tX2NPfAK92DhM2


# For Export-PublicFoldersSTA.ps1
. .\Export-PublicFoldersSTA.ps1 -publicFolderListFile "C:\Temp\t2\Lists\20250225\PFList_01a.CSV" -PWServerFQDN "cdc-pwdint02.powereng.com" -PWDatasourceName "pw_prod_dmsclosed" -PWUserName "_powershell" -PWEncryptedUserPassword "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721" -ProjectWiseBaseFolderName "Outlook Public Folders" -LogFolder "C:\TEMP\t2" -BaseWorkingFolder "C:\TEMP\t2" 

. .\Export-PublicFoldersSTA.ps1 -publicFolderListFile "C:\Temp\t2\Lists\redo.CSV" -PWServerFQDN "cdc-pwdint02.powereng.com" -PWDatasourceName "pw_prod_dmsclosed" -PWUserName "_powershell" -PWEncryptedUserPassword "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721" -ProjectWiseBaseFolderName "Outlook Public Folders" -LogFolder "C:\TEMP\t2" -BaseWorkingFolder "C:\TEMP\t2" 

. .\EPF2.ps1 -publicFolderListFile "C:\Temp\t2\Lists\20250225\PFList_04.csv" -PWServerFQDN "cdc-pwdint02.powereng.com" -PWDatasourceName "pw_prod_dmsclosed" -PWUserName "_powershell" -PWEncryptedUserPassword "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721" -ProjectWiseBaseFolderName "Outlook Public Folders" -LogFolder "C:\TEMP\t2" -BaseWorkingFolder "C:\TEMP\t2" 

# Check PF to PW List
. .\EPF2.ps1 -publicFolderListFile "\\ddc-vdistd-224\Temp$\t2\Lists\20250314\PFList_09.CSV" -PWServerFQDN "cdc-pwdint02.powereng.com" -PWDatasourceName "pw_prod_dmsclosed" -PWUserName "_powershell" -PWEncryptedUserPassword "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721" -ProjectWiseBaseFolderName "Outlook Public Folders" -LogFolder "C:\TEMP\t2" -BaseWorkingFolder "C:\TEMP\t2" -CheckPF2PW


. .\EPF2.ps1 -publicFolderListFile "C:\Temp\t2\Lists\20250314Check\ReCheck2\PFList_00-09a.csv" -PWServerFQDN "cdc-pwdint02.powereng.com" -PWDatasourceName "pw_prod_dmsclosed" -PWUserName "_powershell" -PWEncryptedUserPassword "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721" -ProjectWiseBaseFolderName "Outlook Public Folders" -LogFolder "C:\TEMP\t2" -BaseWorkingFolder "C:\TEMP\t2" -CheckPF2PW


$publicFolderListFile = "C:\Temp\t2\Lists\test4.csv"
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721"
$ProjectWiseBaseFolderName = "Outlook Public Folders"
$LogFolder = "C:\TEMP\t2"
$BaseWorkingFolder = "C:\TEMP\t2"


# Source in most of Export-PublicFolderSTA.ps1


$pfList = @(Import-CSV -Path $Script:publicFolderListFile -Delimiter "`t" -ErrorAction Stop)
InitializeExporter
$pfListIdx = 0
$publicFolderIdentity = $pfList[$pfListIdx]
PublicFolderHasBeenExported -entryID $publicFolderIdentity.EntryID
$Script:PFEntryID = $publicFolderIdentity.EntryId
ResetScriptObjects -PFEntryID $publicFolderIdentity.EntryId
SetWorkingFolder
$Script:ReturnObject.PublicFolder.EntryID = FixEntryID -entryIDtoFix $Script:PFEntryID
$Script:ReturnObject.ExportedItems.Count = 0
$publicFolder = $Script:OutlookNamespace.GetFolderFromID($Script:ReturnObject.PublicFolder.EntryID)
$publicFolder.FolderPath -notmatch "DUMPSTER_ROOT"
$Script:ReturnObject.PublicFolder.Type = ($publicFolder.DefaultItemType -as [Microsoft.Office.Interop.Outlook.OlItemType]).ToString()
$Script:ExportedPublicFolderPath = $publicFolder.FolderPath.Replace($Script:topPublicFolder.FolderPath, "").Trim([System.IO.Path]::DirectorySeparatorChar)
$Script:ReturnObject.PublicFolder.Name = $Script:ExportedPublicFolderPath.Replace("\Outlook Public Folders\", "")
$Script:ReturnObject.PublicFolder.ItemCount = $publicFolder.Items.Count
SavePublicFolderItemsToLocalFolder -publicFolder $publicFolder
SetPublicFolderObjectFileNames
RenameLocalFiles
$exportedFiles = @(Get-ChildItem -Path $Script:WorkingFolder -File -ErrorAction Stop)
$pwFolderPath = FixPath -path $Script:ExportedPublicFolderPath
VerifyCreatePWPath -path $pwFolderPath

$importFolder = $Script:WorkingFolder
$result = ReTryCatch -callee "Import-PWDocuments" -funcParameters @{InputFolder = $importFolder; ProjectWiseFolder = $Script:ReturnObject.ProjectWise.ImportFolder; MultiThreaded = $true; ExcludeSourceDirectoryFromTargetPath = $true; Overwrite = $true}

$filesInImportFolder = @(Get-ChildItem -Path $importFolder -ErrorAction Stop)
$pfObjs = @($Script:PublicFolderItems.Values)
$importedFiles = $result.ReturnValue
# Track how many files where imported into ProjectWise and how large they are.
$importedFiles.ForEach({
    $i = $_
    $importedFile = $filesInImportFolder | Where-Object { $_.Name -eq $i.FileName }
    if($null -ne $importedFile)
    {
        try
        {
            $importedFile.Delete()
        }
        catch
        {
            # For now, just trap the exception.
        }

        $pfObj = $pfObjs | Where-Object { $_.FileName.EndsWith($i.FileName) }
        if($null -ne $pfObj)
        {
            $pfObj.Imported = $true   # Set this just in case the removal below fails.
            try
            {
                $null = $Script:PublicFolderItems.Remove($pfObj.RowEntryID)
            }
            catch
            {
                # Nothing, just trapping the exception.
            }
        } `
        else
        {
            LogWarning ("2:Extra file imported??? {0}" -f @($_.FileName))
        }
    } `
    else
    {
        LogWarning ("Extra file imported??? {0}" -f @($_.FileName))
    }

    $Script:ReturnObject.ImportedItems.Count++
    $Script:ReturnObject.ImportedItems.Size += $i.FileSize
})


$Script:PublicFolderItems.Values | ConvertTo-Json | Set-Clipboard



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
