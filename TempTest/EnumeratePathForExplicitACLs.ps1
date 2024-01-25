$FolderPath = "\\boifs1\Xchange"
$Report = @()
$filesAndFolders = Get-ChildItem $FolderPath -Recurse
foreach ($ffPath in $filesAndFolders) {
    $ACLs = Get-Acl $ffPath.FullName | ForEach-Object { $_.Access }
    foreach ($ACL in $ACLs) {
        if (!$ACL.IsInherited) {
            $Properties = [ordered]@{
                'FolderName'=$ffPath.FullName;
                'AD Rights'=$ACL.IdentityReference;
                'Permissions'=$ACL.FileSystemRights;
                'Inherited'=$ACL.IsInherited
            }
            $Report += New-Object -TypeName PSObject -Property $Properties
        }
    }
}


function GetFFACL($fn)
{
    $ACLs = Get-Acl $_.FullName | ForEach-Object { $_.Access }
    foreach ($ACL in $ACLs) {
        if (!$ACL.IsInherited) {
            $Properties = [ordered]@{
                'Path'=$_.FullName;
                'AD Rights'=$ACL.IdentityReference;
                'Permissions'=$ACL.FileSystemRights;
                'Inherited'=$ACL.IsInherited
            }
            $Report.Add(( New-Object -TypeName PSObject -Property $Properties ))
        }
    }
}


$FolderPath = "\\?\UNC\cdcfs1\shares$"
$Report = [System.Collections.Generic.List[System.Object]]::new()
$allFilesAndFolders = [System.Collections.Generic.List[System.Object]]::new()
Get-ChildItem -LiteralPath $FolderPath -Recurse | Foreach-Object {

}
$Folders | Foreach-Object {
    $_.FullName
#    Get-ChildItem -LiteralPath $_.FullName -Recurse | ForEach-Object {
#        $_.FullName
#    }
} | Foreach-Object { $allFilesAndFolders.Add($_) }


$Folders | ForEach-Object -Parallel {
    $ACLs = Get-Acl $_.FullName | ForEach-Object { $_.Access }
    foreach ($ACL in $ACLs) {
        if (!$ACL.IsInherited) {
            $Properties = [ordered]@{
                'Path'=$_.FullName;
                'AD Rights'=$ACL.IdentityReference;
                'Permissions'=$ACL.FileSystemRights;
                'Inherited'=$ACL.IsInherited
            }
            $Report.Add(( New-Object -TypeName PSObject -Property $Properties ))
        }
    }
}
