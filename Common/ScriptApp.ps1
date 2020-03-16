[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $scriptAppPath,

    [Parameter(Mandatory=$true,Position=1)]
    [String]
    $jsonArgsFile
)

<##################################################################################################################################>
<##›  NOTES to maintainers.                                                                                                     ‹##>
<##›     Pay special attention to the "boxed" comments.  To continue the comment within ‹#  #› and maintain the appearance      ‹##>
<##›     I used special characters for "‹" and "›".  If you look closely, they are different from:                              ‹##>
<##›                                   "<" and ">"                                                                              ‹##>
<##################################################################################################################################>

# Set up a temporary log, used to collect log information prior to the actual Logging facility being initialized.
$Global:startLog = [System.Collections.Generic.List[String]]::new()

# The ScriptApp Name
$Global:scriptAppName = [String]::Empty

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
        $Global:startLog.Add("Unable to determine 'Common' script path.")
    }

    return $commonScriptPath
}

function SetScriptAppName
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $scriptPath
    )
    
    $retval = $false
    $pathFolders = $scriptPath.Split([System.IO.Path]::DirectorySeparatorChar,[System.StringSplitOptions]::RemoveEmptyEntries)
    if($pathFolders.Length -gt 1)
    {
        $Global:scriptAppName = $pathFolders[$pathFolders.Length - 1]
        $retval = $true
    }
    else
    {
        $Global:startLog.Add("Unable to set scriptAppName")
    }

    return $retval
}

if(-not [String]::IsNullOrEmpty($scriptAppPath))
{
    if(Test-Path -Path $scriptAppPath -PathType Container)
    {
        If((SetScriptAppName $scriptAppPath))
        {
            # Path to script containing function Main()
            #  This is validated via $requirements
            $scriptMainAppPath = "{0}\Main.ps1" -f @($scriptAppPath)

            # Path to common scripts used as part of my ScriptApp framework
            #   Must be validated outside of $requirements since other paths rely on it.
            $commonScriptPath =  FindCommonScripts $scriptAppPath

            # If $commonScriptPath is not Null/Empty, the we found (and tested) the path in
            if(-not [String]::IsNullOrEmpty($commonScriptPath))
            {
                $Global:startLog.Add("Common script path: {0}" -f @($commonScriptPath))

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
                        $Global:startLog.Add("Creating alias 'SourceFile' from {0}" -f @($sourceFileAliasScriptPath))
                        Set-Alias -Name SourceFile -Value $sourceFileAliasScriptPath -Force
                    }
                    else
                    {
                        $Global:startLog.Add("SourceFile script not found.")
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
                        # Define the requirements for the script.
                        #   NOTES:
                        #     Make sure to list requirements in dependancy order.  For instance, if a validator function is to be used,
                        #     it must be defined prior to the requirement that uses the validator function.
                        #
                        #   PSAnalyzer will complain that $requirements is not used, but it is... in Process-Requirements.
                        $requirements = @()
                        <##################################################################################################################################>
                        <##›                                                                                                                            ‹##>
                        <##›          DO NOT CHANGE ANYTHING IN THE BOX.  THESE ARE REQUIRED FOR BASIC OPERATION OF THE ScriptApp Framework.            ‹##>
                        <##›               User script requirements are sourced in via Requirements.ps1 in $scriptAppPath following the                 ‹##>
                        <##›               declaration of $requirements.  Eventually I plan to implement a series of 'Requirement' classes.             ‹##>
                        <##›                                                                                                                            ‹##>
                        <##›----------------------------------------------------------------------------------------------------------------------------‹##>
                        <##›     Log class first so [Log] is defined for the rest of the script.  Also contains the ValidatorFunction: LogLevelChecker  ‹##>
                        <##›         Also contains the ValidatorFunction: LogLevelChecker                                                               ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "file";                                                                                           <##>
                        <##>        FileName = $logClassScriptPath;                                                                                     <##>
                        <##>        Description = "File containing the [Log] class."                                                                    <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "type";                                                                                           <##>
                        <##>        TypeName = "Log";                                                                                                   <##>
                        <##>        ScriptPath = $logClassScriptPath;                                                                                   <##>
                        <##>        Description = "Defines the [Log] class."                                                                            <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "function";                                                                                       <##>
                        <##>        FunctionName = "ScriptAppMain";                                                                                     <##>
                        <##>        ScriptPath = $scriptMainAppPath;                                                                                    <##>
                        <##>        Description = "Path to script containing function ScriptAppMain()."                                                 <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "jsonArgsfile";                                                                                   <##>
                        <##>        FileName = $jsonArgsFile;                                                                                           <##>
                        <##>        Description = "Path to JSON file containing run parameters."                                                        <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "variable";                                                                                       <##>
                        <##>        VariableName = "logPath";                                                                                           <##>
                        <##>        Description = "Folder where logs will be stored."                                                                   <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "path";                                                                                           <##>
                        <##>        Create = $true;                                                                                                     <##>
                        <##>        FromVariable = "logPath";                                                                                           <##>
                        <##>        Description = "Folder where logs will be stored."                                                                   <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##›    logLevel ValidatorFunction built into [Log] class source file                                                           ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "variable";                                                                                       <##>
                        <##>        VariableName = "logLevel";                                                                                          <##>
                        <##>        ValidatorFunction = "LogLevelChecker";                                                                              <##>
                        <##>        DefaultValue = "WARNING";                                                                                           <##>
                        <##>        Description = "How much logging is done."                                                                           <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "variable";                                                                                       <##>
                        <##>        VariableName = "maxLogAge";                                                                                         <##>
                        <##>        DefaultValue = 7;                                                                                                   <##>
                        <##>        Description = "How many days are old logs kept."                                                                    <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "variable";                                                                                       <##>
                        <##>        VariableName = "doDebug";                                                                                           <##>
                        <##>        Description = "Execute script in debug mode?"                                                                       <##>
                        <##>        DefaultValue = $false;                                                                                              <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##>    $requirements += @{                                                                                                     <##>
                        <##>        RequirementType = "variable";                                                                                       <##>
                        <##>        VariableName = "testRun";                                                                                           <##>
                        <##>        Description = "Execute script in test run mode?"                                                                    <##>
                        <##>        DefaultValue = $false;                                                                                              <##>
                        <##>    }                                                                                                                       <##>
                        <##›                                                                                                                            ‹##>
                        <##################################################################################################################################>

                        $scriptSpecificRequirementsPath = "{0}\Requirements.PS1" -f @($scriptAppPath)
                        if(Test-Path -Path $scriptSpecificRequirementsPath -ErrorAction SilentlyContinue)
                        {
                            . SourceFile -SourceFile $scriptSpecificRequirementsPath
                        }
                        else
                        {
                            # Nothing, guess there are no specific requirements for the scriptApp we are running...
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
                            $Global:startLog.Add("Initializing logging")

                            [Log]::Init($logPath, $Global:scriptAppName, $Global:maxLogAge, 1, $loggingLevel, $Global:startLog)

                            # Source in script application
                            #    As a minimum, $scriptMainAppPath needs to define function Main.
                            . SourceFile -SourceFile $scriptMainAppPath

                            if (@(Get-Item -Path Function:ScriptAppMain -ErrorAction SilentlyContinue).Length -eq 1)
                            {
                                # Call the "ScriptAppMain" function.

                                # ScriptAppMain
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
                            $Global:startLog.Add("Unable to proceed.  Not all requirements have been met.")
                        }
                    }
                    else
                    {
                        $Global:startLog.Add("Requirements processing script not found.")
                    }
                }
                else
                {
                    $Global:startLog.Add("Unable to create alias 'SourceFile'.")
                }
            }
            else
            {
                # Nothing, already logged an error
            }
        }
        else
        {
            # Nothing, already logged an error.
        }
    }
    else
    {
        $Global:startLog.Add("{0} does not exist." -f @($scriptAppPath))
    }
}
else
{
    $Global:startLog.Add("WARNING: No script application path provided.")
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
