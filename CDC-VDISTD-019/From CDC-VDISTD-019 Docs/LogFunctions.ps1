
$Script:LogFileName = [String]::Empty
$Script:simulatedMsg = [String]::Empty
$Script:DoDebugging = $false
$Script:LoggerNoNewLine = $false
$Script:LogProcessID = [String]::Empty

function LogRaw
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [String]
        $Message
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        if([String]::IsNullOrEmpty($Script:LogFileName))
        {
            if([String]::IsNullOrEmpty($Script:LogFolder))
            {
                $Script:LogFolder = [System.IO.Path]::GetTempPath()
            } `
            else
            {
                # Nothing go wit it.
            }

            if((-not [String]::IsNullOrEmpty($Script:LogFileNamePrefix)) -and (-not $Script:LogFileNamePrefix.EndsWith("-")))
            {
                $Script:LogFileNamePrefix = "{0}-" -f @($Script:LogFileNamePrefix)
            } `
            else
            {
                # Nothing
            }

            $logFileExists = $true
            do
            {
                $Script:LogFileName = "{0}\{1}{2}.log" -f @($Script:LogFolder, $Script:LogFileNamePrefix, [DateTime]::Now.ToString("yyyyMMdd-HHmmssfff"))
                try
                {
                    $logFileExists = [System.IO.File]::Exists($Script:LogFileName)
                }
                catch
                {
                    # Nothing
                }

                if($logFileExists)
                {
                    Start-Sleep -Milliseconds 10
                } `
                else
                {
                    # Nothing
                }
            } while($logFileExists)

            if($Script:DoDebugging)
            {
                Write-Host ("Log file: {0}" -f @($Script:LogFileName))
            } `
            else
            {
                # Nothing
            }
        }
        else `
        {
            # Nothing
        }

        if(-not [String]::IsNullOrEmpty($Script:LogFileName))
        {
            Add-Content -Path $Script:LogFileName -Value $Message -ErrorAction SilentlyContinue
        } `
        else
        {
            # Nothing
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($Message))
    {
        # Nothing.
    }
}

function LogOutput
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Int32]
        $IndentLevel,

        [Parameter(Mandatory = $true, Position = 1)]
        [System.ConsoleColor]
        $Color,

        [Parameter(Mandatory = $true, Position = 3)]
        [String]
        $Prefix,

        [Parameter(Mandatory = $false, Position = 3)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 4)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 5)]
        [Switch]
        $NewLine
    )

    if([String]::IsNullOrEmpty($Script:LogFileName))
    {
        if([String]::IsNullOrEmpty($Script:LogFolder))
        {
            $Script:LogFolder = [System.IO.Path]::GetTempPath()
        } `
        else
        {
            # Nothing go wit it.
        }

        if((-not [String]::IsNullOrEmpty($Script:LogFileNamePrefix)) -and (-not $Script:LogFileNamePrefix.EndsWith("-")))
        {
            $Script:LogFileNamePrefix = "{0}-" -f @($Script:LogFileNamePrefix)
        } `
        else
        {
            # Nothing
        }

        $logFileExists = $true
        do
        {
            $Script:LogFileName = "{0}\{1}{2}.log" -f @($Script:LogFolder, $Script:LogFileNamePrefix, [DateTime]::Now.ToString("yyyyMMdd-HHmmssfff"))
            try
            {
                $logFileExists = [System.IO.File]::Exists($Script:LogFileName)
            }
            catch
            {
                # Nothing
            }

            if($logFileExists)
            {
                Start-Sleep -Milliseconds 10
            } `
            else
            {
                # Nothing
            }
        } while($logFileExists)

        if($Script:DoDebugging)
        {
            Write-Host ("Log file: {0}" -f @($Script:LogFileName))
        } `
        else
        {
            # Nothing
        }
    }
    else `
    {
        # Nothing
    }

    if($NewLine)
    {
        $leadingCRLFs = "`r`n"
    } `
    else
    {
        $leadingCRLFs = [String]::Empty
    }

    $Message = $Message.Replace("~SIMULATED~", $Script:simulatedMsg)
    while(-not [String]::IsNullOrEmpty($Message) -and $Message.StartsWith("`r`n"))
    {
        $leadingCRLFs += "`r`n"
        $Message = $Message.Substring(2, $Message.Length - 2)
    }
    $indent = [String]::new(' ', ($IndentLevel * 3))
    $ts = [String]::Empty
    try
    {
        # [Console] fails when ran as a job...
        if([Console]::CursorLeft -eq 0)
        {
            if(-not [String]::IsNullOrEmpty($Script:LogProcessID))
            {
                $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff[{0,10}]: " -f @($Script:LogProcessID))
            } `
            else
            {
                $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff: ")
            }
        } `
        else
        {
            # Nothing
        }
    }
    catch
    {
        if(-not $Script:LoggerNoNewLine)
        {
            if(-not [String]::IsNullOrEmpty($Script:LogProcessID))
            {
                $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff[{0,10}]: " -f @($Script:LogProcessID))
            } `
            else
            {
                $ts = [DateTime]::Now.ToString("yyyyMMdd-HHmmssfffff: ")
            }
        } `
        else
        {
            # Nothing
        }
    }
    $logMsg = "{0}{1}{2}: {3}{4}" -f @($leadingCRLFs, $ts, $Prefix, $indent, $Message)
    $logParams = @{
        Path = $Script:LogFileName
        Value = $logMsg
    }

    # Track this for subsequent calls...
    $Script:LoggerNoNewLine = $NoNewLine
    if($NoNewLine)
    {
        if($Script:DoDebugging)
        {
            Write-Host -ForegroundColor $Color -NoNewline ("{0}{1}: {2}{3}" -f @($leadingCRLFs, $Prefix, $indent, $Message))
        } `
        else
        {
            # Nothing
        }
        $logParams.Add("NoNewLine", $true)
    } `
    else
    {
        if($Script:DoDebugging)
        {
            Write-Host -ForegroundColor $Color ("{0}{1}: {2}{3}" -f @($leadingCRLFs, $Prefix, $indent, $Message))
        } `
        else
        {
            # Nothing
        }
    }

    if(-not [String]::IsNullOrEmpty($Script:LogFileName))
    {
        Add-Content @logParams -ErrorAction SilentlyContinue
    } `
    else
    {
        # Nothing
    }
}

function LogInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Green -Prefix "INFO" -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogWarning
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Yellow -Prefix "WARNING" -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function LogError
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    LogOutput -IndentLevel $IndentLevel -Color Red -Prefix "ERROR" -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
}

function LogException
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 1)]
        [Int32]
        $IndentLevel = 0,

        [Parameter(Mandatory = $false, Position = 2)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NewLine
    )

    if(-not [String]::IsNullOrEmpty($Message))
    {
        LogOutput -IndentLevel $IndentLevel -Color Red -Prefix "EXCEPTION" -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}
