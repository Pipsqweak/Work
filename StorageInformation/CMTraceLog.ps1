function Write-log {

    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$false)]
          [String]$Path,

          [parameter(Mandatory=$true)]
          [String]$Message,

          [Parameter(Mandatory=$true)]
          [ValidateSet("Info", "Warning", "Error")]
          [String]$Type
    )

    switch ($Type) {
        "Info" { [int]$Type = 1 }
        "Warning" { [int]$Type = 2 }
        "Error" {
            [int]$Type = 3
            $Global:ErrorLogged = $true
        }
    }

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
        $Message, $logTime.ToString("HH:mm:ss.ffffff"), $logTime.ToString("M-d-yyyy"), $myComponent, [System.Security.Principal.WindowsIdentity]::GetCurrent().Name, $Type, [Threading.Thread]::CurrentThread.ManagedThreadId, $myFile)

    # If the log file folder does not exist, then write the message out via Write-Verbose
    if(-not [String]::IsNullOrEmpty($Path))
    {
        $logPath = $Path | Split-Path
        if([System.IO.Directory]::Exists($logPath))
        {
            $content | Out-File -FilePath $Path -Append -Encoding "utf8"
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
}

function LogInfo {

    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$true)]
          [String]$Message
    )

    Write-log $Global:LogPath $Message "Info"
}

function LogWarning {

    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$true)]
          [String]$Message
    )

    Write-log $Global:LogPath $Message "Warning"
}

function LogError {

    [CmdletBinding()]
    Param(
          [parameter(Mandatory=$true)]
          [String]$Message
    )

    Write-log $Global:LogPath $Message "Error"
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
