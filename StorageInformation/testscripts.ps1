function OpenConnection
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn
    )

    $closeBeforeLeave = $false
    if ($conn.State -ne [System.Data.ConnectionState]::Open)
    {
        $conn.Open()
        $closeBeforeLeave = $true
    } `
    else # NOT ($conn.State -ne [System.Data.ConnectionState]::Open)
    {
        # Nothing.
    }

    return $closeBeforeLeave
}

function GetScalarFromQuery
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $query
    )

    $closeBeforeLeave = OpenConnection $conn

    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = $query
    $retVal = $cmd.ExecuteScalar()

    if ($closeBeforeLeave)
    {
        $conn.Close()
    } `
    else # NOT ($closeBeforeLeave)
    {
        # Nothing.
    }

    return $retVal
}

function LoadDataTableFromQuery
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $query,

        [Parameter(Mandatory=$true,Position=2)]
        [System.Data.DataTable]
        $datatable
    )

    #Write-Host ("`r`n{0}`r`n" -f @($query))
    $closeBeforeLeave = OpenConnection $conn

    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = $query

    $rdr = $cmd.ExecuteReader()

    $datatable.Load($rdr)

    if ($closeBeforeLeave)
    {
        $conn.Close()
    } `
    else # NOT ($closeBeforeLeave)
    {
        # Nothing.
    }
}

function GetDataTableFromQuery
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $query,

        [Parameter(Mandatory=$false,Position=2)]
        [System.String]
        $tableName = [String]::Empty
    )

    #Write-Host ("`r`n{0}`r`n" -f @($query))
    $closeBeforeLeave = OpenConnection $conn

    $cmd = $conn.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    $cmd.CommandText = $query

    $rdr = $cmd.ExecuteReader()

    if ([String]::IsNullOrEmpty($tableName))
    {
        $dt = [System.Data.DataTable]::new()
    } `
    else # NOT ([String]::IsNullOrEmpty($tableName))
    {
        $dt = [System.Data.DataTable]::new($tableName)
    }

    $dt.Load($rdr)

    if ($closeBeforeLeave)
    {
        $conn.Close()
    } `
    else # NOT ($closeBeforeLeave)
    {
        # Nothing.
    }

    return @(, $dt)
}

function GetSnapmirrorData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Int32]
        $runID
    )

    $query = "SELECT * FROM SnapmirrorData WHERE (RunID = {0});" -f @($runID)

    $snapmirrorData = GetDataTableFromQuery $conn $query "SnapmirrorData"

    return @(, $snapmirrorData)
}

function GetVolumeDataFromSnapmirrorData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $snapMirrorData
    )

    $volumeData = $null
    if ($snapmirrorData.Rows.Count -gt 0)
    {
        $runID = $snapmirrorData.Rows[0].RunID
        $uniqueVolumeUUIDs = [System.Collections.Generic.List[String]]::new()
        $a = 0
        while($a -lt $snapmirrorData.Rows.Count)
        {
            foreach($uuid in @($snapmirrorData.Rows[$a].SourceVolumeUUID.ToString(), $snapmirrorData.Rows[$a].DestinationVolumeUUID.ToString()))
            {
                $i = $uniqueVolumeUUIDs.BinarySearch($uuid)
                if ($i -lt 0)
                {
                    $uniqueVolumeUUIDs.Insert(-bnot $i, $uuid)
                } `
                else # NOT ($i -lt 0)
                {
                    # Nothing.
                }
            }

            $a++
        }
        $query = "SELECT * FROM VolumeData WHERE (RunID = {0}) AND (VolumeUUID IN ({1}));" -f @($runID, (($uniqueVolumeUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

        $volumeData = GetDataTableFromQuery $conn $query "VolumeData"
    } `
    else # NOT ($snapmirrorData.Rows.Count -gt 0)
    {
        # Nothing.
    }

    return @(, $volumeData)
}

function GetUniqueVolumeUUIDsFromVolumeData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $volumeData
    )

    $uniqueVolumeUUIDs = [System.Collections.Generic.List[String]]::new()
    $a = 0
    while($a -lt $volumeData.Rows.Count)
    {
        $uuid = $volumeData.Rows[$a].VolumeUUID.ToString()
        $i = $uniqueVolumeUUIDs.BinarySearch($uuid)
        if ($i -lt 0)
        {
            $uniqueVolumeUUIDs.Insert(-bnot $i, $uuid)
        } `
        else # NOT ($i -lt 0)
        {
            # Nothing.
        }

        $a++
    }

    return @(, $uniqueVolumeUUIDs)
}

function GetUniqueVServerUUIDsFromVolumeData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $volumeData
    )

    $uniqueVServerUUIDs = [System.Collections.Generic.List[String]]::new()
    $a = 0
    while($a -lt $volumeData.Rows.Count)
    {
        $uuid = $volumeData.Rows[$a].VServerUUID.ToString()
        $i = $uniqueVServerUUIDs.BinarySearch($uuid)
        if ($i -lt 0)
        {
            $uniqueVServerUUIDs.Insert(-bnot $i, $uuid)
        } `
        else # NOT ($i -lt 0)
        {
            # Nothing.
        }

        $a++
    }

    return @(, $uniqueVServerUUIDs)
}

function GetUniqueClusterUUIDsFromVServers
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $vServers
    )

    $uniqueClusterUUIDs = [System.Collections.Generic.List[String]]::new()
    $a = 0
    while($a -lt $vServers.Rows.Count)
    {
        $uuid = $vServers.Rows[$a].ClusterUUID.ToString()
        $i = $uniqueClusterUUIDs.BinarySearch($uuid)
        if ($i -lt 0)
        {
            $uniqueClusterUUIDs.Insert(-bnot $i, $uuid)
        } `
        else # NOT ($i -lt 0)
        {
            # Nothing.
        }

        $a++
    }

    return @(, $uniqueClusterUUIDs)
}

function GetVolumesFromVolumeData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $volumeData
    )

    $volumes = $null
    if ($volumeData.Rows.Count -gt 0)
    {
        $uniqueVolumeUUIDs = GetUniqueVolumeUUIDsFromVolumeData $volumeData

        $query = "SELECT * FROM Volumes WHERE (UUID IN ({0}));" -f @((($uniqueVolumeUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

        $volumes = GetDataTableFromQuery $conn $query "Volumes"
    } `
    else # NOT ($snapmirrorData.Rows.Count -gt 0)
    {
        # Nothing.
    }

    return @(, $volumes)
}

function GetVServersFromVolumeData
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $volumeData
    )

    $vServers = $null
    if ($volumeData.Rows.Count -gt 0)
    {
        $uniqueVServerUUIDs = GetUniqueVServerUUIDsFromVolumeData $volumeData

        $query = "SELECT * FROM VServers WHERE (UUID IN ({0}));" -f @((($uniqueVServerUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

        $vServers = GetDataTableFromQuery $conn $query "VServers"
    } `
    else # NOT ($snapmirrorData.Rows.Count -gt 0)
    {
        # Nothing.
    }

    return @(, $vServers)
}

function GetClustersFromVServers
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $vServers
    )

    $clusters = $null
    if ($vServers.Rows.Count -gt 0)
    {
        $uniqueClusterUUIDs = GetUniqueClusterUUIDsFromVServers $vServers

        $query = "SELECT * FROM Clusters WHERE (UUID IN ({0}));" -f @((($uniqueClusterUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

        $clusters = GetDataTableFromQuery $conn $query "Clusters"
    } `
    else # NOT ($snapmirrorData.Rows.Count -gt 0)
    {
        # Nothing.
    }

    return @(, $clusters)
}

function GetVServerFromVolume
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $vServers,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $volumeData,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [System.Data.DataRow]
        $volume
    )

    $vServer = $null
    $vd = $volumeData.Rows | Where-Object { $_.VolumeUUID -eq $volume.UUID }

    if ($null -ne $vd)
    {
        $vServer = $vServers.Rows | Where-Object { $_.UUID -eq $vd.VServerUUID }
    } `
    else # NOT ($null -ne $vd)
    {
        # Nothing.
    }

    return @(, $vServer)
}

function GetClusterFromVServer
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.DataTable]
        $clusters,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [System.Data.DataRow]
        $vServer
    )

    $cluster = $clusters.Rows | Where-Object { $_.UUID -eq $vServer.ClusterUUID }

    return @(, $cluster)
}

$connectionString = "Data Source=CDC-NTAPMGMT01\SQLExpress;Initial Catalog=StorageInformation;Integrated Security=True;"
$myConn = [System.Data.SqlClient.SqlConnection]::new($connectionString)

$maxRunID = GetScalarFromQuery $myConn "SELECT dbo.MaxRunID();"
$snapmirrorData = GetSnapmirrorData $myConn $maxRunID
$volumeData = GetVolumeDataFromSnapmirrorData $myConn $snapmirrorData
$volumes = GetVolumesFromVolumeData $myConn $volumeData
$vServers = GetVServersFromVolumeData $myConn $volumeData
$clusters = GetClustersFromVServers $myConn $vServers

$myConn.Close()

$a = 0
while($a -lt $volumes.Rows.Count)
{
    $indent = 0
    $srcVolume = $volumes.Rows[$a]
    $srcVServer = GetVServerFromVolume $vServers $volumeData $srcVolume
    if ($null -ne $srcVServer)
    {
        $cluster = GetClusterFromVServer $clusters $srcVServer
        if ($null -ne $cluster)
        {
            $srcVolumeSnapmirrorData = @($snapmirrorData.Rows | Where-Object { $_.SourceVolumeUUID -eq $srcVolume.UUID })

            if ($srcVolumeSnapmirrorData.Length -gt 0)
            {
                $b = 0
                while($b -lt $srcVolumeSnapmirrorData.Length)
                {
                    $dstVolume = $volumes | Where-Object { $_.UUID -eq $srcVolumeSnapmirrorData[$b].DestinationVolumeUUID }
                    if ($null -ne $dstVolume)
                    {

                    } `
                    else # NOT ($null -ne $dstVolume)
                    {
                        # Nothing.
                    }
                    $b++
                }
                $dstVolumeSnapmirrorData = @($snapmirrorData | Where-Object { $_.SourceVolumeUUID -eq $volumes.Rows[$a].UUID })
            } `
            else # NOT ($srcVolumeSnapmirrorData.Length -gt 0)
            {
                # Nothing.
            }
        } `
        else # NOT ($null -ne $cluster)
        {
            # Nothing.
        }
    } `
    else # NOT ($null -ne $srcVServer)
    {
        Write-Host -ForegroundColor Red ("Unable to locate VServer for volume: {0}:{1}." -f @($srcVolume.UUID, $srcVolume.Name))
    }
    $a++
}

class Cluster_04
{
    [System.Data.DataRow] $data
    [System.Collections.Generic.List[System.Data.DataRow]] $vServers

    [void] AddPsuedoMembers()
    {
        # .UUID psuedo property
        $this | Add-Member -Name UUID -MemberType ScriptProperty -Value {
            return $this.data.UUID
        }

        # .Location psuedo property
        $this | Add-Member -Name Location -MemberType ScriptProperty -Value {
            return $this.data.Location
        }

        # .SerialNumber psuedo property
        $this | Add-Member -Name SerialNumber -MemberType ScriptProperty -Value {
            return $this.data.SerialNumber
        }

        # .Contact psuedo property
        $this | Add-Member -Name Contact -MemberType ScriptProperty -Value {
            return $this.data.Contact
        }

        # .Name psuedo property
        $this | Add-Member -Name Name -MemberType ScriptProperty -Value {
            return $this.data.Name
        }
    }

    Cluster_04([System.Data.DataRow] $srcData)
    {

        if ($null -ne $srcData)
        {
            $this.data = $srcData
            $this.vServers = $this.data.GetChildRows($this.data.Table.dataset.Relations["VServers.ClusterUUID->Clusters.UUID"])
            $this.AddPsuedoMembers()
        } `
        else # NOT ($null -ne $srcData)
        {
            # Nothing.
        }
    }
}

class StorageData_13
{
    [System.Data.SqlClient.SqlConnection] $myConn = $null
    [System.Data.Dataset] $dataset
    [System.Int32] $RunID = -1

    [void] LoadVolumeData()
    {
        $volumeData = $this.dataset.Tables.Add("VolumeData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM VolumeData WHERE (RunID = {0});" -f @($this.RunID)) $volumeData
    }

    [void] LoadVolumes()
    {
        $uniqueVolumeUUIDs = @(($this.dataset.Tables["VolumeData"].DefaultView.ToTable($true, "VolumeUUID")).Rows | Select-Object -ExpandProperty VolumeUUID)
        if($uniqueVolumeUUIDs.Length -gt 0)
        {
            $query = "SELECT * FROM Volumes WHERE (UUID IN ({0}));" -f @((($uniqueVolumeUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $volumes = $this.dataset.Tables.Add("Volumes")
            LoadDataTableFromQuery $this.myConn $query $volumes
        } `
        else # NOT ($this.uniqueVolumeUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [void] LoadVServers()
    {
        $uniqueVServerUUIDs = @(($this.dataset.Tables["VolumeData"].DefaultView.ToTable($true, "vServerUUID")).Rows | Select-Object -ExpandProperty vServerUUID)
        if ($uniqueVServerUUIDs.Length -gt 0)
        {
            $query = "SELECT * FROM VServers WHERE (UUID IN ({0}));" -f @((($uniqueVServerUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $vServers = $this.dataset.Tables.Add("VServers")
            LoadDataTableFromQuery $this.myConn $query $vServers
        } `
        else # NOT ($this.uniqueVServerUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [void] LoadAggregateData()
    {
        $aggregateData = $this.dataset.Tables.Add("AggregateData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM AggregateData WHERE (RunID = {0});" -f @($this.RunID)) $aggregateData
    }

    [void] LoadAggregates()
    {
        $uniqueAggregateUUIDs = @(($this.dataset.Tables["AggregateData"].DefaultView.ToTable($true, "AggregateUUID")).Rows | Select-Object -ExpandProperty AggregateUUID)
        if ($uniqueAggregateUUIDs.Length -gt 0)
        {
            $query = "SELECT * FROM Aggregates WHERE (UUID IN ({0}));" -f @((($uniqueAggregateUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $aggregates = $this.dataset.Tables.Add("Aggregates")
            LoadDataTableFromQuery $this.myConn $query $aggregates
        } `
        else # NOT ($this.uniqueVServerUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [void] LoadClusters()
    {
        $uniqueClusterUUIDs = @(($this.dataset.Tables["VServers"].DefaultView.ToTable($true, "ClusterUUID")).Rows | Select-Object -ExpandProperty ClusterUUID)
        if ($uniqueClusterUUIDs.Length -gt 0)
        {
            $query = "SELECT * FROM Clusters WHERE (UUID IN ({0}));" -f @((($uniqueClusterUUIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $clusters = $this.dataset.Tables.Add("Clusters")
            LoadDataTableFromQuery $this.myConn $query $clusters
        } `
        else # NOT ($this.uniqueClusterUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [void] LoadShareData()
    {
        $shareData = $this.dataset.Tables.Add("ShareData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM ShareData WHERE (RunID = {0});" -f @($this.RunID)) $shareData
    }

    [void] LoadSnapmirrorData()
    {
        $snapmirrorData = $this.dataset.Tables.Add("SnapmirrorData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM SnapmirrorData WHERE (RunID = {0});" -f @($this.RunID)) $snapmirrorData
    }

    [void] LoadDatastoreData()
    {
        $datastoreData = $this.dataset.Tables.Add("DatastoreData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM DatastoreData WHERE (RunID = {0});" -f @($this.RunID)) $datastoreData
    }

    [void] LoadDatastores()
    {
        $uniqueDatastoreIDs = @(($this.dataset.Tables["DatastoreData"].DefaultView.ToTable($true, "DatastoreID")).Rows | Select-Object -ExpandProperty DatastoreID)
        if ($uniqueDatastoreIDs.Count -gt 0)
        {
            $query = "SELECT * FROM Datastores WHERE (ID IN ({0}));" -f @((($uniqueDatastoreIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $datastores = $this.dataset.Tables.Add("Datastores")
            LoadDataTableFromQuery $this.myConn $query $datastores
        } `
        else # NOT ($this.uniqueVolumeUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [void] LoadVirtualMachineData()
    {
        $virtualMachineData = $this.dataset.Tables.Add("VirtualMachineData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM VirtualMachineData WHERE (RunID = {0});" -f @($this.RunID)) $virtualMachineData
    }

    [void] LoadVirtualMachine_DatastoreData()
    {
        $virtualMachine_DatastoreData = $this.dataset.Tables.Add("VirtualMachine_DatastoreData")
        LoadDataTableFromQuery $this.myConn ("SELECT * FROM VirtualMachine_DatastoreData WHERE (RunID = {0});" -f @($this.RunID)) $virtualMachine_DatastoreData
    }

    [void] LoadVirtualMachines()
    {
        $uniqueVirtualMachineIDs = @(($this.dataset.Tables["VirtualMachineData"].DefaultView.ToTable($true, "VirtualMachineID")).Rows | Select-Object -ExpandProperty VirtualMachineID)
        if ($uniqueVirtualMachineIDs.Length -gt 0)
        {
            $query = "SELECT * FROM VirtualMachines WHERE (ID IN ({0}));" -f @((($uniqueVirtualMachineIDs | ForEach-Object { "'{0}'" -f @($_) }) -join ","))

            $virtualMachines = $this.dataset.Tables.Add("VirtualMachines")
            LoadDataTableFromQuery $this.myConn $query $virtualMachines
        } `
        else # NOT ($this.uniqueVolumeUUIDs.Count -gt 0)
        {
            # Nothing.
        }
    }

    [System.Data.DataRow[]] GetVolumesByVServerNameAndVolumeName([String] $vServerName, [String] $volumeName)
    {
        [System.Data.DataRow[]] $t_volumes = @()

        $vServerUUIDs = @($this.dataset.Tables["VServers"].Select(("Name = '{0}'" -f @($vServerName))) | Select-Object -Unique -ExpandProperty UUID)
        if ($vServerUUIDs.Length -gt 0)
        {
            $vServerFilter = @($vServerUUIDs | Foreach-Object { ("(vServerUUID = '{0}')" -f @($_)) }) -join " OR "

            $volumeUUIDs = @($this.dataset.Tables["Volumes"].Select(("Name = '{0}'" -f @($volumeName))) | Select-Object -Unique -ExpandProperty UUID)
            if ($volumeUUIDs.Length -gt 0)
            {
                $volumeDataFilter = @($volumeUUIDs | Foreach-Object { ("(VolumeUUID = '{0}')" -f @($_)) }) -join " OR "

                $selectFilter = "({0}) AND ({1})" -f @($vServerFilter, $volumeDataFilter)

                $t_volumeData = $this.dataset.Tables["VolumeData"].Select($selectFilter)

                if ($t_volumeData.Length -gt 0)
                {
                    $volumeFilter = @($t_volumeData | Foreach-Object { "(UUID = '{0}')" -f @($_.VolumeUUID) }) -join " OR "
                    $t_volumes = $this.dataset.Tables["Volumes"].Select($volumeFilter)
                } `
                else # NOT ($volumeData.Length -gt 0)
                {
                    # Nothing.
                }
            } `
            else # NOT ($volumeUUIDs.Length -gt 0)
            {
                # Nothing.
            }
        } `
        else # NOT ($vServerUUIDs.Length -gt 0)
        {
            # Nothing.
        }

        return @(, $t_volumes)
    }

    [System.Data.DataRow[]] GetVServersByClusterUUID([Guid] $clusterUUID)
    {
        [System.Data.DataRow[]] $t_Objs = @($this.dataset.Tables["VServers"].Select(("ClusterUUID = '{0}'" -f @($clusterUUID.ToString()))))

        return @(, $t_Objs)
    }

    [System.Data.DataRow[]] GetAggregatesByClusterUUID([Guid] $clusterUUID)
    {
        [System.Data.DataRow[]] $t_Objs = @($this.dataset.Tables["Aggregates"].Select(("ClusterUUID = '{0}'" -f @($clusterUUID.ToString()))))

        return @(, $t_Objs)
    }

    [void] LoadRelationships([String] $jsonFilePath)
    {
        if (-not [String]::IsNullOrEmpty($jsonFilePath))
        {
            if ([System.IO.File]::Exists($jsonFilePath))
            {
                try
                {
                    $relations = Get-Content -Path $jsonFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $a = 0
                    while($a -lt $relations.Length)
                    {
                        $pc = $this.dataset.Tables[$relations[$a].parentTable.Name].Columns[$relations[$a].parentTable.Column]
                        $b = 0
                        while($b -lt $relations[$a].childTables.Length)
                        {
                            $cc = $this.dataset.Tables[$relations[$a].childTables[$b].Name].Columns[$relations[$a].childTables[$b].Column]
                            $relationshipName = "{0}.{1}->{2}.{3}" -f @($relations[$a].childTables[$b].Name, $relations[$a].childTables[$b].Column, $relations[$a].parentTable.Name, $relations[$a].parentTable.Column)
                            $dr = [System.Data.Datarelation]::new($relationshipName, $pc, $cc)
                            $this.dataset.Relations.Add($dr)

                            $b++
                        }

                        $a++
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("ERROR: Failed to process relationship file: {0}" -f @($jsonFilePath))
                }
            } `
            else # NOT ([System.IO.File]::Exists($jsonFilePath))
            {
                Write-Host -ForegroundColor Red ("WARNING: Relationship file {0} does not exist." -f @($jsonFilePath))
            }
        } `
        else # NOT (-not [String]::IsNullOrEmpty($jsonFilePath))
        {
            # Nothing.
        }
    }

    [void] AddPsuedoMembers()
    {
        # .{TableName} psuedo properties.
        $tableNames = @($this.dataset.Tables | Select-Object -ExpandProperty TableName)
        $a = 0
        while($a -lt $tableNames.Length)
        {
            # Must be completed this was so the actual table name is included in the ScriptProperty
            #
            # ScriptProperty without using Invoke-Expression:
            #    return { $this.dataset.Tables[$tableNames[$a]] }
            #
            # ScriptProperty using Invoke-Expression:
            #    return { $this.dataset.Tables["Clusters"] }

            $cmdStatement = "`$this | Add-Member -Name {0} -MemberType ScriptProperty -Value {{ return @(, `$this.dataset.Tables[`"{0}`"]) }}" -f @($tableNames[$a])
            Invoke-Expression $cmdStatement

            $a++
        }

        # .Relations psuedo property
        $this | Add-Member -Name Relations -MemberType ScriptProperty -Value { return @(, $this.dataset.Relations) }
    }

    StorageData_13([System.Data.SqlClient.SqlConnection] $conn, [System.Int32] $runID, [String] $relationshipConfigFile)
    {
        if ($null -ne $conn)
        {
            if ($runID -gt -1)
            {
                $this.RunID = $runID

                $this.dataset = [System.Data.DataSet]::new("StorageInformation")
                $this.myConn = $conn

                # Load order matters...

                # VolumeData is required so we have Volume and VServer UUIDs available for:
                $this.LoadVolumeData()
                    $this.LoadVolumes()

                    # VServers is require so we have Cluster UUIDs available for:
                    $this.LoadVServers()
                        $this.LoadClusters()

                # AggregateData is required so we have Aggregate UUIDs available for:
                #     LoadAggregate
                $this.LoadAggregateData()
                    $this.LoadAggregates()

                $this.LoadShareData()
                $this.LoadSnapmirrorData()

                # DatastoreData is required so we have Datastore IDs available for:
                $this.LoadDatastoreData()
                    $this.LoadDatastores()

                # VirtualMachineData is required so we have VirtualMachine IDs available for:
                $this.LoadVirtualMachineData()
                    $this.LoadVirtualMachines()

                $this.LoadVirtualMachine_DatastoreData()

                $this.LoadRelationships($relationshipConfigFile)

                $this.AddPsuedoMembers()
            } `
            else # NOT ($runID -gt -1)
            {
                Write-Host -ForegroundColor Red ("Illegal value ({0}) for run ID in StorageData constructor." -f @($runID))
            }
        } `
        else # NOT ($null -ne $conn)
        {
            Write-Host -ForegroundColor Red ("SQL Connection object is null in StorageData constructor.")
        }
    }
}

$maxRunID = (GetNewRunID $myConn) - 1
$sd = [StorageData_13]::new($myConn, $maxRunID, "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\StorageInformation\Relationships.json")
$c1 = [Cluster_04]::new($sd.Clusters.Rows[0])


function GetVolumesByVServerNameAndVolumeName($vServerName, $volumeName)
{
    [System.Data.DataRow[]] $volumes = @()
    $vServerUUIDs = @($sd.VServers.Select(("Name = '{0}'" -f @($vServerName))) | Select-Object -Unique -ExpandProperty UUID)
    if ($vServerUUIDs.Length -gt 0)
    {
        $vServerFilter = @($vServerUUIDs | Foreach-Object { ("(vServerUUID = '{0}')" -f @($_)) }) -join " OR "

        $volumeUUIDs = @($sd.Volumes.Select(("Name = '{0}'" -f @($volumeName))) | Select-Object -Unique -ExpandProperty UUID)
        if ($volumeUUIDs.Length -gt 0)
        {
            $volumeDataFilter = @($volumeUUIDs | Foreach-Object { ("(VolumeUUID = '{0}')" -f @($_)) }) -join " OR "

            $selectFilter = "({0}) AND ({1})" -f @($vServerFilter, $volumeDataFilter)

            $volumeData = $sd.VolumeData.Select($selectFilter)

            if ($volumeData.Length -gt 0)
            {
                $volumeFilter = @($volumeData | Foreach-Object { "(UUID = '{0}')" -f @($_.VolumeUUID) }) -join " OR "
                $volumes = $sd.Volumes.Select($volumeFilter)
            } `
            else # NOT ($volumeData.Length -gt 0)
            {
                # Nothing.
            }
        } `
        else # NOT ($volumeUUIDs.Length -gt 0)
        {
            # Nothing.
        }
    } `
    else # NOT ($vServerUUIDs.Length -gt 0)
    {
        # Nothing.
    }

    return @(, $volumes)
}

$sd.Clusters.Rows[0].GetChildRows($sd.Relations["VServers.ClusterUUID->Clusters.UUID"])

$sd.Clusters.Rows[0].GetChildRows($sd.dataset.Relations["VServers.ClusterUUID->Clusters.UUID"])

# Clusters.UUID -> VServers.ClusterUUID
$sd.Clusters.Rows[0].GetChildRows($sd.dataset.Relations["VServers.ClusterUUID->Clusters.UUID"])
$sd.VServers.Rows[0].GetParentRow($sd.dataset.Relations["VServers.ClusterUUID->Clusters.UUID"])

# Clusters.UUID -> Aggregates.ClusterUUID
$sd.Clusters.Rows[0].GetChildRows($sd.dataset.Relations["Aggregates.ClusterUUID->Clusters.UUID"])
$sd.Aggregates.Rows[0].GetParentRow($sd.dataset.Relations["Aggregates.ClusterUUID->Clusters.UUID"])

# VServers.UUID -> VolumeData.vServerUUID
$sd.VServers.Rows[0].GetChildRows($sd.dataset.Relations["VolumeData.vServerUUID->VServers.UUID"])
$sd.VolumeData.Rows[0].GetParentRow($sd.dataset.Relations["VolumeData.vServerUUID->VServers.UUID"])
$sd.VolumeData.Rows[0].GetParentRow($sd.dataset.Relations["VolumeData.vServerUUID->VServers.UUID"]).GetParentRow("VServers.ClusterUUID->Clusters.UUID")

# Aggregates.UUID -> VolumeData.AggregateUUID
$sd.Aggregates.Rows[0].GetChildRows($sd.dataset.Relations["VolumeData.AggregateUUID->Aggregates.UUID"])
$sd.VolumeData.Rows[0].GetParentRow($sd.dataset.Relations["VolumeData.AggregateUUID->Aggregates.UUID"])

# Aggregates.UUID -> AggregateData.AggregateUUID
$sd.Aggregates.Rows[0].GetChildRows($sd.dataset.Relations["AggregateData.AggregateUUID->Aggregates.UUID"])
$sd.AggregateData.Rows[0].GetParentRow($sd.dataset.Relations["AggregateData.AggregateUUID->Aggregates.UUID"])
$sd.AggregateData.Rows[0].GetParentRow($sd.dataset.Relations["AggregateData.AggregateUUID->Aggregates.UUID"]).GetParentRow($sd.dataset.Relations["Aggregates.ClusterUUID->Clusters.UUID"])


# Volumes.UUID -> DatastoreData.VolumeUUID
$sd.Volumes.Rows[0].GetChildRows($sd.dataset.Relations["DatastoreData.VolumeUUID->Volumes.UUID"])
$sd.DatastoreData.Rows[0].GetParentRow($sd.dataset.Relations["DatastoreData.VolumeUUID->Volumes.UUID"])

# Volumes.UUID -> VolumeData.VolumeUUID
$sd.Volumes.Rows[0].GetChildRows($sd.dataset.Relations["VolumeData.VolumeUUID->Volumes.UUID"])
$sd.VolumeData.Rows[0].GetParentRow($sd.dataset.Relations["VolumeData.VolumeUUID->Volumes.UUID"])

# Volumes.UUID -> SnapmirrorData.SourceVolumeUUID
$sd.Volumes.Rows[0].GetChildRows($sd.dataset.Relations["SnapmirrorData.SourceVolumeUUID->Volumes.UUID"])

# Volumes.UUID -> SnapmirrorData.DestinationVolumeUUID
$sd.Volumes.Rows[0].GetChildRows($sd.dataset.Relations["SnapmirrorData.DestinationVolumeUUID->Volumes.UUID"])
$sd.SnapmirrorData.Rows[0].GetParentRow($sd.dataset.Relations["SnapmirrorData.SourceVolumeUUID->Volumes.UUID"])
$sd.SnapmirrorData.Rows[0].GetParentRow($sd.dataset.Relations["SnapmirrorData.DestinationVolumeUUID->Volumes.UUID"])

# Volumes.UUID -> ShareData.VolumeUUID
$sd.Volumes.Rows[0].GetChildRows($sd.dataset.Relations["ShareData.VolumeUUID->Volumes.UUID"])
$sd.ShareData.Rows[0].GetParentRow($sd.dataset.Relations["ShareData.VolumeUUID->Volumes.UUID"])

# Datastores.ID -> DatastoreData.DatastoreID
$sd.Datastores.Rows[0].GetChildRows($sd.dataset.Relations["DatastoreData.DatastoreID->Datastores.ID"])
$sd.DatastoreData.Rows[0].GetParentRow($sd.dataset.Relations["DatastoreData.DatastoreID->Datastores.ID"])

# Datastores.ID -> VirtualMachine_DatastoreData.DatastoreID
$sd.Datastores.Rows[0].GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData_DatastoreID->Datastores.ID"])
$sd.VirtualMachine_DatastoreData.Rows[0].GetParentRow($sd.dataset.Relations["VirtualMachine_DatastoreData.DatastoreID->Datastores.ID"])

# VirtualMachines.ID -> VirtualMachineData.VirtualMachineID
$sd.VirtualMachines.Rows[0].GetChildRows($sd.dataset.Relations["VirtualMachineData.VirtualMachineID->VirtualMachines.ID"])
$sd.VirtualMachineData.Rows[0].GetParentRow($sd.dataset.Relations["VirtualMachineData.VirtualMachineID->VirtualMachines.ID"])

# VirtualMachines.ID -> VirtualMachine_DatastoreData.VirtualMachineID
$sd.VirtualMachines.Rows[0].GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])
$sd.VirtualMachine_DatastoreData.Rows[0].GetParentRow($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])

# Virtual Machine...
$sd.VirtualMachines.Rows[0]

# VirtualMachine -> VirtualMachine_DatastoreData
$sd.VirtualMachines.Rows[0].
    GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])[0]

# VirtualMachine_DatastoreData -> Datastore
$sd.VirtualMachines.Rows[0].
    GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])[0].
        GetParentRow($sd.dataset.Relations["VirtualMachine_DatastoreData.DatastoreID->Datastores.ID"])

# Datastore -> DatastoreData
$sd.VirtualMachines.Rows[0].
    GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])[0].
        GetParentRow($sd.dataset.Relations["VirtualMachine_DatastoreData.DatastoreID->Datastores.ID"]).
            GetChildRows($sd.dataset.Relations["DatastoreData.DatastoreID->Datastores.ID"])

# DatastoreData -> Volumes
$sd.VirtualMachines.Rows[0].
    GetChildRows($sd.dataset.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"])[0].
        GetParentRow($sd.dataset.Relations["VirtualMachine_DatastoreData.DatastoreID->Datastores.ID"]).
            GetChildRows($sd.dataset.Relations["DatastoreData.DatastoreID->Datastores.ID"])[0].
                GetParentRow($sd.dataset.Relations["DatastoreData.VolumeUUID->Volumes.UUID"])


$sd.VirtualMachines.Rows[2].
    GetChildRows($sd.Relations["VirtualMachine_DatastoreData.VirtualMachineID->VirtualMachines.ID"]) | Foreach-Object {
        $_.GetParentRow($sd.Relations["VirtualMachine_DatastoreData.DatastoreID->Datastores.ID"]).
            GetChildRows($sd.Relations["DatastoreData.DatastoreID->Datastores.ID"]) | Foreach-Object {
                $_.GetParentRow($sd.Relations["DatastoreData.VolumeUUID->Volumes.UUID"])
            }
    }






    $avgCount = $usedSizes | Measure-Object -Average | Select-Object Average, Count



$a = 0
while($a -lt $alarms.Length)
{
    $alarmActions = @(Get-AlarmAction -Server $vCenter -AlarmDefinition $alarms[$a])

    $b = 0
    while($b -lt $alarmActions.Length)
    {
        if($alarmActions[$b].ActionType -eq [VMware.VimAutomation.ViCore.Types.V1.Alarm.ActionType]::SendEmail)
        {
            Write-Host ("Alarm name: {0}" -f @($alarms[$a].Name))
            Write-Host ("`tAction {0}: send mail to:")

            $c = 0
            while($c -lt $alarmActions[$b].To.Length)
            {
                Write-Host ("`t`t{0}" -f @($alarmActions[$b].To[$c]))
                $c++
            }
        }
        $b++
    }
    $a++
}

$sshCmdTemp = "security login publickey create -vserver {0} -username kbriney-dr -index 0 -publickey `"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCiVwrkx1nkRnJUsOiqEzkZAA85NQgfcSijyqi6LuGYiomXx8CXSXFRvNAEhfeoWFEwDwnkYYCTbEtO5jU8+Lf+2+uSfRQP0r6/rGM3cCLIVoK8P66xn09vUoD26Yu0Y+2vMR+RqQdM8+iOTt6jscljbJfQps9Ygj6ba57+XG3LpUOrto70dn8dAuO+DZcl+pPCcAzEToWU+tgcr9LBGPE2hEHnCOMUdY+y6fXN9Bbb8gLMixl6WjSFdadmY1+2L/2pdQyqdd1vPH3LFX0CXznfw6XmjlTzoIkfTnygNPqgYSUwgLveyhiliUjrQAvuoHKpfDU9/0wYaP+75/B/6Zh7bjIjiRerCVA0t/DmRlF2Hoa/+PFW3P+2tC8nGluN5pkVIQIpSpWyXt/8uIEGZQT0FKxb0GijS926lzP1tl0dsIUDX38cmExcsNymdv8pDIm4WBMD7UAHK0RgNbta5A7edMOMIngebO1TUGK0ZxvrQB35vUZL7oNS0YQn2mqNeik= theone@CDC-NTAPMGMT01`""

$cdotCluster = @($cDot.Values)
$a = 0
while($a -lt $cdotCluster.Length)
{
    try
    {
        $ncUser = Get-NCUser -Controller $cdotCluster[$a] -Name "kbriney-dr" -AuthMethod "publickey" -Application "ssh" -ErrorAction Stop
        if($null -ne $ncUser)
        {
            Write-Host ("{0}: {1}: {2}" -f @($a, $cdotCluster[$a].Name, $ncUser.UserName))
        }
        else
        {
            try
            {
                Write-Host ("Creating kbriney-dr on {0}: {1}" -f @($a, $cdotCluster[$a].Name))
                $ncUser = New-NcUser -Controller $cdotCluster[$a] -Vserver $cdotCluster[$a].Name -UserName "kbriney-dr" -Application "ssh" -AuthMethod "publickey" -Role "admin"
                if($null -ne $ncUser)
                {
                    $sshCmd = $sshCmdTemp -f @($cdotCluster[$a].Name)

                    try
                    {
                        # Does not work.  Always get an error...Have to complete this piece manually
                        Write-Host ("Creating public key...")
                        $null = Invoke-NcSsh -Controller $cdotCluster[$a] -Command $sshCmd -ErrorAction Stop
                    }
                    catch
                    {
                        Write-Host ("`tInvoke-NCSSH failed.  Removing account.")
                        try
                        {
                            $null = Remove-NcUser -Controller $cdotCluster[$a] -Vserver $cdotCluster[$a].Name -UserName "kbriney-dr" -Application "ssh" -AuthMethod "publickey" -Role "admin"
                            Write-Host "`t`tAccount removed."
                        }
                        catch
                        {
                            Write-Host ("`t`tFailed to remove account from {0}." -f @($cdotCluster[$a].Name))
                        }
                    }
                }
                else
                {
                    Write-Host ("`tNew-NCUser seems to have failed.")
                }
            }
            catch
            {
            }
        }
    }
    catch
    {

    }
    $a++
}

$vmsToChangeBack = @("BDC-APPSCM05",
"BDCD-APPSCM05",
"BDCD-GITLAB01",
"BDCD-LXADTST",
"BDC-GITLAB01",
"BDC-NTP01",
"BDC-OVMMGR01",
"BDCZ-SFTP03",
"BOIUPDATEMANAGER",
"CDC-BITWRDN01",
"CDC-NTP01",
"CDC-OVMMGR01",
"CDC-POLYCOM01",
"CDC-PPTRAP01",
"CDC-WIKI01",
"CDCZ-NSVPX02",
"DDC-ANSMGMT01",
"DDCD-BITWRDN01",
"DDCD-EXABMCOL01",
"DDCD-GITLAB01",
"DDCD-PDAPP01",
"DDCD-SASAPP01",
"DDCD-WIKI01",
"DDC-EXABMCOL01",
"DDC-IPAM01",
"DDC-NTAPAIQUM01",
"DDC-NTAPHVST01",
"DDC-OVMMGR01",
"DDC-PDAPP01",
"DDC-REPO-01",
"DDC-REPO-02",
"DDC-REPO-03",
"DDC-SASAPP01",
"DDC-STATSEEKER01",
"DDCT-RHEL705",
"DDCT-RHEL709",
"DDCT-RHEL801",
"DDCT-RHEL802",
"DDCTZ-NSVPX01",
"DDC-WIKI01",
"DDC-XCLARITY01",
"DDCZ-NSVPX02",
"vcenter")

$a = 0
$vms = Get-VM -Server $vCenter
while($a -lt $vms.Length)
{
    if($vms[$a].Name -notmatch "^vCLS")
    {
        if($vms[$a].Name -in $vmsToChangeBack)
        {
            $vms[$a].ExtensionData.ReconfigVM($vmConfigSpec)
        }
        <#
        if($vms[$a].ExtensionData.Guest.ToolsVersionStatus -eq "guestToolsUnmanaged")
        {
            Write-Host ("{0}  {1}  {2}  {3}  {4}" -f @($vms[$a].Name, $vms[$a].ExtensionData.Guest.ToolsStatus, $vms[$a].ExtensionData.Guest.ToolsVersionStatus, $vms[$a].ExtensionData.Guest.ToolsVersion, $vms[$a].ExtensionData.Config.Tools.ToolsUpgradePolicy))
            $vms[$a].ExtensionData.ReconfigVM($vmConfigSpec)
        }
        #>

        <#
        if($vms[$a].ExtensionData.Guest.ToolsStatus -in @("toolsOk","toolsOld"))
        {
            if($vms[$a].ExtensionData.Config.Tools.ToolsUpgradePolicy -ne "upgradeAtPowerCycle")
            {
                Write-Host ("{0}  {1}  {2}  {3}" -f @($vms[$a].Name, $vms[$a].ExtensionData.Guest.ToolsStatus, $vms[$a].ExtensionData.Guest.ToolsVersion, $vms[$a].ExtensionData.Config.Tools.ToolsUpgradePolicy))
                $vms[$a].ExtensionData.ReconfigVM($vmConfigSpec)
            }
        }
        #>
    }
    $a++
}

$vCenter = Connect-VIServer -Server vCenter.powereng.com -NotDefault

$vmConfigSpec = [VMware.Vim.VirtualMachineConfigSpec]::new()
$vmConfigSpec.Tools = [VMware.Vim.ToolsConfigInfo]::new()
$vmConfigSpec.Tools.ToolsUpgradePolicy = "UpgradeAtPowerCycle"

$a = 0
$vms = Get-VM -Server $vCenter
while($a -lt $vms.Length)
{
    if($vms[$a].Name -notmatch "^vCLS")
    {
        if($vms[$a].ExtensionData.Guest.ToolsStatus -in @("toolsOk","toolsOld"))
        {
            if($vms[$a].ExtensionData.Config.Tools.ToolsUpgradePolicy -ne "upgradeAtPowerCycle")
            {
                Write-Host ("{0}  {1}  {2}  {3}" -f @($vms[$a].Name, $vms[$a].ExtensionData.Guest.ToolsStatus, $vms[$a].ExtensionData.Guest.ToolsVersion, $vms[$a].ExtensionData.Config.Tools.ToolsUpgradePolicy))
                $vms[$a].ExtensionData.ReconfigVM($vmConfigSpec)
            }
        }
    }
    $a++
}




<#
    Copy test files to each Xchange share then change the test to pull FROM the filer to the client.
#>

$off2RDCMetrics = Get-Content .\RDC\Metrics\config.json | ConvertFrom-Json
$ipv4s = @(Get-NetIPAddress | Where-Object { ($_.AddressFamily -eq "IPv4") -and ($_.InterfaceAlias -notmatch "Loopback") -and ($_.IPAddress.StartsWith("10.") -and ($_.InterfaceAlias -notmatch "Device Tunnel"))})
$hostOffice = $off2RDCMetrics.Offices | Where-object { $ipv4s[0].IPAddress.StartsWith($_.Network) }
$hostRDC = $off2RDCMetrics.RDCs | Where-Object { $_.Name -eq $hostOffice.RDC }


<#
    Copy test files to \\*\Xchange\RDCTestFiles
#>

<#
    To test from remote systems to a datacenter...

    1. Get-DHCPServerInDC
    2. Get 'ClientLAN' scopes
    3. Find active client
    4. Run test from client


    Click test from remote laptop desktop...

    1. Determine which office the laptop is in based on IP address.
    2. Determine which RDC the office is associated (from config.json)
    3. Get the list of test files from \\
#>


<#
    Build RDC test files...
#>
$a = 51
$v = @(0..255)
while($a -le 60)
{
    $size = Get-Random -Minimum 500KB -Maximum 2MB
    $inc = [int] ($size / 40)

    Write-Host -NoNewline ("Creating test file {0} size {1}..." -f @($a, $size))
    $buffer =  [byte[]]::new($size)

    $b = 0
    while($b -lt $size)
    {
        $nxtCount = $v.Length
        if(($nxtCount + $b) -gt $size)
        {
            $nxtCount = $size - $b
        }
        $c = $v | Get-Random -Count $nxtCount

        $d = 0
        while($d -lt $c.Length)
        {
            $buffer[$b] = $c[$d]
            $b++
            $d++
            if(($b % $inc) -eq 0)
            {
                Write-Host -NoNewline "."
            }
        }
    }
    $fn = "C:\Temp\RDCTestFiles\testfile{0:D2}.bin" -f @($a)
    [System.IO.File]::WriteAllBytes($fn, $buffer)
    Write-Host "complete"
    $a++
}


do
{
    $snapmirror = Get-NCSnapmirror -Controller $at4CDOT -DestinationVolume "vol_vmware_RDC_SATA_01"
    if($snapmirror.Status -ne "idle")
    {
        Start-Sleep -Seconds 10
    }
} until ($snapmirror.Status -eq "idle")


    $message = "I think the subject says it all"
    $smtpClient = [System.Net.Mail.SmtpClient]::new("smtp.powereng.com")
    $mailMessage = [System.Net.Mail.MailMessage]::new()
    $mailMessage.Subject = "{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMdd"), "RDC VM Snapmirror is IDLE")
    $mailMessage.From = "Boogie Man <pathcleaner@powereng.com>"
    $toAddresses = @("Ken Briney <ken.briney@powereng.com>", "Chris Chenore <chris.chenore@powereng.com>")
    $toAddresses | ForEach-Object { $mailMessage.To.Add($_) }
    $mailMessage.Body = $message
    $mailMessage.ReplyTo = [mailaddress]::new("DoNotReply <donotreply@powereng.com>")

    try
    {
        $Error.Clear()
        $smtpClient.Send($mailMessage)
    }
    catch
    {
    }

<# Query NetApp based on attributes... #>
$v = Get-NcVol -Template -Controller $cdcCDOT
Initialize-NcObjectProperty $v VolumeAutosizeAttributes
$v.VolumeAutosizeAttributes.IsEnabled = $true
$autoSizeVols = Get-NcVol -Query $v -Controller $cdcCDOT
