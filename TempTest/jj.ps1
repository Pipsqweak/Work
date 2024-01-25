$jj = "" | Select-Object @{N='Share';E={$shareName}}, @{N='Directories'; E={$Global:totalDirectories}}, @{N='Files';E={$Global:totalFiles}}, @{N='TotalSize';E={$Global:totalSize}},
    @{N='yr1size';E={$Global:sizeByAge[$Global:fileAgeKeys[9]]}},
    @{N='yr2size';E={$Global:sizeByAge[$Global:fileAgeKeys[8]]}},
    @{N='yr3size';E={$Global:sizeByAge[$Global:fileAgeKeys[7]]}},
    @{N='yr4size';E={$Global:sizeByAge[$Global:fileAgeKeys[6]]}},
    @{N='yr5size';E={$Global:sizeByAge[$Global:fileAgeKeys[5]]}},
    @{N='yr6size';E={$Global:sizeByAge[$Global:fileAgeKeys[4]]}},
    @{N='yr7size';E={$Global:sizeByAge[$Global:fileAgeKeys[3]]}},
    @{N='yr8size';E={$Global:sizeByAge[$Global:fileAgeKeys[2]]}},
    @{N='yr9size';E={$Global:sizeByAge[$Global:fileAgeKeys[1]]}},
    @{N='yr10size';E={$Global:sizeByAge[$Global:fileAgeKeys[0]]}}
$jj | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
