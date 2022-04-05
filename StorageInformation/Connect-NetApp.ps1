# Ensure CM logging capabilities are available.
if ($Global:CMLoggingAvailable)
{
    # First, connect to all the cluster mode controllers.
    #   -- As of 7/13/2021, only cluster mode controllers are used in this script.

    # Dictionary to contain all the CDOT cluster connections.
    $Global:cDot = [System.Collections.Generic.SortedDictionary[System.String, NetApp.Ontapi.Filer.C.NcController]]::new()

    #  Create a credential for connecting to CDOT clusters
    $cdotCredential = [System.Management.Automation.PsCredential]::new($Global:scriptConfig.Filers.CDOT.UserName, ($Global:scriptConfig.Filers.CDOT.Password | ConvertTo-SecureString))

    $a = 0
    while($a -lt $Global:scriptConfig.Filers.CDOT.Controllers.Length)
    {
        $cdotController = $null
        try
        {
            # Make a transient connection to the cluster controller
            $cdotController = Connect-NcController -Name $Global:scriptConfig.Filers.CDOT.Controllers[$a] -HTTPS  -Credential $cdotCredential -Transient:$true -Timeout 15000 -ErrorAction Stop
            $Global:cDot.Add($cdotController.Name, $cdotController)
            LogInfo ("Connected to {0}" -f @($cdotController.Name))
        }
        catch
        {
            LogError ("Failed to connect to CDOT controller {0}." -f @($Global:scriptConfig.Filers.CDOT.Controllers[$a]))
        }
        $a++
    }
}
else
{
    Write-Error "CM Logging capability not available."
}
