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

function FindJSONArgsFile
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $jsonArgsFile
    )

    # If no JSONArgsFile name was provided, see if there is one in scriptAppPath matching $Global:scriptAppName
    if([String]::IsNullOrEmpty($jsonArgsFile))
    {
        $jsonArgsFile = "{0}\{1}.json" -f @($Global:scriptAppPath, $Global:scriptAppName)
    }
    else
    {
        # Nothing, proceed with locating the file.
    }

    if(-not [String]::IsNullOrEmpty($jsonArgsFile))
    {
        # Test $jsonArgsFile as it was given...
        if(-not (Test-Path -Path $jsonArgsFile))
        {
            # If $jsonArgsFile was not found, see if it has an extension...
            if([String]::IsNullOrEmpty([System.IO.Path]::GetExtension($jsonArgsFile)))
            {
                # No extension, add one, and test it again...
                $jsonArgsFile = "{0}.json" -f @($jsonArgsFile)
                if(-not (Test-Path -Path $jsonArgsFile))
                {
                    # Still no jsonArgsFile...

                    # Append $jsonArgsFile file name to $scriptAppPath ...
                    $parts = @($jsonArgsFile.Split([System.IO.Path]::DirectorySeparatorChar,[System.StringSplitOptions]::RemoveEmptyEntries))

                    $jsonArgsFile = "{0}\{1}" -f @($Global:scriptAppPath, $parts[$parts.Length - 1])

                    # This is the final try... we'll test it below and if it fails, so be it...
                }
            }
            else
            {
                # There was an extension...so...

                # Append $jsonArgsFile file name to $scriptAppPath ...
                $parts = @($jsonArgsFile.Split([System.IO.Path]::DirectorySeparatorChar,[System.StringSplitOptions]::RemoveEmptyEntries))

                $jsonArgsFile = "{0}\{1}" -f @($scriptAppPath, $parts[$parts.Length - 1])

                # This is the final try... we'll test it below and if it fails, so be it...
            }
        }
        else
        {
            # Nothing, found json args file...
        }

        # This is the final test for $jsonArgsFile.
        if(-not (Test-Path -Path $jsonArgsFile -PathType Leaf))
        {
            # Set $jsonArgsFile to empty so the caller knows there is an error
            $jsonArgsFile = [String]::Empty
        }
    }
    else
    {
        $Global:startLog.Add("`t`tJSON arguments file not specified and unable to locate one.")
    }

    return $jsonArgsFile
}

function ProcessJSONArgsFile
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,Position=0)]
        [Object]
        $requirement
    )

    # For the ScriptApp Framework, there must always be a JSON Args File, even if it is empty.
    #   TestRequirementAttribute called with -optional since FindJSONArgsFile will look for a
    #   file if no FileName was specified.  Though I'd recommend always providing one.
    if(TestRequirementAttribute $requirement "FileName" -logMember -optional)
    {
        $jsonArgsFile = FindJSONArgsFile $requirement.FileName

        # If $jsonArgsFile is empty after calling FindJSONArgsFile, then I was unable to locate it
        if(-not [String]::IsNullOrEmpty($jsonArgsFile))
        {
            # Read the contents of the file
            $rawJson = Get-Content -Path $jsonArgsFile -Raw
            if(-not [String]::IsNullOrEmpty($rawJson))
            {
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

                if($requirement.IsValid)
                {
                    $jsonArgNames = @($json | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue)
                    if($jsonArgNames.Length -gt 0)
                    {
                        for($a = 0; $a -lt $jsonArgNames.Length; $a++)
                        {
                            try
                            {
                                Set-Variable -Name $jsonArgNames[$a] -Value $json.$($jsonArgNames[$a]) -Scope global -ErrorAction SilentlyContinue
                                $requirement.IsValid = @(Get-Variable -Name $jsonArgNames[$a] -ErrorAction SilentlyContinue).Length -gt 0

                                if(-not $requirement.IsValid)
                                {
                                    $Global:startLog.Add("`t`tFailed to set parameter: {0}" -f @($jsonArgNames[$a]))
                                }
                            }
                            catch
                            {
                                $Global:startLog.Add("`t`tFailed to set parameter: {0}" -f @($jsonArgNames[$a]))
                                $requirement.IsValid = $false
                            }
                        }
                    }
                    else
                    {
                        $Global:startLog.Add("`t`tNo parameters specified")
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
                $Global:startLog.Add("`t`tAppears to be empty.")
                $requirement.IsValid = $false
            }
        }
        else
        {
            # Already logged a message
            $requirement.IsValid = $false
        }
    }
    else
    {
        # Nothing, already logged a message
    }
}

$Global:startLog.Add("Processing {0} requirements" -f @($requirements.Length))

# Check each requirement
$r = 0
while($r -lt $requirements.Length)
{
    $requirement = $requirements[$r]

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
