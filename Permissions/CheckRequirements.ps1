# Start with the assumption all requirements have been met.
$haveRequirements = $true

# So long as I'm not missing a requirement, and there are more requirements to check, keep checking.
for($r = 0; ($haveRequirements) -and ($r -lt $requirements.Length); $r++)
{
    if(-not [String]::IsNullOrEmpty($requirements[$r].RequirementType))
    {
        $startLog.Add("Checking for {0}..." -f @($requirements[$r].RequirementType))

        # Based on the type of requirement, try to resolve the requirement.
        #   I was tempted to make each of the cases its own function, but sourcing in a script that defines a type would result in the
        #      type only existing with the scope of the function, so I left everything in the global scope.
        switch($requirements[$r].RequirementType)
        {
            "string[]"
            {
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $startLog.Add("`t{0}" -f @($requirements[$r].VariableName))
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if($null -ne $v)
                    {
                        if($v -is [Array])
                        {
                            for($e = 0; $e -lt $v.Length; $e++)
                            {
                                if($v[$e] -isnot [String])
                                {
                                    $startLog.Add("{0}[{1}] : {2} is not a string" -f @($requirements[$r].VariableName, $e, $v[$e]))
                                    $haveRequirements = $false
                                }
                                else
                                {
                                    # Nothing, element is a string.
                                    $startLog.Add("`t`t[{0}] = '{1}'" -f @($e, $v[$e]))
                                }
                            }
                        }
                        else
                        {
                            $startLog.Add("{0} is not an array" -f @($requirements[$r].VariableName))
                            $haveRequirements = $false
                        }
                    }
                    else
                    {
                        $startLog.Add("Missing {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                }
                else
                {
                    $startLog.Add("String[] requirement {0} has not variable name!" -f @($r))
                }

                break
            }

            "string"
            {
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $startLog.Add("`t{0}" -f @($requirements[$r].VariableName))
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if($null -ne $v)
                    {
                        if($v -isnot [String])
                        {
                            $startLog.Add("{0} : {1} is not a string" -f @($requirements[$r].VariableName, $v))
                            $haveRequirements = $false
                        }
                        else
                        {
                            if([String]::IsNullOrEmpty($v))
                            {
                                $startLog.Add("Missing value for {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                                $haveRequirements = $false
                            }
                            else
                            {
                                $startLog.Add("`t`t{0}" -f @($v))
                            }
                        }
                    }
                    else
                    {
                        $startLog.Add("Missing variable {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                }
                else
                {
                    $startLog.Add("String requirement {0} has not variable name!" -f @($r))
                }

                break
            }

            "boolean"
            {
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $startLog.Add("`t{0}" -f @($requirements[$r].VariableName))
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if($null -ne $v)
                    {
                        if($v -isnot [Boolean])
                        {
                            $startLog.Add("{0} : {1} is not a boolean" -f @($requirements[$r].VariableName, $v))
                            $haveRequirements = $false
                        }
                        else
                        {
                            $startLog.Add("`t`t{0}" -f @($v))
                        }
                    }
                    else
                    {
                        $startLog.Add("Missing variable {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                }
                else
                {
                    $startLog.Add("Boolean requirement {0} has not variable name!" -f @($r))
                }

                break
            }

            "int32"
            {
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $startLog.Add("`t{0}" -f @($requirements[$r].VariableName))
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if($null -ne $v)
                    {
                        if($v -isnot [int32])
                        {
                            $startLog.Add("{0} : {1} is not an Int32" -f @($requirements[$r].VariableName, $v))
                            $haveRequirements = $false
                        }
                        else
                        {
                            if(($v -ge $requirements[$r].Minimum) -and ($v -le $requirements[$r].Maximum))
                            {
                                $startLog.Add("`t`t{0}" -f @($v))
                            }
                            else
                            {
                                $startLog.Add("{0} : [Value: {1}] is outside of it's legal range [{2} - {3}]" -f @($requirements[$r].VariableName, $v, $requirements[$r].Minimum, $requirements[$r].Maximum))
                                $haveRequirements = $false
                            }
                        }
                    }
                    else
                    {
                        $startLog.Add("Missing variable {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                }
                else
                {
                    $startLog.Add("Int32 requirement {0} has not variable name!" -f @($r))
                }

                break
            }

            "file"
            {
                $startLog.Add("`t{0}" -f @($requirements[$r].VariableName))
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if([String]::IsNullOrEmpty($v))
                    {
                        $startLog.Add("Missing {0}" -f @($requirements[$r].Description))
                        $haveRequirements = $false
                    }
                    else
                    {
                        if(-not (Test-Path -Path $v))
                        {
                            $startLog.Add("{0}/{1} does not exist." -f @($v, $requirements[$r].Description))
                            $haveRequirements = $false
                        }
                        else
                        {
                            $startLog.Add("`t`t{0}" -f @($v))
                        }
                    }
                }
                else
                {
                    $startLog.Add("File requirement {0} has not variable name!" -f @($r))
                }

                break
            }

            "jsonArgsfile"
            {
                if([String]::IsNullOrEmpty($requirements[$r].FileName))
                {
                    $startLog.Add("Missing {0}" -f @($requirements[$r].Description))
                    $haveRequirements = $false
                }
                else
                {
                    if(-not (Test-Path -Path $requirements[$r].FileName))
                    {
                        $startLog.Add("{0}/{1} does not exist." -f @($requirements[$r].FileName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                    else
                    {
                        # Read the contents of the file
                        $rawJson = Get-Content -Path $requirements[$r].FileName -Raw
                        if(-not [String]::IsNullOrEmpty($rawJson))
                        {
                            try
                            {
                                $json = $rawJson | ConvertFrom-Json
                                $jsonArgNames = @($json | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)
                                for($a = 0; $a -lt $jsonArgNames.Length; $a++)
                                {
                                    Set-Variable -Name $jsonArgNames[$a] -Value $json.$($jsonArgNames[$a])
                                }
                            }
                            catch
                            {
                                $startLog.Add("Failed to convert contents of file {0} to an object." -f @($requirements[$r].FileName))
                                $haveRequirements = $false
                            }
                        }
                        else
                        {
                            $startLog.Add("{0} appears to be empty." -f @($requirements[$r].FileName))
                            $haveRequirements = $false
                        }
                    }
                }

                break
            }

            "module"
            {
                if (-not [String]::IsNullOrEmpty($requirements[$r].ModuleName))
                {
                    $startLog.Add("    {0}" -f @($requirements[$r].ModuleName))

                    if(@(Get-Module -Name $requirements[$r].ModuleName).Length -eq 0)
                    {
                        $startLog.Add("        importing")
                        Import-Module -Global -Name $requirements[$r].ModuleName -ErrorAction SilentlyContinue

                        # Check to make sure the module was imported.
                        $haveRequirements = (@(Get-Module -Name $requirements[$r].ModuleName).Length -gt 0) -and $haveRequirements
                    }
                    else
                    {
                        # Nothing, module already imported.
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].ModuleName))
                {
                    $startLog.Add("Missing module name for requirements[{0}]." -f @($r))
                    $haveRequirements = $false
                }
                break
            }

            "type"
            {
                if (-not [String]::IsNullOrEmpty($requirements[$r].TypeName))
                {
                    $startLog.Add("    {0}" -f @($requirements[$r].TypeName))
                    if($null -eq ($requirements[$r].TypeName -as [Type]))
                    {
                        if (-not [String]::IsNullOrEmpty($requirements[$r].Script))
                        {
                            $startLog.Add("        sourcing {0}" -f $requirements[$r].Script)
                            . SourceFile -SourceFile $requirements[$r].Script

                            # Check to see if the type exists after sourcing the file
                            $haveRequirements = ($null -ne ($requirements[$r].TypeName -as [Type])) -and $haveRequirements
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].Script))
                        {
                            $startLog.Add("Missing script path for type {0}" -f @($requirements[$r].TypeName))
                            $haveRequirements = $false
                        }
                    }
                    else
                    {
                        # Nothing, type already exists
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].TypeName))
                {
                    $startLog.Add("Missing type name for requirements[{0}]." -f @($r))
                    $haveRequirements = $false
                }
                break
            }

            "function"
            {
                if (-not [String]::IsNullOrEmpty($requirements[$r].FunctionName))
                {
                    $startLog.Add("    {0}" -f @($requirements[$r].FunctionName))
                    if (@(Get-Item -Path ("Function:\{0}" -f $requirements[$r].FunctionName) -ErrorAction SilentlyContinue).Length -eq 0)
                    {
                        if (-not [String]::IsNullOrEmpty($requirements[$r].Script))
                        {
                            $startLog.Add("        sourcing {0}" -f $requirements[$r].Script)
                            . SourceFile -SourceFile $requirements[$r].Script

                            # Check to see if the function exists after sourcing the file
                            $haveRequirements = (@(Get-Item -Path ("Function:\{0}" -f $requirements[$r].FunctionName) -ErrorAction SilentlyContinue).Length -gt 0) -and $haveRequirements
                        }
                        else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].Script))
                        {
                            $startLog.Add("Missing script path for function {0}" -f @($requirements[$r].FunctionName))
                            $haveRequirements = $false
                        }
                    }
                    else # NOT (@(Get-Item -Path ("Function:\{0}" -f $requirements[$r].FunctionName)).Length -eq 0)
                    {
                        # Nothing, function already exists
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].FunctionName))
                {
                    $startLog.Add("Missing function name for requirements[{0}]." -f @($r))
                    $haveRequirements = $false
                }
                break
            }

            "assembly"
            {
                if (-not [String]::IsNullOrEmpty($requirements[$r].AssemblyName))
                {
                    $startLog.Add("    {0}" -f @($requirements[$r].AssemblyName))

                    if(@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match $requirements[$r].AssemblyName }).Length -eq 0)
                    {
                        $startLog.Add("        loading")
                        [System.Reflection.Assembly]::LoadWithPartialName($requirements[$r].AssemblyName) | Out-Null

                        # Check to make sure the assembly was loaded.
                        $haveRequirements = (@([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match $requirements[$r].AssemblyName }).Length -gt 0) -and $haveRequirements
                    }
                    else
                    {
                        # Nothing, assembly already loaded.
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($requirements[$r].AssemblyName))
                {
                    $startLog.Add("Missing assembly name for requirements[{0}]." -f @($r))
                    $haveRequirements = $false
                }
                break
            }

            "custom"
            {
                if(-not [String]::IsNullOrEmpty($requirements[$r].VariableName))
                {
                    $v = Get-Variable -Name $requirements[$r].VariableName -ValueOnly -ErrorAction SilentlyContinue
                    if($null -ne $v)
                    {
                        if (@(Get-Item -Path ("Function:\{0}" -f $requirements[$r].ValidatorFunction) -ErrorAction SilentlyContinue).Length -eq 1)
                        {
                            $startLog.Add("Calling {0} to validate {1}" -f @($requirements[$r].ValidatorFunction, $requirements[$r].VariableName))
                            $haveRequirements = & $requirements[$r].ValidatorFunction $v
                        }
                        else
                        {
                            $startLog.Add("Missing custom validator function {0} for {1}." -f @($requirements[$r].ValidatorFunction, $requirements[$r].VariableName))
                            $haveRequirements = $false
                        }
                    }
                    else
                    {
                        $startLog.Add("Missing variable {0} : {1}" -f @($requirements[$r].VariableName, $requirements[$r].Description))
                        $haveRequirements = $false
                    }
                }
                else
                {
                    $startLog.Add("Missing variable name for requirements[{0}]." -f @($r))
                    $haveRequirements = $false
                }
            }
        }
    }
    else
    {
        $startLog.Add("Missing requirement type in {0} for requirements[{1}]" -f @($MyInvocation.MyCommand, $r))
        $haveRequirements = $false
    }
}
