Function Get-vSpherePlusCPUSocketToCoreUsage {
    <#
        .DESCRIPTION Retrieves vSphere+/vSAN+ CPU Core Usage Analysis
        .NOTES  Author:  William Lam, VMware
        .NOTES  Last Updated: 11/24/2022
        .NOTES  Hardware.systemInfo property was missing from filter for vSAN/HCX Virtual Appliance
        .PARAMETER ClusterName
            Name of a specific vSphere Cluster
        .PARAMETER CSV
            Output to CSV file
        .PARAMETER Filename
            Specific filename to save CSV file (default: <vcenter name>.csv)
        .EXAMPLE
            Get-vSpherePlusCPUSocketToCoreUsage
        .EXAMPLE
            Get-vSpherePlusCPUSocketToCoreUsage -ClusterName Production-01
        .EXAMPLE
            Get-vSpherePlusCPUSocketToCoreUsage -ClusterName Production-01 -CSV
        .EXAMPLE
            Get-vSphereCPUSockGet-vSpherePlusCPUSocketToCoreUsagetToCoreUsage -ClusterName Production-01 -CSV -Filename Production-01-Cluster.csv
    #>
        param(
            [Parameter(Mandatory=$false)][string]$ClusterName,
            [Parameter(Mandatory=$false)][string]$Filename,
            [Switch]$Csv
        )

        # Helper Function to build out CPU usage object
        Function BuildvSpherePlusCPUSocketToCoreUsage {
            param(
                [Parameter(Mandatory=$false)]$cluster,
                [Parameter(Mandatory=$true)]$vmhost
            )

            if($null -eq $cluster) {
                $clusterName = Get-Cluster -VMHost (Get-VMHost -Name $vmhost.name )
            } else {
                $clusterName = $cluster.name
            }

            $vmhostName = $vmhost.name

            $sockets = $vmhost.Hardware.CpuInfo.NumCpuPackages
            $coresPerSocket = ($vmhost.Hardware.CpuInfo.NumCpuCores / $sockets)

            # Check if hosts is running vSAN
            if($null -ne $vmhost.Runtime.VsanRuntimeInfo.MembershipList) {
                $isVSANHost = $true
            } else {
                $isVSANHost = $false
                $vsanPlusLicenseCount = 0
            }

            # vSphere+ & vSAN+
            if($coresPerSocket -le 16) {
                $vspherePlusLicenseCount = $sockets * 16
                if($isVSANHost) {
                    $vsanPlusLicenseCount = $sockets * 16
                }
            } else {
                $vspherePlusLicenseCount =  $sockets * $coresPerSocket
                if($isVSANHost) {
                    $vsanPlusLicenseCount = $sockets * $coresPerSocket
                }
            }

            $tmp = [pscustomobject] @{
                CLUSTER = $clusterName;
                VMHOST = $vmhostName;
                NUM_CPU_SOCKETS = $sockets;
                NUM_CPU_CORES_PER_SOCKET = $coresPerSocket;
                VSPHEREPLUS_LICENSE_CORE_COUNT = $vspherePlusLicenseCount;
                VSANPLUS_LICENSE_CORE_COUNT = $vsanPlusLicenseCount
            }

            return $tmp
        }

        $results = @()

        if($ClusterName) {
            try {
                Get-Cluster -Name $ClusterName -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Host "`nCluster with name '$ClusterName' was not found`n" -ForegroundColor Red
                break
            }

            Write-Host "`nQuerying hosts in cluster $ClusterName`n"  -ForegroundColor Green

            $clusters = Get-View -ViewType ClusterComputeResource -Property Name,Host -Filter @{"name"=$ClusterName}
            foreach ($cluster in $clusters) {
                try {
                    $vmhosts = Get-View $cluster.host -Property Name,Hardware.systemInfo,Hardware.CpuInfo,Runtime
                } catch {
                    continue
                }
                foreach ($vmhost in $vmhosts) {
                    if($vmhost.Hardware.systemInfo.Model -ne "VMware Mobility Platform") {
                        $result = BuildvSpherePlusCPUSocketToCoreUsage -cluster $cluster -vmhost $vmhost

                        $results += $result
                    }
                }
            }
        } else {
            Write-Host "`nQuerying all hosts, this may take several minutes...`n" -ForegroundColor Green

            $vmhosts = Get-View -ViewType HostSystem -Property Name,Hardware.systemInfo,Hardware.CpuInfo,Runtime
            $cluster = $null
            foreach ($vmhost in $vmhosts) {
                if($vmhost.Hardware.systemInfo.Model -ne "VMware Mobility Platform") {
                    $result = BuildvSpherePlusCPUSocketToCoreUsage -cluster $cluster -vmhost $vmhost

                    $results += $result
                }
            }
        }

        if($CSV) {
            If(-Not $Filename) {
                $Filename = "$($global:DefaultVIServer.Name).csv"
            }

            Write-Host "`nSaving output as CSV file to $Filename`n"
            $results | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $Filename
        } else {
            if (($results | Measure-Object).Count -eq 0)  {
                Write-Host "`nHosts were not found with searching criteria`n" -ForegroundColor Red
            } else {
                $results | Sort-Object Cluster, VMHost | Format-Table
                $results | Sort-Object Cluster, VMHost | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation | Set-Clipboard
            }
        }
    }
