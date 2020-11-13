<#
.SYNOPSIS
    Entry point for a Script Application.

.DESCRIPTION
    A modular way of constructing a powershell "ScriptApp".  I define ScriptApp as any powershell script that uses this framework
    as a means to be more modular.  Any script that uses this framework must be stored in a sub-folder of the ScriptApp framework
    folder.  Example:

    C:\Scripts
        \Common                           : Various scripts that can be used across multiple ScriptApps, but are not written specfically to be part of the ScriptApp framework
        \ScriptApp                        : Root of the ScriptApp framework [$Global:MyScriptRoot]
            \Common                       : Various scripts that can be used across multiple ScriptApps, but are still part of the ScriptApp framework
            \InfrastrutureScriptApps      : Collection of ScriptApps for "Infrastructure"  ... the name is relative, this is for human readability only.
                \Common                   : Various scripts that can be used across multiple "Infrastructure" ScriptApps
                \RouterBackup             : Folder to contain a specific "Infrastructure" ScriptApp [$Global:scriptAppPath]

    As an example, the [Log] class is stored in .\ScriptApp\Common\Log.ps1.  This class provides a global logger that any ScriptApp can use without having to
        explicitly "source" the class into the powershell script.

.EXAMPLE
    PS C:\> ScriptApp -ScriptAppPath MyScriptApp -JSONArgsFile MyArgs.json
    Execute the ScriptApp stored in sub-folder MyScriptApp, using MyArgs.json as its start-up configuration file.
       (stored in the same folder as the ScriptApp)

.EXAMPLE
    PS C:\> ScriptApp -ScriptAppPath C:\MyScripts\ScriptApps\MyScriptApp -JSONArgsFile C:\MyScripts\ScriptApps\MyArgs.json
    Execute the ScriptApp stored in C:\MyScripts\ScriptApps\MyScriptApp, using
       C:\MyScripts\ScriptApps\MyArgs.json as its start-up configuration file.

.INPUTS
    ScriptAppPath : [String]
        Path (no file name) where the ScriptApp to run is stored.
        This path must contain a file named Main.ps1 and define a function named ScriptAppMain that takes no arguments.
        ScriptAppMain is the entry point for the specific ScriptApp this script calls.

    JSONArgsFile : [String]
        Name of file, may be complete path, containing the settings (defined in JSON format) for this ScriptApp

.OUTPUTS
    Depends on the contents of the script application

.NOTES
    None
#>
[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $ScriptAppPath,

    [Parameter(Mandatory=$true,Position=1)]
    [String]
    $JSONArgsFile
)

<#
    Note to maintainers.  I've implemented a policy of limiting the validation of variables.  During the processing hierarchy, once a
                          variable has been verified, I do not continue to test it if the same variable is used in other places.

                          Example:
                            SetScriptRoot will return $true if it was able to set $Global:MyScriptRoot, or $false if not.  From that
                            point on, whenever another function, or block of code uses it, I will not validate it is set correctly.  If
                            SetScriptRoot returns $false, the script will simply log an error message and not continue.
#>

# Path where this file is stored.
$Global:MyScriptRoot = [String]::Empty

# Set up a temporary log, used to collect log information prior to the actual Logging facility being initialized.
$Global:startLog = $null

# The ScriptApp Name.  The name of the folder where the script application is stored.  Not the complete path, just the last folder name.
$Global:scriptAppName = [String]::Empty

# List of folders to search in looking for script components
$Global:searchPaths = $null

<#
.SYNOPSIS
    Add a message to $Global:startLog

.DESCRIPTION
    Add a message to $Global:startLog

.EXAMPLE
    PS C:\> LogMessage "Some interesting message"
    Add "Some interesting message" to $Global:startLog

.INPUTS
    $message : [String]
    Some interesting message to add to $Global:startLog

.OUTPUTS
    None

.NOTES
    None
#>
function LogMessage
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $message
    )

    # If $Global:startLog has not been initialized yet, initialize it.
    if ($null -eq $Global:startLog)
    {
        # TRUE

        $Global:startLog = [System.Collections.Generic.List[String]]::new()
    }
    else # NOT ($null -eq $Global:startLog)
    {
        # FALSE

        # Nothing.
    }

    $Global:startLog.Add(("{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HHmmss.fff"), $message)))
}  # End LogMessage

<#
.SYNOPSIS
    Set $Global:$MyScriptRoot based on the value of $PSScriptRoot.

.DESCRIPTION
    Sets $Global:$MyScriptRoot = $PSScriptRoot or $Global:PSScriptRootDebug if $PSScriptRoot is not set.

.EXAMPLE
    PS C:\> SetScriptRoot

.INPUTS
    None

.OUTPUTS
    None

.NOTES
    Adds messages to $Global:startLog as appropriate
#>
function SetScriptRoot
{
    # Assume there was an issue in setting $Global:MyScriptRoot
    $retVal = $false

    $Global:MyScriptRoot = $Global:PSScriptRoot

    # If $Glabal:MyScriptRoot is [String]::Empty, then try to use $Global:PSScriptRootDebug
    if ([String]::IsNullOrEmpty($Global:MyScriptRoot))
    {
        # TRUE

        # Has $Global:PSScriptRootDebug been set?
        if (-not [String]::IsNullOrEmpty($Global:PSScriptRootDebug))
        {
            # TRUE

            $Global:MyScriptRoot = $Global:PSScriptRootDebug
        }
        else # NOT (-not [String]::IsNullOrEmpty($Global:PSScriptRootDebug))
        {
            # FALSE

            LogMessage "ERROR: Missing value for `$Global:PSScriptRootDebug while running interactively."
        }
    }
    else # NOT ([String]::IsNullOrEmpty($Global:MyScriptRoot))
    {
        # FALSE

        # Nothing.
    }

    # Finally, if $Global:MyScriptRoot is null/empty, report an error
    if (-not [String]::IsNullOrEmpty($Global:MyScriptRoot))
    {
        # TRUE : $Global:MyScriptRoot is populated

        # Make sure $Global:MyScriptRoot is a full path
        $Global:MyScriptRoot = [System.IO.Path]::GetFullPath($Global:MyScriptRoot)

        # Now make sure $Global:MyScriptRoot exists
        if ([System.IO.Directory]::Exists($Global:MyScriptRoot))
        {
            # TRUE

            $retVal = $true
        }
        else # NOT ([System.IO.Directory]::Exists($Global:MyScriptRoot))
        {
            # FALSE

            LogMessage("{0} does not exist.  Must have a valid value for `$Global:MyScriptRoot." -f @($Global:MyScriptRoot))
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($Global:MyScriptRoot))
    {
        # FALSE : $Global:MyScriptRoot is not populated

        LogMessage "Unable to continue without a valid value for `$Global:MyScriptRoot."
    }

    return $retVal
}

<#
.SYNOPSIS
    Set the script application path and name based on the value of $scriptPath

.DESCRIPTION
    Ensure path and path\main.ps1 exist then set the script path and name.

.EXAMPLE
    PS C:\> SetScriptAppPath "ScriptApps\MyScriptApp"
    Test the path and path\main.ps1 for existence and set $Global:scriptAppPath accordingly.

.INPUTS
    $scriptPath : [String]
        Path (no file name) where the script application to run is stored.

.OUTPUTS
    $true or $false based on the result of setting the script application path and name.

.NOTES
    None
#>
function SetScriptAppPathAndName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $scriptPath
    )

    # Assume something went wrong setting the script application name.
    $retval = $false

    # Assume the script path does not exist until we prove it does
    $scriptPathExists = $false

    # Make $scriptPath is populated
    if (-not [String]::IsNullOrEmpty($scriptPath))
    {
        # TRUE : $scriptPath is populated

        # If $scriptPath is not rooted...
        if (-not [System.IO.Path]::IsPathRooted($scriptPath))
        {
            # TRUE : Prepend various folders to $scriptPath and check for an existing folder

            $cwd = (Get-Location).Path
            foreach ($folder in @($cwd, $Global:MyScriptRoot))
            {
                $testPath = [System.IO.Path]::Combine($folder, $scriptPath)

                if ([System.IO.Directory]::Exists($testPath))
                {
                    # TRUE : A folder has been located.

                    # Set $scriptPath to the value of $testPath
                    $scriptPath = $testPath

                    # Flag the path exists to avoid a redundant call to [System.IO.Path]::Exists below
                    $scriptPathExists = $true
                    break
                }
                else # NOT ([System.IO.Directory]::Exists($testPath))
                {
                    # FALSE

                    # Nothing.
                }
            }
        }
        else # NOT (-not [System.IO.Path]::IsPathRooted($scriptPath))
        {
            # FALSE : $scriptPath is already rooted

            # Nothing.
        }

        # Make sure the path exists.  We may have tested the path when making $scriptPath a rooted path.
        $scriptPathExists = ($scriptPathExists -or [System.IO.Directory]::Exists($scriptPath))
        if ($scriptPathExists)
        {
            # TRUE: $scriptPath exists

            # Path to script containing function Main()
            #  This is validated via $requirements (whether the file actually contains a function named ScriptAppMain or not)
            $Global:scriptAppMainPath = [System.IO.Path]::Combine($scriptPath, "Main.ps1")

            # Make sure the script file exists.
            if ([System.IO.File]::Exists($Global:scriptAppMainPath))
            {
                # TRUE: $scriptPath\Main.ps1 exists

                $Global:scriptAppPath = $scriptPath

                # Break the path down into its components.
                $pathFolders = $Global:scriptAppPath.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)

                # Did splitting $scriptPath result in a list of folder names?
                if ($pathFolders.Length -gt 1)
                {
                    # TRUE : Got a list of folders

                    # Set $Gloabl:scriptAppName to the last folder in the list.
                    $Global:scriptAppName = $pathFolders[$pathFolders.Length - 1]
                    $retval = $true
                }
                else # NOT ($pathFolder.Length -gt 1)
                {
                    # FALSE: WTH!?!  We didn't get a list of folders after the path tested to exist...

                    LogMessage("Unable to set scriptAppName")
                }
            }
            else # NOT ([System.IO.File]::Exists($scriptAppMainPath))
            {
                # FALSE

                LogMessage ("Unable to locate main.ps1 for script application in folder {0}." -f @($scriptPath))
            }
        }
        else # NOT ([System.IO.Directory]::Exists($scriptPath))
        {
            # FALSE

            LogMessage ("{0} is not a valid script application path in {1}." -f @($scriptPath, $MyInvocation.MyCommand))
        }
    }
    else # NOT (-not [String]::IsNullOrEmpty($scriptPath))
    {
        # FALSE : $scriptPath is not populated

        LogMessage ("Missing value for `$scriptPath in {0}." -f @($MyInvocation.MyCommand))
    }

    return $retval
}

<#
.SYNOPSIS
    Builds a list of paths ($Global:searchPaths) used to locate script components based on the values of $Global:MyScriptRoot and $Global:scriptAppPath

.DESCRIPTION
    Builds a list of paths ($Global:searchPaths) used to locate script components based on the values of $Global:MyScriptRoot and $Global:scriptAppPath

.EXAMPLE
    SetSearchPaths

    Assuming the following directory tree and values for $Global:MyScriptRoot and $Global:scriptAppPath

    C:\Scripts
        \Common
        \ScriptApp                  <-- $Global:MyScriptRoot
            \Common
            \InfrastrutureScriptApps
                \Common
                \RouterBackup       <-- $Global:scriptAppPath

    Return the following list:
        C:\Scripts\ScriptApp\InfrastructureScriptApps\RouterBackup         [$Global:scriptAppPath]
        C:\Scripts\ScriptApp\InfrastructureScriptApps\Common               [$Global:scriptAppPath\..\Common]
        C:\Scripts\ScriptApp\Common                                        [$Global:MyScriptRoot\Common]
        C:\Scripts\ScriptApp                                               [$Global:MyScriptRoot]
        C:\Scripts\Common                                                  [$Global:scriptAppPath\..\..\Common]

.INPUTS
    None

.OUTPUTS
    None

.NOTES
    If running the script interactively, i.e. debugging, ensure $Global:PSScriptRootDebug is set to the path where ScriptApp\Main.ps1 is stored.
#>
function SetSearchPaths
{
    # Initialize $Global:searchPaths
    $Global:searchPaths = [System.Collections.Generic.List[String]]::new()

    # First add the specific script application path
    $Global:searchPaths.Add($Global:scriptAppPath)

    # Break the path down into its components.
    $pathFolders = $Global:scriptAppPath.Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)

    # Search for a folder named "Common" in each of the parent folders up to the first folder off the root drive.
    for($a = $pathFolders.Length - 1; $a -gt 1; $a--)
    {
       $testPath = [System.IO.Path]::Combine([String]::Join("\", $pathFolders, 0, $a), "Common")

       if ([System.IO.Directory]::Exists($testPath))
       {
           # TRUE

           $Global:searchPaths.Add($testPath)
       }
       else # NOT ([System.IO.Directory]::Exists($testPath))
       {
           # FALSE

           # Nothing, can't search a path that doesn't exist
       }
    }

    # Finally add the script application framework path
    $Global:searchPaths.Add($Global:MyScriptRoot)


    return ($Global:searchPaths.Count -gt 0)
}
function FindCommonScripts
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $startPath
    )

    $commonScriptPath = [String]::Empty

    # Work back up the path tree until we get to the root, or find a directory named "Common"
    $pathFolders = $startPath.Split([System.IO.Path]::DirectorySeparatorChar,[System.StringSplitOptions]::RemoveEmptyEntries)
    for($p = $pathFolders.Length - 1; ([String]::IsNullOrEmpty($commonScriptPath)) -and ($p -ge 1); $p--)
    {
        $testPath = "{0}\Common" -f @([String]::Join([System.IO.Path]::DirectorySeparatorChar, $pathFolders, 0, $p))
        if(Test-Path -Path $testPath -ErrorAction SilentlyContinue)
        {
            $commonScriptPath = $testPath
        }
    }

    if([String]::IsNullOrEmpty($commonScriptPath))
    {
        LogMessage("Unable to determine 'Common' script path.")
    }

    return $commonScriptPath
}

<#
    Below here, everything must be in the Global scope so variables, functions, classes, etc are defined in the global scope.
#>

# Uncomment and update the following line if running this script interactively.  Ensure it is set to the path where this file is stored.
# $Global:PSScriptRootDebug = "C:\Users\kbriney\KLB\PEI-IT-OPS\ScriptApp"

# Try to set the script root path
if (SetScriptRoot)
{
    # TRUE

    # Try to set the script application name
    if ((SetScriptAppPathAndName $scriptAppPath))
    {
        # TRUE

        if (SetSearchPath)
        {
            # TRUE



        }
        else # NOT (SetSearchPath $scriptAppPath)
        {
            # FALSE

            # Nothing.
        }
    }
    else # NOT ((SetScriptAppName $scriptAppPath))
    {
        # FALSE

        # Nothing.
    }
}
else # NOT (SetScriptRoot)
{
    # FALSE

}



LogMessage("Common script path: {0}" -f @($commonScriptPath))

#  The testing of SourceFile.PS1 must remain outside of $requirements since it is used to source in
#    Process-Requirements.PS1.  It must also remain outside of a function so when the script is
#    sourced, SourceFile is defined globally.
if(@(Get-Alias -Name "SourceFile" -ErrorAction SilentlyContinue).Length -eq 1)
{
    # Nothing, alias already exists
}
else
{
    $sourceFileAliasScriptPath = "{0}\SourceFile.ps1" -f @($commonScriptPath)

    if(Test-Path -Path $sourceFileAliasScriptPath)
    {
        # Create an alias for SourceFile (see SourceFile.ps1 for description)
        #    NOTES:
        #       I would prefer to call a function to source in all the other sub-scripts,
        #       but if a file is sourced in a function, it is scoped to the function,
        #       and will not be globally available.
        LogMessage("Creating alias 'SourceFile' from {0}" -f @($sourceFileAliasScriptPath))
        Set-Alias -Name SourceFile -Value $sourceFileAliasScriptPath -Force
    }
    else
    {
        LogMessage("SourceFile script not found.")
    }
}

# The alias SourceFile should not exist unless an error occurred...
if(@(Get-Alias -Name "SourceFile" -ErrorAction SilentlyContinue).Length -eq 1)
{
    # Create a variable to represent the path to the [Log] class.  Used in $requirements
    $logClassScriptPath = "{0}\Log.ps1" -f @($commonScriptPath)

    # Path to script that will process the requirements.
    #   Cannot be part of $requirements since it needs to be available to process requirements
    $requirementsProcessorScriptPath = "{0}\Process-Requirements.ps1" -f @($commonScriptPath)

    if(Test-Path -Path $requirementsProcessorScriptPath)
    {
        # Path to the requirements for the ScriptApp Framework
        $scriptAppRequirements = "{0}\ScriptAppRequirements.ps1" -f @($Global:MyScriptRoot)

        # Does the requirements file exist?
        if ([System.IO.File]::Exists($scriptAppRequirements))
        {
            # TRUE

            # Source in the ScriptApp Framework requirements
            . SourceFile -SourceFile $scriptAppRequirements

            # Were the requirements successfully sourced?
            if (@(Get-Variable -Name "requirements" -ErrorAction SilentlyContinue).Length -gt 0)
            {
                # TRUE

                # Path to the specific ScriptApp requirements
                $scriptSpecificRequirementsPath = "{0}\Requirements.PS1" -f @($scriptAppPath)
                if ([System.IO.File]::Exists($scriptSpecificRequirementsPath))
                {
                    # TRUE

                }
                else # NOT ([System.IO.File]::Exists($scriptSpecificRequirementsPath))
                {
                    # FALSE

                    # Nothing.
                }
                if(Test-Path -Path $scriptSpecificRequirementsPath -ErrorAction SilentlyContinue)
                {
                    . SourceFile -SourceFile $scriptSpecificRequirementsPath
                }
                else
                {
                    # Nothing, guess there are no specific requirements for the scriptApp we are running...
                }
            }
            else # NOT (@(Get-Variable -Name "requirements" -ErrorAction SilentlyContinue).Length -gt 0)
            {
                # FALSE

                LogMessage("ERROR: Missing requirements after sourcing ScriptApp Framework requirements.")
            }


            # Source in Process-Requirements to process the requirements, even if there are no specific requirements for this specific scriptApp
            . SourceFile -SourceFile $requirementsProcessorScriptPath

            # If all the requirements have been met, initialize logging and call the main function
            #    $Global:haveRequirements is set in Process-Requirements.PS1...
            if($Global:haveRequirements)
            {
                $loggingLevel = [LogLevel] $logLevel
                $Global:isError = $false

                # Initializing logging...
                LogMessage "Initializing logging"

                [Log]::Init($logPath, $Global:scriptAppName, $Global:maxLogAge, 1, $loggingLevel, $Global:startLog)

                # Source in script application
                #    As a minimum, $scriptMainAppPath needs to define function Main.
                . SourceFile -SourceFile $scriptMainAppPath

                if (@(Get-Item -Path Function:ScriptAppMain -ErrorAction SilentlyContinue).Length -eq 1)
                {
                    # Call the "ScriptAppMain" function.

                    if ($Global:launchScriptAppMain)
                    {
                        ScriptAppMain
                    }
                    else # NOT ($Global:launchScriptAppMain)
                    {
                        # Nothing, user does not want to launch ScriptAppMain.  Probably debugging
                    }
                }
                else
                {
                    [Log]::Error("Missing definition for function ScriptAppMain!")
                }

                # Flush the logs to storage
                [Log]::DumpLog()
            }
            else
            {
                LogMessage "Unable to proceed.  Not all requirements have been met."
            }

        }
        else # NOT ([System.IO.File]::Exists($scriptAppRequirements))
        {
            # FALSE

            LogMessage "ERROR: Unable to source in ScriptApp Framework requirements."
        }
    }
    else
    {
        LogMessage "Requirements processing script not found."
    }
}
else
{
    LogMessage "Unable to create alias 'SourceFile'."
}


# If there is anything in the startup log (i.e. it didn't get dumped to [Log] and subsequently cleared...) then dump it out to the screen...
if($Global:startLog.Count -gt 0)
{
    # Dump anything from the startup to the log.
    $Global:startLog | ForEach-Object { Write-Output $_ }
}
else
{
    # What?  What more is there to do...
}
