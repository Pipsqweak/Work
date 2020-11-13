<#
    Global Variables:

        isError - Set to $true by [Log]::Error to signal the existance of an error.  It is still up to the user to decide how to proceed.
#>

# Define various logging levels.
enum LogLevel { ALERT; ERROR; WARNING; INFO; DEBUG; DEBUG1; DEBUG2; DEBUG3; DEBUG4; DEBUG5; DEBUG6; DEBUG7; DEBUG8; DEBUG9; TRACE }

$found = $false
try { $found = ($null -ne [Log]) } catch { }

if(-not $found)
{
    <#
        Class:
            LogBuffer

        Description:
            Internal class used by the Log class to provide buffered logging
    #>

    class LogBuffer
    {
        hidden [System.Collections.Generic.List[String]] $buffer = $null
        # A list of strings where log messages are stored until they are dumped to storage.

        hidden [System.Int32] $bufferSize = 1
        # The number of lines to keep in $buffer before dumping the log to storage.

        hidden [String] $logFileName = [String]::Empty
        # The name of the file where $logBuffer is dumped.

        hidden [Boolean] $logDumpingEnabled = $false
        # Controls the ability to dump the buffer to storage.  Only after the logBuffer has been initialize will log dumping be enabled.

        <#
            Class constructor

            Sets a default buffer size and creating the buffer
        #>
        LogBuffer()
        {
            $this.bufferSize = [System.Int32]::MaxValue
            $this.buffer = [System.Collections.Generic.List[String]]::new()

            if($null -eq $this.buffer)
            {
                throw "Unable to create log buffer!"
            }
            else
            {
                # Nothing, we have setup the logging buffer
            }
        }

        <#
            Init must be called to set the log file name and set the buffer size.

            $logPath    : The name of the log file on storage
            $bufferSize : The number of lines allowed to build in logBuffer before the log is dumped to storage and cleared.
        #>
        Init([String] $logPath, [System.Int32] $bufferSize = 1)
        {
            $this.bufferSize = $bufferSize

            if(-not [String]::IsNullOrEmpty($logPath))
            {
                $this.logFileName = $logPath

                # Make sure the complete path is available for logging.
                New-Item -Path $this.logFileName -ItemType File -Force | Out-Null

                if (-not $Global:isError)
                {
                    # If all the logging setting are good, then initialize logging
                    if(Test-Path -Path $this.logFileName)
                    {
                        Remove-Item -Path $this.logFileName -Confirm:$false -Force | Out-Null
                    }
                    else
                    {
                        # Nothing, log doesn't exist...
                    }
                }
                else
                {
                    # Nothing, CreateFolderPath would have logged an error...
                }

                if($null -eq $this.buffer)
                {
                    $this.buffer = [System.Collections.Generic.List[String]]::new()
                }
                else
                {
                    # Nothing, the buffer has already been initialized.
                }

                if($null -eq $this.buffer)
                {
                    throw "Unable to create log buffer!"
                }
                else
                {
                    # Nothing, we have setup the logging buffer
                }

                $this.logDumpingEnabled = Test-Path -Path $([System.IO.Path]::GetDirectoryName($this.logFileName))

                if(-not $this.logDumpingEnabled)
                {
                    throw "Unable to initialize the logging buffer."
                }
                else
                {
                    # Nothing, all is well
                }
            }
            else
            {
                throw "No path supplied for logging."
            }
        }

        <#
            Dumps the log buffer to storage.
        #>
        [void] Dump()
        {
            if($this.logDumpingEnabled)
            {
                if($null -ne $this.buffer)
                {
                    for($tries = 0; ($this.buffer.Count -gt 0) -and ($tries -lt 10); $tries++)
                    {
                        try
                        {
                            $this.buffer | Out-File -FilePath $this.logFileName -Append -Encoding ascii
                            $this.buffer.Clear()
                        }
                        catch
                        {
                            # Pause for a flash...
                            Start-Sleep -Milliseconds 25
                        }
                    }
                }
                else
                {
                    # Nothing, no buffer setup...
                }
            }
            else
            {
                # Nothing, until this.logDumpingEnabled is set to $true, just keep building the buffer...
            }
        }

        <#
            Appends a message to the buffer.  Additionally, if the buffer has grown large enough, it will attempt to dump the log to storage

            $message : [String] : The message to append to the log
        #>
        [void] Append([String] $message)
        {
            if(-not [String]::IsNullOrEmpty($message))
            {
                $this.buffer.Add($message)

                if($this.buffer.Count -ge $this.bufferSize)
                {
                    $this.Dump()
                }
                else
                {
                    # No worries, only dump the log every $this.bufferSize lines...
                }
            }
            else
            {
                # Nothing, no need to waste space with empty messages.
            }
        }

        <#
            Returns a single string based on the contents of the log buffer.  Lines are concatenated with CRLF
        #>
        [String] ToString()
        {
            [String] $retval = [String]::Empty

            if($this.buffer.Count -gt 0)
            {
                $retval = [String]::Join("`r`n", $this.buffer)
            }
            else
            {
                # Nothing to return...
            }

            return $retval
        }
    }

    function LogLevelChecker
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory = $true, Position = 0)]
            [String]
            $logLevelStr
        )

        $retval = $true

        try
        {
            $ll = [LogLevel] $logLevelStr
        }
        catch
        {
            $retval = $false
        }

        return $retval
    }

    <#
        Class:
            Log

        Description:
            Provides a global (static) logging facility.  Once the logger has been initialized, only messages logged with a message level
            less than or equal to the logging level will be logged.

            Messages logged with [LogLevel]::ALERT - [LogLevel]::WARNING are appended to the alert log so they can be emailed.

            If logging level is set to [LogLevel]::DEBUG or greater, messages are also echoed to the console via Write-Host.

        Example:
            Logging level set to [LogLevel]::INFO

            [Log]::Debug4("Test debug 4 log")  -- This will not be logged, since DEBUG4 has a higher value than the current logging level

            [Log]::Alert("Alert message")      -- This message will be logged to both the log file and the alert buffer so it can later be
                                               -- emailed to someone with a call to [Log]::SendAlerts
    #>
    class Log
    {
        hidden [LogBuffer] $log = $null
        hidden [LogBuffer] $alertLog = $null
        hidden [Boolean] $initialized = $false
        hidden [LogLevel] $level = [LogLevel]::INFO

        hidden static [Log] $_me = $null
        hidden static [Boolean] $_stackDumped = $false

        <#
            Class constructor.  Create the log buffers.
        #>
        Log()
        {
            $this.log = [LogBuffer]::new()
            $this.alertLog = [LogBuffer]::new()
        }

        <#
            Used to implement a singleton model for the logger.
            https://en.wikipedia.org/wiki/Singleton_pattern
        #>
        static [Log] Me()
        {
            if($null -eq [Log]::_me)
            {
                [Log]::_me = [Log]::new()
            }

            return [Log]::_me
        }

        <#
            Prepends a sortable date/time string and level indicator to the message.

            $msgLevel : [LogLevel] : The level assigned to $message
            $message  : [String]   : The message to log
        #>
        hidden [String] FormatMessage([LogLevel] $msgLevel, [String] $message)
        {
            $fmtMessage = "{0}: {1}: {2}" -f @([DateTime]::Now.ToString("yyyyMMdd HHmmss.fff"), $msgLevel, $message)

            return $fmtMessage
        }

        <#
            Called by all "outputter" to format and determine where and how a message is logged

            $msgLevel : [LogLevel] : The level assigned to $message.  If logging is set lower than $msgLevel, the message will not be logged
            $message  : [String]   : The message to log
        #>

        hidden [void] Output([LogLevel] $msgLevel, [String] $message)
        {
            $this.Output($msgLevel, $message, $false)
        }

        hidden [void] Output([LogLevel] $msgLevel, [String] $message, [Boolean] $mustOutput)
        {
            if(-not [String]::IsNullOrEmpty($message))
            {
                $formattedMessage = $this.FormatMessage($msgLevel, $message)

                # Log the message if the logging level is GE to the message level or if $mustOutput
                if($mustOutput -or ([Log]::Me().level -ge $msgLevel))
                {
                    $this.log.Append($formattedMessage)

                    # Include WARNING, ERROR, and ALERT messages in the alertLog
                    if(($msgLevel -lt [LogLevel]::WARNING) -and ($msgLevel -ge [LogLevel]::ALERT))
                    {
                        $this.alertLog.Append($formattedMessage)
                    }
                    else
                    {
                        # Nothing, only WARNING, ERROR, and ALERT go to the alertLog
                    }
                }
                else
                {
                    # Nothing, message level not high enough to output.
                }

                if([Log]::Me().level -ge [LogLevel]::DEBUG)
                {
                    Write-Host $formattedMessage
                }
                else
                {
                    # Nothing
                }
            }
            else
            {
                # Nothing, no message, no logging it.
            }
        }

        <#
            Initializes the logger for use.  This method must be called before messages are logged.

            NOTE:  Calls to the outputters can be made, but until Init is called, nothing will be logged to storage.

            $logRootPath  : [String]   : The folder where logs will be saved too.  If this path does not exist, it will be created.
            $logName      : [String]   : This will be added to a formatted date/time stamp to create the actual log file stored under $logRootPath
            $maxLogAge    : [Int32]    : The maximum age (in days) logs will be kept in $logRootPath where $logName appears in the log file name.  Older files are purged.
            $lineCache    : [Int32]    : The number of lines of buffering to use before saving the buffer to disk
            $loggingLevel : [LogLevel] : The level of logging to retain.  If set to [LogLevel]::INFO, only messages tagged with levels: ALERT - INFO will be logged.
        #>
        static [void] Init([String] $logRootPath, [String] $logName, [System.Int32] $maxLogAge, [System.Int32] $lineCache = 1, [LogLevel] $loggingLevel = [LogLevel]::INFO, [System.Collections.Generic.List[String]] $startLog)
        {
            if(-not [String]::IsNullOrEmpty($logName))
            {
                if(-not [String]::IsNullOrEmpty($logRootPath))
                {
                    # Combine $logRootPath and $logName to get $logPath
                    $logPath = "{0}\{1}" -f @($logRootPath, $logName)

                    # Make sure the complete path is available for logging.
                    New-Item -Path $logPath -ItemType Directory -Force | Out-Null

                    if (-not $Global:isError)
                    {
                        if(Test-Path -LiteralPath $logPath)
                        {
                            # Purge logs older than $logAge days.
                            $oldLogs = @(Get-ChildItem -Path $logPath | Where-Object { (-not $_.PSIsContainer) -and ($_.BaseName.Contains($logName)) -and ($_.CreationTime -le [DateTime]::Now.AddDays(-1 * $maxLogAge)) })
                            $oldLogs | Remove-Item -Confirm:$false | Out-Null
                        }
                        else
                        {
                            # Nothing, can't delete old logs if there aren't any...
                        }

                        [Log]::Me().level = $loggingLevel

                        $dtNow = [DateTime]::Now.ToString("yyyyMMdd HHmmss")

                        # Build the full path to the log file
                        $logFileName = ("{0}\{1}-{2}.log" -f @($logPath, $logName, $dtNow)).Replace("\\","\")

                        # If, after replacing all the \\ with \, there is a leading \, add another \ so the UNC is correct.
                        if($logFileName.StartsWith("\"))
                        {
                            $logFileName = "\{0}" -f @($logFileName)
                        }
                        else
                        {
                            # Nothing
                        }

                        [Log]::Me().log.Init($logFileName, $lineCache)

                        if($null -ne $startLog)
                        {
                            # Dump anything from the startup to the log.
                            [Log]::Separator()
                            [Log]::Must("Start up log:")
                            $startLog | ForEach-Object { [Log]::Must(("   {0}" -f @($_))) }
                            [Log]::Separator()
                            $startLog.Clear()
                        }
                        else
                        {
                            # Nothing, not start log provided
                        }

                        [Log]::Me().initialized = $true
                    }
                    else
                    {
                        # Nothing, CreateFolderPath would have logged an error...
                    }
                }
                else
                {
                    throw "Missing log root path in logging facility"
                }
            }
            else
            {
                throw "Missing log name in logging facility"
            }
        }

        static [void] Init([String] $logRootPath, [String] $logName, [System.Int32] $maxLogAge, [System.Int32] $lineCache = 1, [LogLevel] $loggingLevel = [LogLevel]::INFO)
        {
            [Log]::Init($logRootPath, $logName, $maxLogAge, $lineCache, $loggingLevel, $null)
        }

        <#
            Dump the log to storage
        #>
        static [void] DumpLog()
        {
            if([Log]::Me().initialized)
            {
                if($null -ne [Log]::Me().log)
                {
                    [Log]::Me().log.Dump()
                }
                else
                {
                    # Nothing, no log to dump yet
                }
            }
            else
            {
                [Log]::Info("Cannot dump logs prior to log initialization.")
            }
        }

        <#
            Sends the alert log to email recipients

            $fromAddress : [String]   : Who should appear in the FROM: line
            $smtpRelay   : [String]   : The name/address of the SMTP relay used to send the email
            $recipients  : [String[]] : The list of recipients
            $subject     : [String]   : Subject line of the email message
        #>
        static [void] SendAlerts([String] $fromAddress, [String] $smtpRelay, [System.String[]] $recipients, [String] $subject)
        {
            if([Log]::Me().initialized)
            {
                if(-not [String]::IsNullOrEmpty($fromAddress))
                {
                    if(-not [String]::IsNullOrEmpty($smtpRelay))
                    {
                        if($null -ne $recipients)
                        {
                            if($recipients.Length -gt 0)
                            {
                                # Send the message...
                                $alertMessage = [Log]::Me().alertLog.ToString()
                                if(-not [String]::IsNullOrEmpty($alertMessage))
                                {
                                    #  https://serverfault.com/questions/543052/sending-unauthenticated-mail-through-ms-exchange-with-powershell-windows-server
                                    $anonUsername = "anonymous"
                                    $anonPassword = ConvertTo-SecureString -String "anonymous" -AsPlainText -Force
                                    $anonCredentials = New-Object System.Management.Automation.PSCredential($anonUsername, $anonPassword)

                                    Send-MailMessage -From $fromAddress -To $recipients -SmtpServer $smtpRelay -Subject $subject -Body $alertMessage -Credential $anonCredentials
                                }
                                else
                                {
                                    [Log]::Info("No alert message to send.")
                                }
                            }
                            else
                            {
                                [Log]::Error("No recipients supplied {0}." -f $MyInvocation.MyCommand)
                            }
                        }
                        else
                        {
                            [Log]::Error("Missing value for recipients in {0}." -f $MyInvocation.MyCommand)
                        }
                    }
                    else
                    {
                        [Log]::Error("Missing value for smtp relay in {0}." -f $MyInvocation.MyCommand)
                    }
                }
                else
                {
                    [Log]::Error("Missing value for smtp relay in {0}." -f $MyInvocation.MyCommand)
                }
            }
            else
            {
                [Log]::Info("Cannot send email alert prior to log initialization.")
            }
        }

        <#
            The following are all "outputters" for the [Log] class.  Calling them will attach an appropriate [LogLevel] to the
            message and add the message to the appropriate log buffer based on [LogLevel].
        #>
        static [void] Must ([String] $message) { [Log]::Me().Output([LogLevel]::INFO, $message, $true) }
        static [void] Alert([String] $message) { [Log]::Me().Output([LogLevel]::ALERT, $message) }

        #  VARIOUS DEBUGGING LEVELS  #
        static [void] Debug ([String] $message) { [Log]::Debug([LogLevel]::DEBUG, $message) }
        static [void] Debug1([String] $message) { [Log]::Debug([LogLevel]::DEBUG1, $message) }
        static [void] Debug2([String] $message) { [Log]::Debug([LogLevel]::DEBUG2, $message) }
        static [void] Debug3([String] $message) { [Log]::Debug([LogLevel]::DEBUG3, $message) }
        static [void] Debug4([String] $message) { [Log]::Debug([LogLevel]::DEBUG4, $message) }
        static [void] Debug5([String] $message) { [Log]::Debug([LogLevel]::DEBUG5, $message) }
        static [void] Debug6([String] $message) { [Log]::Debug([LogLevel]::DEBUG6, $message) }
        static [void] Debug7([String] $message) { [Log]::Debug([LogLevel]::DEBUG7, $message) }
        static [void] Debug8([String] $message) { [Log]::Debug([LogLevel]::DEBUG8, $message) }
        static [void] Debug9([String] $message) { [Log]::Debug([LogLevel]::DEBUG9, $message) }

        static [void] Trace([String] $message) { [Log]::Me().Output([LogLevel]::TRACE, $message) }

        static [void] Info([String] $message) { [Log]::Me().Output([LogLevel]::INFO, $message) }

        static [void] Warning([String] $message) { [Log]::Me().Output([LogLevel]::WARNING, $message) }

        static [void] Separator() { [Log]::Must([String]::new('=', 120)) }
        <#
            Calling the Error outputters will also dump the call stack onto the log and set $Global:isError to true
        #>
        static [void] Error([String] $message) { [Log]::Error($message, $false) }
        static [void] Error([String] $message, [Boolean] $doStackDump=$false)
        {
            [Log]::Me().Output([LogLevel]::ERROR, $message)
            [Log]::DumpStack($doStackDump)
            $Global:isError = $true
        }

        static [void] Error([System.String[]] $messageStrings) { [Log]::Error($messageStrings, $false) }
        static [void] Error([System.String[]] $messageStrings, [Boolean] $doStackDump=$false)
        {
            for($s = 0; $s -lt $messageStrings.Length; $s++)
            {
                [Log]::Me().Output([LogLevel]::ERROR, $messageStrings[$s])
            }
            [Log]::DumpStack($doStackDump)
            $Global:isError = $true
        }

        <#
            Used by the DebugX outputter to standardize how the debugging is output
        #>
        hidden static [void] Debug([LogLevel] $debugLevel, [String] $message) { [Log]::Me().Output($debugLevel, $message) }

        <#
            If used, typically will appear in a catch block.  Dumps all the messages in $Error onto the log
        #>
        static [void] CatchException([String] $extraMessage)
        {
            $msgStrings = @()
            for($e = 0; $e -lt $Error.Count; $e++)
            {
                if($null -ne $Error[$e].Exception)
                {
                    if(-not [String]::IsNullOrEmpty($Error[0].Exception.Message))
                    {
                        $msgStrings += $Error[$e].Exception.Message
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
            }

            if(-not [String]::IsNullOrEmpty($extraMessage))
            {
                $msgStrings += $extraMessage
            }
            else
            {
                # Nothing
            }

            [Log]::Error($msgStrings)
        }

        <#
            Called by the Error outputters to dump the call stack onto the log.

            NOTE: Only dumps the call stack once.
        #>
        hidden static [void] DumpStack([Boolean] $doStackDump=$false)
        {
            if($doStackDump)
            {
                if(-not [Log]::_stackDumped)
                {
                    [Log]::_stackDumped = $true
                    $callStack = Get-PSCallStack

                    for($i = 2; $i -lt $callStack.Length; $i++)
                    {
                        [Log]::Me().Output([LogLevel]::ERROR, "{0} : {1}" -f @($callStack[($i-1)].ScriptLineNumber, $callStack[$i].Position.Text))
                    }

                    # Flush logs to disk
                    [Log]::DumpLog()
                }
                else
                {
                    # Nothing
                }
            }
            else
            {
                # Nothing, caller did not ask to dump the stack
            }
        }
    }
}
else
{
    # No need to re-define class/functions...
}
