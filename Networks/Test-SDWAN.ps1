using module PEI.Log

[Log]::Init("C:\Users\kbriney-adm\Tmp", "SDWANTester", 14, 1, [LogLevel]::TRACE)
[Log]::Info("Logging initialized...")

Import-Module Posh-SSH
$possibleInterfaces = @(
    "GigabitEthernet2.400",
    "GigabitEthernet2.401",
    "GigabitEthernet0/0/0",
    "GigabitEthernet0/0/1"
)

[Log]::Trace("Sourcing MySQLDBConnection class")
# Source in the MySQLDBConnection class
. C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Utilities\DBConnectionMYSQL.ps1
#  gestioip -p1n33dmCB!

[Log]::Trace("Testing access to IPAM database.")
# Connect to the IPAM database...
#  Create a credential object for the IPAMDB...
$ipamDBCredential = [System.Management.Automation.PsCredential]::new("gestioip", ($inventoryConfig.IPAMDB.Password | ConvertTo-SecureString))

#  Build a connection string from the configuration data and the credential
$dbConnectionString = "Server={0};Port={1};Database={2};Uid={3};Pwd={4};" -f @(
    "ddc-ipam01.powereng.com",
    3306,
    "gestioip",
    $ipamDBCredential.UserName,
    $ipamDBCredential.GetNetworkCredential().Password
)

#  Make a connection to the database
$Global:db = [MySQLDBConnection]::new($dbConnectionString)

#  Make sure we can query the database
$dt = $Global:db.GetDataTable("SELECT * FROM global_config;")
if(($null -ne $dt) -and ($dt.Rows.Count -gt 0))
{
    [Log]::Info("Successfully connected to IPAM database.")
}
else
{
    # Nothing, already logged an error...
}

$dtSDWANRouters = $Global:db.GetDataTable("SELECT INET_NTOA(ip) as IP, hostname AS Router FROM host WHERE (hostname REGEXP '-SDW[0-9]{2}$') AND (hostname NOT LIKE 'LAB-%') ORDER BY Router;")


$sdwanRouters = @(
    "HLY-MAI-MDF00-SDW01", "HLY-MAI-MDF00-SDW02", "ORL-MDF01-SDW01", "HOU-MDF12-SDW01", "PLV-MDF01-SDW01", "BOI-LEG-MDF01-SDW01",
    "BOI-LEG-MDF01-SDW02", "MIN-MDF02-SDW01", "CLK-MDF02-SDW01", "NY7-RDC02-SDW01", "NY7-RDC02-SDW02", "NY7-RDC02-SDW03",
    "NY7-RDC02-SDW04", "AT4-RDC02-SDW01", "AT4-RDC02-SDW02", "LAS04-RDC01-SDW01", "LAS04-RDC01-SDW02", "DA11-RDC01-SDW01",
    "DA11-RDC01-SDW02", "CH3-RDC02-SDW01", "CH3-RDC02-SDW02", "CH3-RDC02-SDW03", "CH3-RDC02-SDW04", "SE4-RDC01-SDW01",
    "SE4-RDC01-SDW02", "SE4-RDC01-SDW03", "SE4-RDC01-SDW04", "YYC01-RDC01-SDW01", "YYC01-RDC01-SDW02", "CH3-EDC03-SDW01",
    "CH3-EDC03-SDW02", "CH3-EDC03-SDW03", "CH3-EDC03-SDW04", "CH3-EDC03-SDW05", "CH3-EDC03-SDW06", "DE2-EDC01-SDW01",
    "DE2-EDC01-SDW02", "DE2-EDC01-SDW03", "DE2-EDC01-SDW04", "DE2-EDC01-SDW05", "DE2-EDC01-SDW06", "PHX-MDF01-SDW01",
    "BOS-MDF03-SDW01", "AR2-MDF01-SDW01", "MSN-MDF02-SDW01", "SYR-MDF04-SDW01", "HAM-MDF02-SDW01", "VAN-MDF01-SDW01",
    "CIN-MDF01-SDW01", "ARB-MDF02-SDW01", "MTL-MDF04-SDW01", "SAT-MDF02-SDW01", "AST-MDF04-SDW01", "BIL-MDF02-SDW01",
    "AIR-MDF02-SDW01", "EDM-MDF02-SDW01", "SLC-MDF06-SDW01", "FTL-MDF03-SDW01", "COL-MDF02-SDW01", "RIC-MDF04-SDW01",
    "AUG-MDF01-SDW01", "TYL-MDF01-SDW01", "ATL-MDF01-SDW01"
) | Sort-Object
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


$creds = Get-Credential -Message "Provide credentials for SDWAN Router SSH Connections"
$ethMask = "({0})\s+(\d+\.\d+\.\d+\.\d+)\s+([^\s]+)\s+([^\s]+)\s+(administratively down|down|up)\s+(administratively down|down|up)"

$locatedInterfaces = [System.Collections.Generic.List[System.Object]]::new()
$r = 0
while($r -lt $sdwanRouters.Length)
{
    $rtr = $sdwanRouters[$r]
    $success = $false
    $retries = 0
    while((-not $success) -and ($retries -lt 2))
    {
        try
        {
            Write-Host ("Checking {0}..." -f @($rtr))
            $sshSession = $null
            $sshSession = New-SSHSession -ComputerName $rtr -Credential $creds -AcceptKey -ConnectionTimeout 10 -ErrorAction Stop

            if($null -ne $sshSession)
            {
                $stream = $null
                $stream = $sshSession.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)

                if($null -ne $stream)
                {
                    Run-SSHStreamCommand $stream "Terminal Length 0" -SuppressOutput
                    $output = Run-SSHStreamCommand $stream "sh ip int bri"

                    if($null -ne $output)
                    {
                        $sshOutput = $output -split "`r`n"

                        $a = 0
                        while($a -lt $possibleInterfaces.Length)
                        {
                            $ethSearch = $ethMask -f @($possibleInterfaces[$a])
                            $matchedLines = $sshOutput -match $ethSearch
                            if($matchedLines -is [Array])
                            {
                                $b = 0
                                while($b -lt $matchedLines.Length)
                                {
                                    if($matchedLines[$b] -match $ethSearch)
                                    {
                                        $d = "" | Select-Object Router,InterfaceName, IPAddress, Status, Protocol

                                        $d.Router = $rtr
                                        $d.InterfaceName = $Matches[1]
                                        $d.IPAddress = $Matches[2]
                                        $d.Status = $Matches[5]
                                        $d.Protocol = $Matches[6]

                                        Write-Host ("`tFound: {0}, {1}, Status: {2}, Protocol: {3}" -f @($d.InterfaceName, $d.IPAddress, $d.Status, $d.Protocol))
                                        $success = $true
                                        $locatedInterfaces.Add($d)
                                    }
                                    $b++
                                }
                            }
                            $a++
                        }
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Red ("Failed to read output from SSH stream to {0}." -f @($rtr))
                    }
                } `
                else
                {
                    Write-Host -ForegroundColor Red ("Failed to create SSH stream to {0}." -f @($rtr))
                }

                [void] (Remove-SSHSession -SSHSession $sshSession -ErrorAction Stop)
            }
        }
        catch
        {
            if($null -eq $sshSession)   ## New-SSHSession failed...
            {
                Write-Host -ForegroundColor Red ("Failed to open SSH session to {0}." -f @($rtr))
            } `
            else  ## Remove-SSHSession failed
            {
                Write-Host -ForegroundColor Red ("Failed to close SSH session to {0}." -f @($rtr))
            }
        }

        $retries++
    }
    $r++
}

$sw = [System.Diagnostics.Stopwatch]::new()
$sw.Start()
$sb = [System.Text.StringBuilder]::new()
$pingMask = "ping {0} source {1} repeat 100 timeout 1"
$pingSuccessRegEx = "Success rate is (\d+) percent \((\d+)/(\d+)\)([^=]+\s+=\s+(\d+)/(\d+)/(\d+) ms)?$"
$pingResults = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $locatedInterfaces.Count)
{
    $srcInterface = $locatedInterfaces[$a]
    if(($srcInterface.Status -eq "up") -and ($srcInterface.Protocol -eq "up"))
    {
        $dstInterfaces = @(
            $locatedInterfaces | Where-Object {
                ($_.IPAddress -ne $srcInterface.IPAddress) -and
                ($_.Status -eq "up") -and
                ($_.Protocol -eq "up")
            }
        )
        Write-Host ("Pinging from: {0}:{1}:{2}" -f @($srcInterface.Router, $srcInterface.InterfaceName, $srcInterface.IPAddress))

        $b = 0
        while($b -lt $dstInterfaces.Length)
        {
            $d =  "" | Select-Object SourceRouter, SourceInterface, SourceIP, DestinationRouter, DestinationInterface, DestinationIP, SuccessRate, Sent, Received, Min, Avg, Max
            $d.SourceRouter = $srcInterface.Router
            $d.SourceInterface = $srcInterface.InterfaceName
            $d.SourceIP = $srcInterface.IPAddress
            $d.DestinationRouter = $dstInterfaces[$b].Router
            $d.DestinationInterface = $dstInterfaces[$b].InterfaceName
            $d.DestinationIP = $dstInterfaces[$b].IPAddress

            Write-Host ("`tto: {0}:{1}:{2}" -f @($d.DestinationRouter, $d.DestinationInterface, $d.DestinationIP))
            $pingCommand = $pingMask -f @($d.DestinationIP, $d.SourceIP)

            $success = $false
            $retries = 0
            while((-not $success) -and ($retries -lt 2))
            {
                try
                {
                    $sshSession = $null
                    $sshSession = New-SSHSession -ComputerName $d.SourceRouter -Credential $creds -AcceptKey -ConnectionTimeout 10 -ErrorAction Stop
                    if($null -ne $sshSession)
                    {
                        $stream = $null
                        $stream = $sshSession.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)

                        if($null -ne $stream)
                        {
                            Run-SSHStreamCommand $stream "Terminal Length 0" -SuppressOutput

                            $output = Run-SSHStreamCommand -stream $stream -cmd $pingCommand -timeOutMS 1000

                            if($null -ne $output)
                            {
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

                                    Write-Host -ForegroundColor Green ("`t`t{0}" -f @($successLine))
                                    $pingResults.Add($d)
                                    $success = $true
                                } `
                                else
                                {
                                    Write-Host -ForegroundColor Yellow ("`t`tUnable to parse output from  {0} for {1}." -f @($srcInterface.Router, $pingCommand))
                                    Write-Host -ForegroundColor Yellow $output
                                }
                            } `
                            else
                            {
                                Write-Host -ForegroundColor Yellow ("`t`tNo output returned from {0} for {1}." -f @($srcInterface.Router, $pingCommand))
                            }
                        } `
                        else
                        {
                            Write-Host -ForegroundColor Red ("`tFailed to create SSH stream to {0}." -f @($rtr))
                        }

                        [void] (Remove-SSHSession -SSHSession $sshSession -ErrorAction Stop)
                    }
                }
                catch
                {
                    if($null -eq $sshSession)   ## New-SSHSession failed...
                    {
                        Write-Host -ForegroundColor Red ("`tFailed to open SSH session to {0}." -f @($rtr))
                    } `
                    else  ## Remove-SSHSession failed
                    {
                        Write-Host -ForegroundColor Red ("`tFailed to close SSH session to {0}." -f @($rtr))
                    }
                }
                $retries++
            }
            $b++
        }
    }
    Write-Host

    $a++
}
$sw.Stop()
Write-Host $sw.Elapsed.ToString()

$uniqueRouters = @($locatedInterfaces | Select-Object -Unique -ExpandProperty Router)
$uniqueInterfaceNames = @($locatedInterfaces | Select-Object -Unique -ExpandProperty InterfaceName)

$parameterSets = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $uniqueRouters.Length)
{
    $dstRtr = $uniqueRouters[$a]
    $b = 0
    while($b -lt $uniqueInterfaceNames.Length)
    {
        $dstInf = $uniqueInterfaceNames[$b]

        $dst = @($locatedInterfaces | Where-Object { ($_.Router -eq $dstRtr) -and ($_.InterfaceName -eq $dstInf) -and ($_.Status -eq "up") -and ($_.Protocol -eq "up") })
        if($dst.Length -eq 1)
        {
            $dst = $dst[0]
            $c = 0
            while($c -lt $uniqueRouters.Length)
            {
                $srcRtr = $uniqueRouters[$c]
                if($srcRtr -ne $dstRtr)
                {
                    $d = 0
                    while($d -lt $uniqueInterfaceNames.Length)
                    {
                        $srcInf = $uniqueInterfaceNames[$d]

                        $src = @($locatedInterfaces | Where-Object { ($_.Router -eq $srcRtr) -and ($_.InterfaceName -eq $srcInf) -and ($_.Status -eq "up") -and ($_.Protocol -eq "up")} )

                        if($src.Length -eq 1)
                        {
                            $src = $src[0]
                            $p = "" | Select-Object userName, securePassword, sourceRtr, sourceInterface, sourceIPAddress, destinationRtr, destinationInterface, destinationIPAddress, outputFileName
#                            $p = "" | Select-Object NoProfile, NoExit, File, userName, securePassword, sourceRtr, sourceInterface, sourceIPAddress, destinationRtr, destinationInterface, destinationIPAddress, outputFileName
#                            $p.NoProfile = $true
#                            $p.NoExit = $true
#                            $p.File = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Networks\Test-SDWANRouterConnections.ps1"
                            $p.userName = $creds.UserName
                            $p.securePassword = (ConvertFrom-SecureString $creds.Password)
                            $p.sourceRtr = $src.Router
                            $p.sourceInterface = $src.InterfaceName
                            $p.sourceIPAddress = $src.IPAddress
                            $p.destinationRtr = $dst.Router
                            $p.destinationInterface = $dst.InterfaceName
                            $p.destinationIPAddress = $dst.IPAddress
                            $p.outputFileName = $outputFileName

                            $parameterSets.Add($p)
                        }
                        $d++
                    }
                }
                $c++
            }
        }
        $b++
    }
    $a++
}

$saveParameters = [System.Collections.Generic.List[System.Object]]::new()
$parameterSets | ForEach-Object { $saveParameters.Add($_) }

$parameterSets.Clear()
$saveParameters | Sort-Object sourceRtr, sourceInterface, destinationRtr, destinationInterface | ForEach-Object { $parameterSets.Add($_) }


$idx = [System.Collections.Generic.List[int]]::new()
@(0..($parameterSets.Count - 1)) | ForEach-Object { $idx.Add($_)}
$maxSequenceSize = 25
$maxTries = 15

$testSet = [System.Collections.Generic.List[System.Object]]::new()
$tries = 0
$distance = $null
$sb = [System.Text.StringBuilder]::new()
$sequence = [System.Collections.Generic.List[System.Object]]::new()

while($testSet.Count -lt $parameterSets.Count)
{
    $tries++
    $i = Get-Random -InputObject $idx

    $j = 1
    $cleanSequence = $true
    if($null -eq $distance)
    {
        $distance = "" | Select-Object i,j
        $distance.i = $i
        $distance.j = $j
    }

    while(($j -le $maxSequenceSize) -and ($j -le $testSet.Count) -and $cleanSequence)
    {
        $l = $testSet.Count - $j
        $cleanSequence = ($testSet[$l].sourceRtr -ne $parameterSets[$i].sourceRtr) -and `
                         ($testSet[$l].destinationRtr -ne $parameterSets[$i].destinationRtr) -and `
                         ($testSet[$l].sourceRtr -ne $parameterSets[$i].destinationRtr) -and `
                         ($testSet[$l].destinationRtr -ne $parameterSets[$i].sourceRtr)

        #Write-Host ("{0}: `$testSet[{0}].sourceRtr = {2}; `$parameterSets[{1}].sourceRtr = {3}; `$testSet[{0}].destinationRtr = {4}; `$parameterSets[{1}].destinationRtr = {5}; `$cleanSequence = {6}" -f @($j, $i, $testSet[$j].sourceRtr, $parameterSets[$i].sourceRtr, $testSet[$j].destinationRtr, $parameterSets[$i].destinationRtr, $cleanSequence))

        if($cleanSequence -and ($j -gt $distance.j))
        {
            $distance.i = $i
            $distance.j = $j
        }
        $j++
    }

    if(($tries -eq $idx.Count) -or $cleanSequence)
    {
        $i = $distance.i
        $j = $distance.j
        $idx.Remove($i) | Out-Null
        $testSet.Add($parameterSets[$i])
        $d = "" | Select-Object i,j,SRC,DST,Count,Tries,Distance
        $d.i = $i
        $d.j = $j
        $d.SRC = $parameterSets[$i].sourceRtr.Replace("-","")
        $d.DST = $parameterSets[$i].destinationRtr.Replace("-","")
        $d.Count = $testSet.Count
        $d.Tries = $tries
        $d.Distance = $j

        $sequence.Add($d)
        $str = "{0}|{1}|{2}|{3}|Count = {4}|Tries = {5}|Distance: {6}" -f @($d.i, $d.j, $d.SRC, $d.DST, $d.Count, $d.Tries, $d.Distance)
        Write-Host $str
        $tries = 0
        $distance = $null
    }
}

$sequence | ConvertTo-CSV -NoTypeInformation -Delimiter "`t" | Set-Clipboard

$parameterSets | ConvertTo-CSV -NoTypeInformation -Delimiter "`t" | Set-Clipboard

$parameterSets.Clear()
$saveParameters | Sort-Object sourceRtr, sourceInterface, destinationRtr, destinationInterface | ForEach-Object { $parameterSets.Add($_) }


$testSet = [System.Collections.Generic.List[System.Object]]::new()

$i = 0 # index of source router in $sdwanRouters

$skipLength = [int] ($sdwanRouters.Length / 2)

$j = $i + $skipLength - 1    # index of destination router in $sdwanRouters
$oj = -1
$skipSources = [System.Collections.Generic.List[int]]::new()
while($parameterSets.Count -gt 0)
{
    $tries = 0
    do
    {
        $tries++
        do
        {
            $j = ($j + 1) % $sdwanRouters.Length
        } while($j -eq $oj)
        $possible = @($parameterSets | Where-Object { ($_.sourceRtr -eq $sdwanRouters[$i]) -and ($_.destinationRtr -eq $sdwanRouters[$j]) }) | Select-Object -First 1
    } while(($null -eq $possible) -and ($tries -lt $sdwanRouters.Length))

    if($i -gt $j)
    {
        $gap = ($sdwanRouters.Length - $i) + $j
    } `
    else
    {
        $gap = $j - $i
    }

    if($null -ne $possible)
    {
        $testSet.Add($possible)
        $o = $parameterSets.IndexOf($possible)
        $parameterSets.RemoveAt($o)
        $oj = $j

        Write-Host ("i: {0}`tj: {1}`tGAP: {2}`tSRC: {3}`tDST: {4}`tCount: {5}" -f @($i, $j, $gap, $possible.sourceRtr, $possible.destinationRtr, $testSet.Count))
    }
    else
    {
        $nj = ($i + $skipLength) % $sdwanRouters.Length
        if($nj -eq $j)
        {
            $nj++
        }
        $j = $nj % $sdwanRouters.Length
        Write-Host "----------------"
        $g = $skipSources.BinarySearch($i)
        if($g -lt 0)
        {
            $skipSources.Insert(-bnot $g, $i)
        }
    }
    do
    {
        $i = ($i + 1) % $sdwanRouters.Length
        $g = $skipSources.BinarySearch($i)
    } while($g -ge 0)
}


$parameterSets.Clear()
$saveParameters | Sort-Object sourceRtr, sourceInterface, destinationRtr, destinationInterface | ForEach-Object { $parameterSets.Add($_) }

$codeBlock = {
    $skipLength--
    $a = 2770
    $moved = 0
    $passMoves = 0
    $pass = 0
    do
    {
        $a = 0
        $passMoves = 0
        while($a -lt $parameterSets.Count)
        {
            $b = $a + 1

            # @($parameterSets[$a],$parameterSets[$b]) | Select-Object sourceRtr, destinationRtr | ft -AutoSize
            $found = $false
            do
            {
                $found = ($parameterSets[$a].sourceRtr -eq $parameterSets[$b].sourceRtr) -or `
                        ($parameterSets[$a].sourceRtr -eq $parameterSets[$b].destinationRtr) -or `
                        ($parameterSets[$a].destinationRtr -eq $parameterSets[$b].destinationRtr) -or `
                        ($parameterSets[$a].destinationRtr -eq $parameterSets[$b].sourceRtr)
                if(-not $found)
                {
                    $b++
                }
            } until($found  -or ($b -gt ($a + $skipLength)) -or ($b -eq $parameterSets.Count))

            if($found -and ($moved -lt ($parameterSets.Count - $a) ))
            {
                if($passMoves -eq 0)
                {
                    Write-Host ("A = {0}" -f @($a))
                }
                $parameterSets.Add($parameterSets[$b])
                [void] $parameterSets.RemoveAt($b)
                $passMoves++
                $moved++
            } `
            else
            {
                # Write-Host ("PASS = {0}; A = {1}; MOVED = {2}; SRC = {3}; DST = {4}" -f @($pass, $a, $moved, $parameterSets[$a].sourceRtr, $parameterSets[$a].destinationRtr))
                $a++
                $moved = 0
            }
        }
        Write-Host ("Pass: {0}; Moves: {1}" -f @($pass, $passMoves))
        $pass++
    } until($passMoves -le 1)
}

$parameterSets[0..$b] | Select-Object sourceRtr, destinationRtr


$a = 0
$parameterSets | Foreach-Object {
    @{ROW=$a++; SRC=$_.sourceRtr.Replace("-",""); DST=$_.destinationRtr.Replace("-","")}
} | Select-Object ROW, SRC, DST | ConvertTo-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard

$testSet | Foreach-Object -ThrottleLimit 25 -Parallel {
    & C:\users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Networks\Test-SDWANRouterConnections.ps1 -userName $_.userName -securePassword $_.securePassword -sourceRtr $_.sourceRtr -sourceInterface $_.sourceInterface -sourceIPAddress $_.sourceIPAddress -destinationRtr $_.destinationRtr -destinationInterface $_.destinationInterface -destinationIPAddress $_.destinationIPAddress -outputFileName $_.outputFileName
}

foreach($dstInterface in @($locatedInterfaces | Sort-Object Router | Where-Object { ($_.Status -eq "up") -and ($_.Protocol -eq "up") }))
{
    foreach($srcInterface in @($locatedInterfaces | Where-Object { ($_.Router -ne $dstInterface.Router) -and ($_.Status -eq "up") -and ($_.Protocol -eq "up") } | Sort-Object Router))
    {
        $d = @{
            "NoProfile" = $true
            "NoExit" = $true
            "File" = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Networks\Test-SDWANRouterConnections.ps1"
            "userName" = $creds.UserName
            "securePassword" = (ConvertFrom-SecureString $creds.password)
            "sourceRtr" = $srcInterface.Router
            "sourceInterface" = $srcInterface.InterfaceName
            "sourceIPAddress" = $srcInterface.IPAddress
            "destinationRtr" = $dstInterface.Router
            "destinationInterface" = $dstInterface.InterfaceName
            "destinationIPAddress" = $dstInterface.IPAddress
            "outputFileName" = $outputFileName
        }

        $parameterSets.Add($d)
    }
}

<#
            "-NoProfile",
            "-File", "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\Networks\Test-SDWANRouterConnections.ps1"
            "-userName", $creds.UserName
            "-securePassword", (ConvertFrom-SecureString $creds.password)
            "-sourceRtr", $srcInterface.Router
            "-sourceInterface", $srcInterface.InterfaceName
            "-sourceIPAddress", $srcInterface.IPAddress
            "-destinationRtr", $dstInterface.Router
            "-destinationInterface", $dstInterface.InterfaceName
            "-destinationIPAddress", $dstInterface.IPAddress
            "-outputFileName", $outputFileName
#>

$testSet | Foreach-Object -ThrottleLimit 2 -Parallel {
    Start-Process -FilePath "pwsh.exe" -NoNewWindow -ArgumentList $_
}


$a = 0
while($a -lt $locatedInterfaces.Count)
{
    $srcInterface = $locatedInterfaces[$a]
    if(($srcInterface.Status -eq "up") -and ($srcInterface.Protocol -eq "up"))
    {
        $dstInterfaces = @(
            $locatedInterfaces | Where-Object {
                ($_.IPAddress -ne $srcInterface.IPAddress) -and
                ($_.Status -eq "up") -and
                ($_.Protocol -eq "up")
            }
        )

        foreach($dstInterface in $dstInterfaces)
        {
            $d =  "" | Select-Object SourceRouter, SourceInterface, SourceIP, DestinationRouter, DestinationInterface, DestinationIP, SuccessRate, Sent, Received, Min, Avg, Max
            $d.SourceRouter = $srcInterface.Router
            $d.SourceInterface = $srcInterface.InterfaceName
            $d.SourceIP = $srcInterface.IPAddress
            $d.DestinationRouter = $dstInterface.Router
            $d.DestinationInterface = $dstInterface.InterfaceName
            $d.DestinationIP = $dstInterface.IPAddress

            $pingCommand = $pingMask -f @($d.DestinationIP, $d.SourceIP)

            $cmdStr = ".\Test-SDWANRouterConnections.ps1 -userName `"{0}`" -securePassword `"{1}`" -sourceRtr `"{2}`" -sourceInterface `"{3}`" -sourceIPAddress `"{4}`" -destinationRtr `"{5}`" -destinationInterface `"{6}`" -destinationIPAddress `"{7}`" -outputFileName `"{8}`"" -f @($creds.UserName, (ConvertFrom-SecureString $creds.password), $d.SourceRouter, $d.SourceInterface, $d.SourceIP, $d.DestinationRouter, $d.DestinationInterface, $d.DestinationIP, $outputFileName)

            Write-Host $cmdStr
        }
    }
    Write-Host

    $a++
}
