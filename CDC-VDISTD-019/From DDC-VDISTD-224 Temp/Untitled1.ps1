$publicFolderListFile =  "C:\Temp\t2\Lists\20250314Check\ReCheck2\PFList_00-09a.csv"
$PWServerFQDN = "cdc-pwdint02.powereng.com"
$PWDatasourceName = "pw_prod_dmsclosed"
$PWUserName = "_powershell"
$PWEncryptedUserPassword = "01000000d08c9ddf0115d1118c7a00c04fc297eb01000000720c378a81cff44d8665b44e55241dc100000000020000000000106600000001000020000000102a0812b67fe7cd98e91ba631ce79049815dec6558824e888930cd48445c5fa000000000e80000000020000200000005c24e3e461f8e5bf5cb017ecd1668b5dff3203ba43829b4e46cfb808a36eb4ea20000000677d0e2e9b5054b05cfe07b1ae52aac1d275f5efb5af107260581a66be026cf440000000b08893f9c2e3eb82500fb66bb3ae6579be81c68344e89a7e5171daab995fb9aac15d6dc47612199465151ce215dc6ec1d1d54708f6708b9f1e82fcec4558a721"
$ProjectWiseBaseFolderName = "Outlook Public Folders"
$LogFolder = "C:\Temp\T2"
$BaseWorkingFolder = "C:\Temp\T2"
[switch] $CheckPF2PW = $true

InitializeExporter
SetEntryIDPrefix

$eID = "000000009598E9A20E04F041B38518182890A2D50100A3DF33FCC9BD1644BD14FCA330AA9785000028C688A10000"
$entryID = FixEntryID -entryIDtoFix $eID
$pf = GetPublicFolderByEntryID -entryID $entryID

$Script:OutlookApp = [System.Activator]::CreateInstance([Type]::GetTypeFromProgID("Outlook.Application"))
$Script:OutlookNamespace = $Script:OutlookApp.GetNameSpace("MAPI")


$iid = Get-Clipboard
$item = GetItemFromOutlookByEntryID -entryID $iid
if($null -ne $item) { $item.Display() }

$k = Get-Clipboard


$Script:PublicFolderItems = [System.Collections.Generic.List[System.Object]]::new() 
@(Get-Content -Path "\\boifs1\ITxchange\KLBTest\PFExportResults\000000001A447390AA6611CD9BC800AA002FC45A0300A3DF33FCC9BD1644BD14FCA330AA9785000028C688A10000-20250331-170505-PFObjects.json " | ConvertFrom-Json)[0].ForEach({ $Script:PublicFolderItems.Add($_) })

$inputData = @(
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF6000374ED23D90000"; Subject="HAE Project Control - Period ending  40420 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_00904.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF6000366D176840000"; Subject="HAE Project Control - Period ending  22920 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_01057.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF600034ED7DF280000"; Subject="HAE Project Control - Period ending  20120 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_01290.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF600033A4DE5380000"; Subject="HAE Project Control - Period ending  10420 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_01456.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF600031673A5630000"; Subject="HAE Project Control - Period ending  110219 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_01740.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF6000303795C3D0000"; Subject="HAE Project Control - Period ending  100519 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_01897.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF60002F1D48FB30000"; Subject="HAE Project Control - Period ending  90719 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_02024.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF60002D7DAEB7D0000"; Subject="HAE Project Control - Period ending  80319 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_02265.msg" },
    @{EID="000000001A447390AA6611CD9BC800AA002FC45A0900A3DF33FCC9BD1644BD14FCA330AA9785000028C688A1000007EF8BE066970C4098BFA083992B1CF60002C793EB020000"; Subject="HAE Project Control - Period ending  70619 Update"; TFN="C:\TEMP\t2\PFWork-20250331165518\File_02465.msg" }
)

$i = 0

$Script:ReturnObject.Good2Go = $true
# $item = GetItemFromOutlookByEntryID -entryID $inputData[$i].EID
$item = GetItemFromOutlookByEntryID -entryID "000000001A447390AA6611CD9BC800AA002FC45A090012225CC57BF01F4EA8CCA87A792FF35F000670FBD04B000012225CC57BF01F4EA8CCA87A792FF35F000670FC67910000"

if($null -ne $item) { $item.Display() }


# Step 1 - Replace temp file name...
$pfObj = $Script:PublicFolderItems | Where-Object { $_.TempFileName -eq $inputData[$i].TFN }

$pieces = $pfObj.FileName.Split([System.IO.Path]::DirectorySeparatorChar)
$fileName = $pieces[$pieces.Length-1].Replace("¦","│")
$inputData[$i].Subject
$fileName # | Set-Clipboard
$fileName | Set-Clipboard


$files = @(GCI -Path "C:\Temp\Divisions\PD\Project Management Boise\141318_Harry Allen Eldorado" -File)
$pfObj.FileName


# Step 2 - Replace "match"...
$file = $files | Where-Object { $_.BaseName -match $inputData[$i].Subject }

# Step 3 - Verify
#$pieces = $pfObj.FileName.Split([System.IO.Path]::DirectorySeparatorChar)

#$fileName = "{0}\{1}" -f @($file.DirectoryName, $pieces[$pieces.Length-1].Replace("¦","│"))
#$pfObj.FileName
$fileName
$file.Name


# Step 4 - Take action
#$file.MoveTo($fileName)


# $file = $files | Where-Object { $_.Name -eq $fileName }

$file.CreationTime = $pfObj.CreationTime
$file.LastWriteTime = $pfObj.LastModificationTime


$i++