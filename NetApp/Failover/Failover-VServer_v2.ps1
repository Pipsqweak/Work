[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $SourceVServerName,

    [Parameter(Mandatory=$true,Position=1)]
    [ValidateNotNullOrEmpty()]
    [String]
    $DRVServerName,

    [Parameter(Mandatory=$false,Position=2)]
    [Switch]
    $Simulated = $false
)

<#

    NOTES: Add SVM peering checks.

#>

<#
    1. Stop changes to source VServer volumes.  (Only once)
        A. If source VServer has a CIFS server
            1) THEN: Shutdown CIFS server
        B. Shutdown VMs hosted on a datastore (later)

    2. For each volume hosted on the source VServer:
        A. If source volume is host to a VM datastore (this needs more work -- in fact, it is not in the script at all right now)
            NOTE: Likely need an external JSON file to keep track various items.
                What VMHost cluster the VM will be added to.
                What host to register the VMs on.
                What networks to attach the VMs to.
            1) THEN: For each VM stored on the source volume:
                A) Shutdown VM
                B) Remove VM from inventory
                C) Add VM to list of VMs to register on destination host.
        A. Add source volume to list of new snapmirror destination volumes
        B. For each snapmirror destination of the source volume
            1) If snapmirror destination volume is hosted on "DRVServerName"
                A) THEN: Capture as new snapmirror source volume.
                B) ELSE: Add destination volume to list of new snapmirror destination volumes
            2) Update snapmirror -- performed on destination
            3) Break snapmirror -- performed on destination
            4) Update snapshot policy on the destination volume.
                A) Make the destination volume's snapshot policy match the source volume
            5) Set storage efficiency settings on the destination volume
                A) Make the destination volume's storage efficiency settings match the source volume
            6) Remove snapmirror -- performed on destination
            7) Release snapmirror relationship -- performed on source

    3. Migrate CIFS service principal names from source CIFS server's AD computer object to destination CIFS server's AD computer object

    4. Migrate FS1 CName alias from source CIFS server to destination CIFS server

    5. Rebuild snapmirror relationships where the destination volume becomes the new source volume.
        A.

    Snapmirror Lifecycle
    -----------------------------------------------------------------------------------------------------------------
    1. Update snapmirror -- send updates from source to destination.  Completed from perspective of the destination.
        A. Source
            1) Before: Relationship intact
            2) After: Relationship intact
        B. Destination
            1) Before: idle/snapmirrored
            2) After: idle/snapmirrored

    2. Break snapmirror - Completed from perspective of the destination.
        A. Source
            1) Before: Relationship intact
            2) After: Relationship intact
        B. Destination
            1) Before: idle/snapmirrored
            2) After: idle/broken-off

    3. Delete snapmirror - Completed from perspective of the destination.
        A. Source
            1) Before: Relationship intact
            2) After: Relationship intact
        B. Destination
            1) Before: idle/broken-off
            2) After: Will not be able to retrieve snapmirror information

    4. Release snapmirror - Completed from perspective of the source.
        A. Source
            1) Before: Relationship intact
            2) After: No snapmirror relationship
        B. Destination
            1) Before: Will not be able to retrieve snapmirror information
            2) After: Will not be able to retrieve snapmirror information
#>

$Script:MaxActionWaitSeconds = 300

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

        [Parameter(Mandatory = $false, Position = 2)]
        [String]
        $Message = "",

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch]
        $NoNewLine,

        [Parameter(Mandatory = $false, Position = 4)]
        [Switch]
        $NewLine
    )

<#
    if($null -eq $Script:sbMessageLog)
    {
        $Script:sbMessageLog = [System.Text.StringBuilder]::new()
    }
#>
    if($NewLine)
    {
        Write-Host ""
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.AppendLine("")
        }
    }

    $indent = [String]::new(' ', ($IndentLevel * 3))
    if([Console]::CursorLeft -eq 0)
    {
        $indent = "{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMddHHmmss.fff"), $indent)
    }
    if($NoNewLine)
    {
        Write-Host -ForegroundColor $Color -NoNewline ("{0}{1}" -f @($indent, $message))
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.Append(("{0}{1}" -f @($indent, $message)))
        }
    }
    else
    {
        Write-Host -ForegroundColor $color ("{0}{1}" -f @($indent, $message))
        if($null -ne $Script:sbMessageLog)
        {
            [void] $Script:sbMessageLog.AppendLine(("{0}{1}" -f @($indent, $message)))
        }
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

    LogOutput -IndentLevel $IndentLevel -Color Green -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
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
        LogOutput -IndentLevel $IndentLevel -Color Yellow -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
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

    LogOutput -IndentLevel $IndentLevel -Color Red -Message $Message -NoNewLine:$NoNewLine -NewLine:$NewLine
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
        LogOutput -IndentLevel $IndentLevel -Color Red -Message ("Exception: {0}" -f @($Message)) -NoNewLine:$NoNewLine -NewLine:$NewLine
    }
}

function LogAction
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [String]
        $actionString
    )

    if($null -ne $Script:actionSteps)
    {
        if($Script:Simulated)
        {
            $actionString = "{0}-simulated" -f @($actionString)
        }
        $Script:actionSteps.Add([DateTime]::Now.ToString("yyyyMMddHHmmss.fff"), $actionString)
    }
}

function ActionWasCompleted
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [String]
        $actionString
    )

    $wasCompleted = ($null -ne $Script:actionSteps) -and $Script:actionSteps.ContainsValue($actionString)

    return $wasCompleted
}

function GetCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Object]
        $cifsServer
    )

    $good2Go = $true
    $myCIFSServer = $null

    try
    {
        # Try to get the status of the CIFS server.
        if($cifsServer -is [System.String])
        {
            LogInfo ("Getting CIFS server: {0}" -f @($cifsServer)) 1
            $myCIFSServer = Get-NCCifsServer -Controller @($cDot.Values) -Name $cifsServer -ErrorAction Stop
        }
        elseif($cifsServer -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
        {
            LogInfo ("Getting CIFS server: {0}:{1}:{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $cifsServer.CifsServer)) 1
            $myCIFSServer = Get-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -ErrorAction Stop
        }
        else
        {
            LogError ("CIFS server value type [{0}] sent to GetCIFSServerStatus is not a [String] or [DataONTAP.C.Types.Cifs.CifsServerConfig]." -f @($cifsServer.GetType().FullName))
        }

        if($null -eq $myCIFSServer)
        {
            if($cifsServer -is [System.String])
            {
                LogError ("Failed to retrieve CIFS server data from {0}" -f @($cifsServer)) 1 -NewLine
            }
            elseif($cifsServer -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
            {
                LogError ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
            }
            else
            {
                LogError "Failed to retrieve CIFS server data."
            }
            $good2Go = $false
        }
        else
        {
            # Nothing....
        }
    }
    catch
    {
        if($cifsServer -is [System.String])
        {
            LogError ("Failed to retrieve CIFS server data from {0}" -f @($cifsServer)) 1 -NewLine
        }
        elseif($cifsServer -is [DataONTAP.C.Types.Cifs.CifsServerConfig])
        {
            LogError ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
        }
        else
        {
            LogError "Failed to retrieve CIFS server data."
        }
        $good2Go = $false
    }

    return @($good2Go, $myCIFSServer)
}

function WaitForCIFSServerStatus
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [DataONTAP.C.Types.Cifs.CifsServerConfig]
        $cifsServer,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $StatusToWaitFor
    )

    $good2Go = $true

    # Wait for the CIFS service to be $StatusToWaitFor...

    # Use a timer to limit the amount of time we wait...
    $timer = [System.Diagnostics.Stopwatch]::new()
    $timer.Start()

    $myCIFSServer = $null
    $Error.Clear()
    LogInfo ("Waiting (maximum {0} seconds) for CIFS server {1}:{2} to be {3}.{4}" -f @($Script:MaxActionWaitSeconds, $cifsServer.NcController.Name, $cifsServer.Vserver, $StatusToWaitFor, $simulatedMsg)) 2 -NoNewLine
    do
    {
        $tries = 0
        do
        {
            $tries++
            try
            {
                $myCIFSServer = Get-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -ErrorAction Stop
            }
            catch
            {
                if($tries -eq 3)
                {
                    LogException ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 2 -NewLine
                    $good2Go = $false
                }
            }
        } while (($tries -lt 3) -and ($null -eq $myCIFSServer) -and ($timer.Elapsed.TotalSeconds -lt 300))

        if($null -ne $myCIFSServer)
        {
            if((-not $Simulated) -and ($myCIFSServer.AdministrativeStatus -ne $StatusToWaitFor))
            {
                LogInfo "." -NoNewLine
                # Pause a moment for station identification...
                Start-Sleep -Seconds 5
            }
        }
        else
        {
            LogError ("Failed to retrieve CIFS server data from {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1 -NewLine
            $good2Go = $false
        }
    } until (($Simulated) -or (-not $good2Go) -or (($null -ne $myCIFSServer) -and ($myCIFSServer.AdministrativeStatus -eq $StatusToWaitFor)) -or ($timer.Elapsed.TotalSeconds -ge 300))
    $timer.Stop()
    $good2Go = $Simulated -or ($myCIFSServer.AdministrativeStatus -eq $StatusToWaitFor)
    if($good2Go)
    {
        LogInfo
    }

    return $good2Go
}

function StartCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Object]
        $cifsServer,

        [Parameter(Mandatory = $false, Position = 1)]
        [Switch]
        $ReturnValue
    )

    # Use my generic GetCIFSServer here so I can pass in a string or DataONTAP.C.Types.Cifs.CifsServerConfig object
    $good2Go, $cifsServer = GetCIFSServer -cifsServer $cifsServer

    if($good2Go)
    {
        # If the CIFS server is not up, then start it.
        if($cifsServer.AdministrativeStatus -ne "up")
        {
            try
            {
                LogInfo ("Starting CIFS services on: {0}:{1}{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $simulatedMsg)) 1
                if(-not $Simulated)
                {
                    Start-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -Confirm:$false -ErrorAction Stop | Out-Null
                }

                # Wait for the CIFS service to be up...
                $good2Go = WaitForCIFSServerStatus -cifsServer $cifsServer -StatusToWaitFor "up"

                if($good2Go)
                {
                    LogAction ("CIFSServerStarted-{0}:{1}:{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $cifsServer.CifsServer))
                }
            }
            catch
            {
                LogException ("Failed to start CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
                $good2Go = $false
            }

            if(-not $good2Go)
            {
                LogWarning ("Please remember to check CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
            }
        }
        else
        {
            LogInfo ("CIFS server {0}:{1}:{2} is already up." -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $cifsServer.CifsServer)) 2
        }
    }
    else
    {
        # Nothing, already logged a message
    }

    if($ReturnValue)
    {
        return $good2Go
    }
}

function ShutdownCIFSServer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Object]
        $cifsServer,

        [Parameter(Mandatory = $false, Position = 1)]
        [Switch]
        $ReturnValue
    )

    # Use my generic GetCIFSServer here so I can pass in a string or DataONTAP.C.Types.Cifs.CifsServerConfig object
    $good2Go, $cifsServer = GetCIFSServer -cifsServer $cifsServer

    if($good2Go)
    {
        # If the CIFS server is not down, then stop it.
        if($cifsServer.AdministrativeStatus -ne "down")
        {
            try
            {
                LogInfo ("Stopping CIFS services on: {0}:{1}{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $simulatedMsg)) 1
                if(-not $Simulated)
                {
                    Stop-NcCifsServer -Controller $cifsServer.NcController -VserverContext $cifsServer.Vserver -Confirm:$false -ErrorAction Stop | Out-Null
                }

                # Wait for the CIFS service to be up or the action to timeout...
                $good2Go = WaitForCIFSServerStatus -cifsServer $cifsServer -StatusToWaitFor "down"

                if($good2Go)
                {
                    LogAction ("CIFSServerShutdown-{0}:{1}:{2}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $cifsServer.CifsServer))
                }
            }
            catch
            {
                LogException ("Failed to stop CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
                $good2Go = $false
            }

            if(-not $good2Go)
            {
                LogWarning ("Please remember to check CIFS services on {0}:{1}" -f @($cifsServer.NcController.Name, $cifsServer.Vserver)) 1
            }
        }
        else
        {
            LogInfo ("CIFS server {0}:{1}:{2} is already down." -f @($cifsServer.NcController.Name, $cifsServer.Vserver, $cifsServer.CifsServer)) 2
        }
    }
    else
    {
        # Nothing, already logged a message
    }

    if($ReturnValue)
    {
        return $good2Go
    }
}

function UpdateServicePrincipalName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADComputer]
        $adComp,

        [Parameter(Mandatory=$false,Position=1)]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc = $null
    )

    $good2Go = $true

    # This is what the values should be before we update the AD object
    $servicePrincipalNamesStringBefore = (($adComp.servicePrincipalName | Sort-Object) -join "|").ToLower()

    LogInfo ("Updating {0}...{1}" -f @($adComp.Name, $simulatedMsg)) 3
    $setADCompParams = @{
        Instance = $adComp
        ErrorAction = [System.Management.Automation.ActionPreference]::Stop
    }

    # If a domain controller was given, add it to the parameter hash table
    if($null -ne $dc)
    {
        $setADCompParams.Add("Server", $dc.Name)
    }

    try
    {
        if(-not $Simulated)
        {
            Set-ADComputer @setADCompParams | Out-Null
        }
        LogAction ("{0}-SPNUpdated" -f @($adComp.Name))

        # If a domain controller was given, then the updates were made on a specific DC, so we should be able to verify the change happened.
        if($null -ne $dc)
        {
            LogInfo ("Verifying service principal name was updated for {0}" -f @($adComp.Name)) 3 -NoNewline
            $getADCompParams = @{
                Identity = $adComp.Name
                Properties = @("servicePrincipalName")
                ErrorAction = [System.Management.Automation.ActionPreference]::Stop
                Server = $dc.Name
            }

            $tries = 0
            $verified = $false
            $maxRetries = 3
            while(($tries -lt $maxRetries) -and (-not $verified))
            {
                LogInfo "." -NoNewline
                $tries++
                try
                {
                    $adVerifyComp = Get-ADComputer @getADCompParams

                    # This is what the service principal names are after updating the AD computer object...
                    $servicePrincipalNamesStringAfter = (($adVerifyComp.servicePrincipalName | Sort-Object) -join "|").ToLower()

                    $verified = (-not $Simulated) -and ($servicePrincipalNamesStringBefore -eq $servicePrincipalNamesStringAfter)

                    # Don't display an error until we've tried $maxRetries times to verify the settings took.
                    if((-not $verified) -and ($tries -eq $maxRetries))
                    {
                        LogError "Failed" 1
                        LogWarning ("Service principal names for {0} do not appear to have been updated!" -f @($adComp.Name)) 4
                    }
                }
                catch
                {
                    LogException ("Failed to reacquire AD computer object for: {0}" -f @($adComp.Name)) 4 -NewLine
                }

                if (-not $verified)
                {
                    Start-Sleep -Seconds 5
                } `
                else # NOT (-not $verified)
                {
                    # Nothing.
                }
            }

            # An error/warning would have completed the line if -not $verified
            if($verified)
            {
                LogInfo "Success" 1
            }
        }
        else
        {
            # Nothing, since we can't guarantee we'll get the AD computer object back from the same DC we updated it on, we'll just have to roll with it.
        }
    }
    catch
    {
        LogException ("Failed to update AD computer object for: {0}" -f @($adComp.Name)) 4
        $good2Go = $false
    }

    return $good2Go
}

<#
    SetFS1CName

        Register CName record for FS1 alias for the destination CIFS Server
#>
function SetFS1CName
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADComputer]
        $newFS1ADComputer,

        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNull()]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc
    )

    $good2Go = $true
    $need2ChangeCNameRecord = $false
    LogInfo ("Setting {0} as FS1 alias via domain controller: {1}..." -f @($newFS1ADComputer.DNSHostName, $dc.Name)) 1
    try
    {
        $adDomain = Get-ADDomain -ErrorAction Stop
        if($null -ne $adDomain)
        {
            LogInfo ("Acquired AD Domain: {0}" -f @($adDomain.DNSRoot)) 2

            # Find the HOST/FS1 alias service principal name we need to register as a CNAME...
            $hostSPN = $newFS1ADComputer.servicePrincipalName | Where-Object { ($_ -notmatch $newFS1ADComputer.Name) -and ($_ -match ("^HOST/([^.]+)\.{0}" -f @([regex]::Escape($adDomain.DNSRoot)))) } | Select-Object -First 1
            if((-not [String]::IsNullOrEmpty($hostSPN)) -and ($hostSPN -match "^HOST/([^.]+)\."))
            {
                $fs1Alias = $Matches[1]
                if(-not [String]::IsNullOrEmpty($fs1Alias))
                {
                    LogInfo ("FS1 Alias: {0}" -f @($fs1Alias)) 2

                    LogInfo ("Getting current CName records for {0}" -f @($fs1Alias)) 2
                    $cnameRecords = @(Get-DnsServerResourceRecord -Name $fs1Alias -ZoneName $adDomain.DNSRoot -ComputerName $dc.Name -RRType CName -ErrorAction Stop)
                    if($cnameRecords.Length -gt 0)
                    {
                        LogInfo ("Current CName records for {0}:" -f @($fs1Alias)) 3
                        $cnameRecords.ForEach({
                            LogInfo ("{0}" -f @($_.RecordData.HostNameAlias)) 4
                            $need2ChangeCNameRecord = $need2ChangeCNameRecord -or ($_.RecordData.HostNameAlias.TrimEnd('.') -ne $newFS1ADComputer.DNSHostName)
                        })
                    }

                    if($need2ChangeCNameRecord)
                    {
                        LogInfo ("Registering FS1 alias CNAME for {0}." -f @($newFS1ADComputer.Name)) 2
                        $newHostNameAlias = "{0}.{1}" -f @($newFS1ADComputer.Name, $adDomain.DNSRoot)

                        try
                        {
                            Add-DnsServerResourceRecordCName -Name $fs1Alias -HostNameAlias $newHostNameAlias -ZoneName $adDomain.DNSRoot -ComputerName $dc.Name -ErrorAction Stop | Out-Null
                            LogAction ("FS1AliasRegistered-{0}" -f @($newHostNameAlias))
                            $cnameRecordChanged = $false
                            LogInfo "Verifying FS1 alias was registered" 2 -NoNewLine
                            $cnameRecords = @(Get-DnsServerResourceRecord -Name $fs1Alias -ZoneName $adDomain.DNSRoot -ComputerName $dc.Name -RRType CName -ErrorAction Stop)
                            if($cnameRecords.Length -gt 0)
                            {
                                $cnameRecords.ForEach({
                                    $cnameRecordChanged = $cnameRecordChanged -or ($_.RecordData.HostNameAlias.TrimEnd('.') -eq $newFS1ADComputer.DNSHostName)
                                })
                            }

                            if($cnameRecordChanged)
                            {
                                LogInfo "Success" 1
                            }
                            else
                            {
                                LogError "Failed" 1
                                LogError ("Failed to verify FS1 alias: {0} migration to {1}.  Please confirm manually." -f @($fs1Alias, $newFS1ADComputer.DNSHostName)) 2
                            }
                        }
                        catch
                        {
                            LogWarning ("Failed to move {0} CNAME record to {1}.  DNS CNAME records not updated." -f @($fs1Alias, $newHostNameAlias)) 3
                        }
                    }
                    else
                    {
                        LogInfo "CName record is already set correctly." 2
                    }
                }
                else
                {
                    LogError "Unable to determine FS alias name.  Please update manually." 1
                }
            }
            else
            {
                LogWarning ("Failed to determine FS1 alias from {0} service principal names.  DNS CNAME records not updated." -f @($newFS1ADComputer.Name)) 3
                LogWarning "Current service principal names: (Is the FS1 alias missing?)" 4
                $newFS1ADComputer.servicePrincipalName.ForEach({
                    LogWarning ("{0}" -f @($_)) 5
                })
            }
        }
        else
        {
            LogWarning "Failed to acquire a AD domain data.  DNS CNAME records not updated." 3
        }
    }
    catch
    {
        LogWarning "Failed to acquire a AD domain data.  DNS CNAME records not updated." 3
    }

    return $good2Go
}

function GetADComputer
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $computerName,

        [Parameter(Mandatory=$false, Position=1)]
        [Microsoft.ActiveDirectory.Management.ADDomainController]
        $dc = $null
    )

    $adComputer = $null

    # Use a hash table for parameters to Get-ADComputer so I can optionally add the -Server parameter if a domain controller was located.
    $getADComputerParams = @{
        Identity = $computerName
        Properties = @("servicePrincipalName")
        ErrorAction = [System.Management.Automation.ActionPreference]::Stop
    }
    if($null -ne $domainController)
    {
        $getADComputerParams.Add("Server", $domainController.Name)
    }

    try
    {
        $adComputer = Get-ADComputer @getADComputerParams
    }
    catch
    {
        LogException ("Failed to acquire AD computer object for: {0}" -f @($computerName)) 2
    }

    return $adComputer
}

<#
    UpdateServicePrincipalNames

        Move FS1 service principal names from the source CIFS server's AD computer object to the destination CIFS server's AD computer object
        Register CName record for FS1 alias for the destination CIFS Server
#>
function UpdateServicePrincipalNames
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $SourceCIFSServerName,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $DRCIFSServerName
    )

    $good2Go = $true

    LogInfo ("Transferring 'FS' service principal names from: {0} to {1}..." -f @($SourceCIFSServerName, $DRCIFSServerName)) 2

    $domainController = $null
    LogInfo "Acquiring domain controller..." 3
    try
    {
        $domainController = Get-ADDomainController -ErrorAction Stop
        LogInfo ("Got: {0}" -f @($domainController.HostName)) 4
    }
    catch
    {
        LogWarning "Exception: Failed to acquire a domain controller.  AD computer object updates will not be verified." 4
    }

    LogInfo ("Getting computer object for {0} from AD." -f @($SourceCIFSServerName)) 3
    $sourceCIFSServerADComputer = GetADComputer -computerName $SourceCIFSServerName -dc $domainController

    if($null -ne $sourceCIFSServerADComputer)
    {
        LogInfo ("Received: {0}" -f @($sourceCIFSServerADComputer.DistinguishedName)) 4

        LogInfo ("Getting computer object for {0} from AD." -f @($DRCIFSServerName)) 3
        $destCIFSServerADComputer = GetADComputer -computerName $DRCIFSServerName -dc $domainController

        if($null -ne $destCIFSServerADComputer)
        {
            LogInfo ("Received: {0}" -f @($destCIFSServerADComputer.DistinguishedName)) 4

            # Capture the service principal names which need to be removed from the source AD computer object and added to the
            #    destination computer object
            $spnsToMove = @($sourceCIFSServerADComputer.servicePrincipalName | Where-Object { $_ -notmatch $sourceCIFSServerADComputer.Name })
            $srcCompChanged = $destCompChanged = $false
            if($spnsToMove.Length -gt 0)
            {
                LogInfo "Processing the following service principal names:" 3
                $spnsToMove.ForEach({
                    LogInfo ("{0}:" -f @($_)) 4
                    if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogInfo ("-{0}" -f @($sourceCIFSServerADComputer.Name)) 5
                        $sourceCIFSServerADComputer.servicePrincipalName.Remove($_) | Out-Null
                        $srcCompChanged = $true
                    }

                    if(-not $destCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogInfo ("+{0}" -f @($destCIFSServerADComputer.Name)) 5
                        $destCIFSServerADComputer.servicePrincipalName.Add($_) | Out-Null
                        $destCompChanged = $true
                    }

                    if($sourceCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogError ("Failed to remove {0} from {1} computer object." -f @($_, $sourceCIFSServerADComputer.Name)) 4
                        $good2Go = $false
                    }

                    if(-not $destCIFSServerADComputer.servicePrincipalName.Contains($_))
                    {
                        LogError ("Failed to add {0} to {1} computer object." -f @($_, $destCIFSServerADComputer.Name)) 4
                        $good2Go = $false
                    }

                    if(-not $good2Go)
                    {
                        break
                    }
                })

                if($good2Go)
                {
                    if($srcCompChanged)
                    {
                        LogInfo "Pushing the following changes to AD:" 3
                        LogInfo ("{0}:" -f @($sourceCIFSServerADComputer.DistinguishedName)) 4
                        $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                            LogInfo $_ 5
                        })

                        # Send the change to AD...
                        $good2Go = UpdateServicePrincipalName -adComp $sourceCIFSServerADComputer -dc $domainController
                    }
                    else
                    {
                        LogInfo ("No changes required for {0}" -f @($sourceCIFSServerADComputer.DistinguishedName)) 3
                    }

                    if($destCompChanged)
                    {
                        LogInfo ("{0}:" -f @($destCIFSServerADComputer.DistinguishedName)) 4
                        $destCIFSServerADComputer.servicePrincipalName.ForEach({
                            LogInfo $_ 5
                        })

                        # Send the change to AD...
                        $good2Go = UpdateServicePrincipalName -adComp $destCIFSServerADComputer -dc $domainController
                    }
                    else
                    {
                        LogInfo ("No changes required for {0}" -f @($destCIFSServerADComputer.DistinguishedName))
                    }

                    if($good2Go)
                    {
                        if($null -ne $domainController)
                        {
                            $good2Go = SetFS1CName -newFS1ADComputer $destCIFSServerADComputer -dc $domainController
                        }
                        else
                        {
                            LogWarning "'FS1' CNAME record(s) not updated.  Please update manually." 3
                        }
                    }
                    else
                    {
                        # Nothing error was already displayed
                    }
                }
            }
            else
            {
                LogWarning ("{0}'s AD computer object's service principal name list does not appear to have any 'FS1' entries!" -f @($SourceCIFSServerName)) 2
                $sourceCIFSServerADComputer.servicePrincipalName.ForEach({
                    LogWarning $_ 3
                })
                LogWarning "Service principal names and FS1 alias not updated!" 2
            }
        }
        else
        {
            LogError ("Failed to acquire AD computer object for: {0}" -f @($DRCIFSServerName)) 2
            $good2Go = $false
        }
    }
    else
    {
        LogException ("Failed to acquire AD computer object for: {0}" -f @($SourceCIFSServerName)) 2
        $good2Go = $false
    }

    return $good2Go
}

<#
    UpdateCIFSServers

        if source CIFS server found on the source VServer:
            Stop the source CIFS server
            if destination CIFS server found
                Start the destination CIFS server
                Move FS1 service principal names from the source CIFS server's AD computer object to the destination CIFS server's AD computer object
                Register CName record for FS1 alias for the destination CIFS Server
#>
function UpdateCIFSServers
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes[]]
        $SMSrcVols,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo[]]
        $AllSrcVolsSMs,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName
    )

    # Complex return information, so let's just use an object.
    $retval = "" | Select-Object good2Go, sourceCIFSServer, sourceCIFSSharesWithSnapmirrorDestinations, destinationCIFSServer
    $retval.good2Go = $true

    if($SMSrcVols.Length -gt 0)
    {
        LogInfo ("Getting source CIFS shares hosted on snapmirror source volumes from: {0}:{1}" -f @($SMSrcVols[0].NCController.Name, $SMSrcVols[0].Vserver))
        # Get all CIFS shares hosted on snapmirrored source volumes
        $retval.sourceCIFSSharesWithSnapmirrorDestinations = @(Get-NcCifsShare -Controller $SMSrcVols[0].NCController -VserverContext $SMSrcVols[0].Vserver -ErrorAction Stop | Where-Object { $v = $_; @($SMSrcVols | Select-Object -Unique -ExpandProperty Name) -contains $v.Volume })
        if($retval.sourceCIFSSharesWithSnapmirrorDestinations.Length -gt 0)
        {
            LogInfo ("{0} CIFS shares were located on these volumes." -f @($retval.sourceCIFSSharesWithSnapmirrorDestinations.Length)) 1
            $sourceCIFSSharesWithSnapmirrorDestinations.Foreach({
                LogInfo ("{0} -> {1}" -f @($_.ShareName, $_.Volume)) 2
            })

            # Get the CIFS server for the source VServer
            try
            {
                LogInfo ("Getting source CIFS server on {0}:{1}." -f @($retval.sourceCIFSSharesWithSnapmirrorDestinations[0].NcController, $retval.sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                $retval.sourceCIFSServer = Get-NcCifsServer -Controller $retval.sourceCIFSSharesWithSnapmirrorDestinations[0].NcController -VserverContext $retval.sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver -ErrorAction Stop

                if($null -ne $retval.sourceCIFSServer)
                {
                    LogInfo ("Found source CIFS server: {0} status: {1}" -f @($retval.sourceCIFSServer.CifsServer, $retval.sourceCIFSServer.AdministrativeStatus)) 2

                    if($retval.sourceCIFSServer.AdministrativeStatus -ne "down")
                    {
                        # Stop the CIFS Server

                        <# Step 1: Stop CIFS services on the source VServer.  This is to ensure the snapmirror update process send all the latest changes to the destination volume.
                            #Stop SMB service at current source
                            vserver cifs stop -vserver LAB-SMB02
                        #>
                        $retval.good2Go = ShutdownCIFSServer -cifsServer $retval.sourceCIFSServer -ReturnValue
                    }
                    else
                    {
                        # Nothing, CIFS server is already down.
                    }
                }
                else
                {
                    LogWarning ("No CIFS server located for: {0}:{1}.  No CIFS, service principal name or FS1 alias modifications will be done." -f @($retval.sourceCIFSSharesWithSnapmirrorDestinations[0].NcController.Name, $retval.sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                }

                if($retval.good2Go -and ($null -ne $retval.sourceCIFSServer))
                {
                    $drDestinationControllers = @($AllSrcVolsSMs | Where-Object { $_.Vserver -eq $DRVServerName } | Select-Object -Unique -ExpandProperty NCController)

                    if($drDestinationControllers.Length -eq 1)
                    {
                        LogInfo ("Getting destination CIFS server on {0}:{1}." -f @($drDestinationControllers[0].Name, $DRVServerName)) 1
                        $retval.destinationCIFSServer = Get-NcCifsServer -Controller $drDestinationControllers[0] -VserverContext $DRVServerName -ErrorAction Stop

                        if($null -ne $retval.destinationCIFSServer)
                        {
                            LogInfo ("Found destination CIFS server: {0} status: {1}" -f @($retval.destinationCIFSServer.CifsServer, $retval.destinationCIFSServer.AdministrativeStatus)) 2

                            # If the destination VServer's CIFS server is not running, then start it.
                            if($retval.destinationCIFSServer.AdministrativeStatus -ne "up")
                            {
                                # Start the destination CIFS Server
                                StartCIFSServer -cifsServer $retval.destinationCIFSServer
                            }
                            else
                            {
                                # Nothing, CIFS Server is already up.
                            }
                        }
                        else
                        {
                            LogError ("Failed to retrieve destination CIFS server for: {0}:{1}." -f @($drDestinationControllers[0].Name, $DRVServerName)) 1
                            $retval.good2Go = $false
                        }
                    }
                    elseif($drDestinationControllers.Length -eq 0)
                    {
                        LogWarning ("No snapmirror destination controller found having a Vserver named: {0}" -f @($DRVServerName))
                        $retval.good2Go = $false
                    }
                    else # $drDestinationControllers.Length -gt 1
                    {
                        LogWarning ("Multiple snapmirror destination controllers found having a Vserver named: {0}" -f @($DRVServerName))
                        $drDestinationControllers.ForEach({
                            LogError ("{0}" -f @($_.Name))
                        })
                        $retval.good2Go = $false
                    }

                    if($good2Go)
                    {
                        if(($null -ne $retval.sourceCIFSServer) -and ($null -ne $retval.destinationCIFSServer))
                        {
                            <# Step 6: Update service principal names and FS1 aliases...
                                #Migrate SPN's to new source AD object
                                #Update FS1 CNAME record in DNS
                            #>
                            $good2Go = UpdateServicePrincipalNames -SourceCIFSServerName $retval.sourceCIFSServer.CifsServer -DRCIFSServerName $retval.destinationCIFSServer.CifsServer
                        }
                        else
                        {
                            # Nothing, warnings were already displayed
                        }
                    }
                    else
                    {
                        # Nothing
                    }
                }
                else
                {
                    # Nothing, already displayed a message
                }
            }
            catch
            {
                LogException ("Failed to retrieve CIFS server for: {0}:{1}." -f @($retval.sourceCIFSSharesWithSnapmirrorDestinations[0].NcController.Name, $retval.sourceCIFSSharesWithSnapmirrorDestinations[0].Vserver)) 1
                $retval.good2Go = $false
            }
        }
        else
        {
            LogWarning "No CIFS shares located.  No CIFS, service principal name or FS1 alias modifications will be made." 1
        }

        if(-not $retval.good2Go)
        {
            $retval.sourceCIFSSharesWithSnapmirrorDestinations = $null
            $retval.sourceCIFSServer = $null
            $retval.destinationCIFSServer = $null
        }
    }
    else
    {
        LogWarning "No snapmirror source volumes sent to UpdateCIFSServers."
    }

    return $retval
}

function GetSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$false, Position=1)]
        [Switch]
        $NoOutput
    )

    $mySnapMirror = $null
    $good2Go = $true    # Set to false if an error occurs.

    if(-not $NoOutput)
    {
        LogInfo ("Refreshing snapmirror data for {0}:{1} ==> {2}:{3}:{4}..." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume))
    }

    try
    {
        $mySnapMirror = Get-NcSnapmirror -Controller $snapmirror.NcController -VserverContext $snapmirror.Vserver -SourceVserver $snapmirror.SourceVserver -SourceVolume $snapmirror.SourceVolume -ErrorAction Stop
        if($null -ne $mySnapMirror)
        {
            # Nothing.
        }
        else
        {
            LogError ("Failed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}.  (`$null returned)" -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) -NewLine
            $good2Go = $false
        }
    }
    catch
    {
        LogException ("Failed to refresh snapmirror data for {0}:{1} ==> {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) -NewLine
        $good2Go = $false
    }

    if(-not $good2Go)
    {
        $mySnapMirror = $null
    }

    return @($good2Go, $mySnapMirror)
}

function WaitForSnapmirrorStatusAndState
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNullOrEmpty()]
        [String]
        $status2WaitFor,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $mirrorState2WaitFor,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FailureMsg
    )

    $good2Go = $true

    # Now, wait until the snapmirror is $status2WaitFor...
    LogInfo ("Waiting for snapmirror to be {0}/{1} (CTRL-C to abort script)." -f @($status2WaitFor, $mirrorState2WaitFor, $simulatedMsg)) 2 -NoNewLine

    do
    {
        try
        {
            # Refresh the snapmirror info to see if its idle...
            $good2Go, $snapmirror = GetSnapmirror -snapmirror $snapmirror -NoOutput
            if($good2Go)
            {
                if($null -ne $snapmirror)
                {
                    if((-not $Simulated) -and (($snapmirror.Status -ne $status2WaitFor) -or ($snapmirror.MirrorState -ne $mirrorState2WaitFor)))
                    {
                        LogInfo "." -NoNewLine
                        # Pause a moment for station identification...
                        Start-Sleep -Seconds 5
                    }
                    else
                    {
                        # Nothing, snapmirror is good to go...
                    }
                }
                else
                {
                    LogError $FailureMsg 2 -NewLine
                    $good2Go = $false
                }
            }
            else
            {
                # Nothing, already displayed a messaage
            }
        }
        catch
        {
            LogException $FailureMsg 2 -NewLine
            $good2Go = $false
        }
    } until($Simulated -or (-not $good2Go) -or (($snapmirror.Status -eq $status2WaitFor) -and ($snapmirror.MirrorState -eq $mirrorState2WaitFor)))
    LogInfo ""

    return $good2Go
}

function IsSnapmirrorReady
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror,

        [Parameter(Mandatory=$false, Position=1)]
        [System.String]
        $desiredMirrorState = "snapmirrored",

        [Parameter(Mandatory=$false, Position=2)]
        [System.String]
        $desiredStatus = "idle"
    )

    $good2Go, $mySnapMirror = GetSnapmirror -snapmirror $snapmirror

    # Assume the snapmirror is not ready until we determine it is...
    $snapmirrorReady = $false

    if($good2Go)
    {
        # Make sure the snapmirror is in the desired state
        if($mySnapMirror.MirrorState -eq $desiredMirrorState)
        {
            # Further, make sure the snapmirror status is $desiredStatus
            if($mySnapMirror.Status -eq $desiredStatus)
            {
                $snapmirrorReady = $true
            }
            else
            {
                LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} has status {5}.  Expected: {6}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $mySnapMirror.MirrorState, $desiredStatus)) 1
            }
        }
        else
        {
            LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} has mirror state {5}.  Expected: {6}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $mySnapMirror.MirrorState, $desiredMirrorState)) 1
        }
    }
    else
    {
        # Nothing, already displayed a message
    }

    return @($good2Go, $snapmirrorReady)
}

<#
    UpdateSnapmirror

        For most actions, I first try to determine if the action needs to be completed.  However, for UpdateSnapmirror, this is both cumbersome and not necessary.
            Cumbersome because I'd have to make a decision based on the lag time -- how would that tell me if a volume was or wasn't updated just after the last sync??
            Not necessary because there is no harm in simply syncing the destination again... so this is what I do.
#>
function UpdateSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    # Refresh the information we have for the snapmirror...
    $good2Go, $mySnapMirror = GetSnapmirror -snapmirror $snapmirror
    if($good2Go)  # $good2Go implies $mySnapMirror was set...
    {
        if($mySnapMirror.MirrorState -eq "snapmirrored")
        {
            if($mySnapMirror.Status -ne "idle")
            {
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg ("Failed to retrieve snapmirror status before invoking an update between: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))
            }
            else
            {
                # Nothing, snapmirror is already "snapmirrored/idle"
            }

            if($good2Go)
            {
                LogInfo ("Updating snapmirror {0}:{1}:{2}.{3}" -f @($mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $simulatedMsg)) 2
                if(-not $Simulated)
                {
                    $null = Invoke-NcSnapmirrorUpdate -Controller $mySnapMirror.NcController -DestinationVserver $mySnapMirror.Vserver -DestinationVolume $mySnapMirror.DestinationVolume -ErrorAction Stop
                }

                # Now, wait until the snapmirror is snapmirrored/idle...
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg ("Failed to retrieve snapmirror status after invoking an update between: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))

                if($good2Go)
                {
                    LogAction ("SnapmirrorUpdated-{0}" -f @($snapmirror.RelationshipId))
                }
                else
                {
                    # Nothing, no action taken -- err no action applied.
                }
            }
            else
            {
                # Nothing, already displayed a message
            }
        }
        elseif($mySnapMirror.MirrorState -eq "broken-off")
        {
            LogInfo ("Snapmirror between {0}:{1} and {2}:{3}:{4} is already broken-off." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume)) 1
        }
    }
    else
    {
        # Nothing, a message was already displayed
    }

    return $good2Go
}

function BreakSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    # Refresh the information we have for the snapmirror...
    $good2Go, $mySnapMirror = GetSnapmirror -snapmirror $snapmirror
    if($good2Go)  # $good2Go implies $mySnapMirror was set...
    {
        if($mySnapMirror.MirrorState -eq "snapmirrored")
        {
            if($mySnapMirror.Status -ne "idle")
            {
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg ("Failed to retrieve snapmirror status before invoking an update between: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))
            }
            else
            {
                # Nothing, snapmirror is already "snapmirrored/idle"
            }

            if($good2Go)
            {
                LogInfo ("Breaking snapmirror {0}:{1}:{2}.{3}" -f @($mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $simulatedMsg)) 2
                if(-not $Simulated)
                {
                    $null = Invoke-NcSnapmirrorBreak -Controller $mySnapMirror.NcController -DestinationVserver $mySnapMirror.Vserver -DestinationVolume $mySnapMirror.DestinationVolume -Confirm:$false -ErrorAction Stop
                }

                # Now, wait until the snapmirror is broken-off/idle...
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "broken-off" -FailureMsg ("Failed to retrieve snapmirror status after invoking snapmirror break between: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))

                if($good2Go)
                {
                    LogAction ("SnapmirrorBroken-{0}" -f @($snapmirror.RelationshipId))
                }
                else
                {
                    # Nothing, no action taken -- err no action applied.
                }
            }
            else
            {
                # Nothing, already displayed a message
            }
        }
        elseif($mySnapMirror.MirrorState -eq "broken-off")
        {
            LogInfo ("Snapmirror between {0}:{1} and {2}:{3}:{4} is already broken-off." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume)) 1
        }
    }
    else
    {
        # Nothing, a message was already displayed
    }

    return $good2Go
}

<#
    $snapmirror is expected to be broken-off/idle when calling RemoveSnapmirror.  If it is not, then the function waits for it to become broken-off/idle.

HERE

#>
function RemoveSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    # Refresh the information we have for the snapmirror...
    $good2Go, $mySnapMirror = GetSnapmirror -snapmirror $snapmirror
    if($good2Go)  # $good2Go implies $mySnapMirror was set...
    {
        if($mySnapMirror.MirrorState -eq "broken-off")
        {
            if($mySnapMirror.Status -ne "idle")
            {
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "broken-off" -FailureMsg ("Failed to retrieve snapmirror status before removing snapmirror: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))
            }
            else
            {
                # Nothing, snapmirror is already "broken-off/idle" -- don't need to wait for a status/state
            }

            if($good2Go)
            {
                LogInfo ("Removing snapmirror for: {0}:{1}:{2}.{3}" -f @($mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $simulatedMsg)) 2
                if(-not $Simulated)
                {
                    $null = Invoke-NcSnapmirrorBreak -Controller $mySnapMirror.NcController -DestinationVserver $mySnapMirror.Vserver -DestinationVolume $mySnapMirror.DestinationVolume -Confirm:$false -ErrorAction Stop
                }

                # Now, wait until the snapmirror is broken-off/idle...
                $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $mySnapMirror -status2WaitFor "idle" -mirrorState2WaitFor "broken-off" -FailureMsg ("Failed to retrieve snapmirror status after invoking snapmirror break between: {0}:{1} and {2}:{3}:{4}." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume))

                if($good2Go)
                {
                    LogAction ("SnapmirrorBroken-{0}" -f @($snapmirror.RelationshipId))
                }
                else
                {
                    # Nothing, no action taken -- err no action applied.
                }
            }
            else
            {
                # Nothing, already displayed a message
            }
        }
        elseif($mySnapMirror.MirrorState -eq "broken-off")
        {
            LogInfo ("Snapmirror between {0}:{1} and {2}:{3}:{4} is already broken-off." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume)) 1
        }
        else
        {
            LogWarning ("Snapmirror between {0}:{1} and {2}:{3}:{4} has mirror state: {5} which is unexpected.." -f @($mySnapMirror.SourceVserver, $mySnapMirror.SourceVolume, $mySnapMirror.NcController.Name, $mySnapMirror.Vserver, $mySnapMirror.DestinationVolume, $mySnapMirror.MirrorState)) 1
        }
    }
    else
    {
        # Nothing, a message was already displayed
    }

    return $good2Go
}

function DeleteSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    $good2Go = WaitForSnapmirrorStatusAndState -snapmirror $snapmirror -status2WaitFor "idle" -mirrorState2WaitFor "snapmirrored" -FailureMsg

    LogInfo ("Refreshing snapmirror information for {0} --> {1}." -f @($snapmirror.SourceLocation, $snapmirror.DestinationLocation))
    try
    {
        $mySnpMir = Get-NcSnapmirror -Controller $snapmirror.NcController -DestinationLocation $snapmirror.DestinationLocation -SourceLocation $snapmirror.SourceLocation -ErrorAction Stop
        if($null -ne $mySnpMir)
        {

        }
        else
        {
            LogWarning ("Failed to refresh snapmirror information for {0} --> {1}." -f @($snapmirror.SourceLocation, $snapmirror.DestinationLocation))
            LogWarning "Possibly already deleted?"
        }
    }
    catch
    {
        LogException ("Failed to refresh snapmirror information for {0} --> {1}." -f @($snapmirror.SourceLocation, $snapmirror.DestinationLocation))
    }
    <#

       HERE -- need to re-tool this function...

    #>
    $good2Go = $true
    $snapmirrorReady = $true

    $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus "idle"

    if($snapmirrorReady)
    {
        try
        {
            LogInfo ("Removing snapmirror {0}:{1}:{2}.{3}" -f @($snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume, $simulatedMsg)) 2
            if(-not $Simulated)
            {
                Remove-NcSnapmirror -Controller $snapmirror.NcController -DestinationVolume $snapmirror.DestinationVolume -DestinationVserver $snapmirror.DestinationVserver -Confirm:$false -ErrorAction Stop | Out-Null
                # After a snapmirror destination is removed, Get-NCSnapmirror will return $null...
                #   So, if we try to refresh the snapmirror object, and get $null back, we know the snapmirror has been removed.
                #     Food for thought... then how did we ever get the DeleteSnapmirror if $snapmirror was removed??  Think about this in terms of re-running the script after an error...
            }

            <#
                NOTE: Can I confirm the snapmirror was removed?

                $sm = Get-NCSnapmirror  ... if this returns null, then the snapmirror was removed???
            #>

            if($good2Go)
            {
                LogAction ("SnapmirrorRemoved-{0}" -f @($snapmirror.RelationshipId))
            }
        }
        catch
        {
            LogException ("Failed to remove snapmirror relationship between: {0}:{1} and {2}:{3}:{4}." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
            $good2Go = $false
        }
    }
    else
    {
        LogError ("Snapmirror between {0}:{1} and {2}:{3}:{4} is not idle/snapmirrored." -f @($snapmirror.SourceVserver, $snapmirror.SourceVolume, $snapmirror.NcController.Name, $snapmirror.Vserver, $snapmirror.DestinationVolume)) 2
    }

    return $good2Go
}

function ReleaseSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo]
        $snapmirror
    )

    # First, verify the snapmirror relationship is still intact.
    try
    {
        # Create a query template so we can use the unique relationship ID to get the snapmirror destinations.
        $queryObj = Get-NcSnapmirrorDestination -Controller $sourceVolume.NcController -Template
        if($null -ne $queryObj)
        {
            $queryObj.RelationshipId = $snapmirror.RelationshipId

            try
            {
                # Send the query to ONTAP to get the snapmirror destinations for $sourceVolume
                $snapmirrorDestination = Get-NcSnapmirrorDestination -Controller $sourceVolume.NcController -Query $queryObj -ErrorAction Stop

                # Is there still a matching snapmirror relationship?
                if($null -ne $snapmirrorDestination)
                {
                    # Yes

                    # Release the snapmirror relationship ...
                    LogInfo ("Releasing snapmirror {0} -> {1} relationship ID: {2}.{3}" -f @($snapmirrorDestination.SourceLocation, $snapmirrorDestination.DestinationLocation, $snapmirrorDestination.RelationshipId, $simulatedMsg)) 1
                    if(-not $Simulated)
                    {
                        Invoke-NcSnapmirrorRelease -Controller $snapmirrorDestination.NcController -SourceVserver $snapmirrorDestination.SourceVServer -SourceVolume $snapmirrorDestination.SourceVolume -DestinationVolume $snapmirrorDestination.DestinationVolume -DestinationVserver $snapmirrorDestination.DestinationVserver -RelationshipId $snapmirrorDestination.RelationshipId -Confirm:$false -ErrorAction Stop | Out-Null
                        LogAction ("SnapmirrorRelationshipReleased-{0}" -f @($snapmirror.RelationshipId))

                        # Now refresh the snapmirror destination information  to see if the relationship was released...
                        LogInfo ("Refreshing snapmirror destination information for {0} -> {1}.." -f @($snapmirrorDestination.SourceLocation, $snapmirrorDestination.DestinationLocation)) 1 -NoNewLine
                        $tries = 0
                        $released = $false
                        do
                        {
                            $tries++
                            try
                            {
                                $snapmirrorDestination = Get-NcSnapmirrorDestination -Controller $sourceVolume.NcController -Query $queryObj -ErrorAction Stop
                                $released = $null -ne $snapmirrorDestination
                            }
                            catch
                            {
                                # Nothing, we'll handle the error below...
                            }

                            if((-not $released) -and ($tries -lt 3))
                            {
                                LogInfo "." -NoNewLine
                                Start-Sleep -Seconds 5
                            }
                            else
                            {
                                LogInfo ""    # Just to a CR-LF
                            }
                        } while ((-not $refreshed) -and ($tries -lt 3))

                        if(-not $released)
                        {
                            LogWarning ("Failed to verify snapmirror relationship was released for: {0} -> {1}.." -f @($snapmirrorDestination.SourceLocation, $snapmirrorDestination.DestinationLocation)) 1
                            LogWarning ("Please manually verify the snapmirror relationship was released.")
                        }
                    }
                }
                else
                {
                    # No
                    Logwarning ("Snapmirror relationshop for {0} --> {1} does not exist.  Already released?" -f @($snapmirror.SourceLocation, $snapmirror.DestinationLocation))
                }
            }
            catch
            {
                LogException ("Failed to get snapmirror destination for {0} --> {1}" -f @($snapmirror.SourceLocation, $snapmirror.DestinationLocation))
            }
        }
        else
        {
            LogError "Failed to create snapmirror destination query object."
        }
    }
    catch
    {
        LogException "Failed to create snapmirror destination query object."
    }
}

function CreateSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $dstVolume,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNullOrEmpty()]
        [String]
        $snapmirrorPolicyName
    )

    $good2Go = $false

    LogInfo ("Verifying existance of snapmirror policy {0} on {1}" -f @($snapmirrorPolicyName, $dstVolume.NcController.Name)) 2
    try
    {
        $snapmirrorPolicies = @(Get-NcSnapmirrorPolicy -Controller $dstVolume.NcController -Name $snapmirrorPolicyName -ErrorAction Stop)
        if($snapmirrorPolicies.Length -gt 0)
        {
            try
            {
                LogInfo ("Creating snapmirror source: {0}:{1}:{2} destination: {3}:{4}:{5}.{6}" -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name, $simulatedMsg)) 2
                if(-not $Simulated)
                {
                    <#  NOTE new mirror is broken-off! #>
                    $newSnapmirror = New-NcSnapmirror -DestinationVolume $dstVolume.Name -DestinationVserver $dstVolume.VServer -SourceVolume $srcVolume.Name -SourceVserver $srcVolume.VServer -Controller $dstVolume.NCController -Policy $snapmirrorPolicyName -ErrorAction Stop
                }

                $good2Go = $Simulated -or ($null -ne $newSnapmirror)
            }
            catch
            {
                LogException ("Failed to create snapmirror source: {0}:{1}:{2} destination: {3}:{4}:{5}." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
            }
        }
        else
        {
            LogError ("Failed to acquire snapmirror policy {0} from {1}." -f @($snapmirrorPolicyName, $dstVolume.NcController.Name))
        }
    }
    catch
    {
        LogException ("Failed to acquire snapmirror policy {0} from {1}." -f @($snapmirrorPolicyName, $dstVolume.NcController.Name)) 2
    }

    return $good2Go
}

function ResyncSnapmirror
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $srcVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $dstVolume
    )

    $good2Go = $false
    $snapmirrorReady = $true
    # $good2Go, $snapmirrorReady = IsSnapmirrorReady -snapmirror $snapmirror -desiredMirrorState "broken-off" -desiredStatus = "idle"

    if($snapmirrorReady)
    {
        try
        {
            LogInfo ("Resyncing snapmirror {0}:{1}:{2} -> {3}:{4}:{5}.{6}" -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name, $simulatedMsg)) 2
            if(-not $Simulated)
            {
                <# NOTE:  Need to disable ransomware stuff on the destination volume. #>
                $result = Invoke-NcSnapmirrorResync -Controller $dstVolume.NcController -DestinationVserver $dstVolume.Vserver -DestinationVolume $dstVolume.Name -ErrorAction Stop

                <#
                    NcController      : LAB-NTAP01
                    ResultOperationId : 30fc8f26-d10e-11ee-9cb9-d039ea238501
                    ErrorCode         :
                    ErrorMessage      :
                    JobId             :
                    JobVserver        :
                    Status            : succeeded
                #>
            }

            $good2Go = $Simulated -or (($null -ne $result) -and ($result.Status -eq "succeeded"))
        }
        catch
        {
            LogException ("Failed to resync snapmirror {0}:{1}:{2} -> {3}:{4}:{5}." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
        }
    }
    else
    {
        LogError ("Snapmirror between {0}:{1}:{2} and {3}:{4}:{5} is not idle/snapmirrored." -f @($srcVolume.NcController.Name, $srcVolume.Vserver, $srcVolume.Name, $dstVolume.NcController.Name, $dstVolume.Vserver, $dstVolume.Name)) 2
    }

    return $good2Go
}

function UpdateSnapshotPolicy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $destinationVolume
    )

    $good2Go = $true
    <# Step 4 make sure the snapshot policy is correct on the destination volume.
        #Update snapshot policy on new source
        # NOTE: EDC snapshot policies are pre-pended with clst_  Check this.
        vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
    #>

    LogInfo "Updating snapshot policy..." 2
    # Is there a snapshot policy set on the source volume?
    $sourceVolumeSnapshotPolicyName = $sourceVolume.VolumeSnapshotAttributes.SnapshotPolicy
    if(-not [String]::IsNullOrEmpty($sourceVolumeSnapshotPolicyName))
    {
        # Is the source volume hosted in an EDC?
        if($sourceVolumeSnapshotPolicyName -match "^clst_(.*)$")
        {
            LogInfo "Detected EDC snapshot policy..." 3
            # Yes...remove clst_ from the front of the policy name...
            $sourceVolumeSnapshotPolicyName = $Matches[1]
        }
        else
        {
            # Nothing, leave the policy name as it is.
        }

        # Is the snapshot policy on the destination volume "different" than the policy on the source?
        if($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy -notmatch ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))
        {
            # Yes, different policy...
            LogInfo ("Snapshot policies are different...") 3
            LogInfo ("Source volume snapshot policy: {0}" -f @($sourceVolumeSnapshotPolicyName)) 4
            LogInfo ("Destination volume snapshot policy: {0}" -f @($destinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 4

            LogInfo "Getting snapshot policies that match the source from the destination cluster" 3
            # Get any snapshot policy from the destination cluster with a name that matches the source volume's snapshot policy name...
            $destinationSnapshotPolicies = @(Get-NcSnapshotPolicy -Controller $destinationVolume.NcController -ErrorAction Stop | Where-Object { $_.Policy -match $sourceVolumeSnapshotPolicyName })

            # Did we find a single match?
            if($destinationSnapshotPolicies.Length -eq 1)
            {
                # Yes, use it for the snapshot policy on the destination volume.
                $destinationSnapshotPolicyName = $destinationSnapshotPolicies[0].Policy
                LogInfo ("Using destination snapshot policy: {0}" -f @($destinationSnapshotPolicyName)) 4

                # Set up a query object to ensure we update the correct destination volume.
                $queryObj = Get-NCVol -Controller $destinationVolume.NcController -Template
                Initialize-NcObjectProperty -Object $queryObj -Name VolumeIdAttributes
                $queryObj.VolumeIdAttributes.Uuid = $destinationVolume.VolumeIdAttributes.Uuid

                # Set up an update query object to set the snapshot policy
                $updateObj = Get-NCVol -Controller $destinationVolume.NcController -Template
                Initialize-NcObjectProperty -Object $updateObj -Name VolumeSnapshotAttributes
                $updateObj.VolumeSnapshotAttributes.SnapshotPolicy = $destinationSnapshotPolicyName

                try
                {
                    LogInfo ("Sending volume update command to update snapshot policy...") 3
                    $result = Update-NcVol -Controller $destinationVolume.NcController -Query $queryObj -Attributes $updateObj -ErrorAction Stop
                    if($null -ne $result)
                    {
                        if($result.SuccessList.Length -gt 0)
                        {
                            LogInfo "Updated snapshot policy on:" 3
                            $result.SuccessList.Foreach({
                                LogInfo ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                            })
                        }
                        else
                        {
                            # Shouldn't have to do anything here... the next block should cover it...BUT... just to make sure, we'll set $good2Go = $false since there weren't any successes.
                            $good2Go = $false
                        }

                        if($result.FailureList.Length -gt 0)
                        {
                            LogError "Failed to update snapshot policy on:" 3
                            $result.FailureList.Foreach({
                                LogError ("{0}:{1}:{2}" -f @($_.VolumeKey.VolumeAttributes.NcController.Name, $_.VolumeKey.VolumeAttributes.VServer, $_.VolumeKey.VolumeAttributes.Name)) 4
                            })
                            $good2Go = $false
                        }
                        else
                        {
                            # Nothing... all might be good depending on the SuccessList.
                        }
                    }
                    else
                    {
                        LogWarning "No result object returned when updating snaphot policy." 3
                    }
                }
                catch
                {
                    LogException ("Failed to set snapshot policy to {0} on {0}:{1}:{2}." -f @($destinationSnapshotPolicyName, $snapmirrorDestinationVolume.NcController.Name, $snapmirrorDestinationVolume.VServer, $snapmirrorDestinationVolume.Name)) 3
                    $good2Go = $false
                }
            }
            elseif ($destinationSnapshotPolicies.Length -gt 1)
            {
                LogWarning ("{0} snapshot policies found which match: {1}." -f @($destinationSnapshotPolicies.Length, ("{0}`$" -f @($sourceVolumeSnapshotPolicyName)))) 3
                $destinationSnapshotPolicies.ForEach({
                    LogWarning ("{0}" -f @($_)) 4
                })
            }
            else  # there was no matching snapshot policy found on the destination
            {
                LogError ("No snapshot policies found which match: {0} on {1}." -f @(("{0}`$" -f @($sourceVolumeSnapshotPolicyName)), $snapmirrorDestinationVolume.NcController.Name)) 3
            }
        }
        else
        {
            LogInfo ("Source volume snapshot policy: {0} seems to match {1}.  No changes needed." -f @($sourceVolumeSnapshotPolicyName, $snapmirrorDestinationVolume.VolumeSnapshotAttributes.SnapshotPolicy)) 3
        }
    }
    else
    {
        LogWarning ("No snapshot policy found on source volume: {0}:{1}:{2}" -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) 2
        LogWarning "Ensure you check snapshot policies." 2
    }

    return $good2Go
}

function SetVolumeEfficiencySettings
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $volume
    )

    $good2Go = $true
    try
    {
        <# Step 5a: Update volume efficiency settings on the destination volume.
            #Enable/update storage efficiency on new source
            --> vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
        #>

        LogInfo ("Checking status of storage efficiency for: {0}:{1}:{2}..." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name)) 2
        $volSIS = Get-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop
        if($null -ne $volSIS)
        {
            if($volSIS.State -ne "enabled")
            {
                LogInfo ("Storage efficiency not enabled.  Enabling it.") 3
                try
                {
                    # Not enabled, so let's enable it...
                    $result = Enable-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop

                    try
                    {
                        LogInfo "Verifying storage efficiency was enabled..." 3 -NoNewline
                        $volSIS = Get-NcSis -Controller $volume.NcController -VserverContext $volume.VServer -Name $volume.Name -ErrorAction Stop
                        if($volSIS.State -eq "enabled")
                        {
                            LogInfo "Success"
                        }
                        else
                        {
                            LogError "Failed"
                            LogWarning "Manually update storage efficiencies as required." 3
                        }
                    }
                    catch
                    {
                        LogException ("Failed to verify if storage efficiency was enabled on: {0}:{1}:{2}.  Please check manually." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name)) -NewLine
                    }

                }
                catch
                {
                    LogException ("Failed to enable storage efficiency on: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
                    $good2Go = $false
                }
            }
            else
            {
                # Nothing, storage efficiency is already enabled for the volume.
            }

            # Need to recheck $volSIS.State since we may have enabled it above.
            if($volSIS.State -eq "enabled")
            {
                try
                {
                    <# Step 5b: Update volume efficiency settings on the destination volume.
                        #Enable/update storage efficiency on new source
                            vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                        --> vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                    #>
                    $result = Set-NcSis -Name $volume.Name -Compression $true -Controller $volume.NcController -InlineCompression $true -Policy "default" -VserverContext $volume.VServer -ErrorAction Stop
                }
                catch
                {
                    LogException ("Failed to set storage efficiency settings on: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
                    $good2Go = $false
                }
            }
            else
            {
                # Nothing, would have already alerted user.
            }
        }
        else
        {
            LogError ("Failed to get storage efficiency setting for: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
            $good2Go = $false
        }
    }
    catch
    {
        LogException ("Failed to get storage efficiency setting for: {0}:{1}:{2}.  Efficiency settings not updated." -f @($volume.NcController.Name, $volume.Vserver, $volume.Name))
        $good2Go = $false
    }
}

function FailOverVolume
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes]
        $sourceVolume,

        [Parameter(Mandatory=$true,Position=1)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Cifs.CifsShare[]]
        $sourceCIFSSharesWithSnapmirrorDestinations,

        [Parameter(Mandatory=$true,Position=2)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Snapmirror.SnapmirrorInfo[]]
        $allSourceVolumesSnapmirrors,

        [Parameter(Mandatory=$true,Position=3)]
        [ValidateNotNull()]
        [DataONTAP.C.Types.Volume.VolumeAttributes[]]
        $allNonSnaplockVolumes,

        [Parameter(Mandatory=$true,Position=4)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DRVServerName
    )

    $good2Go = $true
    LogInfo ("Processing source volume: {0}:{1}:{2}..." -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) -NewLine

    # Capture all the volumes which will be snapmirror destinations for the new source volume (The volume on $DRVServerName where $sourceVolume is snapmirrored to).
    $newSnapmirrorDestinationVolumes = [System.Collections.Generic.List[System.Object]]::new()

    # $sourceVolume will end up being a snapmirror destination to the DR volume we are bringing online.
    LogInfo ("Added original source volume: {0}:{1}:{2} to the list of new snapmirror destinations." -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) 1
    $newSnapmirrorDestinationVolumes.Add($sourceVolume)

    if($sourceCIFSSharesWithSnapmirrorDestinations.Length -gt 0)
    {
        LogInfo ("CIFS Shares hosted on {0}:{1}:{2}:" -f @($sourceVolume.NcController.Name, $sourceVolume.Vserver, $sourceVolume.Name)) 1
        $sourceCIFSSharesWithSnapmirrorDestinations | Where-Object { ($_.VServer -eq $sourceVolume.Vserver) -and ($_.Volume -eq $sourceVolume.Name) } | ForEach-Object {
            LogInfo ("\\{0}\{1}" -f @($_.CifsServer, $_.ShareName)) 2
        }
    }
    else
    {
        # Nothing, no CIFS shares to deal with...
    }

    # Get the snapmirrors for just this $sourceVolume
    $sourceVolumeSnapmirrors = @($allSourceVolumesSnapmirrors | Where-Object { ($_.SourcevServer -eq $sourceVolume.VServer) -and ($_.SourceVolume -eq $sourceVolume.Name) })
    $sourceVolumeSnapmirrors.ForEach({
        LogInfo ("{0} -> {1}" -f @($_.SourceLocation, $_.DestinationLocation)) 1
    })
    $snapmirrorIdx = 0
    while($good2Go -and ($snapmirrorIdx -lt $sourceVolumeSnapmirrors.Length))
    {
        $snapmirror = $sourceVolumeSnapmirrors[$snapmirrorIdx]
        LogInfo ("Processing snapmirror destination: {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume)) 2
        $snapmirrorDestinationVolume = $allNonSnaplockVolumes | Where-Object { ($_.NCController.Name -eq $snapmirror.NcController.Name) -and ($_.VServer -eq $snapmirror.DestinationvServer) -and ($_.Name -eq $snapmirror.DestinationVolume)}
        if($null -ne $snapmirrorDestinationVolume)
        {
            # Make sure the destination volume is not a SNAPLOCK volume is not
            if($snapmirrorDestinationVolume.VolumeSnaplockAttributes.SnaplockType -eq "non_snaplock")
            {
                # If this snapmirror destination volume is hosted on the requested DR VServer, then capture it as the new snapmirror source volume.
                if($snapmirrorDestinationVolume.Vserver -eq $DRVServerName)
                {
                    LogInfo ("{0}:{1}:{2} will become the new snapmirror source volume." -f @($snapmirrorDestinationVolume.NcController.Name, $snapmirrorDestinationVolume.Vserver, $snapmirrorDestinationVolume.Name)) 3
                    $newSnapmirrorSourceVolume = $snapmirrorDestinationVolume
                }
                else
                {
                    # Add the snapmirror destination volume to the list of new snapmirror destination volumes.... but only add it once.
                    if($newSnapmirrorDestinationVolumes.IndexOf($snapmirrorDestinationVolume) -eq -1)
                    {
                        LogInfo ("{0}:{1}:{2} added to snapmirror destination volume list." -f @($snapmirrorDestinationVolume.NcController.Name, $snapmirrorDestinationVolume.Vserver, $snapmirrorDestinationVolume.Name)) 3
                        $newSnapmirrorDestinationVolumes.Add($snapmirrorDestinationVolume)
                    }
                    else
                    {
                        # Nothing, only add the volume to the snapmirror destination list once.
                    }
                }

                <# Step 2: Update the snapmirrors...
                    #Update applicable snapmirrors
                    snapmirror update -destination-path LABDR-SMB02:*
                #>
                $good2Go = UpdateSnapmirror -snapmirror $snapmirror

                if($good2Go)
                {
                    # Step 3: Now break the snapmirror...
                    <#
                        #Break existing relationships
                        snapmirror break -destination-path LABDR-SMB02:*
                    #>
                    $good2Go = BreakSnapmirror -snapmirror $snapmirror

                    if($good2Go)
                    {
                        <# Step 4 make sure the snapshot policy is correct on the destination volume.
                            #Update snapshot policy on new source
                            # NOTE: EDC snapshot policies are pre-pended with clst_  Check this.
                            vol modify -vserver LABDR-SMB02 -snapshot-policy snp_8AM_12PM_4PM_8PM_6_Retained_Daily_12AM_180_Retained -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                        #>
                        $good2Go = UpdateSnapshotPolicy -sourceVolume $sourceVolume -destinationVolume $snapmirrorDestinationVolume

                        if($good2Go)
                        {
                            <# Step 5: Update volume efficiency settings on the destination volume.
                                #Enable/update storage efficiency on new source
                                vol efficiency on -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01
                                vol efficiency modify -vserver LABDR-SMB02 -volume SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -policy default -compression true -inline-compression true
                            #>

                            # No return value here, it's not vital if we fail to set storage efficiency.  A visual warning is enough.
                            SetVolumeEfficiencySettings -volume $snapmirrorDestinationVolume

                            if($good2Go)
                            {
                                # Step 7a: Now delete the snapmirror relationship...
                                <#
                                    #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                    --> snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                        snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                #>
                                $good2Go = DeleteSnapmirror -snapmirror $snapmirror

                                if($good2Go)
                                {
                                    # Step 7b: Now release the snapmirror relationship...
                                    <#
                                        #  These 2 lines remove the old snapmirror relationship between the original source and destination
                                            snapmirror delete -destination-path LABDR-SMB02:*   # Performed where the mirror volume lives
                                        --> snapmirror release -destination-path LABDR-SMB02:*  # Performed where the source volume lives
                                    #>
                                    ReleaseSnapmirror -sourceVolume $sourceVolume -snapmirror $snapmirror
                                }
                                else
                                {
                                    # Nothing, an error would have been displayed already.
                                }
                            }
                            else
                            {
                                # Nothing, an error would have been displayed already.
                            }
                        }
                        else
                        {
                            # Nothing, an error would have been displayed already.
                        }
                    }
                    else
                    {
                        # Nothing, an error should have already been displayed
                    }
                }
                else
                {
                    # Nothing, an error would have been displayed already.
                }
            }
            else
            {
                LogWarning ("Skipping snaplock snapmirror: {0}:{1}:{2}" -f @($snapmirrorDestinationVolume.NcController.Name, $snapmirrorDestinationVolume.Vserver, $snapmirrorDestinationVolume.Name)) 3
            }
        }
        else
        {
            LogError ("Failed to retrieve snapmirror destination volume object for {0}:{1}:{2}." -f @($snapmirror.NcController.Name, $snapmirror.DestinationvServer, $snapmirror.DestinationVolume)) 3
            $good2Go = $false
        }
        $snapmirrorIdx++
    }

    <#
        Now that:
            all snapmirrors are updated/broken/deleted/released
            destination snapshot policies are updated
            destination volume efficiencies are set

        Recreate reverse snapmirror relationships
    #>
    if($good2Go)
    {
        # Once all the snapmirrors have been sync'd and broken-off, time to rebuild them, but with a new source...
        if($null -ne $newSnapmirrorSourceVolume)
        {
            $snapmirrorIdx = 0
            while($good2Go -and ($snapmirrorIdx -lt $newSnapmirrorDestinationVolumes.Count))
            {
                # Step 8a: Now create the new snapmirror...
                <#
                    --> snapmirror create -source-path LABDR-SMB02:SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -destination-path LAB-SMB02:vol_SMB_DRTest_01 -type XDP -vserver LAB-SMB02 -throttle unlimited -policy smvp_180_nightly_01   # Performed where the mirror volume will lives.
                        snapmirror resync -destination-path -destination-path LAB-SMB02:vol_SMB_DRTest_01    # Performed where the mirror volume will lives.
                #>

                <#    NOTE:  Need to capture the snapmiror policy name... #>
                $good2Go = CreateSnapmirror -srcVolume $newSnapmirrorSourceVolume -dstVolume $newSnapmirrorDestinationVolumes[$snapmirrorIdx] -snapmirrorPolicyName $snapmirror.Policy

                if($good2Go)
                {
                    # Step 8b: Finally, resync the new new snapmirror...
                    <#
                            snapmirror create -source-path LABDR-SMB02:SMDV_vol_LAB_SMB02_vol_SMB_DRTest_01 -destination-path LAB-SMB02:vol_SMB_DRTest_01 -type XDP -vserver LAB-SMB02 -throttle unlimited -policy smvp_180_nightly_01   # Performed where the mirror volume will lives.
                        --> snapmirror resync -destination-path -destination-path LAB-SMB02:vol_SMB_DRTest_01    # Performed where the mirror volume will lives.
                    #>
                    $good2Go = ResyncSnapmirror -srcVolume $newSnapmirrorSourceVolume -dstVolume $newSnapmirrorDestinationVolumes[$snapmirrorIdx]
                }

                $snapmirrorIdx++
            }
        }
        else
        {
            LogError "Failed to identify a new snapmirror source volume." 1
            $good2Go = $false
        }
    }
    else
    {
        # Nothing, an error would have been displayed already.
    }

    return $good2Go, $destinationCIFSServer
}

$good2Go = $true

# Create a message log.
$Script:sbMessageLog = [System.Text.StringBuilder]::new()

<#

    Create an action log -- the idea here is to have a way to track if an action has already been completed so if the script is -Rerun, it knows what
        has already been completed.  When possible, the plan is to test for a condition first instead of relying on $Script:actionSteps i.e.:

    Consider stopping the CIFS server on a VServer...

    Instead of:

        if(($null -ne $Script.actionSteps) -and ($Script.actionSteps.ContainsValue($actionStepString)))
        {
            ShutdownCIFSServer
        }

    Do:

        $cifsServer = Get-NcCifsServer ....
        if($cifsServer.AdministrativeStatus -ne "down")
        {
            ShutdownCIFSServer
        }

    The second method does not rely on the actionsSteps variable....it's more "real-time" friendly.
#>
$Script:actionSteps = [System.Collections.Generic.SortedDictionary[System.String,System.String]]::new()

$simulatedMsg = " (simulated)"
if(-not $Simulated)
{
    $simulatedMsg = ""
}
else
{
    LogInfo "No changes will be made.  Running in simulation mode."
}

if(($null -eq $cDot) -or ($cdot -isnot [System.Collections.Generic.SortedDictionary[[System.String], [NetApp.Ontapi.Filer.C.NcController]]]) -or (@($cdot.Values).Length -eq 0))
{
    LogInfo "Connecting to all ONTAP clusters..."

    ConnectTo cDot
}
else
{
    # Nothing already connected to ONTAP
}

if(($null -ne $cDot) -and ($cdot -is [System.Collections.Generic.SortedDictionary[[System.String], [NetApp.Ontapi.Filer.C.NcController]]]) -and (@($cdot.Values).Length -gt 0))
{
    LogInfo "Connected to:"
    $cDot.Values.ForEach({
        LogInfo $_.Name 1
    })

    # Keep track of run status...
    $good2Go = @($cDot.Values).Length -gt 0   #If this changes to $false, the script should terminate...
    if($good2Go)
    {
        # Initialize some variables
        $destinationCIFSServer = $null
        $sourceCIFSServer = $null

        # Get all volumes hosted on all ONTAP clusters.  Seems overkill, but this way, we have all the volumes for later use.
        LogInfo "Retrieving all non-Snaplock volumes from all clusters..."
        try
        {
            $nonSnaplockVolumesQuery = Get-NCVol -Controller @($cDot.Values)[0] -Template
            Initialize-NcObjectProperty -Object $nonSnaplockVolumesQuery -Name VolumeSnaplockAttributes
            $nonSnaplockVolumesQuery.VolumeSnaplockAttributes.SnaplockType = "non_snaplock"

            $allNonSnaplockVolumes = Get-NCVol -Controller @($cDot.Values) -Query $nonSnaplockVolumesQuery -ErrorAction Stop | Where-Object { $_.Name -notmatch "^(JP)|(ROOT)_" }
            if($allNonSnaplockVolumes.Length -gt 0)
            {
                # Capture all volumes hosted on $SourceVServerName...
                LogInfo ("{0} volumes found." -f @($allNonSnaplockVolumes.Length)) 1

                $snapmirrorSourceVolumes = @($allNonSnaplockVolumes | Where-Object { ($_.VServer -eq $SourceVServerName) -and $_.VolumeMirrorAttributes.IsSnapmirrorSourceSpecified -and $_.VolumeMirrorAttributes.IsSnapmirrorSource })
                if($snapmirrorSourceVolumes.Length -gt 0)
                {
                    LogInfo ("{0} snapmirror source volumes found." -f @($sourceVolumes.Length)) 1
                    $snapmirrorSourceVolumes.ForEach({
                        LogInfo ("{0}:{1}:{2}" -f @($_.NCController.Name, $_.VServer, $_.Name)) 2
                    })

                    # Capture a sorted list of source volume names.
                    $snapmirrorSourceVolumeNames = @($snapmirrorSourceVolumes | Select-Object -Unique -ExpandProperty Name | Sort-Object)

                    try
                    {
                        # Get all snapmirrors hosted on all ONTAP clusters where the source VServer = $SourceVServerName and SourceVolume is one of the $snapmirrorSourceVolumes
                        LogInfo ("Retrieving source volume snapmirrors from all clusters where source VServer = {0}..." -f @($SourceVServerName))
                        $allSourceVolumesSnapmirrors = @(Get-NcSnapmirror -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { ($_.SourceVserver -eq $SourceVServerName) -and ($snapmirrorSourceVolumeNames -contains $_.SourceVolume) })
                        if($allSourceVolumesSnapmirrors.Length -gt 0)
                        {
                            <#
                                Outside the source volume processing loop.
                                Check to see if there are any CIFS shares hosted on any of the source volumes.  If there are, then we need to shutdown the source CIFS server
                                    prior to updating the snapmirror destinations to ensure we don't lose any changed data.  We also ensure the destination CIFS server is running.
                            #>

                            $retObj = UpdateCIFSServers -SMSrcVols $snapmirrorSourceVolumes -AllSrcVolsSMs $allSourceVolumesSnapmirrors -DRVServerName $DRVServerName
                            $good2Go = $retObj.good2Go

                            if($good2Go)
                            {
                                $sourceCIFSSharesWithSnapmirrorDestinations = $retObj.sourceCIFSSharesWithSnapmirrorDestinations
                                $sourceCIFSServer = $retObj.sourceCIFSServer
                                $destinationCIFSServer = $retObj.destinationCIFSServer

                                # On to failing over the source volumes....
                                $srcVolIdx = 0
                                while($good2Go -and ($srcVolIdx -lt $snapmirrorSourceVolumes.Length))
                                {
                                    $volFailoverParams = @{
                                        sourceVolume = $snapmirrorSourceVolumes[$srcVolIdx]
                                        sourceCIFSSharesWithSnapmirrorDestinations = $sourceCIFSSharesWithSnapmirrorDestinations
                                        allSourceVolumesSnapmirrors = $allSourceVolumesSnapmirrors
                                        allNonSnaplockVolumes = $allNonSnaplockVolumes
                                        DRVServerName = $DRVServerName
                                    }
                                    $good2Go, $destinationCIFSServer = FailOverVolume @volFailoverParams

                                    $srcVolIdx++
                                }

                                if($good2Go)
                                {
                                    if($null -ne $sourceCIFSServer)
                                    {
                                        $good2Go, $tmpCIFSServer = GetCIFSServer -cifsServer $sourceCIFSServer
                                        if($good2Go)
                                        {
                                            if($null -ne $tmpCIFSServer)
                                            {
                                                if($tmpCIFSServer.AdministrativeStatus -ne "up")
                                                {
                                                    LogInfo ("Restarting source CIFS server: {0}" -f @($tmpCIFSServer.CifsServer)) 3

                                                    # It's not critical if the source CIFS server is not restarted.  There will be a warning if it was not started.
                                                    StartCIFSServer -cifsServer $tmpCIFSServer
                                                }
                                                else
                                                {
                                                    # Nothing
                                                }
                                            }
                                            else
                                            {
                                                LogWarning ("Failed to refresh CIFS server data for {0}.  Please manually check." -f @($sourceCIFSServer.CifsServer))
                                            }
                                        }
                                        else
                                        {
                                            # Nothing, already displayed a message.
                                        }
                                    }
                                    else
                                    {
                                        # Nothing, evidently, no CIFS servers were updated.
                                    }
                                }
                                else
                                {
                                    # Nothing, already displayed a message
                                }
                            }
                            else
                            {
                                # Nothing, a message would already have been displayed
                            }
                        }
                        else
                        {
                            LogWarning ("No snapmirror source volumes located for VServer: {0}." -f @($SourceVServerName)) 1
                            $good2Go = $false
                        }
                    }
                    catch
                    {
                        LogException "Failed to retrieve snapmirrors from ONTAP." 1
                        $good2Go = $false
                    }
                }
                else
                {
                    LogWarning ("No snapmirror source volumes found where VServer = {0}." -f @($SourceVServerName)) 1
                }
            }
            else
            {
                LogError "No non-snaplock volumes retrieved from ONTAP." 1
                $good2Go = $false
            }
        }
        catch
        {
            LogException "Failed to retrieve all non-snaplock volumes from ONTAP clusters." 1
            $good2Go = $false
        }
    }
    else
    {
        LogError "Failed to connect to any ONTAP clusters."
    }

    if($null -ne $Script:sbMessageLog)
    {
        $Script:sbMessageLog.ToString() | Set-Clipboard
        Write-Host "`r`n`r`nScript output copied to clipboard!!`r`n`r`n"
    }
}
else
{
    LogError "Not connected to any ONTAP controllers."
}
