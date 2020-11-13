<#
    Get file and folder DACLs

    NOTE: If type [class] is sourced in, it CANNOT be sourced in a function or else the type will not exist in the global scope.  This makes for a large
    piece of code not contained in a function, but it necessary to ensure the types are define for the entire session.
#>
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $jsonArgsFile
)

# Set up a temporary log...
$startLog = [System.Collections.Generic.List[String]]::new()

# If running the script interactively, then hard-code $scriptPath
if([String]::IsNullOrEmpty($PSScriptRoot))
{
    $scriptRoot = (Get-Item -Path C:\Users\kbriney\KLB\PEI-IT-Ops\Permissions).PSPath
}
else
{
    $scriptRoot = $PSScriptRoot
}

# Create an alias for SourceFile
if(@(Get-Alias -Name "SourceFile" -ErrorAction SilentlyContinue).Length -eq 0)
{
    $startLog.Add("Creating alias SourceFile for {0}\..\SourceFile.ps1" -f @($scriptRoot))
    Set-Alias -Name SourceFile -Value ("{0}\..\SourceFile.ps1" -f $scriptRoot) -Force
}
else
{
    # Nothing, alias already exists
}

# Define the required pieces and parts for the script.
#   NOTE: Make sure to list "requirements of requirements" first.  i.e. DataAccess needs DBConnection defined, so list DBConnection before DataAccess
$requirements = @(
    # Log first so [Log] is defined for the other script.
    @{ RequirementType="type";         TypeName="Log";                     Script="$($scriptRoot)\..\Log.ps1" },
    # JSON Args file next so the "real" arguments get defined.
    @{ RequirementType="jsonArgsfile"; FileName=$jsonArgsFile;             Description="Path to JSON file containing run parameters" },
    @{ RequirementType="type";         TypeName="DBConnection";            Script="$($scriptRoot)\..\DBConnection.ps1" },
    @{ RequirementType="type";         TypeName="DataAccess";              Script="$($scriptRoot)\..\DataAccess.ps1" },
    @{ RequirementType="function";     FunctionName="Main";                Script="$($scriptRoot)\Main.ps1" },

    # The following MUST be listed after jsonArgsFile so the are defined when they are checked.
    @{ RequirementType="custom";       VariableName="logLevel";            ValidatorFunction="LogLevelChecker";   Description="How much logging is done." },
    @{ RequirementType="int32";        VariableName="maxDepth";            Description="Maximum recursion depth"; Minimum=-1; Maximum=[Int32]::MaxValue },
    @{ RequirementType="boolean";      VariableName="directoriesOnly";     Description="Process directories only" }
    @{ RequirementType="boolean";      VariableName="doDebug";             Description="Execute script in debug mode" }
    @{ RequirementType="string";       VariableName="cifsServerName";      Description="Name of the CIFS Server" },
    @{ RequirementType="string";       VariableName="databaseServer";      Description="Server name hosting the permissions database" },
    @{ RequirementType="string";       VariableName="databaseName";        Description="Name of the permissions database" },
    @{ RequirementType="string";       VariableName="pathToCheck";         Description="UNC path to start scanning" },
    @{ RequirementType="string";       VariableName="logPath";             Description="Root log folder" },
    @{ RequirementType="string[]";     VariableName="pathsToAvoid";        Description="Array of paths under pathToCheck to avoid" },
    @{ RequirementType="string[]";     VariableName="partialPathsToAvoid"; Description="Array of strings, that if detected in a path, cause the path to be skipped." }
)

if((Test-Path -Path "$($scriptRoot)\..\CheckRequirements.ps1"))
{
    # Source in CheckRequirements so we can verify requirements...
    $checkRequirements = "$($scriptRoot)\..\CheckRequirements.ps1"
    . SourceFile -SourceFile $checkRequirements

    # If all the requirements have been met, then we should be good to call "Main"
    if($haveRequirements)
    {
        $loggingLevel = [LogLevel] $logLevel

        $Global:isError = $false

        # Construct the log name from pathToCheck
        $parts = $pathToCheck.Split("\", [System.StringSplitOptions]::RemoveEmptyEntries)
        $logName = [String]::Join("-", $parts)

        # Initializing logging...
        [Log]::Init($logPath, $logName, 1, 1, $loggingLevel)

        $startLog.Add("Initialized logging")
        # Dump anything from the startup to the log.
        $startLog | ForEach-Object { [Log]::Must($_) }
        $startLog.Clear()

        # Call the "Main" function.
        Main -cifsServerName $cifsServerName -pathToCheck $pathToCheck -pathsToAvoid $pathsToAvoid -partialPathsToAvoid $partialPathsToAvoid -maxDepth $maxDepth -directoriesOnly $directoriesOnly  -databaseServer $databaseServer -databaseName $databaseName

        [Log]::DumpLog()
    }
    else
    {
        $startLog.Add("Unable to proceed.  Not all requirements have been met.")
    }
}
else
{
    $startLog.Add("Unable to locate {0}{1} to check requirements." -f @($scriptRoot, "\..\CheckRequirements.ps1"))
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
