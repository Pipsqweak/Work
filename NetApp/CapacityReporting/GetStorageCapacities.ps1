using module PEI.Log
#Requires -Modules DataONTAP

[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [ValidateNotNullOrEmpty()]
    [String]
    $JSONArgsFile
)

<#
    # Convert the plain text password into encrypted strings.
    $config.Filers.Password = ConvertTo-SecureString -String $config.Filers.Password -AsPlainText -Force | ConvertFrom-SecureString

    # Save the configuration data back to the same file it was read from.
    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $JSONArgsFile -Force
#>

$Global:DoDebugging = $true

if($Global:DoDebugging)
{
    # For Debugging
    $JSONArgsFile = "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\NetApp\CapacityReporting\config - kbriney-adm.json"
    Set-Location -Path "C:\Users\kbriney-adm\PSScripts\Repos\PEI-IT-OPS\NetApp\CapacityReporting"
}

function TestConfigPath
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [String]
        $pathToTest,

        [Parameter(Mandatory=$true,Position=1)]
        [String]
        $label
    )

    if([String]::IsNullOrEmpty($pathToTest))
    {
        [Log]::Error("Configuration data missing {0}." -f @($label))
        $pathToTest = $null
    }
    else
    {
        $tempPath = $pathToTest
        while((-not [String]::IsNullOrEmpty($tempPath)) -and ($tempPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)))
        {
            $tempPath = $tempPath.Substring(0, $tempPath.Length - 1)
        }

        if([String]::IsNullOrEmpty($tempPath))
        {
            [Log]::Error("{0} [{1}] is invalid" -f @($label, $pathToTest))
            $pathToTest = $null
        }
        else
        {
            $testFolder = "{0}\{1}.tmp" -f @($tempPath, [DateTime]::Now.ToString("yyyyMMddHHmmssfff"))
            try
            {
                New-Item -Path $testFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Remove-Item -Path $testFolder -Confirm:$false -Force -ErrorAction Stop
                $pathToTest = $tempPath
            }
            catch
            {
                [Log]::Error("Unable to create/remove temporary folder in {0}." -f @($pathToTest))
                $pathToTest = $null
            }
        }
    }

    return $pathToTest
}

function ConnectToCDOT($config)
{
    #  Create a credential for connecting to CDOT clusters
    $cdotCredential = [System.Management.Automation.PsCredential]::new($config.Filers.UserName, ($config.Filers.Password | ConvertTo-SecureString))
    $tDict = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()

    $a = 0
    while($a -lt $config.Filers.Controllers.Length)
    {
        try
        {
            # Make a transient connection to the cluster controller
            $cdotController = Connect-NcController -Name $config.Filers.Controllers[$a] -Credential $cdotCredential -Transient:$true -ErrorAction Stop
            [Log]::Trace("Connected to {0}." -f @($cdotController.Name))
            $tDict.Add($cdotController.Name, $cdotController)
        }
        catch
        {
            [Log]::Error("Failed to connected to {0}." -f @($config.Filers.Controllers[$a]))
        }
        $a++
    }

    return $tDict
}

function Main($config)
{
    $cDot = ConnectToCDOT $config

    if (-not $Global:isError)
    {
        try
        {
            $aggregateData = @()
            $aggregates = @(Get-NcAggr -Controller @($cDot.Values) -ErrorAction Stop | Where-Object { $_.Name -notmatch "ROOT_aggr" } | Sort-Object @{E={$_.NcController.Name}; Descending=$false}, Name)

            $b = 0
            while($b -lt $aggregates.Length)
            {
                $d = "" | Select-Object clusterName, aggrName, totalDataCapacity, usedDataCapacity, availableDataCapacity, <# "Total Capacity (TB)", "Used Capacity (TB)", "Available Capacity (TB)", #> Date
                $d.clusterName = $aggregates[$b].NcController.Name.ToUpper().Replace(".POWERENG.COM", "")
                $d.aggrName = $aggregates[$b].Name
                $d.totalDataCapacity = [decimal] ("{0:N2}" -f @(($aggregates[$b].TotalSize / 1GB)))
                $d.availableDataCapacity = [decimal] ("{0:N2}" -f @(($aggregates[$b].Available / 1GB)))
                $d.usedDataCapacity = [decimal] ("{0:N2}" -f @(($d.totalDataCapacity - $d.availableDataCapacity)))
                <#
                    $d.'Total Capacity (TB)' = [decimal] ("{0:N2}" -f @(($d.totalDataCapacity / 1KB)))
                    $d.'Used Capacity (TB)' = [decimal] ("{0:N2}" -f @(($d.usedDataCapacity / 1KB)))
                    $d.'Available Capacity (TB)' = [decimal] ("{0:N2}" -f @(($d.availableDataCapacity / 1KB)))
                #>
                $d.Date = [System.DateTime]::Now.ToString("M/d/yyyy")

                $aggregateData += $d
                [Log]::Trace("{0,-16}{1,-35}{2,12:N2}{3,12:N2}{4,12:N2}{5,12:N2}{6,12:N2}{7,12:N2} {8}" -f @($d.clusterName, $d.aggrName, $d.totalDataCapacity, $d.usedDataCapacity, $d.availableDataCapacity, $d.'Total Capacity (TB)', $d.'Used Capacity (TB)', $d.'Available Capacity (TB)', $d.Date))
                $b++
            }

            try
            {
                $csvFileName = "{0}\{1}-StorageCapacity.csv" -f @($config.ExportPath, [DateTime]::Now.ToString("yyyyMMdd"))
                $aggregateData | Export-Csv -Force -Path $csvFileName -NoTypeInformation -Delimiter "," -Encoding ASCII
                [Log]::Info("Exported storage capacity data to: {0}" -f @($csvFileName))
            }
            catch
            {
                [Log]::Error("Failed to export storage capacity data.")
            }
        }
        catch
        {
            [Log]::Error("Failed to retrieve comprehensive aggregate data.")
        }
    }
    else # NOT (-not $Global::isError)
    {
        # Nothing.
    }
}

if ($Global:LoggerClassLoaded)
{
    try
    {
        $config = Get-Content -Path $JSONArgsFile -ErrorAction Stop | ConvertFrom-Json

        $tempPath = TestConfigPath $config.LogPath "LogPath"
        if(-not [String]::IsNullOrEmpty($tempPath))
        {
            $config.LogPath = $tempPath
            [Log]::Init($config.LogPath, "StorageCapacity", 14, 1, [LogLevel]::TRACE)
            [Log]::Info("Logging initialized...")

            $tempPath = TestConfigPath $config.ExportPath "ExportPath"
            if(-not [String]::IsNullOrEmpty($tempPath))
            {
                $config.ExportPath = $tempPath
                [Log]::Info("Export Path: {0}" -f @($config.ExportPath))

                Main $config
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
    catch
    {
        [Log]::Error("Failed to load script configuation.")
    }
}
else # NOT ($Global:LoggerClassLoaded)
{
    Write-Error "Missing [Log] class."
}
