enum LogLevel
{
    INFO = 1
    WARNING = 2
    ERROR = 3
}

function Write-Log {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]
        [String]$Message,

        [Parameter(Mandatory=$true)]
        [LogLevel]$Level
    )

    $Global:ErrorLogged = $Global:ErrorLogged -or ($Level -eq [LogLevel]::ERROR)

    $myComponent = [String]::Empty
    $myFile = ""
    $cs = Get-PSCallStack
    $a = 0
    while($a -lt $cs.Length)
    {
        $cmd = $cs[$a].Command
        if($cmd -notin @("Write-log","LogInfo","LogWarning","LogError"))
        {
            # $myComponent = "{0} {1}" -f @($cs[$a].Command, $cs[$a].Arguments)
            $myComponent = $cs[$a].command
            $myFile = $cs[$a].Location
            break
        }
        $a++
    }

    # Create a log entry
    $logTime = [DateTime]::Now

    $content = "<![LOG[{0}]LOG]!><time=`"{1}`" date=`"{2}`" component=`"{3}`" context=`"{4}`" type=`"{5}`" thread=`"{6}`" file=`"{7}`">" -f @(
        $Message, $logTime.ToString("HH:mm:ss.ffffff"), $logTime.ToString("M-d-yyyy"), $myComponent, [System.Security.Principal.WindowsIdentity]::GetCurrent().Name, $Level.value__, [Threading.Thread]::CurrentThread.ManagedThreadId, $myFile)

    # If the log file folder does not exist, then write the message out via Write-Verbose
    if(-not [String]::IsNullOrEmpty($Global:LogPath))
    {
        if([System.IO.Directory]::Exists(($Global:LogPath | Split-Path)))
        {
            $content | Out-File -FilePath $Global:LogPath -Append -Encoding "utf8"
        }
        else
        {
            Write-Verbose $content
        }
    }
    else
    {
        Write-Verbose $content
    }

    if (($Level -eq [LogLevel]::ERROR) -and ($Global:TerminateOnError -eq $true) -and (-not [String]::IsNullOrEmpty($PSScriptRoot)))
    {
        # Only exit if an error was logged, we've been told to terminate on error, and we are NOT running in an interactive session
        exit
    } `
    else # NOT (($Level -eq [LogType]::ERROR) -and ($Global:TerminateOnError -eq $true) -and (-not [String]::IsNullOrEmpty($PSScriptRoot))))
    {
        # Nothing.
    }
}

function LogInfo {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]
        [String]$Message
    )

    Write-Log -Message $Message -Level INFO
}

function LogWarning {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]
        [String]$Message
    )

    Write-Log -Message $Message -Level WARNING
}

function LogError {

    [CmdletBinding()]
    Param(
        [parameter(Mandatory=$true)]
        [String]$Message
    )

    Write-Log -Message $Message -Level ERROR
}

if(-not $Global:CMLoggingAvailable)
{
    # Only set $Global:ErrorLogged to false if this is the first time this script file is sourced in.
    $Global:ErrorLogged = $false
}

$Global:CMLoggingAvailable = $true
try
{
    Get-ChildItem -Path @(
        "Function:\Write-Log",
        "Function:\LogInfo",
        "Function:\LogWarning",
        "Function:\LogError") -ErrorAction Stop | Out-Null
}
catch
{
    $Global:CMLoggingAvailable = $false
}
