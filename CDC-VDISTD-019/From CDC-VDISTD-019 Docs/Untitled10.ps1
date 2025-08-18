

$publicFolder = GetPublicFolderByEntryID -entryID $entryID
$Script:ExportedPublicFolderPath = FixFileOrPath -fileOrPath $publicFolder.FolderPath.Replace($Script:topPublicFolder.FolderPath, "").Trim([System.IO.Path]::DirectorySeparatorChar)
$publicFolder = $OutlookNamespace.GetFolderFromID("000000001A447390AA6611CD9BC800AA002FC45A030012225CC57BF01F4EA8CCA87A792FF35F00000A50CAFE0000")
