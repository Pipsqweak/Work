
$shares = Get-NCCIFsShare -Controller @($cDot.Values) | Where-Object { ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -notin @("admin$","c$","ipc$")) } | Sort-Object CifsServer,ShareName

$edRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    "POWERENG\FS-AllShares-ED",
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny)

$failedShares = [System.Collections.Generic.List[System.String]]::new()
$successShares = [System.Collections.Generic.List[System.String]]::new()
$alreadyACLdShares = [System.Collections.Generic.List[System.String]]::new()
$a = 0
while($a -lt $shares.Length)
{
    $cifsServerName = $shares[$a].CifsServer.Replace("-SMB01","FS1").Replace("-SVMAFS01","FS1").Replace("YYC01","ADC")
    $shareFolder = "\\?\UNC\{0}\{1}" -f @($cifsServerName, $shares[$a].ShareName)
    $newADGroupName = "FS-{0}-{1}-Share-ED" -f @($cifsServerName, $shares[$a].ShareName)
    Write-Host ("Share Folder: [{0}], New AD Group: [{1}]" -f @($shareFolder, $newADGroupName))

    try
    {
        $shareACL = Get-ACL -LiteralPath $shareFolder -ErrorAction Stop
        $successShares.Add($shareFolder)
        if(@($shareACL.Access | Where-Object { $_.IdentityReference -eq $edRule.IdentityReference }).Length -eq 0)
        {
    #        $shareACL.AddAccessRule($edRule)
    <#
            try
            {
                Set-ACL -LiteralPath $shareFolder -AclObject $shareACL -ErrorAction Stop
            }
            catch
            {
                Write-Error ("Failed to add deny ACL rule to {0}." -f @($shareFolder))
            }
    #>
        }
        else
        {
            $alreadyACLdShares.Add($shareFolder)
        }
    }
    catch
    {
        # Write-Error ("Failed to retrieve current ACL from {0}." -f @($shareFolder))
        $failedShares.Add($shareFolder)
    }

    $a++
}


$cifsServer = "CDCFS1"   # Or whatever...
$shareName = "Discovery"
$fileSharePath = "\\{0}\{1}" -f @($cifsServer, $shareName)
$fcGroup = "POWERENG\FS-{0}-{1}-Share-FC" -f @($cifsServer, $shareName)
$rwGroup = "POWERENG\FS-{0}-{1}-Share-RW" -f @($cifsServer, $shareName)
$roGroup = "POWERENG\FS-{0}-{1}-Share-RO" -f @($cifsServer, $shareName)
$xdGroup = "POWERENG\FS-AllShares-ED"

# or perhaps

$xdGroup = "POWERENG\FS-{0}-{1}-Share-XD" -f @($cifsServerName, $shares[$a].ShareName)
$acl = Get-ACL -Path $fileSharePath
$fcRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $fcGroup,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow)
$rwRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $rwGroup,
    [System.Security.AccessControl.FileSystemRights]::Modify -bor [System.Security.AccessControl.FileSystemRights]::Synchronize,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow)
$roRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $roGroup,
    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Synchronize,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow)
$xdRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
    $xdGroup,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Deny)
$acl.AddAccessRule($fcRule)
$acl.AddAccessRule($rwRule)
$acl.AddAccessRule($roRule)
$acl.AddAccessRule($xdRule)

Set-Acl -Path $fileSharePath -AclObject $acl




@(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Foreach-Object {
    $s = $_
    $shareACLs = Get-NcCifsShareAcl -Controller $s.NcController -VserverContext $s.Vserver  -Share $s.ShareName

    if(@($shareACLs | Where-Object { <# ($_.UserOrGroup -eq "POWERENG\FS-AllShares-XD") -and #> ($_.Permission -eq "no_access") }).Length -eq 0)
    {
        Write-Host ("{0}`t{1}`t{2}`tAdding POWERENG\FS-AllShares-XD no_access" -f@($s.NcController.Name, $s.Vserver, $s.ShareName))

        try
        {
            Add-NcCifsShareAcl -Controller $s.NcController -VserverContext $s.Vserver -Share $s.ShareName -UserOrGroup "POWERENG\FS-AllShares-XD" -Permission "no_access" -ErrorAction Stop | Out-Null
        }
        catch
        {
            Write-Host -ForegroundColor Red ("`tFailed adding no_access rule to: {0}`t{1}`t{2}." -f@($s.NcController.Name, $s.Vserver, $s.ShareName))
        }
    }
    else
    {
        # Write-Host ("{0}`t{1}`t{2}`tAlready has POWERENG\FS-AllShares-XD no_access" -f@($s.NcController.Name, $s.Vserver, $s.ShareName))
    }
}

# @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Foreach-Object { Get-NcCifsShareAcl -Controller $_.NcController -VserverContext $_.Vserver  -Share $_.ShareName }
