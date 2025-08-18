function ConvertTo-Timespan
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $duration
    )

    [int] $days = 0
    [int] $hours = 0
    [int] $minutes = 0
    [int] $seconds = 0
    if($duration -match "([\d]+)d")
    {
        $days = [int] $Matches[1]
    }

    if($duration -match "([\d]+)h")
    {
        $hours = [int] $Matches[1]
    }

    if($duration -match "([\d]+)m")
    {
        $minutes = [int] $Matches[1]
    }

    if($duration -match "([\d]*)s")
    {
        $seconds = [int] $Matches[1]
    }

    $ts = [TimeSpan]::new($days, $hours, $minutes, $seconds)
    return $ts
}

try
{
    # Connect to all the Production CDOT clusters...
    ConnectTo cdot,prod

    # Capture the time the data is being collected
    $now = [DateTime]::Now
    $collectionTime = [DateTime]::new($now.Year, $now.Month, $now.Day, $now.Hour, $now.Minute, 0, 0, 0)

    # Capture all the current CIFS sessions on all the CDOT clusters...
    $cifsSessions = @(Get-NcCifsSession -Controller @($cdot.Values))

    # Get a list of all the shares on the CDOT clusters to facilitate creating a list of unique locations.
    $cifsShares = [System.Collections.Generic.List[Object]]::new()
    @(Get-NCCifsShare -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.ShareName -ne "c$") -and ($_.ShareName -ne "ipc$") -and ($_.ShareName -ne "admin$") }) | Sort-Object -Property @{E={$_.NCController.Name}; Descending = $false}, @{E={$_.CifsServer}; Descending = $false}, @{E={$_.Path}; Descending = $false} | Foreach-Object { $cifsShares.Add($_) }

    # Create a list of unique CIFS VServers
    $smbVServers = [System.Collections.Generic.List[String]]::new()
    $cifsShares | Select-Object -Unique -ExpandProperty CifsServer | ForEach-Object { $smbVServers.Add($_) }

    # Next create a list of unique locations based on the names of the VServers.
#    $locations = @($cifsShares | Select-Object -Unique @{N='DC';E={ ($_.NCController.Name -split "`-")[0]}}, @{N='Site';E={ $s = ($_.CifsServer -split "`-")[0]; if($s.EndsWith("DR")) { $s = $s.SubString(0, $s.Length-2) } if($s.EndsWith("Z")) { $s = $s.SubString(0, $s.Length-1) } $s }})
    $locations = @($cifsShares | Select-Object -Unique @{N='DC';E={ ($_.NCController.Name.ToUpper().Replace("BDC","DDC") -split "`-")[0]}}, @{N='Site';E={ ($_.CifsServer.ToUpper() -split "`-")[0] }})

<#
    $locations = @(
        $smbVServers | Foreach-Object {
            $parts = ($_ -split "\-")
            if($parts.Length -gt 1)
            {
                $loc = $parts[0]
                if($loc.Endswith("DR"))
                {
                    $loc = $loc.SubString(0, $loc.Length - 2)
                }

                if($loc.Endswith("Z"))
                {
                    $loc = $loc.SubString(0, $loc.Length - 1)
                }

                $loc
            }
        } | Sort-Object | Select-Object -Unique
    )
#>

# Here is where I capture the session data...
    $cifsData = [System.Collections.Generic.List[Object]]::new()

    # For each of the unique locations, tally up the count of active CIFS sessions from all the VServers at the location...
    $a = 0
    while($a -lt $locations.Length)
    {
        $d = "" | Select-Object CollectionTime, DC, Site, Count
        $d.CollectionTime = $collectionTime.ToOADate()

        $d.DC = $locations[$a].DC
        $d.Site = $locations[$a].Site
        $locationCifsSessions = @($cifsSessions | Where-Object { ($_.NCController.Name.ToUpper().Replace("BDC","DDC").StartsWith($locations[$a].DC)) -and ($_.VServer.ToUpper().StartsWith($locations[$a].Site)) -and ((ConvertTo-Timespan $_.IdleTime).TotalSeconds -lt 120) })
        $d.Count = $locationCifsSessions.Length
        # Write-Host ("DC/Site: {0}/{1} -> {2}" -f @($d.DC, $d.Site, $d.Count)) # (($locationCifsSessions | Select-Object -Unique -ExpandProperty VServer | Sort-Object) -join ", ")))

        $cifsData.Add($d)
        $a++
    }

    # Add the current data to the pre-existing data...
    $cifsData | Export-CSV -Append -Path "E:\Data\CifsSessions.csv" -Delimiter "`t" -NoTypeInformation
    $cifsData | Export-Excel -Append -Path "E:\Data\Stats\CifsSessions.xlsx"
}
catch {
    # Only save data if nothing bad happens...
}


function AddDataMap
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [System.Data.SqlClient.SqlConnection]
        $conn,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $tableName,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [ValidateCount(1, [Int32]::MaxValue)]
        [string[]]
        $keyColumns,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNull()]
        [ValidateCount(1, [Int32]::MaxValue)]
        [System.Object[]]
        $dataSource,

        [Parameter(Mandatory=$true,Position=4)]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $dataMaps
    )

    $dataMap = $null

    # Get a list of property names in the datasource (convert them to all uppercase)
    $propertyNames = @(@($dataSource | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name).ForEach("ToUpper"))

    if($propertyNames.Length -gt 0)
    {
        # Create the datamap object
        $dataMap = "" | Select-Object DataSource,TableName,Columns,KeyColumns,NewRows,ModifiedRows,DeletedRows

        $dataMap.DataSource = $dataSource
        $dataMap.TableName = $tableName
        $dataMap.Columns = [System.Collections.Generic.Dictionary[[System.String],[System.Data.DataRow]]]::new()
        $dataMap.KeyColumns = @($keyColumns.Foreach("ToUpper"))
        $dataMap.NewRows = $null
        $dataMap.ModifiedRows = $null
        $dataMap.DeletedRows = $null

        # Open the connection if it's closed
        $connectionWasClosed = $conn.State -eq [System.Data.ConnectionState]::Closed
        if($connectionWasClosed)
        {
            $conn.Open()
        }

        # Get the table schema
        $cmd = $conn.CreateCommand()
        $cmd.CommandType = [System.Data.CommandType]::Text
        $cmd.CommandText = "SELECT * FROM [{0}] WHERE (1=0);" -f @($tableName)
        $tableSchemaReader = $cmd.ExecuteReader()
        $dtTableSchema = $tableSchemaReader.GetSchemaTable()
        $tableSchemaReader.Close()

        # If the connection was opened in the function, then close it.  (Leave it like it was when the function started)
        if($connectionWasClosed -and ($conn.State -ne [System.Data.ConnectionState]::Closed))
        {
            $conn.Close()
        }

        if($dtTableSchema.Rows.Count -gt 0)
        {
            # Make sure every column is represented in the datasource.
            #   And populate $dataMap.Columns
            $a = 0
            while($a -lt $dtTableSchema.Rows.Count)
            {
                $columnName = $dtTableSchema.Rows[$a].ColumnName.ToUpper()
                $dataMap.Columns.Add($columnName, $dtTableSchema.Rows[$a])

                if(-not $propertyNames.Contains($columnName))
                {
                    LogError ("Missing property {0} in {1} datasource." -f @($columnName, $tableName))
                }
                $a++
            }

            # If $propertyNames has a different number of elements than $dataMap.Columns, then there are missing or extra properties... tell the caller about them.
            #    However, we checked for missing properties in the loop above, so here, there must be extra properties.
            if($propertyNames.Length -ne $dataMap.Columns.Count)
            {
                $a = 0
                while($a -lt $propertyNames.Length)
                {
                    if(-not $dataMap.Columns.ContainsKey($propertyNames[$a]))
                    {
                        LogError ("Extra datasource property {0} in {1}." -f @($propertyNames[$a], $tableName))
                    }
                    $a++
                }
            }
            else
            {
                # Nothing, if $propertyNames.Length -eq $dataMap.Columns.Count then all columns/properties were checked in the previous loop.
            }

            # Make sure all the key columns exist.
            $a = 0
            while($a -lt $dataMap.KeyColumns.Length)
            {
                if(-not $dataMap.Columns.ContainsKey($dataMap.KeyColumns[$a]))
                {
                    LogError ("Unknown key column {0} to table {1}." -f @($dataMap.KeyColumns[$a], $dataMap.TableName))
                }
                $a++
            }
        }
        else
        {
            LogError ("Unable to determine schema for {0}." -f @($tableName))
        }
    }
    else
    {
        LogError ("Unable to determine property names from datasource for {0}." -f @($tableName))
    }

    $dataMaps.Add($dataMap)
    LogInfo ("{0}: {1}" -f @($dataMap.TableName, $dataMap.DataSource.Length))
}


function SaveToDB
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [Object[]]
        $cifsData
    )

    $connectionString = "Data Source=.\SQLExpress;Initial Catalog=CifsSessionStats;Integrated Security=True;"
    try
    {
        $myConn = [System.Data.SqlClient.SqlConnection]::new($connectionString)
        $myConn.Open()

        $columnNames = @("CollectionTime", "Datacenter", "Site", "Sessions")
        # Base INSERT Query for the $dataMap
        $insertQuery = "INSERT INTO [dbo].[Stats] ([CollectionTime], [Datacenter], [Site], [Sessions]) VALUES"

        # $querySB is used to construct a complete SQL Statement
        $querySB = [System.Text.StringBuilder]::new()

        $cmd = $conn.CreateCommand()
        $cmd.CommandType = [System.Data.CommandType]::Text


        $rowNumber = 0
        $totalInserts = 0
        while(($null -ne $cifsData) -and ($rowNumber -lt $cifsData.Count))
        {
            $row = $cifsData[$rowNumber]

            # If the query string builder is empty, then start it out with $insertQuery
            if($querySB.Length -eq 0)
            {
                [void] $querySB.AppendLine($insertQuery)

                # If I'm just now adding $insertQuery to $querySB, then I can also clear $cmd.Parameters for good measure.
                $cmd.Parameters.Clear()
            }

            # temporary array for this row's parameter set
            $parameterSet = @()
            $p = 0
            while($p -lt $columnNames.Length)
            {
                $param = "" | Select-Object Name, Value
                $param.Name = "@{0}{1}" -f @($columnNames[$p], $rowNumber)
                $param.Value = $row.$($columnNames[$p])

                $sqlParam = $cmd.Parameters.Add($param.Name, $dataMap.Columns[$dataMapColumnNames[$p]].ProviderSpecificDataType)
                $sqlParam.Value = $param.Value

                $parameterSet += $param.Name
                $p++
            }

            # Parameters to $querySB
            [void] $querySB.Append(("({0})" -f @(($parameterSet -join ","))))

            # Increment to the next row.  Must be completed prior to the if statements below for them to be evaluated accurately
            $rowNumber++

            # If this is not the last row, append a ,<cr-lf> otherwise, just <cr-lf> to $querySB
            if($rowNumber -ne $dataMap.NewRows.Rows.Count)
            {
                [void] $querySB.AppendLine(",")
            }
            else
            {
                [void] $querySB.AppendLine("")
            }

            <#
                Reference:
                    https://learn.microsoft.com/en-us/sql/sql-server/maximum-capacity-specifications-for-sql-server?redirectedfrom=MSDN&view=sql-server-ver15
                        Parameters per user-defined function: 2100

                    I chose to stop adding parameters closer to 2000 just to be safe.

                If
                    1) adding the next row of parameters to $cmd.Parameters will exceed 2000 parameters, OR
                    2) we are at the end of rows to insert
                then execute the INSERT and reset to start again if we need to.
            #>
            if((($cmd.Parameters.Count + $dataMap.Columns.Count) -gt 2000) -or ($rowNumber -eq $dataMap.NewRows.Rows.Count))
            {
                # Trim extraneous characters off the end of the query.  I think I fixed the issue, but doesn't hurt to leave this as is.
                $cmd.CommandText = $querySB.ToString().TrimEnd(@("`r","`n",","))

                $r = $cmd.ExecuteNonQuery()
                $totalInserts += $r

                # Clear $querySB and reseed it with $insertQuery so it's read for any remaining rows (if the query got too large)...
                [void] $querySB.Clear()
                [void] $querySB.AppendLine($insertQuery)
                $cmd.Parameters.Clear()
            }
        }



    }
    catch
    {
        Write-Error "Unable to connect to CifsSessionStats DB."
    }
}
<#
$cifsData2 = Import-CSV -Path "E:\Data\CifsSessions.csv" -Delimiter "`t"
$a = 0
while($a -lt $cifsData2.Length)
{
    $year = [int] $cifsData2[$a].CollectionTime.Substring(0,4)
    $month = [int] $cifsData2[$a].CollectionTime.Substring(4,2)
    $day = [int] $cifsData2[$a].CollectionTime.Substring(6,2)
    $hour = $cifsData2[$a].CollectionTime.Substring(9,2)
    $minute = $cifsData2[$a].CollectionTime.Substring(11,2)
    $dt = [DateTime]::new($year, $month, $day, $hour, $minute, 0, 0, 0)
    $cifsData2[$a].CollectionTime = $dt.ToOADate()
    $a++
}
$cifsData2 | Export-Excel -Path "E:\Data\Stats\CIFSSessions.xlsx"
#>
