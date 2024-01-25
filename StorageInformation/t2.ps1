
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

# Array to collect the .dll locations for each required assembly.  Used as a parameter for Add-Type.
$requiredAssembliesLocations = @()
$requiredAssemblies | ForEach-Object {
    try
    {
        # Load the assembly based on name
        $assembly = [System.Reflection.Assembly]::Load($_)

        # If the assembly was successfully loaded, capture its location in $requiredAssembliesLocations.
        if($null -ne $assembly)
        {
            $requiredAssembliesLocations += $assembly.Location
            Write-Host ("Loaded assembly: {0} from {1}" -f @($assembly.FullName, $assembly.Location))
        }
        else
        {
            Write-Host -ForegroundColor Red ("Could not load assembly: {0}" -f @($_))
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Could not load assembly: {0}" -f @($_))
    }
}
