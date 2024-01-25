$cdcVolumes | Select-Object `
    @{N='Cluster'; E={ $_.NcController.Name }},
    VServer,
    Name,
    @{N='Size_Raw'; E={ $_.VolumeSpaceAttributes.SizeTotal }},
    @{N='Size'; E={ Format-StorageNumber $_.VolumeSpaceAttributes.SizeTotal }},
    @{N='Used_Raw'; E={ $_.VolumeSpaceAttributes.SizeUsed }},
    @{N='Used'; E={ Format-StorageNumber $_.VolumeSpaceAttributes.SizeUsed }},
    @{N='Available_Raw'; E={ $_.VolumeSpaceAttributes.SizeAvailable }},
    @{N='Available'; E={ Format-StorageNumber $_.VolumeSpaceAttributes.SizeAvailable }} | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard


    # Update firmware package to UCS...

    $imageNames = @(
        "ucs-6300-k9-bundle-infra.4.2.3g.A.bin",
        "ucs-6400-k9-bundle-infra.4.2.3g.A.bin",
        "ucs-mini-k9-bundle-infra.4.2.3g.A.bin",
        "ucs-k9-bundle-b-series.4.2.3g.B.bin",
        "ucs-k9-bundle-c-series.4.2.3g.C.bin"
    )

    $fileName = "E:\Software\UCS Firmware\4.2(3g)\{0}" -f @($image)

    $trash = Send-UcsFirmware -Ucs $ -LiteralPath $fileName | Watch-Ucs -Property TransferState -SuccessValue downloaded -FailureValue failed -PollSec 30 -TimeoutSec 600 -ErrorAction SilentlyContinue


    $trash = Send-UcsFirmware -Ucs $labUCS -LiteralPath $fileName | Watch-Ucs -Ucs $labUCS -Property TransferState -SuccessValue "success" -FailureValue "failed" -PollSec 10 -TimeoutSec 1200 -ErrorAction Stop

    #################################


    # Legal Hold Stuff

    $prj145132Dsts = $copyDestinations | Where-Object { $_.StartsWith("\\?\UNC\cdcfs1\Discovery\GrantTD\145132\") }
    $copyDictionary[$prj145132Dsts[0]]

    $a = 0
    $fileCount = 0
    while($a -lt $prj145132Dsts.Length)
    {
        $fileCount += $copyDictionary[$prj145132Dsts[$a]].Count
        $a++
    }

    $prj145132Srcs = @($copyData | Where-Object { $_.Destination.Endswith("145132") })
    $fileCount = 0
    $dirFileCount = [System.Collections.Generic.List[System.Object]]::new()
    $a = 0
    while($a -lt $prj145132Srcs.Length)
    {
        try
        {
            $files = [System.IO.Directory]::GetFiles($prj145132Srcs[$a].Source, "*.*", [System.IO.SearchOption]::AllDirectories)
            $b = 0
            while($b -lt $files.Length)
            {
                $fi = [System.IO.FileInfo]::new($files[$b])
                if($fi.Length -eq 0)
                {
                    Write-Host ("0KB file: {0}" -f @($fi.FullName))
                }
                $b++
            }
            $d = "" | Select-Object Directory, FileCount
            $d.Directory = $prj145132Srcs[$a].Source
            $d.FileCount = $files.Count
            $dirFileCount.Add($d)
            $fileCount += $files.Length
        }
        catch
        {
            Write-Host ("Failed to get files from {0}." -f @($prj145132Srcs[$a].Source))
        }
        $a++
    }



    ###################################################################

    # Import AD groups and Users into Folders and Files database

$adGroups = Get-ADGroup -Filter *
$adUsers = Get-ADUser -Filter *

$adObjs = $adGroups
$adObjs = $adUsers

$a = 0
while($a -lt $adObjs.Length)
{
    $q = "INSERT INTO Principals (Name, Domain, SamAccountName, SID) VALUES ('{0}', 'POWERENG', '{1}', '{2}');" -f @($adObjs[$a].Name.Replace("'","''"), $adObjs[$a].SamAccountName.Replace("'","''"), $adObjs[$a].SID.ToString())
    if($db.ExecuteNonQuery($q) -eq 0)
    {
        Write-Host ("FAILED: {0}" -f @($q))
    }
    $a++
}

$selectPrincipalByName = "ADAccount = '{0}'" -f @($acl.Owner)
$principals.Select($selectPrincipalByName)

##########################################
<#
    Requires $Global:allCifsShares
        Consider having one PS script to populate a central CSV files with all the NC CIFS Shares, then reading it from
        the scanner script so the scanner script doesn't require the NetApp CmdLets...
#>
