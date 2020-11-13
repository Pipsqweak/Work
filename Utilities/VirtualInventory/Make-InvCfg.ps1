# Make .json configuration file for Virtual Inventory Script.

if($null -ne $cdot)
{
    if($null -ne $smNodes)
    {
        $cdotCredential = Get-Credential -Message "Enter username and password for access to CDOT clusters"

        if($null -ne $cdotCredential)
        {
            $smCredential = Get-Credential -Message "Enter username and password for access to 7-Mode filers ([ESC] to use CDOT credentials)"
            if($null -eq $smCredential)
            {
                $smCredential = $cdotCredential
            }

            $ucsCredential = Get-Credential -Message "Enter username and password for access to UCS Managers (username format: ucs-powereng.com\username)"
            if($null -ne $ucsCredential)
            {
                $xClarityCredential = Get-Credential -Message "Enter username and password for access to xClarity"

                if($null -ne $xClarityCredential)
                {
                    $vCenterCredential = Get-Credential -Message "Enter username and password for access to vCenter"

                    if($null -ne $vCenterCredential)
                    {
                        $ipamDBCredential = Get-Credential -Message "Enter username and password for access to IPAM DB"

                        if($null -ne $ipamDBCredential)
                        {
                            $statseekerCredential = Get-Credential -Message "Enter username and password for access to Statseeker"

                            if($null -ne $statseekerCredential)
                            {
                                $inventoryConfig = "" | Select-Object Filers, UCS, vCenter, xClarity, IPAMDB
                                $inventoryConfig.Filers = "" | Select-Object CDOT, SM
                                $inventoryConfig.Filers.CDOT = "" | Select-Object UserName, Password, Controllers
                                $inventoryConfig.Filers.CDOT.Controllers = $null
                                $inventoryConfig.Filers.CDOT.UserName = $cdotCredential.UserName
                                $inventoryConfig.Filers.CDOT.Password = $cdotCredential.Password | ConvertFrom-SecureString

                                $inventoryConfig.Filers.SM = "" | Select-Object UserName, Password, Nodes
                                $inventoryConfig.Filers.SM.Nodes = $null
                                $inventoryConfig.Filers.SM.UserName = $smCredential.UserName
                                $inventoryConfig.Filers.SM.Password = $smCredential.Password | ConvertFrom-SecureString

                                $inventoryConfig.Intersight = "" | Select-Object URL, APIKey, PrivateKeyFile
                                $inventoryConfig.vCenter = "" | Select-Object Server,UserName,Password
                                $inventoryConfig.xClarity = "" | Select-Object Server,UserName,Password
                                $inventoryConfig.IPAMDB = "" | Select-Object Server,Port,Database,UserName,Password

                                $tList = [System.Collections.Generic.List[System.String]]::new()
                                foreach($c in @($cdot.Values))
                                {
                                    $tList.Add("{0}.powereng.com" -f @($c.Name.ToLower()))
                                }
                                $inventoryConfig.Filers.CDOT.Controllers = $tList.ToArray()

                                $tList.Clear()
                                foreach($c in @($smNodes.Values))
                                {
                                    $tList.Add("{0}.powereng.com" -f @($c.Name.ToLower().Replace(".powereng.com","")))
                                }
                                $inventoryConfig.Filers.SM.Nodes = $tList.ToArray()

                                $inventoryConfig.Intersight.URL = "https://intersight.com/api/v1"
                                $inventoryConfig.Intersight.APIKey = "5b51f81e6a636d6d34958477/5e0f6d207564612d301d07b7/5f7b68017564612d33de8075"
                                $inventoryConfig.Intersight.PrivateKeyFile = "C:\Users\kbriney\KLB\PEI-IT-OPS\intersight.pem"

                                $inventoryConfig.xClarity.Server = "xclarity.powereng.com"
                                $inventoryConfig.xClarity.UserName = $xClarityCredential.UserName
                                $inventoryConfig.xClarity.Password = $xClarityCredential.Password | ConvertFrom-SecureString  # "@Z0H!UUjmSrs%*BK3ea"

                                $inventoryConfig.vCenter.Server = "tdcprdvctr1.powereng.com"
                                $inventoryConfig.vCenter.UserName = $vCenterCredential.UserName # "powereng\SRVCvCenterReadAll"
                                $inventoryConfig.vCenter.Password = $vCenterCredential.Password | ConvertFrom-SecureString # "b&hvGS2!Ep9t"

                                $inventoryConfig.IPAMDB.Server = "ddc-ipam01.powereng.com"
                                $inventoryConfig.IPAMDB.Port = 3306
                                $inventoryConfig.IPAMDB.Database = "gestioip"
                                $inventoryConfig.IPAMDB.UserName = $ipamDBCredential.UserName
                                $inventoryConfig.IPAMDB.Password = $ipamDBCredential.Password | ConvertFrom-SecureString # "1n33dmCB!"

                                $inventoryConfig.Statseeker.URL = "https://statseeker.powereng.com"
                                $inventoryConfig.Statseeker.APIBase = "/api/v2.1"
                                $inventoryConfig.Statseeker.UserName = $statseekerCredential.UserName
                                $inventoryConfig.Statseeker.Password = $statseekerCredential.Password | ConvertFrom-SecureString # # "@Z0H!UUjmSrs%*BK3ea"

                                $inventoryConfig | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Users\kbriney\KLB\PEI-IT-OPS\Utilities\invCfg.json" -Force
                            }
                        }
                    }
                }
            }
        }
    }
    else
    {
        Write-Error "Must be connected to 7-mode nodes with `$smNodes set..."
    }
}
else
{
    Write-Error "Must be connected to cluster controllers with `$cdot set..."
}
