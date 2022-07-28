using module PEI.Log

# Define the database connection class

Class DBConnection : System.IDisposable
{
    static [Int32] $maxRetries = 10
    # The underlying database connection object used by the other methods of the class
    [System.Data.SqlClient.SqlConnection] hidden $connection

    # Used for implementing System.IDisposable
    [Boolean] hidden $disposing = $false

    DBConnection (
        [String] $connectionString
    )
    {
        if(-not [String]::IsNullOrEmpty($connectionString))
        {
            $this.connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)

            if($null -eq $this.connection)
            {
                [Log]::Error("Failed to create DB connection in {0}." -f $MyInvocation.MyCommand)
            }
            else
            {
                # Nothing, the connection was successfully created
            }
        }
        else
        {
            $msg = "DB connection string missing in {0}." -f $MyInvocation.MyCommand
            [Log]::Error($msg)
            throw $msg
        }
    }

    [Boolean] Open()
    {
        if($this.connection.State -ne [System.Data.ConnectionState]::Open)
        {
            try
            {
                $this.connection.Open()
            }
            catch
            {
                [Log]::Error("Failed to open DB connection.")
            }
        }
        else
        {
            # Nothing, connection is already open
        }
        return ($this.connection.State -eq [System.Data.ConnectionState]::Open)
    }

    [Boolean] Close()
    {
        if($this.connection.State -ne [System.Data.ConnectionState]::Closed)
        {
            $this.connection.Close()
        }
        else
        {
            # Nothing, connection is already closed
        }

        return ($this.connection.State -eq [System.Data.ConnectionState]::Closed)
    }

    [Int32] ExecuteNonQuery(
        [String] $query
    )
    {
        $result = $null
        if(-not [String]::IsNullOrEmpty($query))
        {
            if($this.Open())
            {
                $cmd = $this.connection.CreateCommand()
                $cmd.CommandText = $query

                $completed = $false
                $tries = 0
                do
                {
                    try
                    {
                        $result = $cmd.ExecuteNonQuery()
                        $completed = $true
                    }
                    catch
                    {
                        $tries++

                        # Sleep a random period of time to let other transactions complete...
                        $sleepMS = Get-Random -Minimum 3 -Maximum 10
                        Start-Sleep -Milliseconds $sleepMS
                    }
                }
                while((-not $completed) -and ($tries -lt [DBConnection]::maxRetries))
                $cmd.Dispose()
                $this.Close()
            }
            else
            {
                [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
            }
        }
        else
        {
            [Log]::Error("Empty query sent to {0}!" -f $MyInvocation.MyCommand)
        }

        return $result
    }

    [System.Object] ExecuteScalar(
        [String] $query
    )
    {
        $result = $null
        if(-not [String]::IsNullOrEmpty($query))
        {
            if($this.Open())
            {
                $cmd = $this.connection.CreateCommand()
                $cmd.CommandText = $query

                $completed = $false
                $tries = 0
                do
                {
                    try
                    {
                        $result = $cmd.ExecuteScalar()
                        $completed = $true
                    }
                    catch
                    {
                        $tries++

                        # Sleep a random period of time to let other transactions complete...
                        $sleepMS = Get-Random -Minimum 3 -Maximum 10
                        Start-Sleep -Milliseconds $sleepMS
                    }
                }
                while((-not $completed) -and ($tries -lt [DBConnection]::maxRetries))

                $cmd.Dispose()
                $this.Close()
            }
            else
            {
                [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
            }
        }
        else
        {
            [Log]::Error("Empty query sent to {0}!" -f $MyInvocation.MyCommand)
        }

        return $result
    }

    [Boolean] ExecuteLoad([System.Data.SqlClient.SqlCommand] $cmd, [System.Data.DataTable] $tmpDT)
    {
        <#
            I discovered when multiple scripts were trying to make the same query, the following exception would occur:

                Exception calling "Load" with "1" argument(s): "Transaction (Process ID XXX) was deadlocked on lock resources with
                another process and has been chosen as the deadlock victim. Rerun the transaction."

            To handle this, I implemented a retry mechanism that pauses for a random period of time after each failed attempt.
            The pause is to give other transactions time to complete.
        #>

        $completed = $false
        $tries = 0
        do
        {
            try
            {
                $rdr = $cmd.ExecuteReader()
                $tmpDT.Load($rdr)
                $completed = $true
            }
            catch
            {
                $tries++

                # Sleep a random period of time to let other transactions complete...
                $sleepMS = Get-Random -Minimum 10 -Maximum 25
                Start-Sleep -Milliseconds $sleepMS
            }
        }
        while((-not $completed) -and ($tries -lt [DBConnection]::maxRetries))

        return $completed
    }

    [System.Data.DataTable] GetDataTable(
        [String] $query
    )
    {
        $tmpDT = $null
        if(-not [String]::IsNullOrEmpty($query))
        {
            $tmpDT = New-Object 'System.Data.DataTable'

            if($null -ne $tmpDT)
            {
                if($this.Open())
                {
                    $cmd = $this.connection.CreateCommand()
                    if($null -ne $cmd)
                    {
                        $cmd.CommandText = $query

                        if(-not $this.ExecuteLoad($cmd, $tmpDT))
                        {
                            [Log]::Warning("Failed to complete query: {0}" -f @($query))
                        }
                        else
                        {
                            # Nothing all is well
                        }
                        $cmd.Dispose()
                    }
                    else
                    {
                        [Log]::Error("Failed to create connection command in {0}." -f $MyInvocation.MyCommand)
                    }

                    $this.Close()
                }
                else
                {
                    [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
                }
            }
            else
            {
                [Log]::Error("Failed to create datatable in {0}." -f $MyInvocation.MyCommand)
            }
        }
        else
        {
            [Log]::Error("Empty query sent to {0}!" -f $MyInvocation.MyCommand)
        }

        return $tmpDT
    }

    [Int32] ExecuteWithTransaction(
        [System.String[]] $commandStrings
    )
    {
        $totalRowsAffected = 0
        if($null -ne $commandStrings)
        {
            if($commandStrings.Length -gt 0)
            {
                if($this.Open())
                {
                    $cmd = $this.connection.CreateCommand()
                    if($null -ne $cmd)
                    {
                        $transaction = $this.connection.BeginTransaction([System.Data.IsolationLevel]::ReadCommitted)
                        $cmd.Transaction = $transaction

                        try
                        {
                            for($l = 0; $l -lt $commandStrings.Length; $l++)
                            {
                                $cmd.CommandText = $commandStrings[$l]
                                $totalRowsAffected += $cmd.ExecuteNonQuery()
                            }
                            $transaction.Commit()
                        }
                        catch
                        {
                            $transaction.Rollback()
                            [Log]::Error("Failed to commit SQL transaction to database.")
                            [Log]::Error("Last command executed: {0}" -f $cmd.CommandText)
                        }

                        $cmd.Dispose()
                    }
                    else
                    {
                        [Log]::Error("Failed to create connection command in {0}." -f $MyInvocation.MyCommand)
                    }

                    $this.Close()
                }
                else
                {
                    [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
                }
            }
            else
            {
                [Log]::Warning("No SQL commands sent to {0}." -f $MyInvocation.MyCommand)
            }
        }
        else
        {
            [Log]::Warning("Null SQL command string array sent to {0}." -f $MyInvocation.MyCommand)
        }

        return $totalRowsAffected
    }

    [System.Object] ExecuteStoredProcedure([String] $spName, [HashTable[]] $params)
    {
        $results = $null

        if(-not [String]::IsNullOrEmpty($spName))
        {
            if($this.Open())
            {
                $cmd = $this.connection.CreateCommand()
                $cmd.CommandText = $spName
                $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
                $paramsAreValid = $true

                for($p = 0; $p -lt $params.Length; $p++)
                {
                    $isValid = $true
                    if($params[$p].ContainsKey("Name"))
                    {
                        if(-not [String]::IsNullOrEmpty($params[$p].Name))
                        {
                            $paramName = $params[$p].Name
                            if(-not $paramName.StartsWith("@"))
                            {
                                $paramName = ("@{0}" -f $params[$p].Name)
                            }
                            else
                            {
                                # Nothing
                            }

                            if($params[$p].ContainsKey("Value"))
                            {
                                # [Log]::Info("Adding parameter {0} Value {1}" -f @($paramName, $params[$p].Value.ToString()))
                                $cmd.Parameters.Add([System.Data.SqlClient.SqlParameter]::new($paramName, $params[$p].Value))
                            }
                            else
                            {
                                [Log]::Warning("Parameter ({0}) missing Value key." -f @($p))
                                $paramsAreValid = $false
                            }
                        }
                        else
                        {
                            [Log]::Warning("Parameter ({0}) has empty name." -f @($p))
                            $paramsAreValid = $false
                        }
                    }
                    else
                    {
                        [Log]::Warning("Parameter ({0}) missing Name key." -f @($p))
                        $paramsAreValid = $false
                    }
                }

                if($paramsAreValid)
                {
                    $tmpDT = New-Object 'System.Data.DataTable'

                    if(-not $this.ExecuteLoad($cmd, $tmpDT))
                    {
                        [Log]::Warning("Failed to complete query: {0}" -f @($spName))
                    }
                    else
                    {
                        # Nothing all is well
                    }

                    $cmd.Dispose()

                    if($null -ne $tmpDT)
                    {
                        if($null -ne $tmpDT.Rows)
                        {
                            if($tmpDT.Columns.Contains("ERROR"))
                            {
                                for($e = 0; $e -lt $tmpDT.Rows.Count; $e++)
                                {
                                    [Log]::Warning($tmpDT.Rows[$e].ERROR)
                                }
                            }
                            else
                            {
                                # Nothing
                            }
                        }
                        else
                        {
                            # Nothing
                        }
                    }
                    else
                    {
                        # Nothing
                    }
                    $results = $tmpDT
                }
                else
                {
                    [Log]::Warning("Not executing stored procedure {0} due to invalid parameters." -f @($spName))
                }

                $cmd.Dispose()
                $this.Close()
            }
            else
            {
                [Log]::Error("Unable to open connection to database in {0}." -f $MyInvocation.MyCommand)
            }
        }
        else
        {
            [Log]::Warning("Attempt to execute stored procedure with no name.")
        }

        return $results
    }

    static [HashTable] CreateParam([String] $paramName, [System.Object] $paramValue)
    {
        $ht = $null
        if(-not [String]::IsNullOrEmpty($paramName))
        {
            $ht = @{ Name = $paramName; Value = $paramValue }
        }
        else
        {
            [Log]::Warning("Paramater must have a name.")
        }
        return $ht
    }

    # Implement System.IDisposable

    [void] Dispose()
    {
        $this.disposing = $true

        $this.Dispose($true)
        [System.GC]::SuppressFinalize($this)
    }

    [void] Dispose(
        [bool]$disposing
    )
    {
        if($disposing)
        {
            $this.Close()
        }
    }
}
