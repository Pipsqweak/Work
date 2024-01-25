
# UcsInventory.ps1

param(
  [string]${ucsm},
  [switch]${skip},
  [INT]${show},
  [switch]${summ},
  [switch]${verb}
)

Write-Host ""  # must stay
#Write-Host "ucsd = $ucsm"
#Write-Host "skip = $skip"
#Write-Host "show = $show"
#Write-Host "summ = $summ"
#Write-Host "verb = $verb"
#Write-Host "" # can go

if (($ucsm -eq "") -or ($show -lt 0) -or ($show -gt 5)) {
  Write-Host "usage: UcsInventory.ps1 -ucs host1[,host2[,host3...]] [-skip] -show (0..5) [-summ] [-v]"
  Write-Host "       -ucs  - a list of one or more hostnames or IP addresses"
  Write-Host "       -skip - don't collect from UCS Manager, but use existing data"
  Write-Host "       -show - the level of detail to show"
  Write-Host "               0 = default, show all except dimms"
  Write-Host "               1 = only fab-int, chassis, blade, rackmount"
  Write-Host "               2 = add cpu's and memory"
  Write-Host "               3 = also hard drives and adapters"
  Write-Host "               4 = plus psu's and fans"
  Write-Host "               5 = show all dimms"
  Write-Host "       -summ - summarize multiple identical items"
  Write-Host "       -v    - verbose output"
  Write-Host ""
  exit
}

# Constants
$hAlignLeft = -4131
$hAlignCenter = -4108
$hAlignRight = -4152

# Script shouldn't be run from C:\ because can't create spreadsheet there
if ($PSScriptRoot -eq "C:\") {
  Write-Host "Move script from 'C:\' to a folder like 'C:\Program Files\...' or 'C:\Users\You'"
  Write-Host "Exiting..."
  Write-Host ""
  exit
}

# When necessary create C:\Temp
if (-not (Test-Path "C:\Temp")) {
  mkdir "C:\Temp" > $null
  Write-Host "Directory C:\Temp created"
  Write-Host ""
}

# Check for PowerTool module
if (! $skip)
{
  if ((Get-Module | where {$_.Name -ilike "Cisco.UCSManager"}).Name -ine "Cisco.UCSManager")
  {
    Write-Host "Loading Module: Cisco UCS PowerTool Module"
    Write-Host ""
    Import-Module Cisco.UCSManager
  }
}

# Get UID/PWD
if (! $skip)
{
  Try {
    Write-Host "Enter UCS Credentials of UCS Manager(s)"
    ${ucsCred} = Get-Credential
  }
  Catch {
    Write-Host "No credential given"
#   Write-Host "Error equals: ${Error}"
    Write-Host "Exiting..."
    Write-Host ""
    exit
  }
  Write-Host ""
}

# System Configuration
#$ucsCommands = @("Get-UcsBlade","Get-UcsRackunit")
#$ucsCommands | foreach { Write-Host "Executing '$($_)'" ; Invoke-Command -Scriptblock { & $_ | Export-Csv -NoType .\$($_).csv }}

#$ucsClasses = @("networkElement", "computeBlade", "computeRackUnit")
$ucsClasses = @("networkElement", "equipmentSwitchCard", "equipmentFanModule", "equipmentFan", "equipmentPsu", "equipmentChassis", "equipmentIOCard", "equipmentFex", "computeBlade", "computeRackUnit", "computeBoard", "processorUnit", "memoryArray", "memoryUnit", "storageLocalDisk", "adaptorUnit", "graphicsCard", "firmwareRunning", "equipmentManufacturingDef" )
#$ucsClasses = @("networkElement", "equipmentSwitchCard", "equipmentFanModule", "equipmentFan", "equipmentPsu", "equipmentChassis", "equipmentIOCard", "equipmentFex", "computeBlade", "computeRackUnit", "computeBoard", "processorUnit", "memoryArray", "memoryUnit", "storageLocalDisk", "adaptorUnit", "graphicsCard", "equipmentLocatorLed", "firmwareRunning", "equipmentManufacturingDef", "lsServer", "faultInst" )
#$ucsClasses | foreach { Write-Host "Querying '$($_)'" ; Invoke-Command -Scriptblock { & Get-UcsManagedObject -classid $_ | Export-Csv -NoType .\$($_).csv }}

# List of UCS domains
Try {
  [array]$ucsArray = $ucsm.split(" ")
  if ($ucsArray.Count -eq 0) {
    Write-Host "No valid Hostname"
    Write-Host "Exiting..."
    Write-Host ""
    exit
  }
}
Catch {
  Write-Host "Error parsing Hostnames / IP-addresses"
  Write-Host "Error equals: ${Error}"
  Write-Host "Exiting..."
  Write-Host ""
  exit
}

# Start clean
$xlsFile = $PSScriptRoot + "\UcsInventory.xlsx"
if (Test-Path $($xlsFile)) {
  del $xlsFile -ErrorAction SilentlyContinue  # won't succeed when open in Excel
}

# Create Excel spreadsheet
Try {
  $excelApp = New-Object -comobject Excel.Application
  $excelApp.Visible = $False
  $excelApp.sheetsInNewWorkbook = $ucsArray.Count
  $workbook = $excelApp.Workbooks.Add()
}
Catch {
  Write-Host "Can't create Excel spreadsheet, is Microsoft Office installed?"
# Write-Host "Error equals: ${Error}"
  Write-Host "Exiting..."
  Write-Host ""
  exit
}

# Do a PING test on each UCS
if (! $skip)
{
  foreach ($ucs in $ucsArray) {
    $ping = new-object system.net.networkinformation.ping
    $results = $ping.send($ucs)
    if ($results.Status -ne "Success") {
      Write-Host "Can't ping UCS domain '$($ucs)'"
      Write-Host "Exiting..."
      Write-Host ""
      exit
    }
  }
}

# Loop through UCS domains
$sheet = 0
foreach ($ucs in $ucsArray) {
  $sheet++;
  $row = 0

  # Connect to (previous) UCS(s)
  if (! $skip)
  {
    Disconnect-Ucs
  }

  # Login into UCS Domain
  Write-Host "UCS Domain '$($ucs)'"

  if (! $skip)
  {
    Try {
      ${ucsCon} = Connect-Ucs -Name ${ucs} -Credential ${ucsCred} -ErrorAction SilentlyContinue
      if ($ucsCon -eq $null) {
        Write-Host "Can't login to: '$($ucs)'"
        Write-Host "Exiting..."
        Write-Host ""
        exit
      }
#     else {
#       Write-Host "UCS Connection: '$($ucsCon)'"
#     }
    }
    Catch {
      Write-Host "Error creating a session to UCS Manager Domain: '$($ucs)'"
      Write-Host "Error equals: ${Error}"
      Write-Host "Exiting..."
      Write-Host ""
      exit
    }

    Try {
     if ($verb) {
       Write-Host ""
      }
      $ucsClasses | foreach {
        if ($verb) {
          Write-Host "Querying '$($_)'"
        }
        $classId = $($_)
        Invoke-Command -Scriptblock { & Get-UcsManagedObject -classid $_ | Export-Csv -NoType C:\Temp\$($_).csv }
      }
    }
    Catch {
      Write-Host "Error querying Class : '$($classid)'"
      Write-Host "Error equals: ${Error}"
      Write-Host "Exiting..."
      Write-Host ""
      exit
    }
  }

  # Create a WorkSheet in the Excel SpreadSheet
  $worksheet = $workbook.Worksheets.Item($sheet)
  $worksheet.Name = $($ucs)

  $col = 1
  while ($col -le 12) {
    $worksheet.Columns.Item($col).HorizontalAlignment = $hAlignLeft
    $col++
  }

  $worksheet.Columns.Item(1).columnWidth = 4
  $worksheet.Columns.Item(2).columnWidth = 4
  $worksheet.Columns.Item(3).columnWidth = 4
  $worksheet.Columns.Item(4).columnWidth = 24
  $worksheet.Columns.Item(5).columnWidth = 24
  $worksheet.Columns.Item(6).columnWidth = 12
  $worksheet.Columns.Item(7).columnWidth = 12
  $worksheet.Columns.Item(8).columnWidth = 24
  $worksheet.Columns.Item(9).columnWidth = 24
  $worksheet.Columns.Item(10).columnWidth = 24
  $worksheet.Columns.Item(11).columnWidth = 24
  $worksheet.Columns.Item(12).columnWidth = 4

  $row += 2
  $worksheet.Cells.Item($row,2) = "UCS Inventory"
  $worksheet.Cells.Item($row,5) = ${ucs}
  $worksheet.Rows.Item($row).font.size = 14
  $worksheet.Rows.Item($row).font.bold = $true

  $row += 2
  $worksheet.Cells.Item($row,2) = "Components"
  $worksheet.Cells.Item($row,5) = "Model"
  $worksheet.Cells.Item($row,6) = "Quantity"
  $worksheet.Cells.Item($row,7) = "Size"
  $worksheet.Cells.Item($row,8) = "Part Nr"
  $worksheet.Cells.Item($row,9) = "Device"
  $worksheet.Cells.Item($row,10) = "Serial"
  $worksheet.Cells.Item($row,11) = "Firmware"
  $worksheet.Rows.Item($row).font.size = 11
  $worksheet.Rows.Item($row).font.bold = $true
  $worksheet.Rows.Item($row).HorizontalAlignment = $hAlignLeft

  if ($verb) {
    Write-Host ""
  }

  # Fabric Interconnects plus Parts

  $fis = ( Import-Csv -path "C:\Temp\networkElement.csv" | Sort-Object Id ) # Id is here 'A' or 'B', not numeric
  foreach ($fi in $fis) {
    if ($verb) {
      Write-Host "fi: $($fi.Dn)"
    }

    [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $fi.Model } )

#   $eqp.gettype()

#   $len = $eqp.Length
#   Write-Host "len: $len"
#   if ($len -gt 0) {

#    Write-Host "len: $($eqp.Length)"
#    if ($($eqp.Length) -gt 0) {
#      Write-Host "fi-sku: $($eqp[0].Sku)"
#      Write-Host "fi-pid: $($eqp[0].Pid)"
#      Write-Host "fi-mdl: $($eqp[0].Name)"
#    }

    $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($fi.Dn)/mgmt/fw-system" } )

    if ($verb) {
      Write-Host "fw: $($fws.Dn)"
    }
    if (($show -eq 0) -or ($show -gt 1) -or (($show -eq 1) -and ($($fi.Id) -eq 'A'))) {
      $row++
    }
    $row++
    $worksheet.Cells.Item($row,2).font.bold = $true
    $worksheet.Cells.Item($row,2) = "Fabric Interconnect $($fi.Id)"
    $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
    $worksheet.Cells.Item($row,8) = $fi.Model
    $worksheet.Cells.Item($row,10) = $fi.Serial -replace 'N/A',''
    $worksheet.Cells.Item($row,11) = $fws.Version

    if (($show -eq 0) -or ($show -ge 2)) {
      $exp = ( Import-Csv -path "C:\Temp\equipmentSwitchCard.csv" | where { $_.Dn -like "$($fi.Dn)*" } | where { $_.Model -ne "" } | where { $_.Id -gt 1 } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($ex in $exp) {
        if ($verb) {
          Write-Host "ex: $($ex.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ex.Model } )
        $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($ex.Dn)/mgmt/fw-system" } )

        $row++
        $worksheet.Cells.Item($row,3) = "Expansion Module $($ex.Id - 1)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace '.port','x' -replace 'Fibre Channel Expansion Module For UCS Fabric Interconnect','FC' -replace 'Gigabit Ethernet Expansion Module For UCS Fabric Interconnect','GbE' -replace 'Flex Port Expansion Module For UCS Fabric Interconnect','16UP' }
        $worksheet.Cells.Item($row,8) = $ex.Model
        $worksheet.Cells.Item($row,10) = $ex.Serial -replace 'N/A',''
        $worksheet.Cells.Item($row,11) = $fws.Version

        if ($summ) {
          $worksheet.Cells.Item($row,3) = "Expansion Modules"
          $worksheet.Cells.Item($row,6) = @($exp).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $psu = ( Import-Csv -path "C:\Temp\equipmentPsu.csv" | where { $_.Dn -like "$($fi.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($ps in $psu) {
        if ($verb) {
          Write-Host "ps: $($ps.Dn)"
        }
        
        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ps.Model } )

        $row++
        $worksheet.Cells.Item($row,3) = "Power Supply $($ps.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace ' PSU for UCS.*','' }
        $worksheet.Cells.Item($row,8) = $ps.Model
        $worksheet.Cells.Item($row,10) = $ps.Serial -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,3) = "Power Supplies"
          $worksheet.Cells.Item($row,6) = @($psu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $mod = ( Import-Csv -path "C:\Temp\equipmentFanModule.csv" | where { $_.Dn -like "$($fi.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      $fan = ( Import-Csv -path "C:\Temp\equipmentFan.csv" | where { $_.Dn -like "$($fi.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )

      if ($mod.count -ge 0) {

        foreach ($fm in $mod) {
          if ($verb) {
            Write-Host "fm: $($fm.Dn)"
          }

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($fm.Id)"
          $worksheet.Cells.Item($row,8) = $fm.Model
          $worksheet.Cells.Item($row,10) = $fm.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      }
      else { # no fan modules

        foreach ($cf in $fan) {
          if ($verb) {
            Write-Host "cf: $($cf.Dn)"
          }

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($cf.Id)"
          $worksheet.Cells.Item($row,8) = $cf.Model
          $worksheet.Cells.Item($row,10) = $cf.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      } # end if module or fan
    }
  }

  # Chassis's plus Parts

  $chs = ( Import-Csv -path "C:\Temp\equipmentChassis.csv" | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
  foreach ($ch in $chs) {
    if ($verb) {
      Write-Host "ch: $($ch.Dn)"
    }

    [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ch.Model } )

    $row += 2
    $worksheet.Cells.Item($row,2).font.bold = $true
    $worksheet.Cells.Item($row,2) = "UCS Chassis $($ch.Id)"
    $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','UCS-' -replace ' Chassis','' }
    $worksheet.Cells.Item($row,8) = $ch.Model
    $worksheet.Cells.Item($row,10) = $ch.Serial -replace 'N/A',''

    if (($show -eq 0) -or ($show -ge 2)) {
      $iom = ( Import-Csv -path "C:\Temp\equipmentIOCard.csv" | where { $_.Dn -like "$($ch.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($io in $iom) {
        if ($verb) {
          Write-Host "io: $($io.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $io.Model } )

        $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($io.Dn)/mgmt/fw-system" } )
        if ($verb) {
          Write-Host "fw: $($fws.Dn)"
        }

        $row++
        $worksheet.Cells.Item($row,3) = "I/O Module $($io.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
        $worksheet.Cells.Item($row,8) = $io.Model
        $worksheet.Cells.Item($row,10) = $io.Serial -replace 'N/A',''
        $worksheet.Cells.Item($row,11) = $fws.Version

        if ($summ) {
          $worksheet.Cells.Item($row,3) = "I/O Modules"
          $worksheet.Cells.Item($row,6) = @($iom).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $psu = ( Import-Csv -path "C:\Temp\equipmentPsu.csv" | where { $_.Dn -like "$($ch.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($ps in $psu) {
        if ($verb) {
          Write-Host "ps: $($ps.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ps.Model } )

        $row++
        $worksheet.Cells.Item($row,3) = "Power Supply $($ps.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace ' PSU for UCS.*','' -replace 'Platinum AC PSU.*','AC PSU' }
        $worksheet.Cells.Item($row,8) = $ps.Model
        $worksheet.Cells.Item($row,10) = $ps.Serial -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,3) = "Power Supplies"
          $worksheet.Cells.Item($row,6) = @($psu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $mod = ( Import-Csv -path "C:\Temp\equipmentFanModule.csv" | where { $_.Dn -like "$($ch.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      $fan = ( Import-Csv -path "C:\Temp\equipmentFan.csv" | where { $_.Dn -like "$($ch.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )

      if ($mod.count -ge 0) {

        foreach ($fm in $mod) {
          if ($verb) {
            Write-Host "cf: $($fm.Dn)"
          }

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($fm.Id)"
          $worksheet.Cells.Item($row,8) = $fm.Model
          $worksheet.Cells.Item($row,10) = $fm.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      }
      else { # no fan modules

        foreach ($cf in $fan) {
          if ($verb) {
            Write-Host "cf: $($cf.Dn)"
          }

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($cf.Id)"
          $worksheet.Cells.Item($row,8) = $cf.Model
          $worksheet.Cells.Item($row,10) = $cf.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      } # end if module or fan
    }

    # Blades plus Parts

    $bld = ( Import-Csv -path "C:\Temp\computeBlade.csv" | where { $_.Dn -like "$($ch.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.SlotId -as [int]}} )
    foreach ($bl in $bld) {
      if ($verb) {
        Write-Host "bl: $($bl.Dn)"
      }

      [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $bl.Model } )

      $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($bl.Dn)/mgmt/fw-system" } )
      if ($verb) {
        Write-Host "fw: $($fws.Dn)"
      }

      if (($show -eq 0) -or ($show -gt 1)) {
        $row++
      }
      $row++
      $worksheet.Cells.Item($row,3).font.bold = $true
      $worksheet.Cells.Item($row,3) = "UCS Blade $($bl.SlotId)"
      if ($bl.Model.Substring(0,7) -eq "UCSB-EX") {
        $worksheet.Cells.Item($row,5) = if ($bl.ScaledMode -ne "scaled") { "B260-M4" } else { "B460-M4" }
      }
      else
      {
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
      }
      $worksheet.Cells.Item($row,8) = $bl.Model
      $worksheet.Cells.Item($row,10) = $bl.Serial -replace 'N/A',''
      $worksheet.Cells.Item($row,11) = $fws.Version

      if (($show -eq 0) -or ($show -ge 2)) {
        $cpu = ( Import-Csv -path "C:\Temp\processorUnit.csv" | where { $_.Dn -like "$($bl.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
        foreach ($pr in $cpu) {
          if ($verb) {
            Write-Host "pr: $($pr.Dn)"
          }

          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $( $_.Name -replace 'Intel\(R\) Xeon\(R\)','' -replace ' ','' -replace '-','' ) -eq $( $pr.Model -replace 'Intel\(R\) Xeon\(R\)','' -replace 'CPU','' -replace '@','' -replace '[0-9]\.[0-9]*GHz','' -replace ' ','' -replace '-','' ) } )

#         Write-Host "pr-len: $($eqp.Length)"
#         if ($($eqp.Length) -gt 0) {
#           Write-Host "pr-mdl: $($eqp[0].Name)"
#           Write-Host "pr-pid: $($eqp[0].Pid)"
#         }

          $row++
          $worksheet.Cells.Item($row,4) = "Processor $($pr.Id)"
          $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Intel\(R\) Xeon\(R\) ','' }
          $worksheet.Cells.Item($row,7) = "$($pr.Cores)C $( [math]::Round($pr.Speed, 1)) GHz"
          $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
          $worksheet.Cells.Item($row,9) = if ($eqp.Length -gt 0) { $eqp[0].OemPartNumber -replace 'TBD','' }
          $worksheet.Cells.Item($row,10) = $($pr.Serial) -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,4) = "Processors"
            $worksheet.Cells.Item($row,6) = @($cpu).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }
      }

      if (($show -eq 0) -or ($show -ge 2)) {
        $mem = ( Import-Csv -path "C:\Temp\memoryArray.csv" | where { $_.Dn -like "$($bl.Dn)*" } | Sort-Object @{exp = {$_.Id -as [int]}} ) # careful: Model is empty

        [int]$cap = 0
        foreach ($ma in $mem) {
          if ($verb) {
            Write-Host "ma: $($ma.Dn)"
          }
          Try 
          {
            $cap += $ma.CurrCapacity
          }
          Catch
          {
            $cap += 0;
          }
        }
        $cap /= 1024

        $dim = ( Import-Csv -path "C:\Temp\memoryUnit.csv" | where { $_.Dn -like "$($bl.Dn)*" } | where { $_.Model -ne "" } | where { $_.Id -eq "1" } )
        $row++
        $worksheet.Cells.Item($row,4) = "Memory"
        $worksheet.Cells.Item($row,7) = "$($cap) GB"
        $worksheet.Cells.Item($row,9) = $dim.Model
      }

      if (($show -ge 5) -and (-not $summ)) {
        $dim = ( Import-Csv -path "C:\Temp\memoryUnit.csv" | where { $_.Dn -like "$($bl.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
        foreach ($mm in $dim) {
          if ($verb) {
            Write-Host "mm: $($mm.Dn)"
          }

          [int]$cap = 0 + $mm.Capacity
          $cap /= 1024

#         [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -like "$($mm.Model)*" } )
          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $( $_.OemPartNumber -replace '-','' ) -like "$($mm.Model)*" } )

          $row++
          $worksheet.Cells.Item($row,4) = "Module $($mm.Id)"
          $worksheet.Cells.Item($row,7) = "$($cap) GB"
          $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
          $worksheet.Cells.Item($row,9) = $($mm.Model)
          $worksheet.Cells.Item($row,10) = $($mm.Serial) -replace 'N/A',''
        }
      }

      if (($show -eq 0) -or ($show -ge 3)) {
        $hdd = ( Import-Csv -path "C:\Temp\storageLocalDisk.csv" | where { $_.Dn -like "$($bl.Dn)*" } | where { $_.Rn -ne "disk-0" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
        foreach ($hd in $hdd) {
          if ($verb) {
            Write-Host "hd: $($hd.Dn)"
          }

          # old disks (73/146 GB) report too low size (like 70136 MB), newer disks report correct size but in kB
          [double]$sz = 0.0 + $hd.size
          [int]$gb = 0
          if ($sz -ge (1024 * 1024)) {
            $sz /= (1024 * 1024);
            $gb = 10 * [int][Math]::floor($sz / 10.0 + 0.5);
          }
          else {
            $sz = $sz / 960.0
            if (($sz -ge 68.0) -and ($sz -le 78.0)) {
              $gb = 73;
            }
            elseif (($sz -ge 90.0) -and ($sz -le 110.0)) {
              $gb = 100;
            }
            elseif (($sz -ge 136.0) -and ($sz -le 156.0)) {
              $gb = 146;
            }
            else {
              $gb = 20 * [int][Math]::floor($sz / 20.0 + 0.5);
            }
          }

#         [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -eq $hd.Model } )
          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -like "$($hd.Model)*" } )

          $row++
          $worksheet.Cells.Item($row,4) = "Hard Drive $($hd.Id)"
          $worksheet.Cells.Item($row,7) = "$($gb) GB"
          $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
          $worksheet.Cells.Item($row,9) = $($hd.Model) -replace 'INTEL SSD','SSD'
          $worksheet.Cells.Item($row,10) = $($hd.Serial) -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,4) = "Hard Drives"
            $worksheet.Cells.Item($row,6) = @($hdd).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }
      }

      if (($show -eq 0) -or ($show -ge 3)) {
        $ioa = ( Import-Csv -path "C:\Temp\adaptorUnit.csv" | where { $_.Dn -like "$($bl.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
        foreach ($io in $ioa) {
          if ($verb) {
            Write-Host "io: $($io.Dn)"
          }

          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $io.Model } )

          $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($io.Dn)/mgmt/fw-system" } )
          if ($verb) {
            Write-Host "fw: $($fws.Dn)"
          }

          $row++
          $worksheet.Cells.Item($row,4) = "I/O Adaptor $($io.Id)"
          $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
          $worksheet.Cells.Item($row,8) = $io.Model
          $worksheet.Cells.Item($row,10) = $io.Serial -replace 'N/A',''
          $worksheet.Cells.Item($row,11) = $fws.Version

          if ($summ) {
            $worksheet.Cells.Item($row,4) = "I/O Adaptors"
            $worksheet.Cells.Item($row,6) = @($ioa).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }
      }
    }
  }

  # FEXes

  $fex = ( Import-Csv -path "C:\Temp\equipmentFex.csv" | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
  $srv = ( Import-Csv -path "C:\Temp\computeRackUnit.csv" | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
  if ((@($fex).count -gt 0) -or (@($srv).count -gt 0)) {
    $row += 2
    $worksheet.Cells.Item($row,2).font.bold = $true
    $worksheet.Cells.Item($row,2) = "Rackmount Servers"
  }

  $fex = ( Import-Csv -path "C:\Temp\equipmentFex.csv" | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
  foreach ($fx in $fex) {
    if ($verb) {
      Write-Host "fx: $($fx.Dn)"
    }

    [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $fx.Model } )

    $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($fx.Dn)/slot-1/mgmt/fw-system" } )

    if ($verb) {
      Write-Host "fw: $($fws.Dn)"
    }
    if (($show -eq 0) -or ($show -gt 1)) {
      $row++
    }
    $row++
    $worksheet.Cells.Item($row,3).font.bold = $true
    $worksheet.Cells.Item($row,3) = "Fabric Extender $($fx.Id)"
    $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name }
    $worksheet.Cells.Item($row,8) = $fx.Model
    $worksheet.Cells.Item($row,10) = $fx.Serial -replace 'N/A',''
    $worksheet.Cells.Item($row,11) = $fws.Version

    if (($show -eq 0) -or ($show -ge 4)) {
      $psu = ( Import-Csv -path "C:\Temp\equipmentPsu.csv" | where { $_.Dn -like "$($fx.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($ps in $psu) {
        if ($verb) {
          Write-Host "ps: $($ps.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ps.Model } )

        $row++
        $worksheet.Cells.Item($row,4) = "Power Supply $($ps.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name }
        $worksheet.Cells.Item($row,8) = $ps.Model
        $worksheet.Cells.Item($row,10) = $ps.Serial -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "Power Supplies"
          $worksheet.Cells.Item($row,6) = @($psu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $mod = ( Import-Csv -path "C:\Temp\equipmentFanModule.csv" | where { $_.Dn -like "$($fx.Dn)*" } | where { $_.Model -ne "" } | where { $_.Id -eq "1" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      $fan = ( Import-Csv -path "C:\Temp\equipmentFan.csv" | where { $_.Dn -like "$($fx.Dn)*" } | where { $_.Model -ne "" } | where { $_.Id -eq "1" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      if ($mod.count -ge 0) {

        foreach ($fm in $mod) {
          if ($verb) {
            Write-Host "fm: $($fm.Dn)"
          }

          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $fm.Model } )

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($fm.Id)"
          $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name }
          $worksheet.Cells.Item($row,8) = $fm.Model
          $worksheet.Cells.Item($row,10) = $fm.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      }
      else { # no fan modules

        foreach ($cf in $fan) {
          if ($verb) {
            Write-Host "cf: $($cf.Dn)"
          }

          [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $cf.Model } )

          $row++
          $worksheet.Cells.Item($row,3) = "Cooling Fan $($cf.Id)"
          $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name }
          $worksheet.Cells.Item($row,8) = $cf.Model
          $worksheet.Cells.Item($row,10) = $cf.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,3) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      } # end if module or fan
    }
  }

  # Rackmounts plus Parts

  $srv = ( Import-Csv -path "C:\Temp\computeRackUnit.csv" | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
  foreach ($sv in $srv) {
    if ($verb) {
      Write-Host "sv: $($sv.Dn)"
    }

    [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $sv.Model } )

    $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($sv.Dn)/mgmt/fw-system" } )
    if ($verb) {
      Write-Host "fw: $($fws.Dn)"
    }

    if (($show -eq 0) -or ($show -gt 1)) {
      $row++
    }

    $row++
    $worksheet.Cells.Item($row,3).font.bold = $true
    $worksheet.Cells.Item($row,3) = "Server $($sv.Id)"
    $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
    $worksheet.Cells.Item($row,8) = $sv.Model
    $worksheet.Cells.Item($row,10) = $sv.Serial -replace 'N/A',''
    $worksheet.Cells.Item($row,11) = $fws.Version

    if (($show -eq 0) -or ($show -ge 2)) {
      $cpu = ( Import-Csv -path "C:\Temp\processorUnit.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($pr in $cpu) {
        if ($verb) {
          Write-Host "pr: $($pr.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $( $_.Name -replace 'Intel\(R\) Xeon\(R\)','' -replace ' ','' -replace '-','' ) -eq $( $pr.Model -replace 'Intel\(R\) Xeon\(R\)','' -replace 'CPU','' -replace '@','' -replace '[0-9]\.[0-9]*GHz','' -replace ' ','' -replace '-','' ) } )

        $row++
        $worksheet.Cells.Item($row,4) = "Processor $($pr.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Intel\(R\) Xeon\(R\) ','' }
        $worksheet.Cells.Item($row,7) = "$($pr.Cores)C $( [math]::Round($pr.Speed, 1)) GHz"
        $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
        $worksheet.Cells.Item($row,9) = if ($eqp.Length -gt 0) { $eqp[0].OemPartNumber -replace 'TBD','' }
        $worksheet.Cells.Item($row,10) = $($pr.Serial) -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "Processors"
          $worksheet.Cells.Item($row,6) = @($cpu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 2)) {
      $mem = ( Import-Csv -path "C:\Temp\memoryArray.csv" | where { $_.Dn -like "$($sv.Dn)*" } | Sort-Object @{exp = {$_.Id -as [int]}} ) # careful: Model is empty

      [int]$cap = 0
      foreach ($ma in $mem) {
        if ($verb) {
          Write-Host "ma: $($ma.Dn)"
        }
        Try 
        {
          $cap += $ma.CurrCapacity
        }
        Catch
        {
          $cap += 0;
        }
      }
      $cap /= 1024

      $dim = ( Import-Csv -path "C:\Temp\memoryUnit.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | where { $_.Id -eq "1" } )

      $row++
      $worksheet.Cells.Item($row,4) = "Memory"
      $worksheet.Cells.Item($row,7) = "$($cap) GB"
      $worksheet.Cells.Item($row,9) = $dim.Model
    }

    if (($show -ge 5) -and (-not $summ)) {
      $dim = ( Import-Csv -path "C:\Temp\memoryUnit.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($mm in $dim) {
        if ($verb) {
          Write-Host "mm: $($mm.Dn)"
        }

        [int]$cap = 0 + $mm.Capacity
        $cap /= 1024

#       [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -like "$($mm.Model)*" } )
        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $( $_.OemPartNumber -replace '-','' ) -like "$($mm.Model)*" } )

        $row++
        $worksheet.Cells.Item($row,4) = "Module $($mm.Id)"
        $worksheet.Cells.Item($row,7) = "$($cap) GB"
        $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
        $worksheet.Cells.Item($row,9) = $($mm.Model)
        $worksheet.Cells.Item($row,10) = $($mm.Serial) -replace 'N/A',''
      }
    }

    if (($show -eq 0) -or ($show -ge 3)) {
      $hdd = ( Import-Csv -path "C:\Temp\storageLocalDisk.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Rn -ne "disk-0" } |  where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($hd in $hdd) {
        if ($verb) {
          Write-Host "hd: $($hd.Dn)"
        }

        # old disks (73/146 GB) report too low size (like 70136 MB), newer disks report correct size but in kB
        [double]$sz = 0.0 + $hd.size
        [int]$gb = 0
        if ($sz -ge (1024 * 1024)) {
          $sz /= (1024 * 1024);
          $gb = 10 * [int][Math]::floor($sz / 10.0 + 0.5);
        }
        else {
          $sz = $sz / 960.0
          if (($sz -ge 68.0) -and ($sz -le 78.0)) {
            $gb = 73;
          }
          elseif (($sz -ge 90.0) -and ($sz -le 110.0)) {
            $gb = 100;
          }
          elseif (($sz -ge 136.0) -and ($sz -le 156.0)) {
            $gb = 146;
          }
          else {
            $gb = 20 * [int][Math]::floor($sz / 20.0 + 0.5);
          }
        }

#       [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -eq $hd.Model } )
        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.OemPartNumber -like "$($hd.Model)*" } )

        $row++
        $worksheet.Cells.Item($row,4) = "Hard Drive $($hd.Id)"
        $worksheet.Cells.Item($row,7) = "$($gb) GB"
        $worksheet.Cells.Item($row,8) = if ($eqp.Length -gt 0) { $eqp[0].Pid }
        $worksheet.Cells.Item($row,9) = $($hd.Model) -replace 'INTEL ',''
        $worksheet.Cells.Item($row,10) = $($hd.Serial) -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "Hard Drives"
          $worksheet.Cells.Item($row,6) = @($hdd).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 3)) {
      $gpu = ( Import-Csv -path "C:\Temp\graphicsCard.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($gc in $gpu) {
        if ($verb) {
          Write-Host "gc: $($gc.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $gc.Model } )

        $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($gc.Dn)/mgmt/fw-system" } )
        if ($verb) {
          Write-Host "fw: $($fws.Dn)"
        }

        $row++
        $worksheet.Cells.Item($row,4) = "Graphics Card $($gc.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Nvidia ','' -replace ' P2.*','' }
        $worksheet.Cells.Item($row,10) = $($gc.Serial) -replace 'N/A','' -replace 'NA',''
        $worksheet.Cells.Item($row,11) = $fws.Version

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "Graphics Cards"
          $worksheet.Cells.Item($row,6) = @($gpu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 3)) {
      $ioa = ( Import-Csv -path "C:\Temp\adaptorUnit.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($io in $ioa) {
        if ($verb) {
          Write-Host "io: $($io.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $io.Model } )

        $fws = ( Import-Csv -path "C:\Temp\firmwareRunning.csv" | where { $_.Dn -eq "$($io.Dn)/mgmt/fw-system" } )
        if ($verb) {
          Write-Host "fw: $($fws.Dn)"
        }

        $row++
        $worksheet.Cells.Item($row,4) = "I/O Adaptor $($io.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'Cisco UCS ','' }
        $worksheet.Cells.Item($row,8) = $io.Model
        $worksheet.Cells.Item($row,10) = $io.Serial -replace 'N/A',''
        $worksheet.Cells.Item($row,11) = $fws.Version

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "I/O Adaptors"
          $worksheet.Cells.Item($row,6) = @($ioa).Count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $psu = ( Import-Csv -path "C:\Temp\equipmentPsu.csv" | where { $_.Dn -like "$($sv.Dn)*" } | where { $_.Model -ne "" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      foreach ($ps in $psu) {
        if ($verb) {
          Write-Host "ps: $($ps.Dn)"
        }

        [Object[]] $eqp = ( Import-Csv -path "C:\Temp\equipmentManufacturingDef.csv" | where { $_.Pid -eq $ps.Model } )

        $row++
        $worksheet.Cells.Item($row,4) = "Power Supply $($ps.Id)"
        $worksheet.Cells.Item($row,5) = if ($eqp.Length -gt 0) { $eqp[0].Name -replace 'power supply unit for UCS.*','PSU' }
        $worksheet.Cells.Item($row,8) = $ps.Model
        $worksheet.Cells.Item($row,10) = $ps.Serial -replace 'N/A',''

        if ($summ) {
          $worksheet.Cells.Item($row,4) = "Power Supplies"
          $worksheet.Cells.Item($row,6) = @($psu).count
          $worksheet.Cells.Item($row,10) = ""
          break
        }
      }
    }

    if (($show -eq 0) -or ($show -ge 4)) {
      $mod = ( Import-Csv -path "C:\Temp\equipmentFanModule.csv" | where { $_.Dn -like "$($sv.Dn)*" } | Sort-Object @{exp = {$_.Id -as [int]}} )
      $fan = ( Import-Csv -path "C:\Temp\equipmentFan.csv" | where { $_.Dn -like "$($sv.Dn)*" } | Sort-Object @{exp = {$_.Id -as [int]}} )

      if ($mod.count -ge 0) {

        foreach ($fm in $mod) {
          if ($verb) {
            Write-Host "fm: $($fm.Dn)"
          }

#         # model is empty for rackmount fans and fan-modules

          $row++
          $worksheet.Cells.Item($row,4) = "Cooling Fan $($fm.Id)"
          $worksheet.Cells.Item($row,10) = $fm.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,4) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      }
      else { # no fan modules

        foreach ($cf in $fan) {
          if ($verb) {
            Write-Host "cf: $($cf.Dn)"
          }

#         # model is empty for rackmount fans and fan-modules

          $row++
          $worksheet.Cells.Item($row,4) = "Cooling Fan $($cf.Id)"
          $worksheet.Cells.Item($row,10) = $cf.Serial -replace 'N/A',''

          if ($summ) {
            $worksheet.Cells.Item($row,4) = "Cooling Fans"
            $worksheet.Cells.Item($row,6) = @($fan).count
            $worksheet.Cells.Item($row,10) = ""
            break
          }
        }

      } # end if module or fan
    }

  }

  if ($verb) {
    Write-Host ""  
  }

} # end loop $ucs

Try {
  del $xlsFile -ErrorAction SilentlyContinue
  $workbook.SaveAs($xlsFile)
}
Catch {
  Write-Host "Spreadsheet could not be saved (still open in Excel ??)"
  Write-Host ""
}
$excelApp.quit()

# Logout from UCS
if (! $skip)
{
  Disconnect-Ucs
  Write-Host "Logout from '$($ucs)'"
}
Write-Host ""

