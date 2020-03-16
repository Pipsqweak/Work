<#
    Scanner.ps1 is one part of a multi-script project to collect file and folder permissions from shares served from various NetApp filers.

    The first set of scripts are used to connect to the NetApp filers, collect information on shares, update the database, and launch scripts
    on remote management servers to enumerate files and folder on individual shares.  The idea behind running the "Get-ACLs" script remotely is
    geographically related.  Why enumerate thousands and thousands of files and folders from across the country using slower network links when
    a script can be ran on a management server that is much closer (perhaps even on the local network).

    The second piece does the actual enumeration of the files and folders.  When a file/folder is located that has explicit rules (non-inherited
    DACLs), the infomation is recorded in the database.  Initially, the results were returned to the script that launched the remotes, but I
    decided to instead have the remote script do the database updates directly so the main script could simply exit and not wait for all the
    remote scripts to complete.  Just seemed cleaner.

    Scanner.ps1 is the initial entry point for the project.  It is responsible for connecting to all the NetApp filers and clusters, gather
    information about all the shares from them, updating CIFS server information in the database, and launching scripts on the remote management
    server to do the collection of DACLs on files and folder.

    NOTE: If type [class] is sourced in, it CANNOT be sourced in a function or else the type will not exist in the global scope.  This makes for a large
    piece of code not contained in a function, but it necessary to ensure the types are define for the entire session.

#>
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $jsonArgsFile
)

# Set up a temporary log, used to collect log information prior to the actual Logging facility being initialized.
$startLog = [System.Collections.Generic.List[String]]::new()

# If running the script interactively, then hard-code $scriptPath  (this is for debugging the script)
if([String]::IsNullOrEmpty($PSScriptRoot))
{
    $scriptRoot = (Get-Item -Path C:\Users\kbriney\KLB\PEI-IT-Ops\Permissions).PSPath
}
else
{
    $scriptRoot = $PSScriptRoot
}

# Create an alias for SourceFile (see SourceFile.ps1 for description)
#    NOTES:
#       I would prefer to call a function to source in all the other sub-scripts,
#       but if a file is sourced in a function, it exists in the scope of the function
#       and will not be available outside the function.
if(@(Get-Alias -Name "SourceFile" -ErrorAction SilentlyContinue).Length -eq 0)
{
    $startLog.Add("Creating alias SourceFile for {0}\SourceFile.ps1" -f @($scriptRoot))
    Set-Alias -Name SourceFile -Value ("{0}\SourceFile.ps1" -f $scriptRoot) -Force
}
else
{
    # Nothing, alias already exists
}

# Tracker to make sure all requirements listed below have been met.
$haveRequirements = $true

# Define the required pieces and parts for the script.
#   NOTES:
#     Make sure to list "requirements of requirements" first.  i.e. DataAccess needs DBConnection defined, so list DBConnection before DataAccess
$requirements = @(
    # Log class first so [Log] is defined for the rest of the script.
    @{ RequirementType="type";          TypeName="Log";                                                Script="$($scriptRoot)\Log.ps1" },
    # Custom requirements checking functions listed next.
    #   These define the functions used as 'ValidatorFunction' in the following requirements.
    @{ RequirementType="function";      FunctionName="NASListChecker";                                 Script="$($scriptRoot)\NASListChecker.ps1"; },

    @{ RequirementType="jsonArgsfile";  FileName=$jsonArgsFile;                                        Description="Path to JSON file containing run parameters" },
    @{ RequirementType="string";        VariableName="logPath";                                        Description="Root log folder" },
    @{ RequirementType="custom";        VariableName="nasList";  ValidatorFunction="NASListChecker";   Description="List of NAS systems to connect to and the manage server used to process them." },
    @{ RequirementType="custom";        VariableName="logLevel";  ValidatorFunction="LogLevelChecker"; Description="How much logging is done." },
    @{ RequirementType="file";          VariableName="pathToGetACLs";                                  Description="Path to Get-ACLs script" },
    @{ RequirementType="string";        VariableName="remotePSConfigName";                             Description="Remote powershell session configuration name" },
    @{ RequirementType="string";        VariableName="databaseServer";                                 Description="Database server name" },
    @{ RequirementType="string";        VariableName="databaseName";                                   Description="Database name" },
    @{ RequirementType="string[]";      VariableName="partialPathsToAvoid";                            Description="Array of strings, that if detected in a path, cause the path to be skipped." },
    @{ RequirementType="int32";         VariableName="maxSubProcesses";                                Description="Maximum remote scanner processes allowed on a management server at once."; Minimum=1; Maximum=[Int32]::MaxValue },
    @{ RequirementType="int32";         VariableName="maxScanDepth";                                   Description="How many directories deep should the scanner enumerate."; Minimum=-1; Maximum=[Int32]::MaxValue },
    @{ RequirementType="int32";         VariableName="maxSharesToCheck";                               Description="How many shares should be scanned."; Minimum=-1; Maximum=[Int32]::MaxValue },
    @{ RequirementType="boolean";       VariableName="doDebug";                                        Description="Execute script in debug mode" },
    @{ RequirementType="boolean";       VariableName="directoriesOnly";                                Description="Scan only direcorties" },
    @{ RequirementType="boolean";       VariableName="testRun";                                        Description="Execute script in test run mode" },
    @{ RequirementType="boolean";       VariableName="launchRemote";                                   Description="Should the scanner script be launched?" },
    @{ RequirementType="assembly";      AssemblyName="System.DirectoryServices.AccountManagement" },
    @{ RequirementType="module";        ModuleName="DataONTAP" },
    @{ RequirementType="module";        ModuleName="ActiveDirectory" },
    @{ RequirementType="type";          TypeName="DBConnection";                                       Script="$($scriptRoot)\DBConnection.ps1" },
    @{ RequirementType="type";          TypeName="DataAccess";                                         Script="$($scriptRoot)\DataAccess.ps1" },
    @{ RequirementType="type";          TypeName="CIFSShare";                                          Script="$($scriptRoot)\CIFSShare.ps1" },
    @{ RequirementType="type";          TypeName="JobTracker";                                         Script="$($scriptRoot)\JobTracker.ps1" },
    @{ RequirementType="type";          TypeName="NetAppCIFSServer";                                   Script="$($scriptRoot)\NetAppCIFSServer.ps1" },
    @{ RequirementType="type";          TypeName="NetAppCIFSServerCollection";                         Script="$($scriptRoot)\NetAppCIFSServerCollection.ps1" },
    @{ RequirementType="function";      FunctionName="Connect-NetApp";                                 Script="$($scriptRoot)\Connect-NetApp.ps1" },
    @{ RequirementType="function";      FunctionName="Main";                                           Script="$($scriptRoot)\Main.ps1" },
    @{ RequirementType="function";      FunctionName="UpdateCIFSData";                                 Script="$($scriptRoot)\UpdateCIFSData.ps1" }
)

# Check/load all the requirements
if((Test-Path -Path "$($scriptRoot)\CheckRequirements.ps1"))
{
    # Source in CheckRequirements so we can verify requirements...
    $checkRequirements = "$($scriptRoot)\CheckRequirements.ps1"
    . SourceFile -SourceFile $checkRequirements

    # If all the requirements have been met, initialize logging and call the main function
    if($haveRequirements)
    {
        $loggingLevel = [LogLevel] $logLevel
        $Global:isError = $false

        # Initializing logging...
        $startLog.Add("Initializing logging")
        [Log]::Init($logPath, "Scanner", 1, 1, $loggingLevel)

        # Dump anything from the startup to the log.
        $startLog | ForEach-Object { [Log]::Must($_) }
        $startLog.Clear()

        # Call the "Main" function.
        Main $logPath $nasList $pathToGetACLs $remotePSConfigName $databaseServer $databaseName $partialPathsToAvoid $maxSubProcesses $maxScanDepth $maxSharesToCheck $doDebug $directoriesOnly $loggingLevel $testRun $launchRemote

        # Flush the logs to storage
        [Log]::DumpLog()
    }
    else
    {
        $startLog.Add("Unable to proceed.  Not all requirements have been met.")
    }
}
else
{
    $startLog.Add("Unable to locate {0}{1} to check requirements." -f @($scriptRoot, "\CheckRequirements.ps1"))
}

# If there is anything in the startup log (i.e. it didn't get dumped to [Log] and subsequently cleared...) then dump it out to the screen...
if($startLog.Count -gt 0)
{
    # Dump anything from the startup to the log.
    $startLog | ForEach-Object { Write-Output $_ }
}
else
{
    # What?  What more is there to do...
}
