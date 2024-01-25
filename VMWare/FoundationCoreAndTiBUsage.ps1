Function Get-FoundationCoreAndTiBUsage {
    <#
        .DESCRIPTION Retrieves CPU Core/Storage usage analysis for vSphere Foundation and VMware Cloud Foundation (VCF)
        .NOTES  Author:  William Lam, Broadcom
        .NOTES  Last Updated: 01/02/2024
        .PARAMETER ClusterName
            Name of a specific vSphere Cluster
        .PARAMETER CSV
            Output to CSV file
        .PARAMETER Filename
            Specific filename to save CSV file (default: <vcenter name>.csv and <vcenter name>-vsan.csv)
        .PARAMETER CollectLicenseKey
            Collect ESXi and/or vSAN License Key for each host
        .EXAMPLE
            Get-FoundationCoreAndTiBUsage
        .EXAMPLE
            Get-FoundationCoreAndTiBUsage -ClusterName "ML Cluster"
        .EXAMPLE
            Get-FoundationCoreAndTiBUsage -ClusterName "ML Cluster" -CSV
        .EXAMPLE
            Get-FoundationCoreAndTiBUsage -ClusterName "ML Cluster" -CSV -Filename "ML Cluster-Cluster.csv"
        .EXAMPLE
            Get-FoundationCoreAndTiBUsage -ClusterName "ML Cluster" -CollectLicenseKey
    #>
        param(
            [Parameter(Mandatory=$false)][string]$ClusterName,
            [Parameter(Mandatory=$false)][string]$Filename,
            [Switch]$Csv,
            [Switch]$CollectLicenseKey,
            [Switch]$DemoMode
        )

        # Helper Function to build out Computer usage object
        Function BuildFoundationUsage {
            param(
                [Parameter(Mandatory=$false)]$cluster,
                [Parameter(Mandatory=$true)]$vmhost,
                [Parameter(Mandatory=$false)][Boolean]$CollectLicenseKey,
                [Parameter(Mandatory=$false)][Boolean]$DemoMode
            )

            if($cluster -eq $null) {
                $cluster = (Get-Cluster -VMHost (Get-VMHost -Name $vmhost.name)).ExtensionData

                # Determine if ESXi is in cluster
                if($cluster -ne $null) {
                    $clusterName = $cluster.name
                }
            } else {
                $clusterName = $cluster.name
            }

            $vmhostName = $vmhost.name

            $sockets = $vmhost.Hardware.CpuInfo.NumCpuPackages
            $coresPerSocket = ($vmhost.Hardware.CpuInfo.NumCpuCores / $sockets)

            # Check if hosts is running vSAN
            if($vmhost.Runtime.VsanRuntimeInfo.MembershipList -ne $null) {
                $isVSANHost = $true
                $vsanClusters[$clusterName] = 1
            } else {
                $isVSANHost = $false
                $vsanLicenseCount = 0
            }

            # vSphere & vSAN
            if($coresPerSocket -le 16) {
                $vsphereLicenseCount = $sockets * 16
                if($isVSANHost) {
                    $vsanLicenseCount = $sockets * 16
                }
            } else {
                $vsphereLicenseCount =  $sockets * $coresPerSocket
                if($isVSANHost) {
                    $vsanLicenseCount = $sockets * $coresPerSocket
                }
            }

            # Collect vSphere and vSAN License Key
            $vsphereLicenseKey = "N/A"
            $vsanLicenseKey = "N/A"

            if($CollectLicenseKey) {
                $hostLicenses = $licenseAssignementManager.QueryAssignedLicenses($vmhost.MoRef.Value)
                foreach ($hostLicense in $hostLicenses) {
                    if($hostLicense.AssignedLicense.EditionKey -match "esx") {
                        $vsphereLicenseKey = $hostLicense.AssignedLicense.LicenseKey
                        break
                    }
                }

                if($isVSANHost) {
                    $clusterLicenses = $licenseAssignementManager.QueryAssignedLicenses($cluster.MoRef.Value)

                    foreach ($clusterLicense in $clusterLicenses) {
                        if($clusterLicense.AssignedLicense.EditionKey -match "vsan") {
                            $vsanLicenseKey = $clusterLicense.AssignedLicense.LicenseKey
                            break
                        }
                    }
                }

                # demo purpose without print license keys
                if($DemoMode) {
                    if($vsphereLicenseKey -notmatch "00000" -and $vsphereLicenseKey -notmatch "N/A") {
                        $vsphereLicenseKey = "DEMO!-DEMO!-DEMO!-DEMO!-DEMO!"
                    }

                    if($vsanLicenseKey -notmatch "0000" -and $vsanLicenseKey -notmatch "N/A") {
                        $vsanLicenseKey = "DEMO!-DEMO!-DEMO!-DEMO!-DEMO!"
                    }
                }
            }

            $tmp = [pscustomobject] @{
                CLUSTER = $clusterName;
                VMHOST = $vmhostName;
                NUM_CPU_SOCKETS = $sockets;
                NUM_CPU_CORES_PER_SOCKET = $coresPerSocket;
                FOUNDATION_LICENSE_CORE_COUNT = $vsphereLicenseCount;
                VSAN_CORE_COUNT = $coresPerSocket * $sockets;
                VSAN_LICENSE_CORE_COUNT = $vsanLicenseCount;
            }

            if($CollectLicenseKey) {
                $tmp | Add-Member -NotePropertyName VSPHERE_LICENSE_KEY -NotePropertyValue $vsphereLicenseKey
                $tmp | Add-Member -NotePropertyName VSAN_LICENSE_KEY -NotePropertyValue $vsanLicenseKey
            }

            return $tmp
        }

        # Helper Function to build out vSAN usage object
        Function BuildvSANUsage {
            param(
                [Parameter(Mandatory=$false)][string]$ClusterName,
                [Parameter(Mandatory=$false)]$TmpResults
            )

            $vsanUsageResult = Get-VsanSpaceUsage -Cluster $ClusterName

            $totalCapacityInGB = [Math]::Round($vsanUsageResult.CapacityGB,2)
            $vsanTotalCPUCount = [int](($TmpResults | where {$_.CLUSTER -eq $clusterName}).NUM_CPU_SOCKETS | Measure-Object -Sum).Sum

            # Capacity / 1TiB
            $vsanLicenseTibCount =[int]([math]::Ceiling($totalCapacityInGB / 1024))
            # 8TiB per CPU Socket
            $vsanLicenseCoreCount = [int]([math]::Ceiling($vsanTotalCPUCount * 8))

            # Formula - max($vsanTotalCPUCount*8) vs $vsanLicenseTibCount
            $totalVsanCpuCount = [int](($vsanLicenseCoreCount,$vsanLicenseTibCount)|Measure-Object -Maximum).Maximum

            $tmpVsanResult = [pscustomobject] @{
                CLUSTER = $clusterName;
                TOTAL_CAPACITY_TIB = $totalCapacityInGB / 1024;
                TOTAL_VSAN_CPU_SOCKETS = $vsanTotalCPUCount;
                TOTAL_VSAN_LICENSE_TIB_COUNT = $totalVsanCpuCount
            }
            return $tmpVsanResult
        }

        $results = @()
        $vsanResults = @()
        $tmpResults = @()
        $vsanClusters = @{}

        if($CollectLicenseKey) {
            $licenseManager = Get-View $global:DefaultVIServer.ExtensionData.Content.LicenseManager
            $licenseAssignementManager = Get-View $licenseManager.licenseAssignmentManager
        }

        if($ClusterName) {
            try {
                Get-Cluster -Name $ClusterName -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Host "`nCluster with name '$ClusterName' was not found`n" -ForegroundColor Red
                break
            }

            Write-Host "`nQuerying vSphere Cluster: $ClusterName`n"  -ForegroundColor cyan

            $clusters = Get-View -ViewType ClusterComputeResource -Property Name,Host,ConfigurationEx -Filter @{"name"=$ClusterName}
            foreach ($cluster in $clusters) {
                try {
                    $vmhosts = Get-View $cluster.host -Property Name,Hardware.systemInfo,Hardware.CpuInfo,Runtime
                } catch {
                    continue
                }
                foreach ($vmhost in $vmhosts) {
                    # Ingore HCX IX & vSAN Witness Node
                    if($vmhost.Hardware.systemInfo.Model -ne "VMware Mobility Platform" -and (Get-AdvancedSetting -Entity $vmhost.name Misc.vsanWitnessVirtualAppliance).Value -eq 0) {
                        $result = BuildFoundationUsage -cluster $cluster -vmhost $vmhost -CollectLicenseKey $CollectLicenseKey -DemoMode $DemoMode

                        $tmpResults += $result

                        $result = $result | Select-Object -ExcludeProperty VSAN_CORE_COUNT,VSAN_LICENSE_CORE_COUNT,VSAN_LICENSE_CORE_COUNT
                        $results += $result
                    }
                }

                # vSAN Storage Usage
                if($cluster.ConfigurationEx.VsanConfigInfo.Enabled) {
                    $tmpVsanResult = BuildvSANUsage -ClusterName $ClusterName -TmpResults $tmpResults

                    $vsanResults += $tmpVsanResult
                }
            }
        } else {
            Write-Host "`nQuerying all ESXi hosts, this may take several minutes..." -ForegroundColor cyan

            $vmhosts = Get-View -ViewType HostSystem -Property Name,Hardware.systemInfo,Hardware.CpuInfo,Runtime
            $cluster = $null

            foreach ($vmhost in $vmhosts) {
                # Ingore HCX IX & vSAN Witness Node
                if($vmhost.Hardware.systemInfo.Model -ne "VMware Mobility Platform" -and (Get-AdvancedSetting -Entity $vmhost.name Misc.vsanWitnessVirtualAppliance).Value -eq 0) {
                    $result = BuildFoundationUsage -cluster $cluster -vmhost $vmhost -CollectLicenseKey $CollectLicenseKey -DemoMode $DemoMode

                    $tmpResults += $result
                    $result = $result | Select-Object -ExcludeProperty VSAN_CORE_COUNT,VSAN_LICENSE_CORE_COUNT,VSAN_LICENSE_CORE_COUNT

                    $results += $result
                }
            }

            foreach ($key in $vsanClusters.keys) {
                $tmpVsanResult = BuildvSANUsage -ClusterName $key -TmpResults $tmpResults
                $vsanResults += $tmpVsanResult

            }
        }

        if($CSV) {
            If(-Not $Filename) {
                $Filename = "$($global:DefaultVIServer.Name).csv"
            }

            Write-Host "`nSaving output as CSV file to $Filename`n"
            $results | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $Filename

            if($vsanResults.count -gt 0) {
                $vsanFileName = $Filename.replace(".csv","-vsan.csv")
                Write-Host "Saving output as CSV file to $vsanFileName`n"
                $vsanResults | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $vsanFileName
            }
        } else {
            Write-Host "`nCompute Usage Information" -ForegroundColor Magenta
            if (($results | measure).Count -eq 0)  {
                Write-Host "`nESXi Hosts were not found with searching criteria`n" -ForegroundColor Red
            } else {
                $results | ft
            }

            if($vsanResults.count -gt 0) {
                Write-Host "vSAN Usage Information" -ForegroundColor Magenta
                $vsanResults | ft
            }
        }
    }
