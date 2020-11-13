# -----------------------------------------------------------------------------
# Script: Remove-RetiredVMs.ps1
# Script File: Remove-RetiredVMs.ps1
# Author: tford-adm Tim Ford
# Company: POWER Engineers
#
# Initial Release: 09/03/2019 11:55:57
# Version 2.1.5.1
#
# Last Revised: 2020-06-17
# Keywords:
#
# Comments: Script to run as a daily task on BDC-MGMT01.
#
# * Performs the following actions:
# * Removes CNAME, PTR, and A records
# * Removes AD computer object
# * Removes VM from SCOM monitoring
# * Remvoes VM from Config Manager DB.
# * Deletes the VM
# * Disposes the VM in Easy Vista
# * Sends email notification of these steps above and lists resources recovered.
#
# Change Log:
#
# 2020-06-17 - version updated to 2.1.5.1 (DW)
#   * Fixed issue with Send-FailureMessage function sending empty mail message instead of error message text
#   - Bug: $message parameter (the body of the email) was being overwritten so the body was always an empty 'MailMessage' object
#   - Fix: Added temp variable $messageBody to store body text then set $message.Body to it
#   * Other minor fixes:
#   - Removed $VMCount from Send-FailureMessage (it was not defined, so always equal to zero)
#   - Reworded email message sent when VM is powered on, also added the message to the log
#   - For powered on VMs, added deletion date to the log and email alert
# -----------------------------------------------------------------------------

#################################################################################################
# Define some variables
#################################################################################################

$startDTM = (Get-Date)
$endDTM = (Get-Date)
$FileDate = (Get-Date -Format MM-dd-yyyy)
$daysago = 30
$LogDate = (Get-Date -Format MM-dd-yyyy-HH-mm)

$Installer = $env:USERNAME
$ScriptVersion = '1.0.0.0'
$ScriptDirectory = 'C:\scripts\VMware'
Set-Location -Path $ScriptDirectory
$verboseLogFile = ('{0}\VMwareLogs\VM-Delete-task-{1}-{2}.log' -f $ScriptDirectory, $Installer, $LogDate )

[string]$DNSserver = 'bdc-dc01'
[string]$ScriptLocation = Get-Location
[string]$MGMTServer = 'boiscomms02'
[string]$From = 'BDC-MGMT01@powereng.com'
#[string]$To = 'ITInfrastructure@powereng.com'
[string]$To = 'ServerDecomNotifications@powereng.com'
[string]$SMTPServer = 'smtp.powereng.com'

# SCCM Specific Site configuration
$SiteCode = "PEI" # Site code
$ProviderMachineName = "BDC-CSS01.powereng.com" # SMS Provider machine name
[string]$SqlServer= "BDC-CSS01.powereng.com"
[string]$Database = 'CM_PEI'
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors
# Do not change anything below this line
# Import the ConfigurationManager.psd1 module

# VCenter Specific
### Credential Info - Change here when putting into production ###
$username = "administrator@vsphere.local"
$WorkingPath=  '\\boifs1\ITxchange\Automation\VMware'
$KeyFile = "$WorkingPath\VMware-AES.key"
$Key = Get-Content $KeyFile
$PasswordFile = "$WorkingPath\vsphereadministrator-key.txt"
$FileDate = (Get-Date -Format MM-dd-yyyy)
Try {
  if (! ($KeyFile)) {
    Write-Warning "No key to access VMware.  Contact your VMware Administrator."
    break
  }

} Catch {
  Write-Warning "No key to access VMware.  Contact your VMware Administrator."
  break
}

# Define the Report header
$vReptHeader = @"
<style type="text/css">
p.detail { color:#4C4C4C;font-weight:bold;font-family:Calibri;font-size:18 }
span.name { color:#FF0000;font-weight:normal;font-family:Calibri;font-size:18 }
greenspan.name { color:#357a16;font-weight:normal;font-family:Calibri;font-size:18 }
bluespan.name { color:#1451c9;font-weight:bold;font-family:Calibri;font-size:20;font-style:italic }
</style>
<style>
TABLE {border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
TR:Hover TD {Background-Color: #e63d2f;}
TH {border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color: #C1D5F8;}
TD {border-width: 1px;padding: 3px;border-style: solid;border-color: black;}
.odd  { background-color:#ffffff; }
.even { background-color:#e9e6d7; }
</style>
<title>
VM Targeted for Deletion
</title>
"@





#################################################################################################
# Define some functions
#################################################################################################

Function Out-LogFile {
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

      .PARAMETER logFile
      The name of the log file where messages will be written.
  #>
  [cmdletbinding()]
  Param (
    [String]$logText,
    [Switch]$overwrite,
    [String]$logFile=$logFile
  )
  #Do nothing if no log file is defined
  if (($logFile -eq $null) -or ($logFile -eq "")) {
    return
  } else {
    #Create the time stamp for the log entry
    $time = Get-Date -Format HH:mm:ss.fff
    $offset = ([int](Get-Date -Format %z)*-60).ToString().PadLeft(3,"0").PadLeft(4,"+")
    $day = Get-Date -Format MM-dd-yyyy
    if($MyInvocation.ScriptName -ne ''){
      $component = $MyInvocation.ScriptName | Split-Path -Leaf
    }else{
      $component =  "ISE or PS Console"
    }
    $string = "<![LOG[$logText]LOG]!>"+
    "<time=`"$time$offset`" "+
    "date=`"$day`" "+
    "component=`"$component`" "+
    "context=`"$env:USERNAME`" "+
    "type=`"1`" "+
    "thread=`"$PID`" "+
    "file=`"$component`">"
    #Write the data to the log file
    Write-Verbose $logText
    $string | Out-File  -FilePath $logFile -Force -Encoding utf8 -Append:$(!$overwrite)
  }#End else
}#End Out-Log Function

Function Write-Logdata {
  <#
      .SYNOPSIS
      Describe purpose of "Write-Logdata" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER message
      Describe parameter -message.

      .EXAMPLE
      Write-Logdata -message Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Write-Logdata

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>
  param(
    [Parameter(Mandatory=$true,HelpMessage='Message quoted string.')]
    [String]$message
  )

  $timeStamp = Get-Date -Format 'MM-dd-yyyy_hh:mm:ss'
  Write-Host -NoNewline -ForegroundColor White ('[{0}]' -f $timestamp)
  Write-Host -ForegroundColor Green (' {0}' -f $message)
  $logMessage = ('[{0}] {1}' -f $timeStamp, $message)
  $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

Function Remove-RetiredVM {
  param($VM)

  # Process VM for deletion.

  $Task = Remove-VM -VM $vm -Confirm:$False -RunAsync -DeletePermanently
  Start-Sleep 5
  Wait-Task -Task $task

  $DeletionStatus = $($task.State)

  If ($DeletionStatus -like '') {
    $DeletionStatus = '(Not Deleted)'
  } Elseif ($DeletionStatus -like 'Running') {

    $DeletionStatus = '(Completed)'
  }

  return $DeletionStatus
}

Function Get-VmDnsRecord {
  <#
      .SYNOPSIS
      Can retrieve and purges DNS A, PTR, and CNAME records.

      .DESCRIPTION
      Function to remove A, PTR, or CNAME records.

      .PARAMETER computershortname
      Shortname of a Virtual Machine.

      .PARAMETER RecordType
      Valid record type or A, PTR, or CNAME.

      .PARAMETER DNSServer
      A Domain Name Service Server like bdc-dc01

      .PARAMETER zonename
      Zonename used such as powereng.com

      .PARAMETER Purgerecord
      The is a switch paramater that when used will purge the record type specified.  If you purge the A record, the PTR records will also be purged.

      .EXAMPLE
      Get-VmDnsRecord -computershortname Value -RecordType Value -DNSServer Value -zonename Value -Purgerecord
      Describe what this call does

      .NOTES
      # -----------------------------------------------------------------------------
      # Script: Get-VmDnsRecord-function.ps1
      # Script File: Get-VmDnsRecord-function.ps1
      # Author: tford-adm Tim Ford
      # Company: POWER Engineers
      # Version: 1.0.0.0
      # Initial Release: 10/14/2019 13:57:00
      # Last Revised: 10/14/2019 13:57:00
      # Keywords:
      #
      # comments:
      #
      #
      # -----------------------------------------------------------------------------

      .LINK
      URLs to related sites
      None

      .INPUTS
      Recordtype, computershortname

      .OUTPUTS
      Results of query

  #>



  param([Parameter(Mandatory=$true,HelpMessage='Enter the computer short name')]
    [string]$computershortname,
    [ValidateSet('A','PTR','CNAME')]
    [Parameter(Mandatory=$true,HelpMessage='Valid type: A, PTR, or CNAME')][string]$RecordType,
    [Parameter(Mandatory=$False)][string]$DNSServer = 'BDC-DC01',
    [Parameter(Mandatory=$False)][string]$zonename = '10.in-addr.arpa',
    [switch]$Purgerecord
  )
  # Start Fresh slate.
  $error.clear()


  $DeleteStatus = @()
  $Results = @()
  $AResults = @()
  $PTRResults = @()
  $CNAMEResults = @()

  Switch ($RecordType) {
    'A' {
      # A Record
      $zonename = "$env:USERDNSDOMAIN"
      $EverythingA_OK = ('{0}' -f $True)
      Try
      {
        #Write-Logdata -message "Getting $RecordType record for $computershortname"
        $DNSArecords = (Get-DnsServerResourceRecord -Name $computershortname  -ComputerName $DNSServer -RRType $RecordType -ZoneName $Zonename -ErrorAction SilentlyContinue)
        #Write-Logdata -message $Arecords
        #$ARecords = $Arecords -join ','

      } Catch {
        $EverythingA_OK = ('{0}' -f $False)
        $ARecords += ('None')
        #Write-Warning ('A Record for {0} does not exist.' -f $computershortname)

      }# Try/Catch

      $Arecord = ''
      $Arecords = @()

      If ($DNSArecords)
      {

        Foreach ($Arecord in $DNSArecords)
        {
          If ($Purgerecord) {

            Write-Logdata -message "Removing $($Arecord.hostname) Arecord $($ARecord.RecordData.ipv4Address.ipaddresstostring) for $computershortname"
            Remove-DnsServerResourceRecord -Name $($Arecord.hostname) -ZoneName $zonename -ComputerName $DNSServer -RRType $RecordType -RecordData $($ARecord.RecordData.ipv4Address.ipaddresstostring)  -Confirm:$False -Force

            If ($?)
            {
              $Arecords += "$($ARecord.hostname):Completed"

            } Else {
              $Arecords += "$($ARecord.hostname):Failed"
            }


          } Else {
            $Arecords += ('{0}' -f $($ARecord.hostname))
          }

        }# Foreach ($Arecord in $ARecords)


      } Else {

        Write-Logdata -message "No $RecordType records"

      }
      return $ARecords


    }# A

    'PTR'{
      # PTR Record # Test  Has 4 records kck44377ll.powereng.com

      #$PTRRecordsToRemove = @()
      $ZoneFirstOctet = $ZoneName.Split(".")[0]
      $EverythingPTR_OK = ('{0}' -f $True)
      Try {
        #Write-Host "Getting $RecordType record for $computershortname" -ForegroundColor Yellow

        $DNSPTRrecords = Get-DnsServerResourceRecord  -ZoneName $ZoneName -ComputerName $DNSServer -RRType $RecordType -ThrottleLimit 25 | Select-Object Hostname, RecordType,timestamp, @{Name='RecordData';Expression={$_.RecordData.PtrDomainName}} | Where-Object {$_.RecordData -like "$($computershortname)*"}


      } Catch {
        $EverythingPTR_OK = ('{0}' -f $False)
        $PTRrecords += 'None'
        #Write-Warning "PTR Record(s) for $computershortname not found."
      }

      <#
          Hostname   RecordType timestamp RecordData
          --------   ---------- --------- ----------
          140.80.247 PTR                  ddct-rhel700.powereng.com.
          148.80.247 PTR                  ddct-rhel700.powereng.com.
      #>

      $PTRrecord = ''
      $PTRrecords = @()

      If ($DNSPTRrecords)
      {
        Foreach ($PTRrecord in $DNSPTRrecords)
        {
          If ($Purgerecord)
          {

            Write-host "Removing $($PTRrecord.hostname) PTR record for $computershortname" -ForegroundColor Yellow
            Remove-DnsServerResourceRecord -ZoneName $zonename -ComputerName $DNSServer -RRType $RecordType -Name $($PTRrecord.Hostname) -Confirm:$False -Force

            If ($?)
            {
              $PTRIP = $ZoneFirstOctet+"."
              $SPlit = $PTRrecord.HostName.Split(".")
              for($i=1;$i -le 3;$i++)
              {
                $PTRIP +=$SPlit[-$i]+"."
              }
              $PTRIP = $PTRIP.Substring(0,$PTRIP.Length-1)

              $PTRrecords += ('{0}:Completed' -f $PTRIP)

            } Else {
              $PTRrecords += ('{0}:Failed' -f $PTRIP)
            }



          } Else {   # Purgerecord

            # Convert to IP address
            $PTRIP = $ZoneFirstOctet+"."
            $SPlit = $PTRrecord.HostName.Split(".")
            for($i=1;$i -le 3;$i++)
            {
              $PTRIP +=$SPlit[-$i]+"."
            }
            $PTRIP = $PTRIP.Substring(0,$PTRIP.Length-1)

            $PTRrecords += $PTRIP

          }


        }

      } Else  {
        Write-Logdata -message "No $RecordType records"
        $PTRrecords = 'None'
      }

      return $PTRrecords


    }# PTR

    'CNAME' {
      # CNAME Record

      $zonename = "$env:USERDNSDOMAIN"
      $EverythingCNAME_OK = ('{0}' -f $True)

      $CNAMErecord = ''
      $DNSCNAMERecords = ''
      $CNAMErecords = @()

      Try {
        #Write-Logdata -message "Getting CNAME record for $computershortname"
        $DNSCNAMERecords = (Get-DnsServerResourceRecord -ZoneName $zonename -ComputerName $DNSServer -RRType "CName"  |
          Select-Object HostName,RecordType,Timestamp,TimeToLive,
          @{Name='RecordData';Expression={$_.RecordData.HostNameAlias.ToString()}} |
        Where-Object {$_.RecordData -match $Computershortname})
        #$CNAMErecords = $CNAMErecords -join ','
        #Write-Logdata -message $CNAMErecords

      } Catch {
        $EverythingCNAME_OK = ('{0}' -f $False)
        $CNAMErecords += 'None'
        #Write-Warning "CNAME Record for $computershortname does not exist. Or this more than one CNAME record."
      }
      <#        Foreach ($CNAMErecord in $DNSCNAMERecords) {
          $CNAMErecords += ('{0}' -f $CNameRecord.Hostname)
      }#>

      If ($DNSCNAMERecords)
      {

        Foreach ($CNAMErecord in $DNSCNAMERecords)
        {

          If ($Purgerecord)
          {

            Write-host "Removing $($CNAMErecord.hostname) CNAME record for $computershortname" -ForegroundColor Yellow
            Remove-DnsServerResourceRecord -ZoneName $zonename -ComputerName $DNSServer -RRType $RecordType -Name $($CNAMErecord.hostname) -Confirm:$False -Force

            If ($?)
            {
              $CNAMErecords += ('{0}:Completed' -f $($CNAMErecord.hostname))

            } Else {
              $CNAMErecords += ('{0}:Failed' -f $($CNAMErecord.hostname))
            }


          } Else {
            $CNAMErecords += ('{0}' -f $CNameRecord.Hostname)
          }


        }


      } Else {
        Write-Logdata -message "No $RecordType records"
      }

      return $CNAMErecords

    }# CNAME

  }# Switch $RecordType

}# End Function Get-VmDnsRecord

Function Get-VMSerialNumber {
  param([Parameter(Mandatory=$true,HelpMessage='Enter the VM name.')][String]$VM

  )
  New-VIProperty -Name BIOSNumber -ObjectType VirtualMachine -Value {
    [CmdletBinding()]
    param($vm)

    $s = ($vm.ExtensionData.Config.Uuid).Replace("-", "")
    $Uuid = "VMware-"
    for ($i = 0; $i -lt $s.Length; $i += 2)
    {
      $Uuid += ("{0:x2}" -f [byte]("0x" + $s.Substring($i, 2)))
      if ($Uuid.Length -eq 30) { $Uuid += "-" } else { $Uuid += " " }
    }
    $Uuid.TrimEnd()
  } -Force | Out-Null


  $VM = Get-VM -Name $VM

  $VMSerial = (Get-VM $VM | Select-Object Name,BIOSNumber).BIOSNumber

  return $VMSerial

}#Function Get-VMSerialNumber

Function Get-VMOsName {
  param([Parameter(Mandatory=$true,HelpMessage='Enter the VM name.')][String[]]$VM

  )
  # Setup new VI property to get OSname
  $null = New-VIProperty -Name 'OSName' -ObjectType VirtualMachine -Value {
    [CmdletBinding()]
    param($vm)
    $vm.ExtensionData.Guest.GuestFullName
  } -BasedOnExtensionProperty 'Guest.GuestFullName' -Force

  $VMOsName = (Get-VM -name $VM |Select-Object OSname).OSName

  IF (!($VMOsname)) {
    $VMOsName = (Get-VM -name $VM  | Select @{N='Configured OS';E={$_.ExtensionData.Config.GuestFullname}}).'Configured OS'
  }

  return $VMOsName

}#Function

Function Set-VMMonitorMaintenceMode {
  [CmdletBinding()]
  Param(
    [string[]]$AgentComputerName,
    [string]$MSServer = 'Boiscomms02'
  )

  If (! ($AgentComputerName -like '*.powereng.com') ){
    $AgentComputerName = ('{0}.powereng.com' -f ($AgentComputerName))
  }

  New-SCManagementGroupConnection -ComputerName $MSServer

  $Class = Get-SCClass | where-object {$_.Name -eq "Microsoft.Windows.Computer"}
  #$ClassID = $Class.Id
  #$ClassMgmtGrp = $Class.ManagementGroup

  $agentWatcherClass = Get-SCClass -name:Microsoft.SystemCenter.AgentWatcher
  $healthServiceWatcherClass = Get-SCClass -name:Microsoft.SystemCenter.HealthServiceWatcher

  $StartTime = [DateTime]::Now.ToUniversalTime()
  $EndTime = $StartTime.AddMinutes(45000) # 45000 equal to 4.46 weeks.
  $Reason = "PlannedOther"
  $Comments = "Putting Servers in Maint mode for 4.5 weeks as it is being retired."
  $Instance = Get-SCOMClassInstance -Class $Class | Where-Object {$_.Displayname -eq ('{0}' -f $AgentComputerName)}
  $instance
  $null = Start-SCOMMaintenanceMode -Instance $Instance -Reason $Reason -EndTime $endTime -Comment $Comments
  $result = (Get-SCOMClassInstance -Class $Class | Where-Object {$_.Displayname -eq ('{0}' -f $AgentComputerName)}).InMaintenanceMode

  return $result

} # Function Remove-AgentMangedComputer

Function Get-VMMonitorMaintenceMode {
  [CmdletBinding()]
  Param(
    [string[]]$AgentComputerName,
    [string]$MSServer = 'Boiscomms02'
  )

  If (! ($AgentComputerName -like '*.powereng.com') ){
    $AgentComputerName = ('{0}.powereng.com' -f ($AgentComputerName))
  }

  New-SCManagementGroupConnection -ComputerName $MSServer

  $Class = Get-SCClass | where-object {$_.Name -eq "Microsoft.Windows.Computer"}
  #$ClassID = $Class.Id
  #$ClassMgmtGrp = $Class.ManagementGroup

  #$agentWatcherClass = Get-SCClass -name:Microsoft.SystemCenter.AgentWatcher
  #$healthServiceWatcherClass = Get-SCClass -name:Microsoft.SystemCenter.HealthServiceWatcher

  #$StartTime = ([DateTime]::Now).ToUniversalTime()
  #$EndTime = $StartTime.AddMinutes(45000) # 45000 equal to 4.46 weeks.
  #$Reason = "PlannedOther"
  #$Comments = "Putting Servers in Maint mode for 4.5 weeks as it is being retired."
  $Instance = Get-SCOMClassInstance -Class $Class | Where-Object {$_.Displayname -eq ('{0}' -f $AgentComputerName)}
  $instance
  #$null = Start-SCOMMaintenanceMode -Instance $Instance -Reason $Reason -EndTime $endTime -Comment $Comments
  $result = (Get-SCOMClassInstance -Class $Class | Where-Object {$_.Displayname -eq ('{0}' -f $AgentComputerName)}).InMaintenanceMode

  return $result

} # Function Remove-AgentMangedComputer

Function Remove-AgentManagedComputer {
  [CmdletBinding()]
  Param(
    [string[]]$AgentComputerName,
    [string]$MSServer
  )

  $deleteCollection = $null

  $null = [System.Reflection.Assembly]::Load("Microsoft.EnterpriseManagement.Core, Version=7.0.5000.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35")
  $null = [System.Reflection.Assembly]::Load("Microsoft.EnterpriseManagement.OperationsManager, Version=7.0.5000.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35")

  function New-Collection ( [type] $type )
  {
    $typeAssemblyName = $type.AssemblyQualifiedName;
    $collection = new-object ("System.Collections.ObjectModel.Collection``1[[{0}]]" -f $typeAssemblyName)
    return ,($collection)
  }

  # Connect to management group
  Write-output "Connecting to management group"

  $ConnectionSetting = New-Object Microsoft.EnterpriseManagement.ManagementGroup($MSServer)
  $admin = $ConnectionSetting.GetAdministration()


  Write-output "Getting agent managed computers"
  $agentManagedComputers = $admin.GetAllAgentManagedComputers()

  # Get list of agents to delete
  foreach ($name in $AgentComputerName)
  {
    Write-output ('Checking for {0}' -f $name)
    foreach ($agent in $agentManagedComputers)
    {
      if ($deleteCollection -eq $null)
      {
        $deleteCollection = new-collection $agent.GetType()
      }


      if (@($agent.PrincipalName -eq $name))
      {
        Write-output ('Matched {0}' -f $name)
        $deleteCollection.Add($agent)
        break
      }
    }
  }

  if ($deleteCollection.Count -gt 0)
  {
    Write-output "Deleting agents"
    $admin.DeleteAgentManagedComputers($deleteCollection)
    if($?){ Write-output "Agents deleted" }
  }
} # Function Remove-AgentMangedComputer

Function Set-AlternatingRows {
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
    [object[]]$HTMLDocument,

    [Parameter(Mandatory=$True)]
    [string]$CSSEvenClass,

    [Parameter(Mandatory=$True)]
    [string]$CSSOddClass
  )
  Begin {
    $ClassName = $CSSEvenClass
  }
  Process {
    [string]$Line = $HTMLDocument
    $Line = $Line.Replace("<tr>","<tr class=""$ClassName"">")
    If ($ClassName -eq $CSSEvenClass)
    {    $ClassName = $CSSOddClass
    }
    Else
    {    $ClassName = $CSSEvenClass
    }
    $Line = $Line.Replace("<table>","<table width=""70%"">")
    Return $Line
  }
}



Function Send-FailureMessage {
  Param([Parameter(Mandatory=$true,HelpMessage='Add a message for your user')]$message)
  [string]$From = 'BDC-MGMT01@powereng.com'
  [string]$To = 'ITInfrastructure@powereng.com'
  [string]$SMTPServer = 'smtp.powereng.com'
  #[string]$To = 'timothy.ford@powereng.com'
  $messageBody = $message

  $message = New-Object System.Net.Mail.MailMessage $from, $To
  $smtp = New-Object Net.Mail.SmtpClient($smtpServer)

  # Send a message on script failures.
  $subject = "Notification: VM deletion script failure. [Script Time:] $([math]::Round(($endDTM-$startDTM).totalminutes,2)) minutes."
  # Create specific message content
  $message.Subject = $subject
  $message.Body = ($messageBody | Out-String)
  $message.IsBodyHTML = $true

  #Send it!
  $smtp.Send($message)#>

}

#################################################################################################
# Start some functions
#################################################################################################

# Start of Logging.
Write-Logdata -message "Script Version: $ScriptVersion"

# Start with a fresh screeen and 0 errors
Clear-Host
$error.clear()

# Define EasyVista production environment.
$EVEnvironment = 'Prod'

# Import the EasyVista module.
Write-Logdata -message 'Importing EasyVista Module'
Import-module power-eng.easyvista

# Connect to appropriate EasyVista Environment.
Write-Logdata -message "Connecting to EasyVista $EVEnvironment environment."
Connect-EasyVista -EVEnvironment $EVEnvironment

If (!(get-module -name VMware.VimAutomation.Core)) {
  Import-Module -Name VMware.VimAutomation.Core
  ## Install-Module VMware.PowerCLI -Scope AllUsers -AllowClobber
} Else {
  Write-Verbose -Message "VMware.VimAutomation.Core module found."
}

Write-Logdata -message 'Setting PowerCLI Configuraion to user scope.'
$null = Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $False -Confirm:$False -ErrorAction SilentlyContinue

$VCS = ''
[array]$VCS = ('vcenter.powereng.com')

Write-Logdata -message 'Removing current vCenter connections if they exist'
Try {Disconnect-VIServer * -Confirm:$false -ErrorAction SilentlyContinue }
# NOTE: When you use a SPECIFIC catch block, exceptions thrown by -ErrorAction Stop MAY LACK
# some InvocationInfo details such as ScriptLineNumber.
# REMEDY: If that affects you, remove the SPECIFIC exception type [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException] in the code below
# and use ONE generic catch block instead. Such a catch block then handles ALL error types, so you would need to
# add the logic to handle different error types differently by yourself.
catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException]
{
  <#
      # get error record
      [Management.Automation.ErrorRecord]$e = $_

      # retrieve information about runtime error
      $info = [PSCustomObject]@{
      Exception = $e.Exception.Message
      Reason    = $e.CategoryInfo.Reason
      Target    = $e.CategoryInfo.TargetName
      Script    = $e.InvocationInfo.ScriptName
      Line      = $e.InvocationInfo.ScriptLineNumber
      Column    = $e.InvocationInfo.OffsetInLine
      }

      # output information. Post-process collected info, and log info (optional)
      $info
  #>
} Catch {}

#################################################################################################
# Import SCCM Module
#################################################################################################
Write-Logdata -message 'Importing ConfigurationManager Module'
if((Get-Module ConfigurationManager) -eq $null) {
  Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams
}

# Connect to the site's drive if it is not already present
Write-Logdata -message "Creating new $Sitecode PSdrive."
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
  New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}


#################################################################################################
# Test/Connect Credential for VMware Access
#################################################################################################
# Get the contents of the encrypted secure string file by using the provided key.
Try {

  If (Test-Path $PasswordFile -PathType Leaf) {
    # Access the encrypted password file using the key.
    $Password = Get-Content $PasswordFile | ConvertTo-SecureString -Key $key

    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    # Free the BSTR when finishing the call.
    $BSTR = $null
  }

} Catch {
  Write-Logdata -message 'The key cannot be obtained.  Check that the VMware-AES.key and vsphereadministrator-key.txt file exist.'
  Send-FailureMessage -message 'The key cannot be obtained.  Check that the VMware-AES.key and vsphereadministrator-key.txt file exist.'
  break
}

Write-Logdata -message "Setting up credential for $username"
$credential = New-Object System.Management.Automation.PSCredential $username,$password

$VCServer = 'vCenter.powereng.com'
Write-Logdata -message "Connecting to $VCServer"
Try {$null = Connect-VIServer -Server $VCServer -Credential $credential} Catch {}

#################################################################################################
# Get list of systems that have tag assignments "MarkedForDeletion" and have a deletion-date
# assigned.
#################################################################################################

#Write-Logdata -message ('Connecting to rCisServer {0}.' -f $VCServer)
Write-Logdata -message "Connecting to rCIisServer for Tags"
$null = Connect-rCisServer -Server $VCServer -Credential $credential #$Creds

Write-Logdata -message "Scrub VMs from the past $daysago days"

# This gets all VMs that have a Deletion-Date Attribute.
Write-Logdata -message "Getting VMs that have a Deletion-Date attribute and are tagged with a Marked-For-Deletion"
$eolsystems = (Get-rCisTagAssignment -Category Deletion-Date).entity

#################################################################################################
# Filter systems for testing.
#################################################################################################
### Prod Comment: For testing a single VM. ###
# Comment the next line to remove the single VM filter.
#Write-Logdata -message "Filtering on a single VM (comment out when done testing)"
#$eolsystems = $eolsystems | Where-Object {$_ -like 'segaslx.segainc.com'}


#################################################################################################
# Loop through all end of life systems.
#################################################################################################

foreach ($ComputerShortname in $eolsystems) {

  # One last check to make sure the system being deleted is powered off.  If it is powered
  # on then we need to just send an email.
  $pwCheck = Get-VM -Name $ComputerShortname | Where-Object {$_.PowerState -eq 'PoweredOff'}

  If ($pwCheck)
  {
    $Rept = @()
     # reset variables per system processed
    [string]$To = 'ITInfrastructure@powereng.com'
    $null = $additionalnotifyemail
    $null = $message
    $null = $Requestor
    $null = $DelDate

    [string]$FQDNComputername = ('{0}.powereng.com' -f ($ComputerShortname))


    # Get custom annotations that have dates populated in the DeletionDate attribute.
    Write-Logdata -message "Getting $ComputerShortname DeletionDate custom attribute"
    # Get DeleteDate from vCenter
    $DelDate = (Get-Annotation -Entity $ComputerShortname -CustomAttribute DeletionDate).Value
    $DeleteDate = Get-Date $DelDate

    # Get who requested the VM be deleted.
    $Requestor = (Get-Annotation -Entity $ComputerShortname -CustomAttribute DeleteRequestedBy).Value

    # Delete Request Date
    $DeleteRequestDate = (Get-Annotation -Entity $ComputerShortname -CustomAttribute DeleteRequestDate).Value

    $additionalnotifyemail   = (Get-Annotation -Entity $ComputerShortname -CustomAttribute Additional-Notification-Email).Value
    # Renew the $message with additional contacts in the $to variable.
    if($additionalnotifyemail){
      Write-Logdata -message "Adding  $additionalnotifyemail to the send to address."
      $to += ",$additionalnotifyemail"
    }

    $message = New-Object System.Net.Mail.MailMessage $from, $To
    $smtp = New-Object Net.Mail.SmtpClient($smtpServer)

    Write-Logdata -message "Getting $ComputerShortname notes."
    $VMNotes = Get-VM $ComputerShortname | Select-Object -ExpandProperty Notes
    If (! ($VMNotes)) {
      Write-Logdata -message "No notes present on $ComputerShortname"
      $VMNotes = 'No notes present'
    }


    Write-Logdata -message "Days until deletion $(($deleteDate - $startDTM).days)"

    If (($deleteDate - $startDTM).days -lt 1) {

      Write-Logdata -message "Getting $ComputerShortname details."
      $vm = Get-VM -name $ComputerShortname

      # Get VM IP address.
      $IPAddress =  (Get-VmDnsRecord -computershortname $ComputerShortname -RecordType PTR -DNSServer $DNSserver) -join ','
      If ($null -eq $IPAddress -or $IPAddress.Length -lt 10 ) {
        $IPAddress = 'None available'
      }


      $ResourcesUsed =  $VM | Select-Object NumCpu, MemoryGB,@{n='ProvisionedGB';e={[math]::Round($_.ProvisionedSpaceGB)}}, @{n='UsedGB';e={[math]::Round($_.UsedSpaceGB)}}
      #$ResourcesUsed | ConvertTo-Html -Property NumCpu, MemoryGB, ProvisionedGB, UsedGB -Fragment -As Table

      Write-Logdata -message "Formatting the resources results output as HTML."
      $VMResources = $ResourcesUsed | ConvertTo-Html -Property NumCpu, MemoryGB, ProvisionedGB, UsedGB -Fragment -As Table

      #$VMid = $vm.Id.ToString().split('VirtualMachine-VM-')[-1]
      $OperatingSystem = Get-VMOsName -VM $ComputerShortname

      If ($OperatingSystem -like 'Microsoft Windows*') {

        $Ostype = 'Windows'
        Write-Logdata -message "OS Type is $Ostype"

      } Elseif ($OperatingSystem -notlike 'Microsoft Windows*' ) {
        $Ostype = 'Linux'
        Write-Logdata -message "OS Type is $Ostype"
      }

      Switch ($Ostype) {
        'Windows' {

          # Setup query of system from CM database
          $SQLQuery = @"
        use CM_PEI
        select
	        --*
	        v_GS_LocalGroupMembers0.Account0
	        ,v_R_System.Name0
        from
	        v_GS_LocalGroupMembers0
	        left join v_R_System on v_GS_LocalGroupMembers0.ResourceID = v_R_System.ResourceID
        where
	        (
		        v_GS_LocalGroupMembers0.Domain0 = 'SEGA'
		        or v_GS_LocalGroupMembers0.Domain0 = 'POWERENG'
	        )
	        and v_R_System.Name0 = '$ComputerShortname'
	        and v_GS_LocalGroupMembers0.Name0 = 'Administrators'
"@
          # Invoke the SQL query.
          Write-Logdata -message ('Executing SQL query for local administrators of {0}.' -f $ComputerShortname)
          $SQLResults = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $Database -Query $SQLQuery -QueryTimeout 5 -OutputSqlErrors:$true # -Username 'powereng\SRVC-VMSERVERDECOM' -Password 'wHXQH*495W2e'

          $Data = $SQLResults | ForEach-Object {
            $row = $_;
            New-Object -TypeName PSobject -Property @{
              Account = $row.item("Account0")
              Name = $row.item("Name0")
            }
          }
          #$Data

          If ($Data) {
            $results = ($Data | Select-Object Name,Account | Out-String)
            Write-Logdata -message "Formatting the sql results output as HTML."
            $Admins = [PSCustomobject]$Data| ConvertTo-Html -Fragment -As Table -Property Name, Account
            Write-Logdata -message ('Admins: {0}' -f $Admins)
            $GroupCleanupStatus = 'Pending'
            $GrpCleanupCol = 'Span'

          } Else {
            Write-Logdata -message ('No Admins found')
            $AdminUsers = New-Object -TypeName PSObject
            $AdminUsers | Add-Member -MemberType NoteProperty -Name Name -Value 'None'
            $AdminUsers | Add-Member -MemberType NoteProperty -Name Account -Value 'None'

            #$Admins =  $AdminUsers | ConvertTo-Html -Fragment -As Table -Property Name, Account

            $GroupCleanupStatus = 'Completed'
            $Results = 'None'
            $GrpCleanupCol = 'greenspan'
          }


          If (! ($SQLResults.account0)) {
            #Write-Logdata -message  ('No Admin accounts present: {0}' -f $($SQLResults.account0))
            $SQLResults = 'None'
            $results = 'None'
          }

          # Display results of query
          Write-Logdata -message ('Results of query {0}.' -f $results)
          #Write-Host "Results of query: $results" -ForegroundColor Yellow



        }# Windows

        'Linux'{
          <#
              $Adobject = ''
              Write-Logdata -message "Checking for $ComputerShortname AD object"
              Try
              {
              $Adobject = (Get-ADComputer -Identity $ComputerShortname).DistinguishedName
              Remove-ADObject -Identity $Adobject -Confirm:$False
              Write-Logdata -message "Removing $ComputerShortname AD object"
              Write-Logdata -message ('Adobject DistinquishedName:{0}' -f $Adobject)
              $adobjectdelstatus = "Completed"
              }
              Catch
              {
              Write-Logdata -message "No AD object for this Linux record"
              $Adobject = 'No Record'
              $adobjectdelstatus = "Completed"
              }
          #>
          $Results = 'Non Windows server'
          $GrpCleanupCol = 'Span'
          $GroupCleanupStatus = 'No AD Groups'

        }# Linux
      }# Switch

      # Steps below do not depend on the OS flavor.

      # AD ojbect cleanup
      $Adobject = ''
      Try {
        Write-Logdata -message "Checking on existence of an AD object for $ComputerShortname"
        $Adobject = (Get-ADComputer -Identity $ComputerShortname).DistinguishedName

        If (!($null -eq $Adobject))
        {
          $ADdelStatus = Remove-ADObject -Identity $Adobject -Confirm:$False -ErrorAction SilentlyContinue
          if($?)
          {
            Write-Logdata -message ('Successfully removed: {0}' -f $Adobject)
            $adobjectdelstatus = "Completed"
          }
          Else
          {
            Write-Logdata -message ('Failed to removed: {0}' -f $Adobject)
            $adobjectdelstatus = "Failed"
          }

        }
        Else
        {
          Write-Logdata -message ('Adobject DistinquishedName:{0}' -f $Adobject)
          Write-Logdata -message 'No AD object to delete.'
          $Adobject = 'None'
        }# If ($Adobject)

      }
      Catch
      {
        $Adobject = 'None'
        $adobjectdelstatus = 'Completed'
      }





      #Write-Logdata -message ('Setting the script location to {0}.' -f $ScriptLocation)
      Set-Location $ScriptLocation

      # Remove from CM Database
      $Currentpath = Get-Location  # Set the current location to be the site code.
      Write-Logdata -message "Setting directory location to $SiteCode"
      Set-Location "$($SiteCode):\" @initParams

      # Get the CM Device From SCCM
      $removeCMstatus = ''
      Try {
        Write-Logdata -message "Checking on device in CM"
        $removeCMstatus = Get-CMDevice -Name $ComputerShortname
      } Catch {
        Write-Logdata -message "No device present in Config Manager"
        $removeCMstatus = $Null
      }

      # Removes the Device from SCCM
      If (! ($null -eq $removeCMstatus)) {
        Write-Logdata -message "Removing $ComputerShortname from CM"
        $removeCMstatus =  Remove-CMDevice -Name $ComputerShortname -Confirm:$False -Force
        $removeCMstatus = '(Completed)'
      } Else {
        $removeCMstatus = '(None) (Completed)'
      }

      # Set Location Back to original path.
      Write-Logdata -message "Setting directory back to $Currentpath"
      Set-Location -Path $Currentpath


      # Check if the system is being monitored by SCOM and if it is, remove it.
      Write-Logdata -message ('Checking if {0} is in SCOM.' -f $ComputerShortname)
      $MonitorTest = Get-VMMonitorMaintenceMode -AgentComputerName $FQDNComputername -MSServer $MGMTServer

      If ($MonitorTest -eq $False) {
        # First enter maintenance mode if not already set.
        Write-Logdata -message "Putting SCOM $ComputerShortname into maintenance mode"
        Set-VMMonitorMaintenceMode -AgentComputerName $FQDNComputername -MSServer $MGMTServer
        Write-Logdata -message "Removing $ComputerShortname from SCOM"
        $removeTask = Remove-AgentManagedComputer -AgentComputerName $FQDNComputername -MSServer $MGMTServer

      } Elseif ($MonitorTest -eq $True) {

        # Used to remove the agent at time of deletion.
        Write-Logdata -message "Removing $ComputerShortname from SCOM"
        $removeTask = Remove-AgentManagedComputer -AgentComputerName $FQDNComputername -MSServer $MGMTServer

      } Else {
        Write-Logdata -message "$ComputerShortname not in SCOM"
        $RemoveTask = '(Not in SCOM)'
      }


      If ($removeTask.count -eq '3') {
        $RemoveTask = '(Not in SCOM)'
        Write-Logdata -message ('{0} Not in SCOM' -f $ComputerShortname)
      } Else {
        Write-Logdata -message ('{0} removed from SCOM' -f $ComputerShortname)
        $RemoveTask = '(Completed)'
        Write-Logdata -message  ('{0} Status: {1}' -f $FQDNComputername, $RemoveTask)
      }


      # Cleanup DNS Records.
      #$DNSCleanupReport = @()

      Write-Logdata -message "Checking CNAME record for $ComputerShortname"
      $CNAMECleanup = (Get-VMDnsRecord -computershortname $ComputerShortname -DNSServer $DNSserver  -RecordType CNAME -Purgerecord)

      If (! ($Null -eq $CNAMECleanup))
      {
        $CNAMECleanup = $CNAMECleanup -join ','
      }
      Else
      {
        $CNAMECleanup = 'None'
      }
      #Write-Logdata -message $CNAMECleanup


      Write-Logdata -message "Checking PTR record for $ComputerShortname"
      $PTRCleanup = (Get-VMDnsRecord -computershortname $ComputerShortname -DNSServer $DNSserver -RecordType PTR -Purgerecord)

      If (! ($null -eq $PTRCleanup))
      {
        $PTRCleanup = $PTRCleanup -join ','

      } Else {

        $PTRCleanup = 'None'
      }

      #Write-Logdata -message $PTRRecord
      Write-Logdata -message "Checking A record for $ComputerShortname"
      $ACleanup = (Get-VMDnsRecord -computershortname $ComputerShortname -DNSServer $DNSserver -RecordType A -Purgerecord)

      If (! ($null -eq $ACleanup))
      {
        $ACleanup = $ACleanup -join ','

      } Else {

        $ACleanup = 'None'
      }

      # Check for existence in EasyVista
      Write-Logdata -message "Checking EasyVista record for $ComputerShortname"

      Try
      {
        $AssetDetail = Get-EVAssetDetailByAssetName -evHostname $ComputerShortname.Split('.')[0] -evOption ALL-Data
      }
      Catch
      {
        Write-Logdata -message "No Asset info found for $ComputerShortname"
      }

      If (! ($AssetDetail -eq '---'))
      {

        Write-Logdata -message "Checking EasyVista AssetID record for $ComputerShortname"
        $AssetID =  Get-EVAssetDetailByAssetName -evHostname $ComputerShortname.Split('.')[0] -evOption ASSET_ID

        If (!($null -eq $AssetID))
        {
          Write-Logdata -message "EasyVista record found for $ComputerShortname"
          $bAssetisPresent = $true

          $AssetTag = Get-EVAssetDetailByAssetName -evhostname $ComputerShortname.Split('.')[0] -evOption ASSET_TAG

          # Mark asset as disposed.
          Write-Logdata -message "Disposing of EasyVista record for $ComputerShortname"
          $EVStatus = Update-EVAsset -evAssetName $ComputerShortname.Split('.')[0] -evIsCI 1 -evCIStatusID 4 -evStatusID 7 -evNotes "Asset disposed on $DeleteDate via automated retirement process." -evReleaseGrp 3 -evCustomer (Get-EVEmployee -evEmployeeName 'Folz, Jeff' -evReturnData EmployeeID) -Discard
        }
        Else
        {
          Write-Logdata -message "No EasyVista record for $ComputerShortname"
          $AssetID = 'Not Found'
        }

        Write-Logdata -message "Checking EasyVista notes/comments for $ComputerShortname"
        $AssetNotes = Get-EVAssetComment -evAssetID $AssetID
        $AssetNotes = $AssetNotes += "`nAsset disposed on $DeleteDate via automated retirement process."


        If ($bAssetisPresent)
        {
          $NewEVStatus = Get-EVAssetDetailByAssetName -evHostname $ComputerShortname.Split('.')[0] -evOption ASSET_ID
          if ($NewEVStatus)
          {
            $NewEVStatus = 'Completed'
          }
        }

        Else
        {
          $NewEVStatus = 'Record does not exist'
        }

      }
      Else
      {
        $AssetDetail = 'None'
        $NewEVStatus = 'Completed'

      }


      Write-Logdata -message "Deleting $ComputerShortname from vCenter"
      #>
      ### Prod Comment: Remove < from above when ready for production. ###
      $RemoveVMStatus = Remove-RetiredVM -VM $ComputerShortname

      #>
      If ($null -eq $RemoveVMStatus)
      {
        $RemoveVMStatus = '(VM does not exist)'

      }

      $DeletionInfo = New-Object -TypeName PSObject -Property @{
        'Virtual Machine' = $ComputerShortname
        'Deletion Date' = (get-date -format MM/dd/yyyy)
        'IP Address' = $IPAddress
        'Operating System' = $OperatingSystem
        #'AssetID' = $AssetID
        #'AssetTag' = $AssetTag
        'Notes' = $VMNotes

      }
      $Rept += $DeletionInfo

      $ReportCsv = "$($ComputerShortname)_VM_To_Delete_$($FileDate).csv"
      Write-Logdata -message "Creating report Csv $ReportCsv"

      $Reporthtml = "$($ComputerShortname)_VM_To_Delete_$($FileDate).html"
      Write-Logdata -message "Creating report Html $Reporthtml"

      [string]$PathToReport='C:\scripts\VMware\VMwareLogs\DeletedVMs'

      $PreContent = @"
      <td style="width:427px;">
        <h3 style="color:#e63d2f";margin-bottom:-10px;>The following Virtual Machine has been deleted.</h3>
        <p style="color:#00A651"></p>
      </td>
"@

      $WindowAdminContent

      $PostContent = @"
      <DIV ALIGN=LEFT>Date Submitted: <b> $($DeleteRequestDate) </b></br></p></DIV><DIV ALIGN=Left>Submitted By: <b>$Requestor </b></br></DIV>

        <p class="detail"><bluespan class="name">Tasks completed today:</bluespan> </p>
        <UL>
            <LI><p class="detail">Cleanup AD object record: ($($ADObject)) <greenspan class="name">($($adobjectdelstatus))</span> </p>
            <LI><p class="detail">Delete A records from DNS <greenspan class="name">($($ACleanup))</span> </p>
            <LI><p class="detail">Delete PTR records from DNS <greenspan class="name">($($PTRCleanup))</span> </p>
        	<LI><p class="detail">Delete CNAME records from DNS <greenspan class="name">($($CNAMECleanup))</span> </p>
            <LI><p class="detail">Delete the VM <greenspan class="name">$($RemoveVMStatus)</span> </p>
            <LI><p class="detail">Delete from SCOM <greenspan class="name">$($removeTask)</span> </p>
            <LI><p class="detail">Delete from CM <greenspan class="name">$($removeCMstatus )</span> </p>
            <LI><p class="detail">Marked Disposed in EasyVista ($EVEnvironment) - Asset ID:$($AssetID) <greenspan class="name">($($NewEVStatus))</span> </p>
        </UL>

        <p class="detail"><bluespan class="name">Tasks that need to be completed manually:</bluespan> </p>
        <UL>
            <LI><p class="detail">Remove from Sophos <span class="name">(Pending)</span> </p>
            <LI><p class="detail">Update IPAM <span class="name">(Pending)</span> </p>
            <LI><p class="detail">Email sent for Firewall Rule updates <span class="name">(Pending)</span> </p>
            <LI><p class="detail">AD Group cleanup <$($GrpCleanupCol) class="name">($($GroupCleanupStatus))</span> </p>
            $Admins

        </UL>
            <p class="detail"><bluespan class="name">Resources Recovered:</bluespan> </p>
        <UL>

            $VMResources

        </UL>

    <hr>
"@
      #<LI><p class="detail">CPU <span class="name">($($VCPU))</span> </p>
      #<LI><p class="detail">Memory <span class="name">($($VMEM))</span> </p>
      # <LI><p class="detail">Disk <span class="name">($($VDISK))</span> </p>



      # Get End Time
      $endDTM = (Get-Date)

      $Rept | Export-Csv "$Pathtoreport\$ReportCSV" -NoTypeInformation -UseCulture

      Write-Logdata -message "Creating final html report $ReportCsv"
      $Rept = $Rept |
      ConvertTo-Html -Head $vReptHeader -PreContent $PreContent -PostContent $Postcontent |
      Set-AlternatingRows -CSSEvenClass even -CSSOddClass odd
      $Rept | Out-File $PathToReport\$Reporthtml


      # Removed from MailSplat   Attachments= "$PathToReport\$ReportCsv"
      If ($DeletionInfo.'Virtual Machine') {
        Write-Logdata -message "Emailing the report to: $TO"
        $subject = "Notification: $ComputerShortname deletion processed today.  [Script Time:] $([math]::Round(($endDTM-$startDTM).totalminutes,2)) minutes."
        #Create specific message content
        $message.Subject = $subject
        $message.Body = ($Rept | Out-String)
        $message.IsBodyHTML = $true

        #Send it!
        $smtp.Send($message)

      } Else {

        Write-Host "No Virtual Machines targeted for deletion in the last $daysago days."

      }


    }# If $timespandays


  }
  Else
  {
    # VM is powered on, log and send an email notification

    # Get DeleteDate from vCenter (also convert to powershell Date type to verify it is interpreted correctly)
    Write-Logdata -message "$ComputerShortname is powered on. VM deletion processing has been skipped. Getting DeletionDate custom attribute for log and notification email."
    $DelDate = (Get-Annotation -Entity $ComputerShortname -CustomAttribute DeletionDate).Value
    $DeleteDate = Get-Date $DelDate

    Send-FailureMessage -message "$ComputerShortname with deletion date '$($DeleteDate.ToString('MM-dd-yyyy'))' was ignored by the script because it is currently powered on."
    Write-Logdata -message "$ComputerShortname with deletion date '$($DeleteDate.ToString('MM-dd-yyyy'))' was ignored by the script because it is currently powered on."
  }
} #Foreach $eolsystem


Write-Logdata -message "Disconnecting from $VCServer"
Try {Disconnect-VIServer $VCServer -Confirm:$false} Catch {}

Try {Disconnect-rCisServer $VCServer -Confirm:$false} Catch {}

Write-Logdata -message "Verboselog File $verboseLogFile"

Function Set-NewDNSTest ([string]$Num){
  $DNSServer = "bdc-dc01"
  $ZoneName = "powereng.com"
  $ComputerShortname = "ddct-rhel70$num"
  Add-DnsServerResourceRecordA -Name $ComputerShortname -ZoneName $ZoneName  -AllowUpdateAny -IPv4Address "10.247.80.140" -TimeToLive 01:00:00 -ComputerName $DNSServer -CreatePtr
  Add-DnsServerResourceRecordA -Name $ComputerShortname -ZoneName $ZoneName  -AllowUpdateAny -IPv4Address "10.247.80.148" -TimeToLive 01:00:00 -ComputerName $DNSServer -CreatePtr

  Add-DnsServerResourceRecordCName -Name "ansible700-$num" -HostNameAlias "$($ComputerShortname).$Zonename." -ZoneName "powereng.com" -ComputerName $DNSServer
  Add-DnsServerResourceRecordCName -Name "ansible700-$($num + 1 )" -HostNameAlias "$($ComputerShortname).$Zonename." -ZoneName "powereng.com" -ComputerName $DNSServer
  Add-DnsServerResourceRecordCName -Name "ansible700-$($num + 2 )" -HostNameAlias "$($ComputerShortname).$Zonename." -ZoneName "powereng.com" -ComputerName $DNSServer
  #Add-DnsServerResourceRecordCName -Name "ddct-rhel703" -HostNameAlias "$($ComputerShortname).$Zonename." -ZoneName "powereng.com" -ComputerName $DNSServer
}
