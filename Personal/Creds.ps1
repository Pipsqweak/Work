
function InitCreds()
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [Switch] $reinitialize
    )

    if ((-not $Global:credsInitialized) -or $reinitialize)
    {
        Write-Verbose "Initializing credentials..."
        $Global:credsPath = "C:\Users\kbriney-adm\Documents\WindowsPowerShell\creds.json"
        $Global:credsData = Get-Content -Path $credsPath | ConvertFrom-Json
        $Global:ucsManagers = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()

        $a = 0
        $newEncryptedPassword = $false
        while($a -lt $Global:credsData.Credentials.Length)
        {
            if (-not $Global:credsData.Credentials[$a].Encrypted)
            {
                Write-Host $Global:credsData.Credentials[$a].Name
                $Global:credsData.Credentials[$a].Password = ConvertTo-SecureString -String $Global:credsData.Credentials[$a].Password -AsPlainText -Force | ConvertFrom-SecureString
                $Global:credsData.Credentials[$a].Encrypted = $true
                $newEncryptedPassword = $true
            } `
            else # NOT (-not $Global:credsData.Credentials[$a].Encrypted)
            {
                # Nothing.
            }

            $a++
        }

        # Make sure to save the creds back to the creds file before we create the actual credential.
        if ($newEncryptedPassword)
        {
            $Global:credsData | ConvertTo-Json -Depth 10 | Set-Content -Path $credsPath -Force
        } `
        else # NOT ($newEncryptedPassword)
        {
            # Nothing.
        }

        $a = 0
        while($a -lt $Global:credsData.Credentials.Length)
        {
            $Global:credsData.Credentials[$a].Credential = [System.Management.Automation.PsCredential]::new($Global:credsData.Credentials[$a].UserName, ($Global:credsData.Credentials[$a].Password | ConvertTo-SecureString))
            $a++
        }

        $Global:credsInitialized = $true
    } `
    else # NOT ($null -eq )
    {
        # Nothing.
    }
}

function Get-ConnectCredentials($credentailName)
{
    $connectionCredentials = $Global:credsData.Credentials | Where-Object { $_.Name -eq $credentailName }

    return $connectionCredentials
}

$a = 0
while($a -lt $Global:credsData.Connections.Length)
{
    $connectionCred = Get-ConnectCredentials $Global:credsData.Connections[$a].CredName

    if ($null -eq $connectionCred)
    {
        Write-Warning ("Missing credentials for connection: {0}" -f @($Global:credsData.Connections[$a].Name))
    } `
    else # NOT ($null -eq $connectionCred)
    {
        # Nothing.
    }
    $a++
}

function ConnectTo-CDOT
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $connectionToMake,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [System.Management.Automation.PSCredential] $credential
    )

    $k = $null
    try
    {
        Write-Verbose ("Connecting to NC Controller {0}..." -f @($connectionToMake.Server))
        $k = Connect-NcController -Name $connectionToMake.Server -Transient -HTTPS -Credential $credential -ErrorAction Stop -Verbose:$false
        if ($null -ne $k)
        {
            if ($null -eq $Global:cDot)
            {
                $Global:cDot = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()
            } `
            else # NOT ($null -eq $Global:cDot)
            {
                # Nothing.
            }

            if (-not $Global:cDot.ContainsKey($connectionToMake.Name))
            {
                 $Global:cDot.Add($connectionToMake.Name, $k)
            } `
            else # NOT (-not $Global:cDot.ContainsKey($connectionToMake.Name))
            {
                Write-Warning ("`$cDot already contains an entry for {0}." -f @($connectionToMake.Name))
            }

            if (-not $Global:cDot.ContainsKey($connectionToMake.Server))
            {
                 $Global:cDot.Add($connectionToMake.Server, $k)
            } `
            else # NOT (-not $Global:cDot.ContainsKey($connectionToMake.Server))
            {
                Write-Warning ("`$cDot already contains an entry for {0}." -f @($connectionToMake.Server))
            }
        } `
        else # NOT ($null -ne $k)
        {
            Write-Error ("No connection object returned from Connect-NCController for {0}" -f @($connectionToMake.Server))
        }
    }
    catch
    {
        Write-Error ("Failed to connect to CDOT Controller: {0}" -f @($connectionToMake.Server))
    }

    return $k
}

function ConnectTo-vCenter
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $connectionToMake,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [System.Management.Automation.PSCredential] $credential
    )

    $k = $null
    try
    {
        Write-Verbose ("Connecting to vCenter {0}..." -f @($connectionToMake.Server))
        $k = Connect-VIServer -Server $connectionToMake.Server -NotDefault -Credential $credential -ErrorAction Stop -Verbose:$false
        if ($null -ne $k)
        {
            if ($null -eq $Global:vCtr)
            {
                $Global:vCtr = [System.Collections.Generic.SortedDictionary[System.String, VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl]]::new()
            } `
            else # NOT ($null -eq $Global:vCtr)
            {
                # Nothing.
            }

            if (-not $Global:vCtr.ContainsKey($connectionToMake.Name))
            {
                 $Global:vCtr.Add($connectionToMake.Name, $k)
            } `
            else # NOT (-not $Global:vCtr.ContainsKey($connectionToMake.Name))
            {
                Write-Warning ("`$vCtr already contains an entry for {0}." -f @($connectionToMake.Name))
            }

            if (-not $Global:vCtr.ContainsKey($connectionToMake.Server))
            {
                 $Global:vCtr.Add($connectionToMake.Server, $k)
            } `
            else # NOT (-not $Global:vCtr.ContainsKey($connectionToMake.Server))
            {
                Write-Warning ("`$vCtr already contains an entry for {0}." -f @($connectionToMake.Server))
            }
        } `
        else # NOT ($null -ne $k)
        {
            Write-Error ("No connection object returned from Connect-VIServer for {0}" -f @($connectionToMake.Server))
        }
    }
    catch
    {
        Write-Error ("Failed to connect to vCenter: {0}" -f @($connectionToMake.Server))
    }

    return $k
}

function ConnectTo-UCS
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [Object] $connectionToMake,

        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=1)]
        [System.Management.Automation.PSCredential] $credential
    )

    $k = $null
    try
    {
        Write-Verbose ("Connecting to UCS Manager {0}..." -f @($connectionToMake.Server))
        $k = Connect-Ucs -Name $connectionToMake.Server -Credential $credential -NotDefault -Verbose:$false
        if ($null -ne $k)
        {
            if ($null -eq $Global:ucsManagers)
            {
                $Global:ucsManagers = [System.Collections.Generic.SortedDictionary[System.String, System.Object]]::new()
            } `
            else # NOT ($null -eq $Global:ucsManagers)
            {
                # Nothing.
            }

            if (-not $Global:ucsManagers.ContainsKey($connectionToMake.Name))
            {
                 $Global:ucsManagers.Add($connectionToMake.Name, $k)
            } `
            else # NOT (-not $Global:ucsManagers.ContainsKey($connectionToMake.Name))
            {
                Write-Warning ("`$ucsManagers already contains an entry for {0}." -f @($connectionToMake.Name))
            }

            if (-not $Global:ucsManagers.ContainsKey($connectionToMake.Server))
            {
                 $Global:ucsManagers.Add($connectionToMake.Server, $k)
            } `
            else # NOT (-not $Global:ucsManagers.ContainsKey($connectionToMake.Server))
            {
                Write-Warning ("`$ucsManagers already contains an entry for {0}." -f @($connectionToMake.Server))
            }
        } `
        else # NOT ($null -ne $k)
        {
            Write-Error ("No connection object returned from Connect-UCS for {0}" -f @($connectionToMake.Server))
        }
    }
    catch
    {
        Write-Error ("Failed to connect to UCS: {0}" -f @($connectionToMake.Server))
    }

    return $k
}

function ConnectTo
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$false, Position=0)]
        [String[]] $keywords
    )

    InitCreds
    if (-not ($keywords -is [Array]))
    {
        $keywords = @($keywords)
    } `
    else # NOT (-not ($keywords -is [Array]))
    {
        # Nothing.
    }
    $connectionsToMake = @()
    $a = 0
    while($a -lt $Global:credsData.Connections.Length)
    {
        $b = 0
        $keywordsMatched = @()
        while(($keywordsMatched -notcontains $keywords[$b]) -and ($b -lt $keywords.Length))
        {
            # Does $keywords[$b] match the name of the connection?
            if ($Global:credsData.Connections[$a].Name -eq $keywords[$b])
            {
                $keywordsMatched += $keywords[$b]
            } `
            # No, does $keywords[$b] match the connection's server name?
            elseif ($Global:credsData.Connections[$a].Server -eq $keywords[$b])
            {
                $keywordsMatched += $keywords[$b]
            } `
            # No, see if any of the connection's tags match $keywords[$b]...
            else # NOT ($Global:credsData.Connections[$a].Name -eq $keywords[$b])
            {
                $c = 0
                while(($keywordsMatched -notcontains $keywords[$b]) -and ($c -lt $Global:credsData.Connections[$a].Tags.Length))
                {
                    # Write-Host ("Connection: {0}, Tag: {1}, Keyword: {2}" -f @($Global:credsData.Connections[$a].Name, $Global:credsData.Connections[$a].Tags[$c], $keywords[$b]))
                    if ($Global:credsData.Connections[$a].Tags[$c] -eq $keywords[$b])
                    {
                        $keywordsMatched += $keywords[$b]
                    } `
                    else # NOT ($Global:credsData.Connections[$a].Tags[$c] -eq $keywords[$b])
                    {
                        # Nothing.
                    }
                    $c++
                }
            }
            $b++
        }

        if($keywordsMatched.Length -eq $keywords.Length)
        {
            $connectionsToMake += $Global:credsData.Connections[$a]
        }
        $a++
    }

    $connectionsMade = @()
    $a = 0
    while($a -lt $connectionsToMake.Length)
    {
        $credential = $Global:credsData.Credentials | Where-Object { $_.Name -eq $connectionsToMake[$a].CredName }
        if ($null -ne $credential)
        {
            $credential = $credential.Credential
            if ($connectionsToMake[$a].Tags -contains "netapp")
            {
                $newConnection = ConnectTo-CDOT $connectionsToMake[$a] $credential
            } `
            elseif(($connectionsToMake[$a].Tags -contains "ucs") -or ($connectionsToMake[$a].Tags -contains "ucspe")) # NOT ($connectionsToMake[$a].Tags -contains "netapp")
            {
                $newConnection = ConnectTo-UCS $connectionsToMake[$a] $credential
            }
            elseif($connectionsToMake[$a].Tags -contains "vcenter") # NOT (($connectionsToMake[$a].Tags -contains "ucs") -or ($connectionsToMake[$a].Tags -contains "ucspe"))
            {
                $newConnection = ConnectTo-vCenter $connectionsToMake[$a] $credential
            }
            else # NOT ($connectionsToMake[$a].Tags -contains "vCenter")
            {
                Write-Warning ("Unknown connection type: {0}" -f @($connectionsToMake[$a].Name))
            }
        } `
        else # NOT ($null -ne $credential)
        {
            Write-Error ("Missing credentials to connect to {0}.  Credentials name: {1}" -f @($connectionsToMake[$a].Name, $connectionsToMake[$a].CredName))
        }

        if ($null -ne $newConnection)
        {
            $connectionsMade += $newConnection

            if (-not [String]::IsNullOrEmpty($connectionsToMake[$a].VariableName))
            {
                Set-Variable -Name $connectionsToMake[$a].VariableName -Value $newConnection -Scope "Global"
            } `
            else # NOT (-not [String]::IsNullOrEmpty($connectionToMake.VariableName))
            {
                # Nothing.
            }
        } `
        else # NOT ($null -ne $newConnection)
        {
            # Nothing.
        }
        $a++
    }

    # return $connectionsMade
}
