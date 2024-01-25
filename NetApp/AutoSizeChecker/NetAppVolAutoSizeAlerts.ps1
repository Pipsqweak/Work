<#
.SYNOPSIS
Collects volume autosize data and reports on at-risk volumes.

.DESCRIPTION
This script connects to each CDOT cluster and 7-Mode node and gathers volume autosize information. This information is parsed to check for
    any volumes that are near or at the autosize maximum size limit.

.EXAMPLE
.\volAutosizeCheck.ps1

.NOTES
Author: duane.reed@powereng.com
Last revised: 23-Jul-23

Any other notes about the script (revision history, etc.)
Initial version 0.1 (26-Jul-16)

23-Feb-23: KLB Changed the way parameters are provided.
    Going forward, parameters for the script are stored in a .JSON file.
.LINK
An external link if needed. The syntax of comment-based help is available here:
http://technet.microsoft.com/en-us/library/hh847834.aspx
#>

#Configure script command line parameters
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ConfigFile,

    [Parameter(Mandatory=$false)]
    [Switch]
    $EncryptOnly
)

$Script:ontapModule = Get-Module -Name "NetApp.ONTAP"

if (!(Get-Module -Name DataONTAP))
{
    Import-Module DataONTAP
}

# Default Values
$Script:logfile = "E:\Scripts\Logs\Volume Autosize Check\VolAutoSizeCheck.log"
$Script:sendTo = "itstorage@powereng.com"
$Script:from = "cdc-ntapmgmt01@powereng.com"
$Script:subject = "NetApp Volume AutoSize Alerts"
$Script:smtpServer = "smtp.powereng.com"
$Script:subjectFail = "FAILED :: NetApp Volume AutoSize Report"
$Script:failMessages = $null
$Script:netAppCredentials = $null
$Script:alertPercentage = 0.8999

# [KLB: 20200805: Maximum number of times we try 7-mode commands before failing.]
$Script:maxRetries = 4

#Confgure HTML settings
$htmlHeader = "<style>"
$htmlHeader = $htmlHeader + "BODY{background-color:White;}"
$htmlHeader = $htmlHeader + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$htmlHeader = $htmlHeader + "TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color: green}"
$htmlHeader = $htmlHeader + "TD{border-width: 1px;padding: 5px;text-align: center;border-style: solid;border-color: black;background-color: Silver}"
$htmlHeader = $htmlHeader + "</style>"

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

    Param (
        [String]$logText,
        [Switch]$overwrite,
        [string]$type = 1
    )

    # Do nothing if no log file is defined
    if (!$Script:logFile)
    {
        return
    }
    else
    {
        #Create the time stamp for the log entry
        $time = Get-Date -Format HH:mm:ss.fff
        $offset = ([int](Get-Date -Format %z) * -60).ToString().PadLeft(3, "0").PadLeft(4, "+")
        $day = Get-Date -Format MM-dd-yyyy
        try
        {
            $component = $MyInvocation.ScriptName | Split-Path -Leaf -ErrorAction Stop
        }
        catch
        {
            $component = "Interactive"
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
        $string | Out-File  -FilePath $Script:logFile -Force -Encoding utf8 -Append:$(!$overwrite)
    }#End else
}#End Out-Log Function

Function Connect-Cluster
{
    Param (
        $clusters
    )

    $cdotConnections = [System.Collections.Generic.List[Object]]::new()
    foreach ($cluster in $clusters)
    {
        Out-Logfile "Attempting to connect to cluster --> $cluster"

        $useZapiCall = $false

        if($null -ne $Script:ontapModule)
        {
            $useZapiCall = $Script:ontapModule.Version.ToString() -eq "9.11.1.2208"
        }
        if ($useZapiCall)
        {
            $connection = Connect-NcController -Name $cluster -Transient -HTTPS -Credential $Script:netAppCredentials -ZapiCall -ErrorAction Stop -Verbose:$false
        } `
        else # NOT ($useZapiCall)
        {
            $connection = Connect-NcController -Name $cluster -Transient -HTTPS -Credential $Script:netAppCredentials -ErrorAction Stop -Verbose:$false
        }

        if ($connection)
        {
            $cdotConnections.Add($connection)
        }
        else
        {
            #Write-Host "FAILURE: Could not connect to $cluster." -ForegroundColor Red
            Out-LogFile "FAILURE: Could not connect to $cluster."
            $Script:failMessages += "FAILURE: Could not connect to $cluster.`n"
        }
    }

    return $cdotConnections
}

Function Connect-7Mode
{
    Param (
        $nodes
    )

    $smConnections = [System.Collections.Generic.List[Object]]::new()
    foreach ($node in $nodes)
    {
        Out-Logfile "Attempting to connect to 7-mode filer: $node"

        $tries = 0
        $smConnection = $null
        do
        {
            $tries++

            # Changed connection type to RPC, seemed to have constant issues with HTTP and/or HTTPS.
            $smConnection = Connect-NaController -Name $node -Transient -RPC -Credential $Script:netAppCredentials -ErrorAction SilentlyContinue -Verbose:$false
        }
        until(($tries -ge $Script:maxRetries) -or ($null -ne $smConnection))

        if($null -ne $smConnection)
        {
            $smConnections.Add($smConnection)
        } `
        else
        {
            Out-LogFile "FAILURE: Could not connect to 7-Mode node, $node."
            #                Write-Host "FAILURE: Could not connect to 7-Mode node, $node."
            $Script:failMessages += "FAILURE: Could not connect to 7-Mode node, $node.`n"
        }
    }

    return $smConnections
}

Out-LogFile "-----------------------------Starting Volume AutoSize Check-----------------------------" -overwrite #-logfile ("$env:TEMP\"+$MyInvocation.MyCommand.Name+".log")

<#
    Parse the configuration file
#>
$configData = $null
if([System.IO.File]::Exists($ConfigFile))
{
    $configFileContent = [String]::Empty
    try
    {
        $configFileContent = Get-Content -Path $ConfigFile -ErrorAction Stop
    }
    catch
    {
        $message = "Failed to read configuration file: {0}." -f @($ConfigFile)
        Out-LogFile $message
        $Script:failMessages += $message
    }

    if(-not [String]::IsNullOrEmpty($configFileContent))
    {
        try
        {
            $configData = $configFileContent | ConvertFrom-Json -ErrorAction Stop
        }
        catch
        {
            $message = "Failed to parse JSON content from {0}." -f @($ConfigFile)
            Out-LogFile $message
            $Script:failMessages += $message
        }
    }
} `
else
{
    $message = "Configuration file: {0} was not found." -f @($ConfigFile)
    Out-LogFile $message
    $Script:failMessages += $message
}

if($null -ne $configData)
{
    # Update default values with data from the configuration file.
    if(-not [String]::IsNullOrEmpty($configData.LogFile))
    {
        $Script:logfile = $configData.LogFile
    }

    if($null -ne $configData.SendTo)
    {
        $Script:sendTo = $configData.SendTo
    }

    if(-not [String]::IsNullOrEmpty($configData.From))
    {
        $Script:from = $configData.From
    }

    if(-not [String]::IsNullOrEmpty($configData.Subject))
    {
        $Script:subject = $configData.Subject
    }

    if(-not [String]::IsNullOrEmpty($configData.SmtpServer))
    {
        $Script:smtpServer = $configData.SmtpServer
    }

    if($null -ne $configData.Credentials)
    {
        if(-not [String]::IsNullOrEmpty($configData.Credentials.Password))
        {
            if($null -ne $configData.Credentials.Encrypted)
            {
                if(-not $configData.Credentials.Encrypted)
                {
                    # Encrypt the plain-text password and save it back to the config file.
                    $configData.Credentials.Password = ConvertTo-SecureString -String $configData.Credentials.Password -AsPlainText -Force | ConvertFrom-SecureString

                    # Make sure to set .Encrypted to $true so the password doesn't get double encrypted.
                    $configData.Credentials.Encrypted = $true
                    $configData | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile -Force
                }
            } `
            else
            {
                $message = "Credentials in {0} does not contain an 'Encrypted' property." -f @($ConfigFile)
                Out-LogFile $message
                $Script:failMessages += $message
            }

            if(-not [String]::IsNullOrEmpty($configData.Credentials.UserName))
            {
                $Script:netAppCredentials = [System.Management.Automation.PsCredential]::new($configData.Credentials.UserName, ($configData.Credentials.Password | ConvertTo-SecureString))
            } `
            else
            {
                $message = "User name is missing from {0}." -f @($ConfigFile)
                Out-LogFile $message
                $Script:failMessages += $message
            }
        } `
        else
        {
            $message = "Password is missing from {0}." -f @($ConfigFile)
            Out-LogFile $message
            $Script:failMessages += $message
        }
    } `
    else
    {
        $message = "No credentials in {0}." -f @($ConfigFile)
        Out-LogFile $message
        $Script:failMessages += $message
    }
} `
else
{
    # Nothing, already logged a message...
}
<#
    Finished with reading/processing the configuration file.
#>

if (-not $EncryptOnly)
{
    # Create the SMTP client object, after parsing configuration data....might have updated $Script:smtpServer...
    $smtp = [Net.Mail.SmtpClient]::new($Script:smtpServer)

    if($null -ne $Script:netAppCredentials)
    {
        $volCollection = [System.Collections.Generic.List[Object]]::new()

        if(($null -ne $configData.CDOTClusters) -and ($configData.CDOTClusters -is [Array]) -and ($configData.CDOTClusters.Length -gt 0))
        {
            $cdotConnections = Connect-Cluster $configData.CDOTClusters

            if($cdotConnections.Length -gt 0)
            {
                # Create a query to get only volumes with Autosize enabled.
                $queryAttributes = Get-NcVol -Template -Controller $cdotConnections[0]
                Initialize-NcObjectProperty $queryAttributes VolumeAutosizeAttributes
                $queryAttributes.VolumeAutosizeAttributes.IsEnabled = $true

                # Now get all volumes with autosize enabled ... from all the controllers.
                $autoSizeVolumes = Get-NCVol -Query $queryAttributes -Controller $cdotConnections

                if ($autoSizeVolumes.Length -gt 0)
                {
                    foreach ($volume in $autoSizeVolumes)
                    {
                        $percentOfMax = (($volume.TotalSize) / ($volume.VolumeAutosizeAttributes.MaximumSize))

                        if ($percentOfMax -gt $Script:alertPercentage)
                        {
                            $volItem = New-Object System.Object
                            $volItem | Add-Member -MemberType NoteProperty -Name "Node/vServer" -Value $volume.Vserver
                            $volItem | Add-Member -MemberType NoteProperty -Name "volName" -Value $volume.Name
                            $volItem | Add-Member -MemberType NoteProperty -Name "TotalSize (GB)" -Value ([Math]::Round($volume.TotalSize / 1GB))
                            $volItem | Add-Member -MemberType NoteProperty -Name "AutoSizeMaximum (GB)" -Value ([Math]::Round($volume.VolumeAutosizeAttributes.MaximumSize / 1GB))
                            $volItem | Add-Member -MemberType NoteProperty -Name "%OfAutoMax" -Value ((($volume.TotalSize) / ($volume.VolumeAutosizeAttributes.MaximumSize))).ToString("P")

                            $volCollection.Add($volItem)
                        }
                    }
                }
                else
                {
                    $message = "Failed to retrieve any volumes from CDOT cluster $cdotConnection"
                    Out-LogFile $message
                    $Script:failMessages += $message
                }
            } `
            else
            {
                $message = "Not connected to any CDOT clusters provided in {0}" -f @($ConfigFile)
                Out-LogFile $message
                $Script:failMessages += $message
            }
        } `
        else
        {
            $message = "No CDOT clusters provided in {0}" -f @($ConfigFile)
            Out-LogFile $message
            $Script:failMessages += $message
        }

        if(($null -ne $configData.SevenModeNodes) -and ($configData.SevenModeNodes -is [Array]) -and ($configData.SevenModeNodes.Length -gt 0))
        {
            $smConnections = Connect-7Mode $configData.SevenModeNodes

            foreach ($connection in $smConnections)
            {
                Out-Logfile "Getting 7 mode volumes on node $($connection.name)"

                $tries = 0
                do
                {
                    $tries++
                    $7modeVolumes = @(Get-NaVol -Controller $connection -ErrorAction SilentlyContinue)
                }
                until(($7modeVolumes.Count -gt 0) -or ($tries -ge $Script:maxRetries))

                if($7modeVolumes.Length -gt 0)
                {
                    foreach ($7modeVolume in $7modeVolumes)
                    {
                        if ($7modeVolume.Autosize.AutosizeInfo.IsEnabled -eq $true)
                        {
                            $7modePercentOfMax = (($7modeVolume.TotalSize) / ($7modeVolume.Autosize.AutosizeInfo.MaximumSize))

                            if ($7modePercentOfMax -gt $Script:alertPercentage)
                            {
                                $7modeVolItem = New-Object System.Object
                                $7modeVolItem | Add-Member -MemberType NoteProperty -Name "Node/vServer" -Value $connection.Name
                                $7modeVolItem | Add-Member -MemberType NoteProperty -Name "volName" -Value $7modeVolume.Name
                                $7modeVolItem | Add-Member -MemberType NoteProperty -Name "TotalSize (GB)" -Value ([Math]::Round($7modeVolume.TotalSize / 1GB))
                                $7modeVolItem | Add-Member -MemberType NoteProperty -Name "AutoSizeMaximum (GB)" -Value ([Math]::Round($7modeVolume.Autosize.AutosizeInfo.MaximumSize / 1GB))
                                $7modeVolItem | Add-Member -MemberType NoteProperty -Name "%OfAutoMax" -Value ((($7modeVolume.TotalSize) / ($7modeVolume.Autosize.AutosizeInfo.MaximumSize))).ToString("P")

                                $volCollection.Add($7modeVolItem)
                            }
                        }
                    }
                } `
                else
                {
                    $message = "Failed to retrieve any volumes from node: $($connection.Name)"
                    Out-LogFile $message
                    $Script:failMessages += $message
                }
            }
        } `
        else
        {
            $message = "No 7-mode filers provided in {0}" -f @($ConfigFile)
            Out-LogFile $message
            $Script:failMessages += $message
        }

        # Finally, send a report...
        $reportMessage = [System.Net.Mail.MailMessage]::new()
        foreach($recipient in $Script:sendTo)
        {
            $reportMessage.To.Add($recipient)
        }
        $reportMessage.From = [System.Net.Mail.MailAddress]::new($Script:from)
        $reportMessage.Subject = $Script:subject
        $reportMessage.IsBodyHTML = $true

        if ($volCollection.Count -gt 0)
        {
            Out-LogFile "Sending standard report to $sendTo using server $smtpServer."

            #Create aggregate specific message content
            $reportMessage.Body = $volCollection | ConvertTo-Html -Head $htmlHeader
        }
        else
        {
            Out-LogFile "Sending all clear (Nothing found) to $sendTo using server $smtpServer."

            #Create aggregate specific message content
            $reportMessage.Body = "No autogrow issues found. <br /><br /> An error email will still be sent if other errors (such as connect failures, etc) were encountered."
        }

        #Send it!
        $smtp.Send($reportMessage)
    }


    if ($null -ne $Script:failMessages)
    {
        Out-LogFile "Sending failure email message to ($Script:sendTo -join ", ") using server $smtpServer."

        $failMessage = [System.Net.Mail.MailMessage]::new()
        foreach($recipient in $Script:sendTo)
        {
            $failMessage.To.Add($recipient)
        }
        $failMessage.From = [System.Net.Mail.MailAddress]::new($Script:from)
        $failMessage.Subject = "WARNING :: Failures Encountered During NetApp Volume AutoSize Check Script Run"
        $failMessage.IsBodyHTML = $true
        $failMessage.Body = $Script:failMessages

        $smtp.Send($failMessage)
    }

    $smtp.Dispose()
} `
else # NOT (-not $EncryptOnly)
{
    # Nothing.
}
