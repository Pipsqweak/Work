<#
.SYNOPSIS
Collects configuration information from CDOT to aid in DR.

.DESCRIPTION
This script connects to each CDOT cluster and gathers configuration information. This information can
    be used to rebuild in the event of a DR scenario.

.EXAMPLE
.\netappConfigBackup.ps1

.NOTES
Author: duane.reed@powereng.com
Last revised: 20 Oct 2022
 - KLB              : Reformatted script for readability and made various changes for efficiency.
 - KLB, 20 Oct 2022 : Various changes to facilitate backing up cluster key manager database.

=================================================================================================================
 For CDOT connections, since they use https, you have to catpure logins via the NetApp Powershell toolkit
  so that they can be accessed magically when you run a scheduled task non-interactively.

 To capture credentials (encrypted of course) to be available at scheduled task run time, perform the following.

  First: Capture login and password as follows:
   $credentials = Get-Credential -Credential POWERENG\<ACCOUNT NAME>

  Second: Add the capture credentials to the NetApp PowerShell toolkit cache.
   Add-NcCredential -Name "<CLUSTER FQDN>" -Credential $credentials
   Repeat this r

  Third: Verify credentials
   Get-NcCredential
#>

#Configure script command line parameters
[cmdletbinding()]
Param
(
    [String]$logFileBasePath = "E:\Scripts\Logs\ConfigBackup\",
    [String]$logFileBaseName = "netappConfigBackup",
    [String]$sendTo = "itstorage@powereng.com",
    [String]$from = "cdc-ntapmgmt01@powereng.com",
    [string]$subject = "NetApp Configuration Backup Script Ran",
    [string]$smtpServer = "smtp.powereng.com",
    [string]$subjectFail = "FAILED :: NetApp Configuration Gatherer",
    [String]$cdotClusterListFile = "E:\Scripts\Config\cdotList.txt",
    [String]$destinationPath = "E:\NetApp Config Backups\",
    [int]$logFileRetentionDays = 30,
    [int]$dataFileRetentionDays = 7
)

# Logging function
Function Out-LogFile
{
    <#
    .SYNOPSIS
    Writes data to a log file

    .DESCRIPTION
    Writes data to a log file. The format of the log file attempts to mimic the logging
    used by Configuration Manager, so that the log files will render nicely using cmtrace.

    .PARAMETER logText
    This is the string that will be written to the log file

    .PARAMETER overwrite
    By default, log file entries are appended to the specified log file. If this switch is specified,
    the log file will be overwritten.

    .PARAMETER type
    Determines the type of message that will be written to a log. The default value is 1:
    1 - Information
    2 - Warning
    3 - Error

    .PARAMETER logFile
    The name of the log file where messages will be written.
    #>

    Param
    (
        [String]$logText,
        [Switch]$overwrite,
        [string]$type = 1,
        [String]$logFile = $logFile
    )

    # Do nothing if no log file is defined
    if (!$logFile)
    {
        return
    }
    else
    {
        #Create the time stamp for the log entry
        $time = Get-Date -Format HH:mm:ss.fff
        $offset = ([int](Get-Date -Format %z) * -60).ToString().PadLeft(3, "0").PadLeft(4, "+")
        $day = Get-Date -Format MM-dd-yyyy
        if (($null -ne $MyInvocation) -and -not [String]::IsNullOrEmpty($MyInvocation.ScriptName))
        {
            $component = $MyInvocation.ScriptName | Split-Path -Leaf
        } `
        else # NOT ($null -ne $MyInvocation -and -not [String]::IsNullOrEmpty($MyInvocation.ScriptName))
        {
            $component = "[Interactive]"
        }

        $string = "<![LOG[$logText]LOG]!>" +
        "<time=`"$time$offset`" " +
        "date=`"$day`" " +
        "component=`"$component`" " +
        "context=`"$env:USERNAME`" " +
        "type=`"$type`" " +
        "thread=`"$PID`" " +
        "file=`"$component`">"
        #Write the data to the log file
        Write-Verbose $logText
        $string | Out-File  -FilePath $logFile -Force -Encoding utf8 -Append:$(!$overwrite)
    }#End else
}#End Out-Log Function

Function Remove-OldFiles
{
    [cmdletbinding()]
    Param (
        [String]$path,
        [Int]$daysToKeep = 7,
        [String]$includeFilter = "*.csv",
        [Switch]$recurse,
        [Switch]$delete,
        [String]$logFunctionName
    )

    #Correct path input.
    if ($recurse.IsPresent)
    {
        if ($path.EndsWith("/"))
        {
            $path = $path.Replace("/", "\")
        }
    }
    else
    {
        if ($path.EndsWith("\"))
        {
            $path += "*"
        }

        if ($path.EndsWith("/"))
        {
            $path = $path.Replace("/", "\")
            $path += "*"
        }

        if (!$path.EndsWith("\*"))
        {
            $path += "\*"
        }
    }

    $maxAge = (Get-Date).AddDays(-$daysToKeep)

    if (Test-Path $path.Replace("*", ""))
    {
        if ($maxAge)
        {
            if ($recurse.IsPresent)
            {
                #Write-Host "`nRecursion enabled.`n"
                if ($logFunctionName)
                {
                    Invoke-Expression  "$logFunctionName -logText `"[Remove-OldFiles] Recursion enabled.`""
                    #Out-LogFile -logText "[Remove-OldFiles] Recursion enabled."
                }
                Try
                {
                    $oldFiles = Get-ChildItem -File -Recurse -Path $path -Include $includeFilter -ErrorAction SilentlyContinue -ErrorVariable getChildErrors | Where-Object { $_.LastWriteTime -lt $maxAge }
                }
                catch
                {
                    Out-LogFile "`n`n[Remove-OldFiles] Errors encountered while collecting child items.`n`nError message: $($_.Exception.Message)`n`n"
                }
            }
            else
            {
                Out-LogFile "`n[Remove-OldFiles] Recursion disabled."
                Try
                {
                    $oldFiles = Get-ChildItem -File -Path $path -Include $includeFilter -ErrorAction SilentlyContinue -ErrorVariable getChildErrors | Where-Object { $_.LastWriteTime -lt $maxAge } -ErrorAction Stop
                }
                catch
                {
                    Out-LogFile "[Remove-OldFiles] $($_.Exception.Message)"
                }
            }

            if ($oldFiles)
            {
                if (!$delete.IsPresent)
                {
                    Out-LogFile "[Remove-OldFiles] Delete switch not present. Logging files that would be deleted with `$delete switch enabled.`n"
                }

                foreach ($file in $oldFiles)
                {
                    if ($delete.IsPresent)
                    {
                        try
                        {
                            Remove-Item $file -ErrorAction Stop
                            Out-LogFile "[Remove-OldFiles] Successfully removed $file"
                        }
                        catch
                        {
                            Out-LogFile "[Remove-OldFiles] Failed to remove $file"
                        }
                    }
                    else
                    {
                        Out-LogFile "[Remove-OldFiles] Would delete $file if -delete was specified when calling the function."
                    }
                }
            }
            else
            {
                Out-LogFile "`n[Remove-OldFiles] No files found. Exiting."
            }
        }
        else
        {
            Out-LogFile "[Remove-OldFiles] Maximum age was not calculated. Cannot continue."
        }
    }
    else
    {
        Out-LogFile "[Remove-OldFiles] Path, $path, not found."
    }

    if ($getChildErrors)
    {
        Write-Host "`n"
        foreach ($object in $getChildErrors)
        {
            Out-LogFile "[Remove-OldFiles] Failure: $($object.Exception.Message)`n"
        }
    }
}

Function Connect-Cluster
{
    Param
    (
        $clusters
    )

    foreach ($cluster in $clusters)
    {
        #Out-LogFile "Connecting to CDOT cluster $cluster."
        $connection = Connect-NcController -Name $cluster

        if ($connection)
        {
            [void]$cdotConnectionArrayList.Add($connection)
        }
        else
        {
            Out-LogFile "FAILURE: Could not connect to $cluster."
            [void] $Script:sbErrorMessages.AppendLine(("Could not connect to: {0}." -f @($cluster)))
        }

        $connection = $null
    }
}

Function Get-NetAppCDOTShareData
{
    [cmdletbinding()]
    Param
    (
        $shares,
        $cdotConnection
    )

    $Script:sharePermsCollection = @()
    #DEBUG
    foreach ($share in $shares)
    {
        #DEBUG
        if (!(($share.ShareName.ToString() -eq "admin$") -or ($share.ShareName.ToString() -eq "ipc$") -or ($share.ShareName.ToString() -eq "c$")))
        {
            #Write-Host "Printing Share: $($share.ShareName.ToString())"
            $sharePerms = $share | Get-NcCifsShareAcl -Controller $cdotConnection # -ErrorVariable cdotSharePermError

            if ($sharePerms)
            {
                foreach ($perm in $sharePerms)
                {
                    #Write-Host "Perm is $($perm.Permission)"
                    $sharePermItem = New-Object System.Object

                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "Node/vServer" -Value $share.Vserver
                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "ShareName" -Value $perm.Share
                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "User/Group" -Value $perm.UserOrGroup.ToUpper()
                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "Permission" -Value $perm.Permission.ToUpper()
                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "MountPoint" -Value $share.Path
                    $sharePermItem | Add-Member -MemberType NoteProperty -Name "Volume" -Value $share.Volume

                    $Script:sharePermsCollection += $sharePermItem
                }
            }
            else
            {
                #DEBUG
                # Out-Logfile "FAILURE: Unable to retrieve share ACL information for $($share.ShareName) on  cluster $cdotConnection.`nError was $cdotSharePermError."
            }
        }
        $sharePerms = $null
    }

    $Script:sharePermsCollection = @($Script:sharePermsCollection | Select-Object -Unique "Node/vServer","ShareName","User/Group","Permission","MountPoint","Volume" | Sort-Object "Node/vServer","ShareName","User/Group","Permission","MountPoint","Volume")
}

Function Output-NTAPFile
{
    [cmdletbinding()]
    Param (
        $cdotConnection,
        [String]$type,
        $data,
        $dateLabel,
        [String] $rootPath,
        [Switch] $OutputString
    )

    $folderName = ($cdotConnection.Name.Split("."))[0]
    $outputPath = ""

    if ($rootPath.EndsWith("\"))
    {
        $outputPath = $rootPath + $folderName + "\"
    }
    else
    {
        $outputPath = $rootPath + "\" + $folderName + "\"
    }

    if (!(Test-Path -Path $outputPath))
    {
        Out-LogFile "Creating path $outputPath"
        New-Item -Path $outputPath -ItemType directory | Out-Null
    }
    if (Test-Path -Path $outputPath)
    {
        $fileName = "{0}{1}-{2}-{3}" -f @($outputPath, $folderName, $type, $dateLabel)
        if (-not $OutputString)
        {
            $fileName = "{0}.csv" -f @($fileName)
            $data | Export-Csv -Path "$outputPath$folderName-$type-$dateLabel.csv" -NoTypeInformation
        } `
        else # NOT (-not $OutputString)
        {
            $fileName = "{0}.txt" -f @($fileName)
            Set-Content -Path $fileName -Value $data -Force
        }

    }
    else
    {
        Out-LogFile "FAILURE: Path, $outputPath , not found."
    }
}

Function Get-NetAppIFGroups
{
    [cmdletbinding()]
    Param
    (
        $ifGrps,
        $cdotConnection
    )

    $ifGroupFunctionCollection = @()

    foreach ($ifGroup in $ifGrps)
    {
        $portList = ""

        foreach ($port in $($ifGroup.Ports)) { $portList += ($port + ",") }

        $portList = $portList.Trim(",")

        $iGroupItem = New-Object System.object

        $iGroupItem | Add-Member -MemberType NoteProperty -Name "IfgrpName" -Value $ifGroup.IfgrpName
        $iGroupItem | Add-Member -MemberType NoteProperty -Name "DistributionFunction" -Value $ifGroup.DistributionFunction
        $iGroupItem | Add-Member -MemberType NoteProperty -Name "Mode" -Value $ifGroup.Mode
        $iGroupItem | Add-Member -MemberType NoteProperty -Name "Node" -Value $ifGroup.Node
        $iGroupItem | Add-Member -MemberType NoteProperty -Name "Ports" -Value $portList

        $ifGroupFunctionCollection += $igroupItem
    }

    return $ifGroupFunctionCollection
}

Function Get-NetAppBroadcastDomains
{
    [cmdletbinding()]
    Param
    (
        $bcastDomains
    )

    $bcastDomainsFunctionCollection = @()

    foreach ($bcastDomain in $bcastDomains)
    {
        $portList = ""

        foreach ($port in $($bcastDomain.Ports.Port))
        {
            $portList += ($port + ",")
        }

        $portList = $portList.Trim(",")

        $fGroupList = ""

        foreach ($fGroup in $($bcastDomain.FailoverGroups))
        {
            $fGroupList += ($fGroup + ",")
        }

        $fGroupList = $fGroupList.Trim(",")

        $bcastItem = New-Object System.object

        $bcastItem | Add-Member -MemberType NoteProperty -Name "BroadcastDomain" -Value $bcastDomain.BroadcastDomain
        $bcastItem | Add-Member -MemberType NoteProperty -Name "Ipspace" -Value $bcastDomain.IPspace
        $bcastItem | Add-Member -MemberType NoteProperty -Name "Mtu" -Value $bcastDomain.Mtu
        $bcastItem | Add-Member -MemberType NoteProperty -Name "Ports" -Value $portList
        $bcastItem | Add-Member -MemberType NoteProperty -Name "MtuSpecified" -Value $bcastDomain.MtuSpecified
        $bcastItem | Add-Member -MemberType NoteProperty -Name "FailoverGroups" -Value $fGroupList

        $bcastDomainsFunctionCollection += $bcastItem
    }

    return $bcastDomainsFunctionCollection
}

Function Get-NetAppExportRules
{
    [cmdletbinding()]
    Param
    (
        $exportRules
    )

    $exportRulesFunctionCollection = @()

    foreach ($exportRule in $exportRules)
    {
        $protocolList = ""
        foreach ($protocol in $($exportRule.Protocol)) { $protocolList += (($protocol.ToString()) + ",") }
        $protocolList = $protocolList.Trim(",")

        $roRuleList = ""
        foreach ($roRule in $($exportRule.RoRule)) { $roRuleList += ($roRule + ",") }
        $roRuleList = $roRuleList.Trim(",")

        $rwRuleList = ""
        foreach ($rwRule in $($exportRule.RwRule)) { $rwRuleList += ($rwRule + ",") }
        $rwRuleList = $rwRuleList.Trim(",")

        $superUserSecurityList = ""
        foreach ($superUser in $($exportRule.SuperUserSecurity)) { $superUserSecurityList += ($superUser + ",") }
        $superUserSecurityList = $superUserSecurityList.Trim(",")

        $exportRuleItem = New-Object System.object

        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "PolicyName" -Value $exportRule.PolicyName
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "Vserver" -Value $exportRule.Vserver
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "ClientMatch" -Value $exportRule.ClientMatch
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "Protocol" -Value $protocolList
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "RoRule" -Value $roRuleList
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "RwRule" -Value $rwRuleList
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "SuperUserSecurity" -Value $superUserSecurityList
        $exportRuleItem | Add-Member -MemberType NoteProperty -Name "RuleIndex" -Value $exportRule.RuleIndex

        $exportRulesFunctionCollection += $exportRuleItem
    }

    return $exportRulesFunctionCollection
}

Function Get-NetAppIGroups
{
    [cmdletbinding()]
    Param
    (
        $iGrps
    )

    $iGrpFunctionCollection = @()

    foreach ($iGrp in $iGrps)
    {
        $initiatorList = ""

        foreach ($initiator in $($iGrp.Initiators)) { $initiatorList += ($($initiator.InitiatorName) + ",") }

        $initiatorList = $initiatorList.Trim(",")

        $iGrpItem = New-Object System.object

        $iGrpItem | Add-Member -MemberType NoteProperty -Name "Name" -Value $iGrp.Name
        $iGrpItem | Add-Member -MemberType NoteProperty -Name "Type" -Value $iGrp.Type
        $iGrpItem | Add-Member -MemberType NoteProperty -Name "Portset" -Value $iGrp.Portset
        $iGrpItem | Add-Member -MemberType NoteProperty -Name "Initiators" -Value $initiatorList
        $iGrpItem | Add-Member -MemberType NoteProperty -Name "Vserver" -Value $iGrp.Vserver

        $iGrpFunctionCollection += $iGrpItem
    }

    return $iGrpFunctionCollection
}

Function Get-NetAppPortsets
{
    [cmdletbinding()]
    Param
    (
        $portsets
    )

    $portsetFunctionCollection = @()

    foreach ($portset in $portsets)
    {
        $initiatorGroupList = ""

        foreach ($initiatorGroupInfo in $($portset.InitiatorGroupInfo)) { $initiatorGroupList += ($initiatorGroupInfo + ",") }

        $initiatorGroupList = $initiatorGroupList.Trim(",")

        $portsetPortInfoList = ""

        foreach ($portsetPortInfo in $($portset.PortsetPortInfo)) { $portsetPortInfoList += ($portsetPortInfo + ",") }

        $portsetPortInfoList = $portsetPortInfoList.Trim(",")

        $portsetItem = New-Object System.object

        $portsetItem | Add-Member -MemberType NoteProperty -Name "PortsetName" -Value $portset.PortsetName
        $portsetItem | Add-Member -MemberType NoteProperty -Name "InitiatorGroups" -Value $initiatorGroupList
        $portsetItem | Add-Member -MemberType NoteProperty -Name "PorsetMembers" -Value $portsetPortInfoList
        $portsetItem | Add-Member -MemberType NoteProperty -Name "Node" -Value $portset.Vserver

        $portsetFunctionCollection += $portsetItem
    }

    return $portsetFunctionCollection
}

Function Get-NetAppSnapMirrorPolicies
{
    [cmdletbinding()]
    Param
    (
        $snapPolicies
    )

    $snapPolicyFunctionCollection = @()

    foreach ($snapPolicy in $snapPolicies)
    {
        $SnapPoliciesLabelList = ""
        $snapPoliciesKeepList = ""

        foreach ($rule in $($snapPolicy.SnapmirrorPolicyRules)) { $snapPoliciesLabelList += ($rule.SnapmirrorLabel + ","); $snapPoliciesKeepList += ($rule.Keep + ",") }

        $SnapPoliciesLabelList = $SnapPoliciesLabelList.Trim(",")
        $snapPoliciesKeepList = $snapPoliciesKeepList.Trim(",")

        $snapPolicyItem = New-Object System.object

        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "PolicyName" -Value $snapPolicy.Name
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "Vserver" -Value $snapPolicy.Vserver
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "NetCompressed" -Value $snapPolicy.IsNetworkCompressionEnabled
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "Restart" -Value $snapPolicy.Restart
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "SnapRules" -Value $snapPoliciesLabelList
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "SnapRulesKeep" -Value $snapPoliciesKeepList
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "TotalKeep" -Value $snapPolicy.TotalKeep
        $snapPolicyItem | Add-Member -MemberType NoteProperty -Name "TotalRules" -Value $snapPolicy.TotalRules

        $snapPolicyFunctionCollection += $snapPolicyItem
    }

    return $snapPolicyFunctionCollection
}

Function Get-NetAppSnapshotPolicies
{
    [cmdletbinding()]
    Param
    (
        $snapshotPolicies
    )

    $snapshotFunctionCollection = @()

    foreach ($snapShot in $snapshotPolicies)
    {
        $schedulePrefixList = ""
        $scheduleCountList = ""
        $scheduleScheduleList = ""
        $scheduleSnapMIrrorLabelList = ""

        foreach ($schedule in $($snapshot.SnapshotPolicySchedules))
        {
            $schedulePrefixList += ($schedule.Prefix + ",")
            $scheduleCountList += ($schedule.Count.ToString() + ",")
            $scheduleScheduleList += ($schedule.Schedule + ",")
            $scheduleSnapMirrorLabelList += ($schedule.SnapmirrorLabel + ",")
        }

        $schedulePrefixList = $schedulePrefixList.Trim(",")
        $scheduleCountList = $scheduleCountList.Trim(",")
        $scheduleScheduleList = $scheduleScheduleList.Trim(",")
        $scheduleSnapMirrorLabelList = $scheduleSnapMIrrorLabelList.Trim(",")

        $scheduleItem = New-Object System.object

        $scheduleItem | Add-Member -MemberType NoteProperty -Name "Policy" -Value $snapshot.Policy
        $scheduleItem | Add-Member -MemberType NoteProperty -Name "Vserver" -Value $snapshot.VserverName
        $scheduleItem | Add-Member -MemberType NoteProperty -Name "PolicyPrefix" -Value $schedulePrefixList
        $scheduleItem | Add-Member -MemberType NoteProperty -Name "RetentionCount" -Value $scheduleCountList
        $scheduleItem | Add-Member -MemberType NoteProperty -Name "Schedule" -Value $scheduleScheduleList
        $scheduleItem | Add-Member -MemberType NoteProperty -Name "SnapMirrorLabel" -Value $scheduleSnapMirrorLabelList

        $snapshotFunctionCollection += $scheduleItem
    }

    return $snapshotFunctionCollection
}

Function Get-NetAppSVMs
{
    [cmdletbinding()]
    Param
    (
        $svms
    )

    $svmFunctionCollection = @()

    foreach ($svm in $svms)
    {
        $svmProtocolList = ""

        foreach ($protocol in $($svm.AllowedProtocols)) { $svmProtocolList += ($protocol + ",") }

        $svmProtocolList = $svmProtocolList.Trim(",")

        $svmItem = New-Object System.object

        $svmItem | Add-Member -MemberType NoteProperty -Name "Vserver" -Value $svm.Vserver
        $svmItem | Add-Member -MemberType NoteProperty -Name "AllowedProtocols" -Value $svmProtocolList
        $svmItem | Add-Member -MemberType NoteProperty -Name "Language" -Value $svm.Language
        $svmItem | Add-Member -MemberType NoteProperty -Name "RootVolume" -Value $svm.Rootvolume
        $svmItem | Add-Member -MemberType NoteProperty -Name "RootVolumeAggregate" -Value $svm.RootvolumeAggregate
        $svmItem | Add-Member -MemberType NoteProperty -Name "RootVolumeSecurityStyle" -Value $svm.RootvolumeSecurityStyle

        $svmFunctionCollection += $svmItem
    }

    return $svmFunctionCollection
}

#====================END FUNCTION DECLARATION==============================================================================

$date = Get-Date -Format MM-dd-yyyy_HHmmss

if ($date)
{
    $logfile = $logFileBasePath + $logFileBaseName + $date + ".log"
} `
else
{
    $logfile = $logFileBasePath + $logFileBasePath + ".log"
}

if (!(Test-Path -Path $logFileBasePath))
{
    New-Item -Path $logFileBasePath -ItemType "Directory" | Out-Null
}

Out-LogFile "-----------------------------Starting NetApp Configuration Backup-----------------------------" -overwrite

#BEGIN MAIN

#Create the SMTP client object.
$smtp = New-Object Net.Mail.SmtpClient($smtpServer)

# If $emailMessage is not null at the end of the script, it is used to send an appropriate message
$emailMessage = $null

# Create an error log (for email purposes) ...
$sbErrorMessages = [System.Text.StringBuilder]::new()

if (Test-Path -Path $logFileBasePath)
{
    $cdotConnectionArrayList = New-Object System.Collections.ArrayList

    if (!(Get-Module -Name DataONTAP))
    {
        Import-Module DataONTAP
    }

    if (Test-Path -Path $cdotClusterListFile)
    {
        #Clean up old script log files
        Remove-OldFiles -path $logFileBasePath -daysToKeep $logFileRetentionDays -includeFilter "*.log" -recurse -delete -logFunctionName "Out-Logfile"

        #Clean up old data CSV files
        Remove-OldFiles -path $destinationPath -daysToKeep $dataFileRetentionDays -includeFilter "*.csv" -recurse -delete -logFunctionName "Out-Logfile"

        $cdotClusterList = Get-Content -Path $cdotClusterListFile

        foreach ($cluster in $cdotClusterList)
        {
            Connect-Cluster $cluster
        }

        foreach ($cdotConnection in $cdotConnectionArrayList)
        {
            $folderName = ($cdotConnection.Name.Split("."))[0]
            $outputPath = "$destinationPath$folderName\"

            Out-Logfile "Retrieving shares from CDOT cluster $cdotConnection."


            # Reinitialize $sharePermsCollection for each cluster checked.
            $sharePermsCollection = @()

            $shares = @(Get-NcCifsShare -Controller $cdotConnection)

            if ($?)
            {
                if($shares.Length -gt 0)
                {
                    Get-NetAppCDOTShareData -shares $shares -cdotConnection $cdotConnection
                }
            } `
            else
            {
                Out-LogFile "Failed to retrieve any shares from CDOT cluster $cdotConnection"
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("share data", $cdotConnection.Name)))
            }

            if ($sharePermsCollection.Length -gt 0)
            {
                Output-NTAPFile -cdotConnection $cdotConnection -type "Share" -data $sharePermsCollection -dateLabel $date -rootPath $destinationPath
            }

            #Gather LIFs
            $lifs = @(Get-NcNetInterface -Controller $cdotConnection | Where-Object { $_.Role -ne "Cluster" } | Select-Object InterfaceName, Role, HomeNode, HomePort, IsAutoRevert, Address, Netmask, Vserver)

            if ($?)
            {
                if($lifs.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "LIF" -data $lifs -dateLabel $date -rootPath $destinationPath
                }
            } `
            else
            {
                Out-LogFile "FAILURE: Was not able to gather LIFs for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("LIFs", $cdotConnection.Name)))
            }

            #Gather IFGroups
            $ifGrps = @(Get-NcNetPortIfgrp -Controller $cdotConnection | Select-Object Node, IfgrpName, Ports, Mode, DistributionFunction)

            if ($?)
            {
                if($ifGrps.Length -gt 0)
                {
                    $ifGrpOutput = Get-NetAppIFGroups -ifGrps $ifGrps

                    if($ifGrpOutput.Length -gt 0)
                    {
                        Output-NTAPFile -cdotConnection $cdotConnection -type "IFGRP" -data $ifGrpOutput -dateLabel $date -rootPath $destinationPath
                    }
                }
            } `
            else
            {
                Out-LogFile "FAILURE: Was not able to gather IFGroups for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("IFGroups", $cdotConnection.Name)))
            }

            #Gather Aggregates
            $aggrs = @(Get-NcAggr -Controller $cdotConnection | Select-Object Name, @{N = "TotalSize-GB"; E = { "{0:N0}" -f ($_.TotalSize / 1GB) } }, RaidType, RaidSize, Disks)

            if ($?)
            {
                if($aggrs.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "AGGR" -data $aggrs -dateLabel $date -rootPath $destinationPath
                }
            } `
            else
            {
                Out-LogFile "FAILURE: Was not able to gather aggregates for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("aggregates", $cdotConnection.Name)))
            }

            #Gather Broadcast Domains
            $broadcastDomains = @(Get-NcNetPortBroadcastDomain -Controller $cdotConnection | Select-Object BroadcastDomain, IpSpace, MTU, Ports, MtuSpecified, FailoverGroups)

            if ($?)
            {
                if($broadcastDomains.Length -gt 0)
                {
                    $bcastDomainOutput = Get-NetAppBroadcastDomains -bcastDomains $broadcastDomains
                    Output-NTAPFile -cdotConnection $cdotConnection -type "BCASTDOMAIN" -data $bcastDomainOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather broadcast domains for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("broadcast domains", $cdotConnection.Name)))
            }

            #Gather Volumes
            $volumes = @(Get-NcVol -Controller $cdotConnection  | Select-Object Name, @{N = "TotalSize-GB"; E = { "{0:N0}" -f ($_.TotalSize / 1GB) } }, Dedupe, @{N = "SnapshotsEnabled"; E = { $_.VolumeSnapshotAttributes.AutoSnapshotsEnabled } }, @{N = "SnapshotPolicy"; E = { $_.VolumeSnapshotAttributes.SnapshotPolicy } }, @{N = "SnapshotCount"; E = { $_.VolumeSnapshotAttributes.SnapshotCount } }, Aggregate, JunctionPath, Vserver, @{N = "Language"; E = { $_.VolumeLanguageAttributes.Language } }, @{Name = "AutoSize-Max-GB"; E = { "{0:N0}" -f ($_.VolumeAutosizeAttributes.MaximumSize / 1GB) } }, @{N = "Autosize-Enabled"; E = { $_.VolumeAutosizeAttributes.IsEnabled } }, @{Name = "AutoSize-Increment-GB"; E = { "{0:N0}" -f ($_.VolumeAutosizeAttributes.IncrementSize / 1GB) } }, @{Name = "Caching-Policy"; E = { $_.VolumeHybridCacheAttributes.CachingPolicy } }, @{Name = "Cache-Eligibility"; E = { $_.VolumeHybridCacheAttributes.Eligibility } })

            if ($?)
            {
                if($volumes.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "Volume" -data $volumes -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather volumes for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("volumes", $cdotConnection.Name)))
            }

            #Gather Export Policies
            $exportPolicies = @(Get-NcExportPolicy -Controller $cdotConnection | Select-Object PolicyName, Vserver)

            if ($?)
            {
                if($exportPolicies.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "ExportPolicies" -data $exportPolicies -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather export policies for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("export policies", $cdotConnection.Name)))
            }

            #Gather Export Rules
            $exportRules = @(Get-NcExportRule -Controller $cdotConnection | Select-Object PolicyName, Vserver, ClientMatch, Protocol, RoRule, RuleIndex, RwRule, SuperUserSecurity)

            if ($?)
            {
                if($exportRules.Length -gt 0)
                {
                    $exportRuleOutput = Get-NetAppExportRules -exportRules $exportRules
                    Output-NTAPFile -cdotConnection $cdotConnection -type "ExportRules" -data $exportRuleOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather export rules for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("export rules", $cdotConnection.Name)))
            }

            #Gather iSCSI iGroups
            $iGroups = @(Get-NcIgroup -Controller $cdotConnection | Select-Object Name, Type, portSet, Initiators, Vserver)

            if ($?)
            {
                if($iGroups.Length -gt 0)
                {
                    $iGrpOutput = Get-NetAppIGroups -iGrps $iGroups
                    Output-NTAPFile -cdotConnection $cdotConnection -type "iGroup" -data $iGrpOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather iGroups for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("iGroups", $cdotConnection.Name)))
            }

            #iSCSI IQN
            $iscsiIQN = @(Get-NcIscsiService -Controller $cdotConnection | Select-Object Vserver, NodeName)

            if ($?)
            {
                if($iscsiIQN.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "iSCSIIQN" -data $iscsiIQN -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather iSCSI IQNs for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("iSCSI IQNs", $cdotConnection.Name)))
            }

            #Gather LUNs
            $luns = @(Get-NcLun -Controller $cdotConnection | Select-Object Path, Protocol, @{N = "Size-GB"; E = { "{0:N0}" -f ($_.Size / 1GB) } })

            if ($?)
            {
                if($luns.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "LUN" -data $luns -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather LUNS for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("LUNs", $cdotConnection.Name)))
            }

            #Gather VLANs
            $vlans = @(Get-NcNetPortVlan -Controller $cdotConnection | Select-Object InterfaceName, Node, Vlanid)

            if ($?)
            {
                if($vlans.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "VLAN" -data $vlans -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather VLANs for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("VLANs", $cdotConnection.Name)))
            }

            #Gather routes
            $routes = @(Get-NcNetRoute  -Controller $cdotConnection | Select-Object Destination, Gateway, Metric, Vserver)

            if ($?)
            {
                if($routes.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "Route" -data $routes -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather routes for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("routes", $cdotConnection.Name)))
            }

            #Gather Portsets
            $portsets = @(Get-NcPortset -Controller $cdotConnection | Select-Object PortsetName, InitiatorGroupInfo, PortSetPortInfo, Vserver)

            if ($?)
            {
                if($portsets.Length -gt 0)
                {
                    $portsetOutput = Get-NetAppPortsets -portsets $portsets
                    Output-NTAPFile -cdotConnection $cdotConnection -type "Portset" -data $portsetOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather portsets for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("portsets", $cdotConnection.Name)))
            }

            #Gather SnapMirror Relationships
            $snapMirrorRelationships = @(Get-NcSnapmirror -Controller $cdotConnection | Select-Object SourceLocation, DestinationLocation, Policy, Schedule)

            if ($?)
            {
                if($snapMirrorRelationships.Length -gt 0)
                {
                    Output-NTAPFile -cdotConnection $cdotConnection -type "SnapMirror-Relationship" -data $snapMirrorRelationships -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather SnapMirror relationships for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("snapmirror relationships", $cdotConnection.Name)))
            }

            #Gather SnapMirror Policies
            $snapMirrorPolicies = @(Get-NcSnapmirrorPolicy -Controller $cdotConnection | Select-Object Name, Vserver, IsNetworkCompressionEnabled, Restart, SnapmirrorPolicyRules, TotalKeep, TotalRules)

            if ($?)
            {
                if($snapMirrorPolicies.Length -gt 0)
                {
                    $snapMirrorPolicyOutput = Get-NetAppSnapMirrorPolicies -snapPolicies $snapMirrorPolicies
                    Output-NTAPFile -cdotConnection $cdotConnection -type "SnapMirror-Policy" -data $snapMirrorPolicyOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather SnapMirror policies for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("snapmirror policies", $cdotConnection.Name)))
            }

            #Gather Snapshot Policies
            $snapshotPolicies = @(Get-NcSnapshotPolicy -Controller $cdotConnection | Select-Object Policy, VserverName, SnapshotPolicySchedules)

            if ($?)
            {
                if($snapshotPolicies.Length -gt 0)
                {
                    $snapshotPolicyOutput = Get-NetAppSnapshotPolicies -snapshotPolicies $snapshotPolicies
                    Output-NTAPFile -cdotConnection $cdotConnection -type "Snapshot-Policies" -data $snapshotPolicyOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather Snapshot policies for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("snapshot policies", $cdotConnection.Name)))
            }

            #Gather SVMs (FIXME Need to expand the AllowedProtocols property)
            $svms = @(Get-NcVserver -Controller $cdotConnection | Select-Object Vserver, AllowedProtocols, Language, RootVolume, RootVolumeAggregate, RootVolumeSecurityStyle)

            if ($?)
            {
                if($svms.Length -gt 0)
                {
                    $svmOutput = Get-NetAppSVMs -svms $svms
                    Output-NTAPFile -cdotConnection $cdotConnection -type "SVM" -data $svmOutput -dateLabel $date -rootPath $destinationPath
                }
            }
            else
            {
                Out-LogFile "FAILURE: Was not able to gather SVMs for cluster $cdotConnection."
                [void] $sbErrorMessages.AppendLine(("Was not able to gather {0} for cluster: {1}." -f @("SVMs", $cdotConnection.Name)))
            }

            # Get the key manager backup string...
            try
            {
                $keyManagerBackup = Get-NcSecurityKeyManagerBackup -Controller $cdotConnection -ErrorAction Stop
                Output-NTAPFile -cdotConnection $cdotConnection -type "KeyManager" -data $keyManagerBackup -dateLabel $date -rootPath $destinationPath -OutputString
            }
            catch
            {
                # Nothing to save
            }
        }
    } `
    else
    {
        Out-Logfile "FAILURE: Could not find the cdot file, $cdotClusterListFile."
        [void] $sbErrorMessages.AppendLine(("Could not find the cdot file: {0}." -f @($cdotClusterListFile)))
    }

    $reportBody = "The NetApp configuration backup script run completed."

    # If there were no messages added to $sbErrorMessages, then email an all clear report...
    if ($sbErrorMessages.Length -gt 0)
    {
        Out-LogFile "Sending error report to $sendTo using server $smtpServer."
        $reportBody = $sbErrorMessages.ToString()
    } `
    else    # ... otherwise, send the error report.
    {
        Out-LogFile "Sending all clear (Nothing found) to $sendTo using server $smtpServer."
        # No need to change $reportBody....we initialized it assuming all was good.
    }

    $emailMessage = [System.Net.Mail.MailMessage]::new($from, $sendTo, $subject, $reportBody)
} `
else #End of If log file path check
{
    $emailMessage = [System.Net.Mail.MailMessage]::new($from, $sendTo, "NetApp Backup Script Failure :: Log File Location Not Found", "Could not find log file location $logFileBasePath.")
}

# If an email message was created, send it...
if(($null -ne $smtp) -and ($null -ne $emailMessage))
{
    $smtp.send($emailMessage)
    $smtp.Dispose()
}
