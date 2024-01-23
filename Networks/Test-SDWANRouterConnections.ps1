[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $userName,

    [Parameter(Mandatory=$true, Position=1)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $securePassword,

    [Parameter(Mandatory=$true, Position=2)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceRtr,

    [Parameter(Mandatory=$true, Position=3)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceInterface,

    [Parameter(Mandatory=$true, Position=4)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $sourceIPAddress,

    [Parameter(Mandatory=$true, Position=5)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $destinationRtr,

    [Parameter(Mandatory=$true, Position=6)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $destinationInterface,

    [Parameter(Mandatory=$true, Position=7)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $destinationIPAddress,

    [Parameter(Mandatory=$true, Position=8)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $outputFileName
)
<#
Write-Host ("-userName: {0}`r`n-securePassword: {1}:`r`n-sourceRtr: {2}`r`n-sourceInterface: {3}`r`n-sourceIPAddress: {4}`r`ndestinationRtr-: {5}`r`ndestinationInterface-: {6}`r`n-destinationIPAddress: {7}`r`n-outputFileName: {8}" -f @(
    $userName,
    $securePassword,
    $sourceRtr,
    $sourceInterface,
    $sourceIPAddress,
    $destinationRtr,
    $destinationInterface,
    $destinationIPAddress,
    $outputFileName
))

Start-Sleep 10
#>
function Run-SSHStreamCommand
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [Renci.SshNet.ShellStream]
        $stream,

        [Parameter(Mandatory=$true, Position=1)]
        [String]
        $cmd,

        [Parameter(Mandatory=$false, Position=2)]
        [int]
        $timeOutMS=100,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $SuppressOutput
    )

    $sb = [System.Text.StringBuilder]::new()
    if(-not [String]::IsNullOrEmpty($cmd))
    {
        if(-not $cmd.EndsWith("`n"))
        {
            $cmd = "{0}`n" -f @($cmd)
        }

        $stream.Write($cmd)
        Start-Sleep -MilliSeconds 100
        while($stream.DataAvailable)
        {
            $data = $stream.Read()
            if($null -ne $data)
            {
                [void] $sb.Append($data)
            }
            Start-Sleep -MilliSeconds $timeOutMS
        }
    }
    else
    {
        [void] $sb.Append("No command provided")
    }

    if(-not $SuppressOutput)
    {
        return $sb.ToString()
    }
}

$sb = [System.Text.StringBuilder]::new()
$d =  "" | Select-Object SourceRouter, SourceInterface, SourceIP, DestinationRouter, DestinationInterface, DestinationIP, SuccessRate, Sent, Received, Min, Avg, Max, Comment

$d.SourceRouter = $sourceRtr
$d.SourceInterface = $sourceInterface
$d.SourceIP = $sourceIPAddress
$d.DestinationRouter = $destinationRtr
$d.DestinationInterface = $destinationInterface
$d.DestinationIP = $destinationIPAddress

$pingCommand = "ping {0} source {1} repeat 100 timeout 1" -f @($d.DestinationIP, $d.SourceIP)
$cred = [PSCredential]::new($userName, (ConvertTo-SecureString $securePassword))
$pingSuccessRegEx = "Success rate is (\d+) percent \((\d+)/(\d+)\)([^=]+\s+=\s+(\d+)/(\d+)/(\d+) ms)?$"

$success = $false
$retries = 0
while((-not $success) -and ($retries -lt 2))
{
    try
    {
        $sshSession = $null
        $sshSession = New-SSHSession -ComputerName $d.SourceRouter -Credential $cred -AcceptKey -ConnectionTimeout 10 -ErrorAction Stop
        if($null -ne $sshSession)
        {
            $stream = $null
            $stream = $sshSession.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)

            if($null -ne $stream)
            {
                Run-SSHStreamCommand $stream "Terminal Length 0" -SuppressOutput
# Write-Host $output
                $output = Run-SSHStreamCommand -stream $stream -cmd $pingCommand -timeOutMS 1000

                if($null -ne $output)
                {
# Write-Host $output
                    $sshOutput = $output -split "`r`n"
                    $successLine = $sshOutput -match $pingSuccessRegEx
                    if($successLine -is [Array])
                    {
                        $successLine = $successLine[0]
                    }

                    if(-not [String]::IsNullOrEmpty($successLine))
                    {
                        if($successLine -match $pingSuccessRegEx)
                        {
                            $d.SuccessRate = $Matches[1]
                            $d.Received = $Matches[2]
                            $d.Sent = $Matches[3]
                        }
                        if($Matches.Count -ge 8)
                        {
                            $d.Min = $Matches[5]
                            $d.Avg = $Matches[6]
                            $d.Max = $Matches[7]
                        }

                        # Write-Host -ForegroundColor Green ("`t`t{0}" -f @($successLine))
                        $success = $true
                    } `
                    else
                    {
                        [void] $sb.Append(("ERROR: Unable to parse output from {0} for {1}." -f @($d.SourceRouter, $pingCommand)))
                    }
                } `
                else
                {
                    [void] $sb.Append(("ERROR: No output returned from {0} for {1}." -f @($d.SourceRouter, $pingCommand)))
                }
            } `
            else
            {
                [void] $sb.Append(("ERROR: Failed to create SSH stream to {0}." -f @($d.SourceRouter)))
            }

            [void] (Remove-SSHSession -SSHSession $sshSession -ErrorAction Stop)
        }
    }
    catch
    {
        if($null -eq $sshSession)   ## New-SSHSession failed...
        {
            [void] $sb.Append(("ERROR: Failed to open SSH session to {0}." -f @($d.SourceRouter)))
        } `
        else  ## Remove-SSHSession failed
        {
            [void] $sb.Append(("ERROR: Failed to close SSH session to {0}." -f @($d.SourceRouter)))
        }
    }
    $retries++
}

$d.Comment = $sb.ToString()
$output = $d | ConvertTo-Csv -Delimiter "`t" -NoTypeInformation

$newFile = $false

try
{
    while ($true)
    {
        try
        {
            $outputFileStream = [System.IO.FileStream]::new($outputFileName, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $newFile = $outputFileStream.Length -eq 0
            break;
        }
        catch
        {
            Start-Sleep -Milliseconds 20
        }
    }

    try
    {
        [void] $outputFileStream.Seek(-1, [System.IO.SeekOrigin]::End)
    }
    catch
    {

    }

    # If this is the first time the script is writing to the output file, then include the column names...
    if($newFile)
    {
        $output = $output -join "`r`n"
    }
    else  # ...otherwise, just need to values
    {
        $output = $output[1]
    }

    $streamWriter = [System.IO.StreamWriter]::new($outputFileStream)
    $streamWriter.WriteLine($output)

    $streamWriter.Close()
    $streamWriter.Dispose()
    $outputFileStream.Close()
    $outputFileStream.Dispose()
}
finally
{
    if ($null -ne $outputFileStream)
    {
        $outputFileStream.Dispose();
    }
}

# $output
