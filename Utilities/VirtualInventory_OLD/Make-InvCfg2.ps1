# Make .json configuration file for Virtual Inventory Script.
$JSONArgsFile = "E:\Scripts\VirtualInventory\inventoryConfiguration.json"
$inventoryConfig = Get-Content -Path $JSONArgsFile | ConvertFrom-Json

$inventoryConfig.Filers.CDOT.Password = ConvertTo-SecureString -String $inventoryConfig.Filers.CDOT.Password -AsPlainText -Force
$inventoryConfig.Filers.SM.Password = ConvertTo-SecureString -String $inventoryConfig.Filers.SM.Password -AsPlainText -Force
$inventoryConfig.xClarity.Password = ConvertTo-SecureString -String $inventoryConfig.xClarity.Password -AsPlainText -Force
$inventoryConfig.vCenter.Password = ConvertTo-SecureString -String $inventoryConfig.vCenter.Password -AsPlainText -Force
$inventoryConfig.IPAMDB.Password = ConvertTo-SecureString -String $inventoryConfig.IPAMDB.Password -AsPlainText -Force
$inventoryConfig.Statseeker.Password = ConvertTo-SecureString -String $inventoryConfig.Statseeker.Password -AsPlainText -Force


$inventoryConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $JSONArgsFile -Force
