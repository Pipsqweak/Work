class LocalDB
{
    static [String] $DB_DIRECTORY = "E:\Data"

    static [System.Data.SqlClient.SqlConnection] GetLocalDB([String] $dbName, [bool] $deleteIfExists = $false)
    {
        [System.Data.SqlClient.SqlConnection] $conn = $null

        try
        {
            # $outputFolder = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName([System.Reflection.Assembly]::GetExecutingAssembly().Location), [LocalDB]::DB_DIRECTORY)
            $outputFolder = [LocalDB]::DB_DIRECTORY

            $mdfFilename = "{0}.mdf" -f @($dbName)
            $dbFileName = [System.IO.Path]::Combine($outputFolder, $mdfFilename)
            $logFileName = [System.IO.Path]::Combine($outputFolder, ("{0}_log.ldf" -f @($dbName)))

            # Create Data Directory If It Doesn't Already Exist.
            if (-not [System.IO.Directory]::Exists($outputFolder))
            {
                [System.IO.Directory]::CreateDirectory($outputFolder)
            }

            # If the file exists, and we want to delete old data, remove it here and create a new database.
            if ([System.IO.File]::Exists($dbFileName) -and $deleteIfExists)
            {
                if ([System.IO.File]::Exists($logFileName))
                {
                    [System.IO.File]::Delete($logFileName)
                }
                [System.IO.File]::Delete($dbFileName)
                [LocalDB]::CreateDatabase($dbName, $dbFileName)
            }
            # If the database does not already exist, create it.
            elseif (-not [System.IO.File]::Exists($dbFileName))
            {
                [LocalDB]::CreateDatabase($dbName, $dbFileName)
            }

            # Open newly created, or old database.
            $connectionString = "Data Source=(LocalDB)\MSSQLLocalDB;AttachDBFileName={1};Initial Catalog={0};Integrated Security=True;" -f @($dbName, $dbFileName)
            $conn = [System.Data.SqlClient.SqlConnection]::new($connectionString)
            $conn.Open()
        }
        catch
        {
            throw
        }

        return $conn
    }

    static [bool] CreateDatabase([string] $dbName, [string] $dbFileName)
    {
        [bool] $retval = $false

        try
        {
            $connectionString = "Data Source=(LocalDB)\MSSQLLocalDB;Initial Catalog=master;Integrated Security=True"

            $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
            $connection.Open()
            $cmd = $connection.CreateCommand()

            [LocalDB]::DetachDatabase($dbName)

            $cmd.CommandText = "CREATE DATABASE {0} ON (NAME = N'{0}', FILENAME = '{1}')" -f @($dbName, $dbFileName)
            $cmd.ExecuteNonQuery()

            $connection.Close()

            if ([System.IO.File]::Exists($dbFileName))
            {
                $retval = $true
            }
        }
        catch
        {
            throw
        }

        return $retval
    }

    static [bool] DetachDatabase([string] $dbName)
    {
        [bool] $retval = $false

        try
        {
            $connectionString = "Data Source=(LocalDB)\MSSQLLocalDB;Initial Catalog=master;Integrated Security=True"
            $connection = [System.Data.SqlClient.SqlConnection]::new($connectionString)
            $connection.Open()
            $cmd = $connection.CreateCommand()
            $cmd.CommandText = "ALTER DATABASE [{0}] SET OFFLINE WITH ROLLBACK IMMEDIATE" -f @($dbName)
            $cmd.ExecuteNonQuery()

            $cmd.CommandText = "exec sp_detach_db '{0}'" -f @($dbName)
            $cmd.ExecuteNonQuery();
            $connection.Close()

            $retval = $true
        }
        catch
        {
        }

        return $retval
    }
}
