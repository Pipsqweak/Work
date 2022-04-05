[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $csSourceFile
)

if(-not $Global:CMLoggingAvailable)
{
    Write-Error "CM Logging capabilities not available"
    return
}

# Instead of hard coding the .dll file locations, the script relies on the GAC to get the .dll locations.
$requiredAssemblies = @(
    "DataONTAP.C",
    "OntapiPS",
    "VMware.VimAutomation.Sdk.Util10",
    "VMware.VimAutomation.Sdk.Types",
    "VMware.VimAutomation.Sdk.Interop",
    "VMware.VimAutomation.ViCore.Impl",
    "VMware.VimAutomation.ViCore.Interop",
    "VMware.VimAutomation.ViCore.Types"
)

# Array to collect the .dll locations for each required assembly
$requiredAssembliesLocations = @()
$requiredAssemblies | ForEach-Object {
    try
    {
        # Load the assembly based on name
        $assembly = [System.Reflection.Assembly]::Load($_)

        # If the assembly was successfully loaded, capture its location $requiredAssemblies so we can use the array as a parameter for Add-Type
        if($null -ne $assembly)
        {
            $requiredAssembliesLocations += $assembly.Location
            LogInfo ("Loaded assembly: {0} from {1}" -f @($assembly.FullName, $assembly.Location))
        }
        else
        {
            LogError ("Could not load assembly: {0}" -f @($_))
        }
    }
    catch
    {
        LogError ("Could not load assembly: {0}" -f @($_))
    }
}

if($requiredAssembliesLocations.Length -eq $requiredAssemblies.Length)
{
#    Add-Type -Path ".\SnaplockClasses.cs" -ReferencedAssemblies $requiredAssembliesLocations
    Add-Type -Path $csSourceFile -ReferencedAssemblies $requiredAssembliesLocations
    LogInfo "Snaplock C# classes loaded."
}
else
{
    LogError "Unable to add snaplock classes.  Missing required assemblies."
}

<# Completed locating required assemblies and adding the C# code. #>
