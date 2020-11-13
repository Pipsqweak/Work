# For Debugging
$JSONArgsFile = "C:\Users\kbriney\KLB\PEI-IT-OPS\Utilities\VirtualInventory\invCfg.json"
Set-Location -Path "C:\Users\kbriney\KLB\PEI-IT-OPS\Utilities\VirtualInventory"


$sb = [System.Text.StringBuilder]::new()

# Import the modules we need for access to various management systems

# Assume we have all the required modules until we learn otherwise.
$haveRequiredModules = $true

# The list of all modules required for this script.
$requiredModules = @(
    "Cisco.UCS.Core",
    "Cisco.UCSManager",
    "LXCAPSTool",
    "VMWare.VimAutomation.Core",
    "DataONTAP",
    "Intersight"
)

$availableModules = @(Get-Module -ListAvailable)
$a = 0
while($a -lt $requiredModules.Length)
{
    if(($availableModules | Where-Object { $_.Name -match $requiredModules[$a] }).Length -gt 0)
    {
        Import-Module -Name $requiredModules[$a]
    }
    else
    {
        [void] $sb.AppendLine(("Missing required module {0}" -f @($requiredModules[$a])))
        $haveRequiredModules = $false
    }

    $a++
}

# Source in LoadConfigurationData function.  This function is stored externally since it is used in other scripts.
. .\LoadConfigurationData.ps1

# Verify LoadConfigurationData was source into the script.
$found = $false
try { Get-ChildItem -Path Function:\LoadConfigurationData -ErrorAction Stop | Out-Null; $found = $true } catch { }

if ($found)
{
    # TRUE

    # Source in the [Log] class
    . .\Log.ps1   # Once the [Log] class is loaded, the Global variable LoggerClassLoaded is set to $true

    if($Global:LoggerClassLoaded -eq $true)
    {
        # Initialize logging.
        [Log]::Init("..\Logs", "VirtualInventory", 14, 1, [LogLevel]::INFO)
        [Log]::Info("Initialized...")

        # Load the Virtual Inventory configuration data.
        $inventoryConfig = LoadConfigurationData $JSONArgsFile

        #
        #  The following lines must be executed before DBConnectionMYSQL.ps1 is sourced it.  I don't have any documentation,
        #    but I assume powershell tries to define any types/classes in a file prior to running any other code.  When placing the 
        #    following lines at the top of the file, they do not seem to execute.
        #

        if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
        {
            [System.Reflection.Assembly]::LoadWithPartialName("MySQL.Data") | Out-Null

            if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match "MySQL.Data" }).Length -eq 0)
            {
                throw "Unable to load MySQL.Data assembly."
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

        # Source in the MySQLDBConnection class
        . .\DBConnectionMYSQL.ps1

        $ipamDBCredential = [System.Management.Automation.PsCredential]::new($inventoryConfig.IPAMDB.UserName, ($inventoryConfig.IPAMDB.Password | ConvertTo-SecureString))

        #  Build a connection string from the configuration data and the credential
        $dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};" -f @(
            $inventoryConfig.IPAMDB.Server,
            $inventoryConfig.IPAMDB.Port,
            $inventoryConfig.IPAMDB.Database,
            $ipamDBCredential.UserName,
            $ipamDBCredential.GetNetworkCredential().Password
        )

        #  Make a connection to the database
        $Global:db = [MySQLDBConnection]::new($dbConnectionString)

        #  Make sure we can query the database
        $dt = $Global:db.GetDataTable("SELECT * FROM global_config;")
        if(($null -ne $dt) -and ($dt.Rows.Count -gt 0))
        {
            [Log]::Info("Successfully connected to IPAM database.")
        }
        else
        {
            # Nothing, already logged an error...
        }

        try { $found = ($null -ne [MySQLDBConnection]) } catch { $found = $false }
        if($found)
        {
            [Log]::Info("MySQLDBConnection class loaded.")

            # Source in the EVDataPoint class
            . .\EVDatapoint.ps1

            try { $found = ($null -ne [EVDatapoint]) } catch { $found = $false }
            if($found)
            {
                [Log]::Info("EVDatapoint class loaded.")
            }
            else
            {
                [Log]::Error("Unable to source in [EVDatapoint] class.")
            }
        }
        else
        {
            [Log]::Error("Unable to source in [MySQLDBConnection] class.")
        }
    }
    else
    {
        [void] $sb.AppendLine("Unable to source in [Log] class.")
    }
}
else # NOT ($found)
{
    # FALSE

    [void] $sb.AppendLine("Unable to source LoadConfigurationData.ps1.")
}

Write-Host ("Errors: [{0}]" -f @($sb.ToString()))

$invCfg = $inventoryConfig
