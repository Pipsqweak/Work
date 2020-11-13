$backupPath = "C:\Windows\DirectAccess\db\RaAcctDb.bak"
$backupDescription = "Weekly full backup"
$commandTimeout = 3600

$Global:DA_DBName = "RaAcctDb"

function Get-DaDatabaseSize {
    <#
        .Synopsis
        Checks if the Direct Access Database size

        .DESCRIPTION
        This function connects to the Windows Internal Database (WID) in order to check the DirectAccess DB file sizes.

        .NOTES
        Name:        Get-DaDatabaseSize
        Author:      Javy de Koning
        Version:     1.0.0
        DateCreated: 2016-10-04
        DateUpdated: 2016-10-04
        Blog:        http://www.javydekoning.com

        .EXAMPLE
        Get-DaDatabaseSize

        Description:
        Will get filesize for the DA DB files.
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param()

    process {
        $ConnectionString = 'Server=np:\\.\pipe\MICROSOFT##WID\tsql\query;Integrated Security=True;Initial Catalog=RaAcctDb;'
        Write-Verbose "Connecting using: '$ConnectionString'"

        if ($PSCmdlet.ShouldProcess('.','Creating index')) {
            try {
                #Setup Connection to WID
                $Connection = New-Object System.Data.SqlClient.SqlConnection
                $Connection.ConnectionString = $ConnectionString
                $Connection.Open()

                #Prep Query
                $Query = $Connection.CreateCommand()
                $Query.CommandText = "SELECT name, physical_name AS current_file_location FROM sys.master_files`r`n"
                $SQLOutput = $Query.ExecuteReader()

                $Table = New-Object -TypeName 'System.Data.DataTable'
                $Table.Load($SQLOutput)

                #Get FileSize
                $Files = $Table | Where-Object {$_.name -match 'RaAcctDb|RaAcctDb_log'}
                $Size  = $Files | ForEach-Object {Get-Item $_.current_file_location} | Select-Object Name,Length

                #Close connection and return object
                $Connection.Close()
                Return $Size
            } catch {
                throw $_
            }
        }
    }
}

function Connect-DADatabase
{
    <#
        .Synopsis
        Connect to the Direct Access Database

        .DESCRIPTION
        This function connects to the Windows Internal Database (WID).

        .NOTES
        Name:        Connect-DaDatabase
        Author:      Ken Briney
        Version:     1.0.0
        DateCreated: 2020-09-02
        DateUpdated: 2020-09-02
        Blog:        Yeah Right!!

        .EXAMPLE
        $connection = Connect-DADatabase

        Description:
        Attempt to connect to the DirectAccess database ($Global:DA_DBName) -Retries times and return the connection object, or fail.

        .INPUTS
        $Retries
            0: Only try to connect to the database once. (default)
           -1: Keep trying until connected... (use with caution)

        .OUTPUTS
        $Connection
            $null if the connection failed to open, an System.Data.SqlClient.SqlConnection object if successful
    #>
    [CmdletBinding()]
    Param(
        # Path to backup file
        [Parameter(Mandatory=$false,Position=0)]
        [Int32]
        $Retries = 0
    )

    $Connection = $null

    if(-not [String]::IsNullOrEmpty($Global:DA_DBName))
    {
        $ConnectionString = "Server=np:\\.\pipe\MICROSOFT##WID\tsql\query;Integrated Security=True;Initial Catalog={0};" -f @($Global:DA_DBName)
        $Connection = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)

        $connectionAttempts = 0
        do
        {
            try
            {
                $connectionAttempts++
                $Connection.Open()

                if(($Connection.State -ne [System.Data.ConnectionState]::Open) -and (($Retries -eq -1) -or ($connectionAttempts -lt $Retries)))
                {
                    Start-Sleep -Milliseconds 500
                }
            }
            catch
            {
                throw $_
            }
        }
        while(($Connection.State -ne [System.Data.ConnectionState]::Open) -and (($Retries -eq -1) -or ($connectionAttempts -lt $Retries)))
    }
    else
    {
        Write-Error ("Missing global database name 'DA_DBName'.")
    }

    return $Connection
}

function Backup-DADatabase
{
    <#
        .Synopsis
        Backup a the Direct Access Database

        .DESCRIPTION
        This function connects to the Windows Internal Database (WID) in order to backup the DirectAccess DB files.

        .NOTES
        Name:        Backup-DaDatabase
        Author:      Ken Briney
        Version:     1.0.0
        DateCreated: 2020-09-02
        DateUpdated: 2020-09-02
        Blog:        Yeah Right!!

        .EXAMPLE
        Backup-DADatabase -BackupPath "C:\DBBackups" -BackupDescription "Comment" -RemoveBackupFile:$true

            Description:
            Will backup the DA database ($Global:DA_DBName) to "C:\DBBackups\{$Global:DA_DBName}.bak" annotating it with "Comment" then remove the back up file.

        .INPUTS
        $BackupPath : Path where the database backup file should be stored.  Do not include the file name.
        $BackupDescription : Passed to the DB backup function as the description of the backup.
        $RemoveBackupFile : IsPresent - Remove the backup file, -not IsPresent - Leave the backup file.

        .OUTPUTS
        None

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        # Path to backup file
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $BackupPath,

        [Parameter(Mandatory=$false,Position=1)]
        [String]
        $BackupDescription = [String]::Empty,

        # Do we remove the backup file once completed?
        [Parameter(Mandatory=$false,Position=2)]
        [Switch]
        $RemoveBackupFile
    )

    Process
    {
        if(-not [String]::IsNullOrEmpty($BackupPath))
        {
            if([System.IO.Directory]::Exists($BackupPath))
            {
                if(-not [String]::IsNullOrEmpty($Global:DA_DBName))
                {
                    $BackupPath = "{0}\{1}.bak" -f @($BackupPath, $Global:DA_DBName)
                    if ($PSCmdlet.ShouldProcess('.','Backup DA Database'))
                    {
                        try
                        {
                            #Setup Connection to WID
                            $Connection = Connect-DADatabase -Retries 10

                            if(($null -ne $Connection) -and ($Connection.State -eq [System.Data.ConnectionState]::Open))
                            {
                                $cmd = $Connection.CreateCommand()
                                $cmd.CommandTimeout = 3600
                                $cmd.CommandText = "BACKUP database {0} TO DISK='{1}'" -f @($Global:DA_DBName, $BackupPath)

                                if(-not [String]::IsNullOrEmpty($BackupDescription))
                                {
                                    $cmd.CommandText = "{0} WITH DESCRIPTION = '{1}'" -f @($cmd.CommandText, $BackupDescription)
                                }

                                Write-Host ("Backing up {0} to {1}." -f @($Global:DA_DBName, $BackupPath))
                                $result = $cmd.ExecuteNonQuery()
                                Write-Host ("Result: {0}" -f @($result))
                                $Connection.close()

                                if(([System.IO.File]::Exists($BackupPath)) -and ($RemoveBackupFile.IsPresent))
                                {
                                    Remove-Item -Path $BackupPath
                                }
                            }
                            else
                            {
                                Write-Error ("Failed to establish connection to DA database.  Database not backed up.")
                            }
                        }
                        catch
                        {
                            throw $_
                        }
                    }
                }
                else
                {
                    Write-Error ("Missing backup path.")
                }
            }
            else
            {
                Write-Error ("Path: {0} does not exist." -f @($BackupPath))
            }
        }
        else
        {
            Write-Error ("Missing global database name 'DA_DBName'.")
        }
    }
}

function Shrink-DaDatabase {
    <#
        .Synopsis
        Shirnks the Direct Access Database

        .DESCRIPTION
        This function connects to the Windows Internal Database (WID) in order to Shrink the DirectAccess DB files.

        .NOTES
        Name:        Shrink-DaDatabase
        Author:      Javy de Koning
        Version:     1.0.0
        DateCreated: 2016-10-04
        DateUpdated: 2016-10-04
        Blog:        http://www.javydekoning.com

        .EXAMPLE
        Shrink-DaDatabase

        Description:
        Will shrink the DA DB files (Default C:\Windows\DirectAccess\db).
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param()

    process {
        $ConnectionString = 'Server=np:\\.\pipe\MICROSOFT##WID\tsql\query;Integrated Security=True;Initial Catalog=RaAcctDb;MultipleActiveResultSets=True'
        Write-Verbose "Connecting using: '$ConnectionString'"

        if ($PSCmdlet.ShouldProcess('.','Creating index')) {
            try {
                #Setup Connection to WID
                $Connection                  = New-Object System.Data.SqlClient.SqlConnection
                $Connection.ConnectionString = $ConnectionString
                $Connection.Open()

                #ShrinkDB_Log
                $Query                = $Connection.CreateCommand()
                $query.CommandTimeout = 3600
                $Query.CommandText    = "DBCC SHRINKFILE ('RaAcctDb_log')`r`n"
                $Null = $Query.ExecuteReader()

                #ShrinkDB_Log
                $Query                = $Connection.CreateCommand()
                $query.CommandTimeout = 3600
                $Query.CommandText    = "DBCC SHRINKFILE ('RaAcctDb')`r`n"
                $Null = $Query.ExecuteReader()

                #Close connection and return object
                $Connection.Close()

            } catch {
                throw $_
            }
        }
    }
}


# Cleanup an old DB Backup
if (Test-Path $backupPath) {
    Remove-Item $backupPath -Force
}

#Backup the DA datbase
$connection = New-Object -TypeName System.Data.SqlClient.SqlConnection
$connection.ConnectionString =  'Server=np:\\.\pipe\Microsoft##WID\tsql\query;Database=RaAcctDb;Trusted_Connection=True;'
$command = $connection.CreateCommand()
$command.CommandText = " BACKUP database RaAcctDb TO DISK='$backupPath' WITH DESCRIPTION = '$backupDescription'"
$connection.Open()
$command.CommandTimeout = $commandTimeout
$command.ExecuteNonQuery()
$connection.close()

#Shrink the database
Shrink-DaDatabase
