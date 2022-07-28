class clsVirtualizationDefinition
{
    [VMware.VimAutomation.ViCore.Impl.V1.VIServerImpl] $vCenter
    [Cisco.Ucsm.UcsHandle] $ucsManager
    [NetApp.Ontapi.Filer.C.NcController] $ncController
    [Object] $configuration
    [bool] $DoReportSuccess = $false

    clsVirtualizationDefinition([String] $vCenterName, [String] $ucsManagerName, [String] $cdotClusterName, [String] $virtualizationDefinitionFileName)
    {
        if (-not [String]::IsNullOrEmpty($vCenterName))
        {
            # TRUE
            if (-not [String]::IsNullOrEmpty($ucsManagerName))
            {
                # TRUE
                if (-not [String]::IsNullOrEmpty($cdotClusterName))
                {
                    # TRUE
                    if (-not [String]::IsNullOrEmpty($virtualizationDefinitionFileName))
                    {
                        # TRUE

                    }
                    else # NOT (-not [String]::IsNullOrEmpty($virtualizationDefinitionFileName))
                    {
                        # FALSE

                        # Nothing.
                    }
                }
                else # NOT (-not [String]::IsNullOrEmpty($cdotClusterName))
                {
                    # FALSE

                    # Nothing.
                }
            }
            else # NOT (-not [String]::IsNullOrEmpty($ucsManagerName))
            {
                # FALSE

                # Nothing.
            }
        }
        else # NOT (-not [String]::IsNullOrEmpty($vCenterName))
        {
            # FALSE

            # Nothing.
        }
    }
}   # clsVirtualizationDefinition
