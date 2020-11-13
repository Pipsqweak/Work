<#
.SYNOPSIS
    Short description

.DESCRIPTION
    Long description

.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does

.INPUTS
    Inputs (if any)

.OUTPUTS
    Output (if any)

.NOTES
    General notes
#>
function HasMember
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $parentObject,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $memberName
    )

    return ($parentObject.Keys -contains $memberName)
}

function TestRequirementAttribute
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $memberName,

        [Parameter(Mandatory=$false,Position=2)]
        [Switch]
        $optional,

        [Parameter(Mandatory=$false,Position=2)]
        [Switch]
        $logMember
    )

    $memberExists = (HasMember $requirement $memberName)

    if($memberExists)
    {
        $memberExists = -not [String]::IsNullOrEmpty($requirement.$($memberName))

        if($memberExists)
        {
            if($logMember.IsPresent)
            {
                # This may log funny for anything other than simple types...
                $Global:startLog.Add("`t{0}: {1}" -f @($memberName, $requirement.$($memberName)))
            }
            else
            {
                # Nothing, no not log
            }
        }
        else
        {
            if(-not $optional.IsPresent)
            {
                $Global:startLog.Add("`tMissing {0} value." -f @($memberName))
            }
        }
    }
    else
    {
        if(-not $optional.IsPresent)
        {
            $Global:startLog.Add("`tMissing {0} attribute." -f @($memberName))
        }
    }

    if(-not $optional.IsPresent)
    {
        $requirement.IsValid = $requirement.IsValid -and $memberExists
    }

    return $memberExists
}

function SetDefaultValue
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement
    )

    $valueWasSet = $false

    Set-Variable -Name $requirement.VariableName -Value $requirement.DefaultValue -Scope global -ErrorAction SilentlyContinue
    $valueWasSet = (Get-Variable -Name $requirement.VariableName -ValueOnly -ErrorAction SilentlyContinue) -eq $requirement.DefaultValue
    if(-not $valueWasSet)
    {
        if($null -eq $requirement.DefaultValue)
        {
            $defVal = "null"
        }
        elseif($requirement.DefaultValue -is [Array])
        {
            $defVal = $requirement.DefaultValue -join ", "
        }
        else
        {
            $defVal = $requirement.DefaultValue
        }
        $Global:startLog.Add("`t`t`tFailed to set to default value: {0}" -f @($defVal))
    }
    else
    {
        # Nothing, default value was set
    }

    return $valueWasSet
}

function LogTestValue
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement,

        [Parameter(Mandatory=$true,Position=1)]
        [Object]
        $testValue,

        [Parameter(Mandatory=$true,Position=2)]
        [Boolean]
        $isValid
    )

    $tVal = "null"
    if($testValue -is [Array])
    {
        $tVal = $testValue -join ", "
    }
    else
    {
        $tVal = $testValue
    }

    if($isValid)
    {
        $Global:startLog.Add("`t`t{0}" -f @($tVal))
    }
    else
    {
        $Global:startLog.Add("`t`t{0} is not a valid value for {1}" -f @($tVal, $requirement.Description))
    }
}

function ValidateRequirement
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement,

        [Parameter(Mandatory=$true,Position=1)]
        [Object]
        $testValue
    )

    # $testValue is valid until we prove otherwise
    $isValid = $true

    # First thing.... If the requirement has a custom validator function, let it decide the fate of $testValue
    if(TestRequirementAttribute $requirement "ValidatorFunction" -optional -logMember)
    {
        if (@(Get-Item -Path ("Function:\{0}" -f $requirement.ValidatorFunction) -ErrorAction SilentlyContinue).Length -eq 1)
        {
            $Global:startLog.Add("`t`tCalling {0} to validate {1}" -f @($requirement.ValidatorFunction, $requirement.VariableName))
            $isValid = & $requirement.ValidatorFunction $testValue
            LogTestValue $requirement $testValue $isValid
        }
        else
        {
            $Global:startLog.Add("`t`tMissing custom validator function definition for {0}." -f @($requirement.ValidatorFunction))
            $isValid = $false
        }
    }
    else
    {
        if($null -ne $testValue)
        {
            if(TestRequirementAttribute $requirement "Minimum" -optional -logMember)
            {
                if(($null -ne $testValue) -and ($requirement.Minimum -is $testValue.GetType()))
                {
                    $isValid = $isValid -and ($testValue -ge $requirement.Minimum)
                }
                else
                {
                    # Nothing $testValue is not valid
                }
            }
            else
            {
                $isValid = $true
            }

            if(TestRequirementAttribute $requirement "Maximum" -optional -logMember)
            {
                if(($null -ne $testValue) -and ($requirement.Maximum -is $testValue.GetType()))
                {
                    $isValid = $isValid -and ($testValue -le $requirement.Maximum)
                }
                else
                {
                    # Nothing $testValue is not valid
                }
            }
            else
            {
                $isValid = $true
            }
        }
        else
        {
            $isValid = $false
        }

        LogTestValue $requirement $testValue $isValid
    }

    return $isValid
}

function ValidateFileOrPath
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement
    )

    $pathName = [String]::Empty

    if(TestRequirementAttribute $requirement "FromVariable" -optional -logMember)
    {
        $pathName = Get-Variable -Name $requirement.FromVariable -ValueOnly -ErrorAction SilentlyContinue
    }
    elseif(TestRequirementAttribute $requirement "PathName" -optional -logMember)
    {
        $pathName = $requirement.PathName
    }
    elseif(TestRequirementAttribute $requirement "FileName" -optional -logMember)
    {
        $pathName = $requirement.FileName
    }
    else
    {
        $Global:startLog.Add("`tMissing {0}Name and FromVariable attribute" -f @((Get-Culture).TextInfo.ToTitleCase($requirement.RequirementType)))
        $requirement.IsValid = $false
    }

    if($requirement.IsValid)
    {
        if(-not [String]::IsNullOrEmpty($pathName))
        {
            $Global:startLog.Add("`t{0}Name: {1}" -f @((Get-Culture).TextInfo.ToTitleCase($requirement.RequirementType), $pathName))
            if(-not (Test-Path -Path $pathName))
            {
                if($requirement.RequirementType -eq "path")
                {
                    if(TestRequirementAttribute $requirement "Create" -optional -logMember)
                    {
                        New-Item -ItemType Directory -Path $pathName -ErrorAction SilentlyContinue | Out-Null
                        if(-not (Test-Path -Path $pathName))
                        {
                            $requirement.IsValid = $false
                            $Global:startLog.Add("`t`tFailed to create")
                        }
                        else
                        {
                            # Nothing
                        }
                    }
                    else
                    {
                        $Global:startLog.Add("`t`tDoes not exist.")
                        $requirement.IsValid = $false
                    }
                }
                else
                {
                    $Global:startLog.Add("`t`tDoes not exist.")
                    $requirement.IsValid = $false
                }
            }
            else
            {
                # Nothing.
            }
        }
        else
        {
            $Global:startLog.Add("`tEmpty {0} name specified." -f @($requirement.RequirementType))
            $requirement.IsValid = $false
        }
    }
    else
    {
        # Nothing, already logged an error message
    }
}

<#
.SYNOPSIS
    Search $Global:commonPaths for the specified $filePath.

.DESCRIPTION
    Searches each of the paths in $Global:commonPaths until $filePath is found, or each path has been checked.

.EXAMPLE
    PS C:\> FindFile "class.ps1"

    Loop through each path in $Global:commonPaths checking to see if $Global:commonPaths[$a]\class.ps1 exists.

.EXAMPLE
    PS C:\> FindFile "class" "ps1"

    Loop through each path in $Global:commonPaths checking to see if $Global:commonPaths[$a]\class or $Global:commonPaths[$a]\class.ps1 exists.

.EXAMPLE
    PS C:\> FindFile "class.ps1" "json"

    Loop through each path in $Global:commonPaths checking to see if $Global:commonPaths[$a]\class.ps1 exists.  Since $filePath includes an extension, the user supplied extension is never used.

.INPUTS
    $filePath : [String]
        Name of file to search for.

    $fileExtension : [String]
        [OPTIONAL] An extension to append to $filePath if $filePath does not include an extension.

.OUTPUTS
    [String]
        The path to the file that was located, or [String]::Empty if no match was found.

.NOTES
    N/A
#>

function FindFile
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $filePath,

        [Parameter(Mandatory=$false,Position=1)]
        [String]
        $fileExtension = [String]::Empty
    )

    # Initialize the return value
    $locatedFilePath = [String]::Empty

    # First, check to see if a file exists that is named $filePath
    if ([System.IO.File]::Exists($filePath))
    {
        # TRUE

        $locatedFilePath = $filePath
    }
    else # NOT ([System.IO.File]::Exists($filePath))
    {
        # FALSE

        # Did the caller include an extension?
        $haveUserExtension = -not [String]::IsNullOrEmpty($fileExtension)
        if ($haveUserExtension)
        {
            # TRUE

            # Does the extension include a leading '.'?
            if ($fileExtension.StartsWith("."))
            {
                # TRUE

                # Remove the leading '.'
                $fileExtension = $fileExtension.Substring(1, $fileExtension.Length - 1)
            }
            else # NOT ($fileExtension.StartsWith("."))
            {
                # FALSE

                # Nothing.
            }
        }
        else # NOT ($haveUserExtension)
        {
            # FALSE

            # Nothing.
        }

        # Get the file name in $filePath
        $fileName = [System.IO.Path]::GetFileName($filePath)

        # Flag if $fileName includes an extension
        $hasExtension = -not [String]::IsNullOrEmpty([System.IO.Path]::GetExtension($fileName))

        # Check each of the paths in $Global:commonPaths for $filePath and/or $filePath.$fileExtension
        $a = 0
        while(([String]::IsNullOrEmpty($locatedFilePath) -and ($a -lt $Global:commonPaths.Count)))
        {
            # Construct $testPath from the next $Global:commonPaths and $fileName
            $testPath = "{0}\{1}" -f @($Global:commonPaths[$a], $fileName)

            # Does $testPath exist?
            if ([System.IO.File]::Exists($testPath))
            {
                # TRUE

                # Capture the existing file path
                $locatedFilePath = $testPath
            }
            else # NOT ([System.IO.File]::Exists($testPath))
            {
                # FALSE

                # Does $fileName include an extension?
                if (-not $hasExtension)
                {
                    # TRUE

                    # $fileName did not include an extension...

                    # Did the caller include an extension?
                    if ($haveUserExtension)
                    {
                        # TRUE

                        # Add the user supplied extension to the path.
                        $testPath = ("{0}\{1}.{2}" -f @($Global:commonPaths[$a], $fileName, $fileExtension))

                        if ([System.IO.File]::Exists($testPath))
                        {
                            # TRUE

                            # Capture the existing file path
                            $locatedFilePath = $testPath
                        }
                        else # NOT ([System.IO.File]::Exists($testPath))
                        {
                            # FALSE

                            # Nothing.
                        }
                    }
                    else # NOT ($haveUserExtension)
                    {
                        # FALSE

                        # Nothing.
                    }
                }
                else # NOT (-not $hasExtension)
                {
                    # FALSE

                    # Nothing.
                }
            }

            $a++
        }
    }

    return $locatedFilePath
}

<#
.SYNOPSIS
    Converts JSON data into global variables.

.DESCRIPTION
    Loads JSON data from file and sets $Global:<attribute_name> = <value>.

.EXAMPLE
    PS C:\> ProcessJSONArgsFile $requirement

    Uses $requirement.FileName as the name of a JSON formatted data file.  Each attribute/value pair in the file is converted to a global variable $Global:<attribute> = <value>.

.INPUTS
    $requirement : [Object]
        An object containing at least a "FileName" member used as the name of a JSON file to load and parse.

.OUTPUTS
    Nothing indirectly, however, $Global:startLog is updated with relevant messages.

.NOTES
    N/A
#>
function ProcessJSONArgsFile
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement
    )

    # For the ScriptApp Framework, there must always be a JSON Args File, even if it is empty.  Does $requirement have a member named "FileName"?
    if (TestRequirementAttribute $requirement "FileName" -logMember)
    {
        # TRUE

        # Can I find a file named $requirement.FileName?
        $jsonArgsFile = FindFile $requirement.FileName "json"

        # If $jsonArgsFile is empty after calling FindFile, then I was unable to locate it
        if (-not [String]::IsNullOrEmpty($jsonArgsFile))
        {
            # TRUE

            # Read the contents of the file
            $rawJson = Get-Content -Path $jsonArgsFile -Raw

            # Did I read anything from $jsonArgsFile?
            if (-not [String]::IsNullOrEmpty($rawJson))
            {
                # TRUE

                $json = $null
                try
                {
                    $json = $rawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                }
                catch
                {
                    $Global:startLog.Add("`t`tFailed to initialize parameters from {0}" -f @($jsonArgsFile))
                    $requirement.IsValid = $false
                }

                # Is $requirement still valid?
                if ($requirement.IsValid)
                {
                    # TRUE

                    # Extract the attribute names from $json
                    $attributeNames = @($json | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue)

                    # Did we get any attribute names?  This could have been handled with the for statement, but I wanted to log an error message if no attribute names where extracted.
                    if ($attributeNames.Length -gt 0)
                    {
                        # TRUE

                        # Loop through $attributeNames converting $json.$($attributeNames[$a]) into $Global:$attributeNames[$a]
                        for($a = 0; $a -lt $attributeNames.Length; $a++)
                        {
                            try
                            {
                                # Convert $json.$($attributeNames[$a]) into $Global:$attributeNames[$a]
                                Set-Variable -Name $attributeNames[$a] -Value $json.$($attributeNames[$a]) -Scope global -ErrorAction SilentlyContinue

                                # Set $requirement.IsValid to $true if I can Get-Variable -Name $attributeNames[$a], $false otherwise
                                $requirement.IsValid = @(Get-Variable -Name $attributeNames[$a] -ErrorAction SilentlyContinue).Length -gt 0

                                if (-not $requirement.IsValid)
                                {
                                    # TRUE

                                    # Add a message to the log.
                                    $Global:startLog.Add("`t`tFailed to set parameter: {0}" -f @($attributeNames[$a]))
                                }
                                else # NOT (-not $requirement.IsValid)
                                {
                                    # FALSE

                                    # Nothing.
                                }
                            }
                            catch
                            {
                                $Global:startLog.Add("`t`tFailed to set parameter: {0}" -f @($attributeNames[$a]))
                                $requirement.IsValid = $false
                            }
                        }
                    }
                    else # NOT ($attributeNames.Length -gt 0)
                    {
                        # FALSE

                        # Add a message to the log.
                        $Global:startLog.Add("`t`tNo parameters specified")

                        # Flag the requirement as invalid.
                        $requirement.IsValid = $false
                    }
                }
                else # NOT ($requirement.IsValid)
                {
                    # FALSE

                    # Nothing.
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($rawJson))
            {
                # FALSE

                # Add a message to the log.
                $Global:startLog.Add("`t`tAppears to be empty.")

                # Flag the requirement as invalid.
                $requirement.IsValid = $false
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($jsonArgsFile))
        {
            # FALSE

            # Flag the requirement as invalid.
            $requirement.IsValid = $false
        }
    }
    else # NOT (TestRequirementAttribute $requirement "FileName" -logMember)
    {
        # FALSE

        # Nothing.
    }
}

$Global:startLog.Add("Processing {0} requirements" -f @($requirements.Length))

# Check each requirement
$r = 0
while($r -lt $requirements.Length)
{
    $requirement = $requirements[$r]

    # Add an attribute to the requirement to track whether or not the requirement is valid.
    # Assume the requirement is valid unless proven otherwise
    $requirement.IsValid = $true

    $Global:startLog.Add("")
    # Used to output the Description attribute to the log
    [void] (TestRequirementAttribute $requirement "Description" -optional -logMember)

    # Temporary variable used to validate the requirement
    $testValue = $null

    if(TestRequirementAttribute $requirement "RequirementType" -logMember)
    {
        switch ($requirement.RequirementType)
        {
            "variable"
            {
                # Does this requirement have "VariableName"?
                if(TestRequirementAttribute $requirement "VariableName" -logMember)
                {
                    # Is there a variable with "VariableName"
                    if(@(Get-Variable -Name $requirement.VariableName -ErrorAction SilentlyContinue).Length -eq 1)
                    {
                        # Nothing, there is a variable for this requirement, now just need to validate it.
                        #
                        # TODO: Validate the variable...
                        #
                    }
                    else
                    {
                        # No variable named $requirement.VariableName....
                        #   does the requirement define a default value?
                        if(HasMember $requirement "DefaultValue")
                        {
                            # Try to set "VariableName" to "DefaultValue"
                            if(SetDefaultValue $requirement)
                            {
                                # Nothing, a default value was set.
                            }
                            else
                            {
                                $requirement.IsValid = $false
                            }
                        }
                        else
                        {
                            $Global:startLog.Add("`t`tERROR: No default or specified value." -f @($requirement.VariableName))
                            $requirement.IsValid = $false
                        }
                    }

                    # Does the requirement still seem valid?
                    #    $requirement.IsValid may have been changed to $false above...
                    if($requirement.IsValid)
                    {
                        # Try to get the value of the requirement variable name
                        $testValue = Get-Variable -Name $requirement.VariableName -ValueOnly -ErrorAction SilentlyContinue
                        $requirement.IsValid = ValidateRequirement $requirement $testValue
                    }
                    else
                    {
                        # Nothing, I'm out...
                    }
                }
                else
                {
                    # Nothing already logged a message
                }

                break
            }

            "jsonArgsFile"
            {
                ProcessJSONArgsFile $requirement


                break
            }

            { $_ -in @("file" ,"path") }
            {
                ValidateFileOrPath $requirement
                break
            }

            "module"
            {
                if(TestRequirementAttribute $requirement "ModuleName" -logMember)
                {
                    if(@(Get-Module -Name $requirement.ModuleName).Length -eq 0)
                    {
                        Import-Module -Global -Name $requirement.ModuleName -ErrorAction SilentlyContinue

                        # Check to make sure the module was imported.
                        $requirement.IsValid = (@(Get-Module -Name $requirement.ModuleName).Length -gt 0)
                        if(-not $requirement.IsValid)
                        {
                            $Global:startLog.Add("`tFailed to import module")
                        }
                    }
                    else
                    {
                        # Nothing, module already imported.
                    }
                }
                else
                {
                    # Nothing, already logged a message
                }

                break
            }

            "type"
            {
                if(TestRequirementAttribute $requirement "TypeName" -logMember)
                {
                    if($null -eq ($requirement.TypeName -as [Type]))
                    {
                        if(TestRequirementAttribute $requirement "ScriptPath" -logMember)
                        {
                            if(Test-Path -Path $requirement.ScriptPath)
                            {
                                . SourceFile -SourceFile $requirement.ScriptPath

                                # Check to see if the type exists after sourcing the file
                                $requirement.IsValid = ($null -ne ($requirement.TypeName -as [Type]))
                                if(-not $requirement.IsValid)
                                {
                                    $Global:startLog.Add("`t`tFailed to source script")
                                }
                            }
                            else
                            {
                                $Global:startLog.Add("`t`tScript not found.")
                                $requirement.IsValid = $false
                            }
                        }
                        else
                        {
                            # Nothing, already logged a message
                        }
                    }
                    else
                    {
                        $Global:startLog.Add("`t`tAlready defined")
                    }
                }
                else
                {
                    # Nothing, already logged a message
                }

                break
            }

            "function"
            {
                if(TestRequirementAttribute $requirement "FunctionName" -logMember)
                {
                    if (@(Get-Item -Path ("Function:\{0}" -f $requirement.FunctionName) -ErrorAction SilentlyContinue).Length -eq 0)
                    {
                        if(TestRequirementAttribute $requirement "ScriptPath" -logMember)
                        {
                            . SourceFile -SourceFile $requirement.ScriptPath

                            # Check to see if the function exists after sourcing the file
                            $requirement.IsValid = (@(Get-Item -Path ("Function:\{0}" -f $requirement.FunctionName) -ErrorAction SilentlyContinue).Length -gt 0)
                            if(-not $requirement.IsValid)
                            {
                                $Global:startLog.Add("`t`tFailed to source script")
                            }
                        }
                        else
                        {
                            # Nothing, already logged a message
                        }
                    }
                    else # NOT (@(Get-Item -Path ("Function:\{0}" -f $requirements[$r].FunctionName)).Length -eq 0)
                    {
                        $Global:startLog.Add("`t`tFunction already defined.")
                    }
                }
                else
                {
                    # Nothing, already logged a message
                }

                break
            }

            "assembly"
            {
                if(TestRequirementAttribute $requirement "AssemblyName" -logMember)
                {
                    if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match $requirement.AssemblyName }).Length -eq 0)
                    {
                        [System.Reflection.Assembly]::LoadWithPartialName($requirement.AssemblyName) | Out-Null

                        # Check to make sure the assembly was loaded.
                        $requirement.IsValid = (@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match $requirement.AssemblyName }).Length -gt 0)
                    }
                    else
                    {
                        # Nothing, assembly already loaded.
                    }
                }
                else
                {
                    # Nothing, already logged a message
                }

                break
            }

            default
            {
                $requirement.IsValid = $false
                $Global:startLog.Add("Unknown requirement type: {0}" -f @($requirement.RequirementType))
                break
            }
        }
    }
    else
    {
        # Nothing, already logged a message
    }

    $r++
}

# If any of the requirement are invalid, then I have not met the requirements...
$Global:haveRequirements = (@($requirements | Where-Object { -not $_.IsValid }).Length -eq 0)
