$tr = Import-csv -path \\cdcfs1\reference\perftest\results\202304101250-AUS-AUS-MGMT01.csv -Delimiter "`t"
$html = $tr |
    Select-Object `
        @{N='Datacenter'; E={$_.DCName}},
        @{N='Test host'; E={$_.TestHost}},
        @{N='File server'; E={$_.ServerName}},
        Description,
        @{N='Small file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileAverageMS)) }},
        @{N='Small file standard<br/>deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileMSStdDev)) }},
        @{N='Small file<br />variance'; E={ if($_.SmallFileMSVariance -gt 25) { ("<div style='color:red;'>{0:N2}%</div>" -f @([decimal]$_.SmallFileMSVariance)) } else { ("{0:N2}%" -f @([decimal]$_.SmallFileMSVariance)) }}},
        @{N='Medium file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileAverageMS)) }},
        @{N='Medium file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileMSStdDev)) }},
        @{N='Medium file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.MediumFileMSVariance)) }},
        @{N='Large file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileAverageMS)) }},
        @{N='Large file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileMSStdDev)) }},
        @{N='Large file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.LargeFileMSVariance)) }} |
    ConvertTo-Html -Head $htmlHeader |
    Set-AlternatingRows -CSSEvenClass even -CSSOddClass odd

$html2 = [System.Collections.Generic.List[String]]::new()
$html | ForEach-Object { $html2.Add( ([System.Web.HttpUtility]::HtmlDecode($_)) )}
$html = $html.Replace("`r`n","__")
    |
    $html | Set-Clipboard


function Set-AlternatingRows {
    <#
    .SYNOPSIS
        Simple function to alternate the row colors in an HTML table
    .DESCRIPTION
        This function accepts pipeline input from ConvertTo-HTML or any
        string with HTML in it.  It will then search for <tr> and replace
        it with <tr class=(something)>.  With the combination of CSS it
        can set alternating colors on table rows.

        CSS requirements:
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }

        Classnames can be anything and are configurable when executing the
        function.  Colors can, of course, be set to your preference.

        This function does not add CSS to your report, so you must provide
        the style sheet, typically part of the ConvertTo-HTML cmdlet using
        the -Head parameter.
    .PARAMETER Line
        String containing the HTML line, typically piped in through the
        pipeline.
    .PARAMETER CSSEvenClass
        Define which CSS class is your "even" row and color.
    .PARAMETER CSSOddClass
        Define which CSS class is your "odd" row and color.
    .EXAMPLE $Report | ConvertTo-HTML -Head $Header | Set-AlternateRows -CSSEvenClass even -CSSOddClass odd | Out-File HTMLReport.html

        $Header can be defined with a here-string as:
        $Header = @"
        <style>
        TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
        TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #6495ED;}
        TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        </style>
        "@

        This will produce a table with alternating white and grey rows.  Custom CSS
        is defined in the $Header string and included with the table thanks to the -Head
        parameter in ConvertTo-HTML.
    .NOTES
        Author:         Martin Pugh
        Twitter:        @thesurlyadm1n
        Spiceworks:     Martin9700
        Blog:           www.thesurlyadmin.com

        Changelog:
            1.1         Modified replace to include the <td> tag, as it was changing the class
                        for the TH row as well.
            1.0         Initial function release
    .LINK
        http://community.spiceworks.com/scripts/show/1745-set-alternatingrows-function-modify-your-html-table-to-have-alternating-row-colors
    .LINK
        http://thesurlyadmin.com/2013/01/21/how-to-create-html-reports/
    #>
    [CmdletBinding()]
        Param(
            [Parameter(Mandatory,ValueFromPipeline)]
            [string]$Line,

            [Parameter(Mandatory)]
            [string]$CSSEvenClass,

            [Parameter(Mandatory)]
            [string]$CSSOddClass
        )

    Begin
    {
        $ClassName = $CSSEvenClass
    }

    Process
    {
        if ($Line.Contains("<tr><td>"))
        {
            $Line = $Line.Replace("<tr>","<tr class=""$ClassName"">")
            if ($ClassName -eq $CSSEvenClass)
            {
                $ClassName = $CSSOddClass
            }
            else
            {
                $ClassName = $CSSEvenClass
            }
        }

        return $Line
    }
}

$htmlHeader = @"
<head>
    <title>AUS Perf Testing</title>
    <style>
        body { font-family: Consolas,monaco,monospace; font-size: 9pt; }
        th { background-color:#0083FF; padding: 2px; font-size: 10pt; }
        td { text-align: center; padding: 2px; }
        .odd  { background-color:#ffffff; }
        .even { background-color:#dddddd; }
        table, th, td { border: 1px solid black; border-collapse: collapse; }
    </style>
</head>
"@

$html = $allTestResults | Select-Object DCName,
    @{N='TestHost';E={hostname}},
    ServerName, DateTime, Description,

    @{N='SmallFileAverageMS';E={$_.FileTestSummary.Small.AverageMS}},
    @{N='SmallFileMSStdDev';E={$_.FileTestSummary.Small.MSStdDev}},
    @{N='SmallFileMSVariance';E={($_.FileTestSummary.Small.MSStdDev / $_.FileTestSummary.Small.AverageMS) * 100.0}},

    @{N='MediumFileAverageMS';E={$_.FileTestSummary.Medium.AverageMS}},
    @{N='MediumFileMSStdDev';E={$_.FileTestSummary.Medium.MSStdDev}},
    @{N='MediumFileMSVariance';E={($_.FileTestSummary.Medium.MSStdDev / $_.FileTestSummary.Medium.AverageMS) * 100.0}},

    @{N='LargeFileAverageMS';E={$_.FileTestSummary.Large.AverageMS}},
    @{N='LargeFileMSStdDev';E={$_.FileTestSummary.Large.MSStdDev}},
    @{N='LargeFileMSVariance';E={($_.FileTestSummary.Large.MSStdDev / $_.FileTestSummary.Large.AverageMS) * 100.0}} |
    Select-Object `
        @{N='Datacenter'; E={$_.DCName}},
        @{N='Test host'; E={$_.TestHost}},
        @{N='File server'; E={$_.ServerName}},
        Description,
        @{N='Small file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileAverageMS)) }},
        @{N='Small file standard<br/>deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.SmallFileMSStdDev)) }},
        @{N='Small file<br />variance'; E={ if($_.SmallFileMSVariance -gt 25) { ("<div style='color:red;'>{0:N2}%</div>" -f @([decimal]$_.SmallFileMSVariance)) } else { ("{0:N2}%" -f @([decimal]$_.SmallFileMSVariance)) }}},
        @{N='Medium file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileAverageMS)) }},
        @{N='Medium file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.MediumFileMSStdDev)) }},
        @{N='Medium file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.MediumFileMSVariance)) }},
        @{N='Large file average<br />read time (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileAverageMS)) }},
        @{N='Large file standard<br />deviation (MS)'; E={ ("{0:N2}" -f @([decimal]$_.LargeFileMSStdDev)) }},
        @{N='Large file<br />variance'; E={ ("{0:N2}%" -f @([decimal]$_.LargeFileMSVariance)) }} |
    ConvertTo-Html -Head $htmlHeader |
    Set-AlternatingRows -CSSEvenClass even -CSSOddClass odd

$html2 = [System.Collections.Generic.List[String]]::new()
$html | ForEach-Object { $html2.Add( ([System.Web.HttpUtility]::HtmlDecode($_)) )}
$html2 | Set-Clipboard



$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert
Set-AuthenticodeSignature -Certificate $cert -FilePath "..\PEI-IT-OPS\RDC\Metrics\SpeedTest.ps1"


$results = Import-CSV -Path \\cdcfs1\Reference\PerfTest\Results\PreSDWAN.csv


function NextPow2()
{
    $d = 999
    $c = 0
    while($d -ge 0)
    {
        $s = $Global:digits[$d] + $Global:digits[$d] + $c
        $c = 0
        if($s -gt 9)
        {
            $s -= 10
            $c = 1
        }
        $Global:digits[$d] = $s
        $d--
    }

    $Global:power2++
    $v = ($Global:digits -join "").TrimStart(@('0'))
    if([String]::IsNullOrEmpty($v))
    {
        $v = "0"
    }
    $a = $v.Length - 1
    $v2 = [System.Collections.Generic.Stack[System.Object]]::new()
    while($a -ge 0)
    {
        $v2.Push($v[$a])
        if(($a -gt 0) -and ((($v.Length - $a) % 3) -eq 0))
        {
            $v2.Push(',')
        }
        $a--
    }
    $addedCombos = [System.Collections.Generic.List[System.String]]::new()
    $combos = @(($v2 -join "") -split ",") | Sort-Object
    $combos | ForEach-Object {
        if(-not $Global:comboCount.ContainsKey($_))
        {
            $Global:comboCount.Add($_, 0)
            $addedCombos.Add($_)
        }
        $Global:comboCount[$_]++
    }

    Write-Host ("{0}" -f @(($addedCombos -join ", ")))
    Write-Host ("2^{0,3}: Combos: {1,4} {2,200}" -f @($Global:power2, $comboCount.Count, ($v2 -join "")))
}

$comboCount = [System.Collections.Generic.SortedDictionary[[String],[Int32]]]::new()

$power2 = 0
$digits = @(0..999)

@(0..($digits.Length - 1)) | ForEach-Object { $digits[$_] = 0 }

$digits[999] = 1

$currentCC = $comboCount.Count
do
{
    NextPow2
} until($comboCount.Count -ge 1099)


<#
    To facilitate retrieving AoVPN statistics in parallel (much faster), I need to create a list of objects containing:

        Index of a site within $aoStatsConfig.Sites
        Index of an AoVPNServer with $aoStatsConfig.Sites[_idx_]
        A list object to contain the results of Get-RemoteAccessConnectionStatistics from the AoVPN Server

    This is to ensure each thread created for the Foreach-Object -Parallel, has it's own uniquely addressable list to
    store the results from Get-RemoteAccessConnectionStatistics.
#>
$stats = [System.Collections.Generic.List[System.Object]]::new()

$a = 0
while($a -lt $aoStatsConfig.Sites.Length)
{
    $b = 0
    while($b -lt $aoStatsConfig.Sites[$a].VPNServers.Length)
    {
        $stat = "" | Select-Object SiteNumber,ServerNumber,CurrentStats,HourlyStats
        $stat.SiteNumber = $a
        $stat.ServerNumber = $b
        $stat.CurrentStats = [System.Collections.Generic.List[System.Object]]::new()
        $stat.HourlyStats = [System.Collections.Generic.List[System.Object]]::new()

        $stats.Add($stat)
        $b++
    }
    $a++
}

$endDateTime = [DateTime]::Now.ToUniversalTime()
$startDateTime = $endDateTime.AddHours(-4)

# In parallel, get all the AoVPN stats from the various servers.
$stats | Foreach-Object -Parallel {
    <#
        I tried a few variation of the following 7 lines of code, but $using makes it a little more complex.
        What I came up with seemed to work consistently.
    #>
    $eDT = $using:endDateTime
    $sDT = $using:startDateTime
    $ao = $using:aoStatsConfig
    $site = $ao.Sites[$_.SiteNumber]
    $aoVPNServer = $site.VPNServers[$_.ServerNumber]
    $currStats = $_.CurrentStats
    $hourlyStats = $_.HourlyStats

    $currStats.Clear()

    try
    {
        Invoke-Command -ComputerName $aoVPNServer -ScriptBlock { Get-RemoteAccessConnectionStatistics } | Foreach-Object {
            $currStats.Add($_)
        }
    }
    catch
    {
        Write-Error ("Failed to retrieve current AoVPN stats from {0}." -f @($aoVPNServer))
    }
    $hourlyStats.Clear()
    try
    {
        Invoke-Command -ComputerName $aoVPNServer -ScriptBlock { Get-RemoteAccessConnectionStatistics -StartDateTime ([DateTime]::Now.AddHours(-1)) -EndDateTime ([DateTime]::Now) } | Foreach-Object {
            $hourlyStats.Add($_)
        }
    }
    catch
    {
        Write-Error ("Failed to retrieve hourly AoVPN stats from {0}." -f @($aoVPNServer))
    }
}

$stats | ForEach-Object {
    Write-Host ("{0}/{1}: {2}/{3}" -f @($aoStatsConfig.Sites[$_.SiteNumber].SiteCode, $aoStatsConfig.Sites[$_.SiteNumber].VPNServers[$_.ServerNumber], $_.CurrentStats.Count, $_.HourlyStats.Count))
}


$licMgr = Get-View LicenseManager -Server $vCenter
$licAssignmentMgr = Get-View -Id $licMgr.LicenseAssignmentManager -Server $vCenter

$usedLicenses = $licAssignmentMgr.QueryAssignedLicenses($vCenter.InstanceUid)
$usedLicenses | Foreach-Object {
    $_ | Select-Object @{N='vCenter';E={$vCenter.Name}},EntityDisplayName,
        @{N='LicenseKey';E={$_.AssignedLIcense.LicenseKey}},
        @{N='LicenseName';E={$_.AssignedLicense.Name}},
        @{N='ExpirationDate';E={$_.AssignedLicense.Properties.where{$_.Key -eq 'expirationDate'}.Value }}
}


$licenseDataManager = Get-LicenseDataManager
$licenseDataManager.QueryEntityLicenseData()



$LicenseManager = Get-view LicenseManager

$LicenseAssignmentManager = Get-View $LicenseManager.LicenseAssignmentManager

$LicenseAssignmentManager.GetType().GetMethod("QueryAssignedLicenses").Invoke($LicenseAssignmentManager,@($null)) |
    Select-Object EntityDisplayName,
        @{N='Product';E={$_.Properties | where-object {$_.Key -eq 'ProductName'} | select-Object -ExpandProperty Value}},
        @{N='Product Version';E={$_.Properties | where-Object{$_.Key -eq 'FileVersion'} | select-Object -ExpandProperty Value}},
        @{N='License';E={$_.AssignedLicense.LicenseKey}},
        @{N='License Name';E={$_.AssignedLicense.Name}},
        @{N='Used License';E={$_.Properties | where-Object{$_.Key -eq 'EntityCost'} | select-Object -ExpandProperty Value}},
        @{N='Total';E={$_.AssignedLicense.Total}}





        $DN = (Get-ADUser -Identity "jdollus" -Properties DistinguishedName).DistinguishedName
        Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=CN=Ken Briney-adm,OU=Admin Accounts,OU=IT,OU=PEI,DC=powereng,DC=com)"



([ADSISEARCHER]"(member:1.2.840.113556.1.4.1941:=$(([ADSISEARCHER]"samaccountname=jdollus").FindOne().Properties.distinguishedname))").FindAll().Properties.distinguishedname -replace '^CN=([^,]+).+$','$1'


$projects = Get-ChildItem -Path "\\boifs1\shares$\Projects" | Where-Object { $_.PSIsContainer }
$explicitPaths = [System.Collections.Generic.List[System.String]]::new()
$p = 0
while($p -lt $projects.Length)
{
    Write-Host -ForegroundColor White -NoNewline ("Checking {0} of {1}: {2}..." -f @(($p + 1), $projects.Length, $projects[$p].Name))
    $acls = Get-Acl -Path $projects[$p].FullName
    if($null -ne $acls)
    {
        if($null -ne $acls.Access)
        {
            $explicitAccess = @($acls.Access | Where-Object { -not $_.IsInherited })
            if($explicitAccess.Length -gt 0)
            {
                $i = $explicitPaths.BinarySearch($projects[$p].Name)
                if($i -lt 0)
                {
                    $explicitPaths.Insert(-bnot $i, $projects[$p].Name)
                    Write-Host -NoNewline -ForegroundColor Green "explicit"
                }
            }
        }
    }
    Write-Host ""
    $p++
}

$explicitPaths -join ", " | Set-Clipboard


$cifsData = [System.Collections.Generic.List[System.Object]]::new()

$ctrlrs = @($cDOT.Values)
$b = 0
while($b -lt $ctrlrs.Length)
{
    $ctrlr = $ctrlrs[$b]
    $cifsServers = @(Get-NCCifsServer -Controller $ctrlr)
    $cifsSessions = @(Get-NcCifsSession -Controller $ctrlr)
    $a = 0
    while($a -lt $cifsServers.Length)
    {
        $d = "" | Select-Object Controller,VServer,SMB1Enabled,SMB2Enabled,SMB3Enabled,SMB31Enabled,SMBEncryptionRequired,SMBSigningRequired

        $cifsOptions = Get-NcCifsOption -Controller $ctrlr -VserverContext $cifsServers[$a].Vserver

        $d.Controller = $ctrlr.Name
        $d.VServer = $cifsServers[$a].Vserver
        $d.SMB1Enabled = $cifsOptions.IsSmb1Enabled -and $cifsOptions.IsSmb1EnabledSpecified
        $d.SMB2Enabled = $cifsOptions.IsSmb2Enabled -and $cifsOptions.IsSmb2EnabledSpecified
        $d.SMB3Enabled = $cifsOptions.IsSmb3Enabled -and $cifsOptions.IsSmb3EnabledSpecified
        $d.SMB31Enabled = $cifsOptions.IsSmb31Enabled -and $cifsOptions.IsSmb31EnabledSpecified

        $cifsSecurity = Get-NcCifsSecurity -Controller $ctrlr -VserverContext $cifsServers[$a].Vserver
        $d.SMBEncryptionRequired = $cifsSecurity.IsSmbEncryptionRequired -and $cifsSecurity.IsSmbEncryptionRequiredSpecified
        $d.SMBSigningRequired = $cifsSecurity.IsSigningRequired -and $cifsSecurity.IsSigningRequiredSpecified

        $sessions = @($cifsSessions | Where-Object { $_.Vserver -eq $cifsServers[$a].Vserver })
        if($sessions.Length -gt 0)
        {
            $sessionGroups = $cifsSessions | Group-Object -Property ProtocolVerion
            $a = $cifsServers.Length
            $b = $ctrlrs.Length
        }

        Write-Host ("{0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}" -f @($d.Controller, $d.VServer, $d.SMB1Enabled, $d.SMB2Enabled, $d.SMB3Enabled, $d.SMB31Enabled, $d.SMBEncryptionRequired, $d.SMBSigningRequired))
        $cifsData.Add($d)

        $a++
    }
    $b++
}

$cifsData | ConvertTo-Csv -NoTypeInformation -Delimiter "`t" | Set-Clipboard

$cifsShares = Get-NcCifsShare -Controller @($cdcCDOT) | Where-Object { ($_.VServer -eq "CDC-SVMA01") -and ($_.ShareName -notin @("admin`$","ipc`$","c`$"))}
$shares = $cifsShares | Where-Object { $_.ShareName -in @("PW", "PW_Active_01$", "PW_Active_02$", "PW_Active_03$", "PW_Active_04$", "Reference", "SAW", "CDCZ_WEB01_Backup", "SQL_DB_Backups", "UpdateManager", "Vault_Backup", "Vault_FileStore$", "Xchange")}
$vols = Get-NCVol -Controller $cdcCDOT -Vserver "CDC-SVMA01" -Volume @($shares | Select-Object -ExpandProperty Volume)
$cdcExtraShares = @(
    $shares | ForEach-Object {
        $s = $_
        $d = "" | Select-Object ShareName, Used, Size, Volume, Available
        $v = $vols | Where-Object { $_.Name -eq $s.Volume }
        $d.ShareName = "\\cdcfs1\{0}" -f @($s.ShareName)
        $d.Volume = $s.Volume
        $d.Size = $v.TotalSize
        $d.Used = ($v.TotalSize - $v.Available) + $v.VolumeSisAttributes.TotalSpaceSaved
        $d.Available = $v.Available

        $d
    }
)
$cdcExtraShares | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard

$pwVols = Get-NCVol -Controller $cdcCDOT -Vserver "CDC-SVMA01" | Where-Object { $_.JunctionPath -match "^/Shares/PW"}

$otherPWVols = @(
    $pwVols | ForEach-Object {
        $v = $_
        $vv = @($vols | Where-Object { $_.Name -eq $v.Name })
        if($vv.Length -eq 0)
        {
            $v
        }
    }
)

$sheetData = [System.Collections.Generic.List[System.Object]]::new()
@($cDot.Values) | ForEach-Object {
    $d = "" | Select-Object Name, IP, Location, SiteCode, Type, TotalSize, TotalUsed
    $c = $_
    $aggrs = @(Get-NCAggr -Controller $c)

    $d.Name = $c.Name
    $d.IP = $c.Address
    $d.SiteCode = ""
    $d.Location = "DC"
    $d.Type = "NAS"
    $d.TotalSize = 0
    $d.TotalUsed = 0
    $aggrs | Foreach-Object {
        $a = $_
        $d.TotalSize += $a.TotalSize
        $d.TotalUsed += ($a.TotalSize - $a.Available)
    }
    Write-Host ("Cluster: {0}, Total Size: {1}, Total Used: {1}" -f @($d.Name, (Format-StorageNumber $d.TotalSize), (Format-StorageNumber $d.TotalUsed)))
    $sheetData.Add($d)
}

$vms = @(Get-VM -Server $vCenter | Where-Object { $_.Name -notmatch "^vCLS\-" })
$sheetData = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $vms.Length)
{
    $d = "" | Select-Object Name, Location, SiteCode, Domain, Status, IPAddress, FQDN, ServerType, OS, Function, MoveToNutanix, MigrationType, MigrationStatus, Notes, Manufacturer, Model, AssetTag, vCPUs, MemoryGB, OSDiskSizeGB, DataDisk1UsedGB, DataDisk2UsedGB, DataDisk3UsedGB, OOBIPAddress, OOBAdministrator, OOBPassword, PurchaseDate, WarrantyExpiryDate
    if($null -eq $noteProperties)
    {
        $noteProperties = @($d | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
    }
    $d.Domain = "powereng.com"
    $d.ServerType = "Virtual"
    $d.Function = ""
    $d.MoveToNutanix = ""
    $d.MigrationType = ""
    $d.MigrationStatus = ""
    $d.Manufacturer = "N/A"
    $d.Model = "N/A"
    $d.AssetTag = "N/A"
    $d.OOBIPAddress = "N/A"
    $d.OOBAdministrator = "LAPS"
    $d.OOBPassword = "N/A"
    $d.PurchaseDate = "N/A"
    $d.WarrantyExpiryDate = "N/A"

    $d.Name = $vms[$a].Name
    $d.Location = $vms[$a].VMHost.Name
    $d.SiteCode = @($d.Location -split "-")[0].ToUpper().TrimEnd('Z')
    $d.Status = if($vms[$a].PowerState -eq "PoweredOn") { "UP" } else { "DOWN" }
    try
    {
        $d.OS = $vms[$a].Guest.ExtensionData.GuestFullName
    }
    finally
    {
        if([String]::IsNullOrEmpty($d.OS))
        {
            $d.OS = $vms[$a].GuestId
        }
    }
    if($d.Location -match "esxvcad\d\d")
    {
        $d.Function = "VCAD/VDI"
    } `
    elseif (($d.Name -match "\-VDI") -or ($d.OS -match "Windows 10 "))
    {
        $d.Function = "VDI"
    }

    $d.vCPUs = $vms[$a].NumCpu
    $d.MemoryGB = $vms[$a].MemoryGB

    $d.Notes = $vms[$a].Notes -join "`r`n"

    $d.OSDiskSizeGB = 0
    if(($null -ne $vms[$a].Guest) -and ($null -ne $vms[$a].Guest.Disks) -and ($vms[$a].Guest.Disks.Count -gt 0))
    {
        $disks = $vms[$a].Guest.Disks | Sort-Object Path

        if($null -ne $disks[0])
        {
            $d.OSDiskSizeGB = [math]::Ceiling($disks[0].CapacityGB)
        }

        $d.DataDisk1UsedGB = 0
        $d.DataDisk2UsedGB = 0
        $d.DataDisk3UsedGB = 0
        $b = 1
        while(($b -lt $disks.Length) -and ($b -le 3))
        {
            $d.("DataDisk{0}UsedGB" -f @($b)) = [math]::Ceiling(($disks[$b].CapacityGB - $disks[$b].FreeSpaceGB))
            $b++
        }
    } `
    else
    {
        try
        {
            $disks = $vms[$a] | Get-HardDisk -Server $vCenter -ErrorAction Stop
            $labels = @($disks | Select-Object @{N="Label"; E={$_.ExtensionData.DeviceInfo.Label}} | Select-Object -ExpandProperty Label | Sort-Object)
            if($labels.Length -gt 0)
            {
                $osDisk = $disks | Where-Object { $_.ExtensionData.DeviceInfo.Label -eq $labels[0] }
                if($null -ne $osDisk)
                {
                    $d.OSDiskSizeGB = $osDisk.CapacityGB
                }

                $d.DataDisk1UsedGB = 0
                $d.DataDisk2UsedGB = 0
                $d.DataDisk3UsedGB = 0
                $b = 1
                while(($b -lt $labels.Length) -and ($b -lt 3))
                {
                    $dataDisk = $disks | Where-Object { $_.ExtensionData.DeviceInfo.Label -eq $labels[$b] }
                    if($null -ne $dataDisk)
                    {
                        $d.("DataDisk{0}UsedGB" -f @($b)) = [math]::Ceiling($dataDisk[$b].CapacityGB)
                    }
                    $b++
                }
            }
        }
        catch
        {

        }
    }


    if(($null -ne $vms[$a].Guest) -and ($null -ne $vms[$a].Guest.IPAddress))
    {
        $d.IPAddress = ($vms[$a].Guest.IPAddress -match "\d+\.\d+\.\d+\.\d+")[0]
    }

    if(-not [String]::IsNullOrEmpty($vms[$a].Guest.HostName))
    {
        $d.FQDN = $vms[$a].Guest.HostName.ToLower()
    }

    try
    {
        $dns = Resolve-DnsName $d.Name -ErrorAction Stop
        if([String]::IsNullOrEmpty($d.IPAddress))
        {
            $d.IPAddress = $dns.IPAddress
        }
        if([String]::IsNullOrEmpty($d.FQDN))
        {
            $d.FQDN = $dns.Name.ToLower()
        }
    }
    catch
    {
        try
        {
            $dns = Resolve-DnsName -Name $d.Name -Server 10.247.80.10 -ErrorAction Stop
            if([String]::IsNullOrEmpty($d.IPAddress))
            {
                $d.IPAddress = $dns.IPAddress
            }
            if([String]::IsNullOrEmpty($d.FQDN))
            {
                $d.FQDN = $dns.Name.ToLower()
            }
        }
        catch {}
    }

    if([String]::IsNullOrEmpty($d.IPAddress))
    {

    }

    $sheetData.Add($d)

    Write-Host ($d | ConvertTo-CSV -Delimiter "," -NoTypeInformation)[1]
    $a++
}
$sheetData | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard


$cifsShares = @(Get-NcCifsShare -Controller @($cdot.Values) | Where-Object { ($_.CifsServer -ne "LAB-SMB01") -and ($_.CifsServer -notmatch "DR\-") -and ($_.ShareName -notin @("admin`$","ipc`$","c`$"))})
$shareVolumes = [System.Collections.Generic.List[System.Object]]::new()
$allVolumes = @(Get-NCVol -Controller @($cDot.Values))

$a = 0
while($a -lt $cifsShares.Length)
{
    if(@($shareVolumes | Where-Object { ($_.VServer -eq $cifsShares[$a].VServer) -and ($_.Name -eq $cifsShares[$a].Volume)}).Length -eq 0)
    {
        $shareVols = @($allVolumes | Where-Object { ($_.VServer -eq $cifsShares[$a].VServer) -and ($_.Name -eq $cifsShares[$a].Volume)})
        $b = 0
        while($b -lt $shareVols.Length)
        {
            $shareVolumes.Add($shareVols[$b])
            $b++
        }
    }
    $a++
}
