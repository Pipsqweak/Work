#----------------- Start of code capture -----------------

#---------------get---------------
$partial = $true
$_this = Get-CisService -Server $k -Name 'com.vmware.vcenter.vcha.cluster'
$_this.get($null, $partial)

$vm = Get-VM -Server $vCenter -Name "DDC-vCAD-009"
#---------------Config---------------
$_this = Get-View -Id $vm.Id
$_this.Config

#---------------QueryConfigOptionDescriptor---------------
$_this = Get-View -Server -Id 'EnvironmentBrowser-envbrowser-5978'
$_this.QueryConfigOptionDescriptor()

#---------------Config---------------
$_this = Get-View -Id 'VirtualMachine-vm-5978'
$_this.Config

#---------------QueryConfigOptionDescriptor---------------
$_this = Get-View -Id 'EnvironmentBrowser-envbrowser-5978'
$_this.QueryConfigOptionDescriptor()

#---------------QueryAvailablePerfMetric---------------
$entity = New-Object VMware.Vim.ManagedObjectReference
$entity.Type = 'VirtualMachine'
$entity.Value = 'vm-5978'
$intervalId = 20
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.QueryAvailablePerfMetric($entity, $null, $null, $intervalId)

#---------------QueryAvailablePerfMetric---------------
$entity = New-Object VMware.Vim.ManagedObjectReference
$entity.Type = 'VirtualMachine'
$entity.Value = 'vm-5978'
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.QueryAvailablePerfMetric($entity, $null, $null, $null)

#---------------QueryPerfCounter---------------
$counterId = New-Object int[] (10)
$counterId[0] = 1024
$counterId[1] = 1025
$counterId[2] = 1026
$counterId[3] = 1027
$counterId[4] = 1028
$counterId[5] = 1029
$counterId[6] = 1030
$counterId[7] = 1031
$counterId[8] = 1032
$counterId[9] = 1033
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.QueryPerfCounter($counterId)

#---------------QueryPerf---------------
$querySpec = New-Object VMware.Vim.PerfQuerySpec[] (1)
$querySpec[0] = New-Object VMware.Vim.PerfQuerySpec
$querySpec[0].MetricId = New-Object VMware.Vim.PerfMetricId[] (14)
$querySpec[0].MetricId[0] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[0].Instance = ''
$querySpec[0].MetricId[0].CounterId = 2
$querySpec[0].MetricId[1] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[1].Instance = '5'
$querySpec[0].MetricId[1].CounterId = 1016
$querySpec[0].MetricId[2] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[2].Instance = '7'
$querySpec[0].MetricId[2].CounterId = 1016
$querySpec[0].MetricId[3] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[3].Instance = '4'
$querySpec[0].MetricId[3].CounterId = 1016
$querySpec[0].MetricId[4] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[4].Instance = '8'
$querySpec[0].MetricId[4].CounterId = 1016
$querySpec[0].MetricId[5] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[5].Instance = ''
$querySpec[0].MetricId[5].CounterId = 1016
$querySpec[0].MetricId[6] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[6].Instance = '0'
$querySpec[0].MetricId[6].CounterId = 1016
$querySpec[0].MetricId[7] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[7].Instance = '6'
$querySpec[0].MetricId[7].CounterId = 1016
$querySpec[0].MetricId[8] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[8].Instance = '3'
$querySpec[0].MetricId[8].CounterId = 1016
$querySpec[0].MetricId[9] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[9].Instance = '2'
$querySpec[0].MetricId[9].CounterId = 1016
$querySpec[0].MetricId[10] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[10].Instance = '1'
$querySpec[0].MetricId[10].CounterId = 1016
$querySpec[0].MetricId[11] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[11].Instance = '9'
$querySpec[0].MetricId[11].CounterId = 1016
$querySpec[0].MetricId[12] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[12].Instance = '10'
$querySpec[0].MetricId[12].CounterId = 1016
$querySpec[0].MetricId[13] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[13].Instance = '11'
$querySpec[0].MetricId[13].CounterId = 1016
$querySpec[0].Format = 'csv'
$querySpec[0].IntervalId = 20
$querySpec[0].Entity = New-Object VMware.Vim.ManagedObjectReference
$querySpec[0].Entity.Type = 'VirtualMachine'
$querySpec[0].Entity.Value = 'vm-5978'
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.QueryPerf($querySpec)

#---------------QueryPerf---------------
$querySpec = New-Object VMware.Vim.PerfQuerySpec[] (1)
$querySpec[0] = New-Object VMware.Vim.PerfQuerySpec
$querySpec[0].MetricId = New-Object VMware.Vim.PerfMetricId[] (13)
$querySpec[0].MetricId[0] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[0].Instance = '6'
$querySpec[0].MetricId[0].CounterId = 12
$querySpec[0].MetricId[1] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[1].Instance = '4'
$querySpec[0].MetricId[1].CounterId = 12
$querySpec[0].MetricId[2] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[2].Instance = '5'
$querySpec[0].MetricId[2].CounterId = 12
$querySpec[0].MetricId[3] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[3].Instance = '1'
$querySpec[0].MetricId[3].CounterId = 12
$querySpec[0].MetricId[4] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[4].Instance = '10'
$querySpec[0].MetricId[4].CounterId = 12
$querySpec[0].MetricId[5] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[5].Instance = '2'
$querySpec[0].MetricId[5].CounterId = 12
$querySpec[0].MetricId[6] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[6].Instance = '7'
$querySpec[0].MetricId[6].CounterId = 12
$querySpec[0].MetricId[7] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[7].Instance = '0'
$querySpec[0].MetricId[7].CounterId = 12
$querySpec[0].MetricId[8] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[8].Instance = '8'
$querySpec[0].MetricId[8].CounterId = 12
$querySpec[0].MetricId[9] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[9].Instance = '11'
$querySpec[0].MetricId[9].CounterId = 12
$querySpec[0].MetricId[10] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[10].Instance = '3'
$querySpec[0].MetricId[10].CounterId = 12
$querySpec[0].MetricId[11] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[11].Instance = ''
$querySpec[0].MetricId[11].CounterId = 12
$querySpec[0].MetricId[12] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[12].Instance = '9'
$querySpec[0].MetricId[12].CounterId = 12
$querySpec[0].Format = 'csv'
$querySpec[0].IntervalId = 20
$querySpec[0].Entity = New-Object VMware.Vim.ManagedObjectReference
$querySpec[0].Entity.Type = 'VirtualMachine'
$querySpec[0].Entity.Value = 'vm-5978'
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.QueryPerf($querySpec)

#---------------HistoricalInterval---------------
$_this = Get-View -Id 'PerformanceManager-PerfMgr'
$_this.HistoricalInterval

#---------------QueryPerf---------------
$querySpec = New-Object VMware.Vim.PerfQuerySpec[] (1)
$querySpec[0] = New-Object VMware.Vim.PerfQuerySpec
$querySpec[0].MetricId = New-Object VMware.Vim.PerfMetricId[] (13)
$querySpec[0].MetricId[0] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[0].Instance = ''
$querySpec[0].MetricId[0].CounterId = 12
$querySpec[0].MetricId[1] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[1].Instance = '0'
$querySpec[0].MetricId[1].CounterId = 12
$querySpec[0].MetricId[2] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[2].Instance = '1'
$querySpec[0].MetricId[2].CounterId = 12
$querySpec[0].MetricId[3] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[3].Instance = '10'
$querySpec[0].MetricId[3].CounterId = 12
$querySpec[0].MetricId[4] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[4].Instance = '11'
$querySpec[0].MetricId[4].CounterId = 12
$querySpec[0].MetricId[5] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[5].Instance = '2'
$querySpec[0].MetricId[5].CounterId = 12
$querySpec[0].MetricId[6] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[6].Instance = '3'
$querySpec[0].MetricId[6].CounterId = 12
$querySpec[0].MetricId[7] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[7].Instance = '4'
$querySpec[0].MetricId[7].CounterId = 12
$querySpec[0].MetricId[8] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[8].Instance = '5'
$querySpec[0].MetricId[8].CounterId = 12
$querySpec[0].MetricId[9] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[9].Instance = '6'
$querySpec[0].MetricId[9].CounterId = 12
$querySpec[0].MetricId[10] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[10].Instance = '7'
$querySpec[0].MetricId[10].CounterId = 12
$querySpec[0].MetricId[11] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[11].Instance = '8'
$querySpec[0].MetricId[11].CounterId = 12
$querySpec[0].MetricId[12] = New-Object VMware.Vim.PerfMetricId
$querySpec[0].MetricId[12].Instance = '9'
$querySpec[0].MetricId[12].CounterId = 12
$querySpec[0].Format = 'csv'
$querySpec[0].IntervalId = 300
$now = [DateTime]::Now
$querySpec[0].StartTime = $now.AddMinutes(-30)
$querySpec[0].EndTime = $now
$querySpec[0].Entity = New-Object VMware.Vim.ManagedObjectReference
$querySpec[0].Entity.Type = 'VirtualMachine'
$querySpec[0].Entity.Value = 'vm-5978'
$_this = Get-View -Server $vCenter -Id 'PerformanceManager-PerfMgr'
$data = $_this.QueryPerf($querySpec)



#----------------- End of code capture -----------------


$vcadHosts = @(Get-VMHost -Server $vCenter | Where-Object { $_.ExtensionData.Hardware.PciDevice | Where-Object { ($_.VendorName -match "Nvidia") -and ($_.DeviceName -match "Tesla") } } | Sort-Object Name)
$vcadVMs = @(Get-VM -Server $vCenter -Location $vcadHosts | Where-Object { ($_.PowerState -eq "PoweredOn") -and ($_.Name -notmatch "^vCLS") })

$collectionTime = Measure-Command { $stats = Get-Stat -Server $vCenter -Entity $vcadVMs -Stat @("cpu.usage.average","cpu.ready.summation","mem.active.average") -Realtime }

$a = $stats | Group-Object EntityId
$b = $a[0].Group | Group-Object MetricId
$c = $b[0].Group | Group-Object Timestamp
