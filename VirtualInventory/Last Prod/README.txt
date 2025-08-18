The virtual inventory script "Get-EVData.ps1" collects virtual inventory data from various sources and exports the data to a CSV file that is later uploaded to EasyVista via an Orchestrator runbook.  See Russel Riley for details.

The script is current ran at 12:00:00am everyday via a scheduled task on CDC-NTAPMGMT01.

The script is broken into several powershell script files.

    1. Get-EVData.ps1 - This is the "main" script for collecting inventory data.  It "sources" in the other script files to gain their functionality.
    
    2. Log.ps1 - Provides generic logging capabilities.
    
    3. LoadConfigurationData.ps1 - Loads the configuration data file and does some basic checking to ensure all information is available to the script.
        a. Requires [Log] class created in Log.ps1
    
    4. DBConnectionMYSQL.ps1 - Defines a custom class used to connect to and query MySQL databases.
        a. Requires [Log] class created in Log.ps1

    5. EVDataPoint.ps1 - Defines a custom class to store inventory data that will be exported to EasyVista.
        a. Requires [Log] class created in Log.ps1
        b. Requires [MySQLDBConnection] class created in DBConnectionMYSQL.ps1

NOTE: All "\" characters used in JSON strings must be escaped.  i.e.  \\CDC-MGMT01\VIExports needs to be \\\\CDC-MGMT01\\VIExports.

    
Connect to Cisco Intersight to collect inventory data for UCS chasses, Fabric Interconnects, and servers.
    
    1. Uses an API key and secret key file created at our Cisco Intersight portal.

    2. The following data from the configuration JSON file is used to connect to Intersight.
    
        "Intersight":  {
            "URL":  "https://intersight.com/api/v1",
            "APIKey":  "5b51f81e6a636d6d34958477/5fa321e97564612d33de8994/5fa3256f7564612d33debaad",
            "PrivateKeyFile":  "E:\\Scripts\\VirtualInventory\\srvc-virt-inv.SecretKey.pem"
        }

Connect to xClarity to collect inventory data for all Lenovo (IBM) servers.

    1. The account, SRVC-VIRT-INV, is a POWERENG AD account.   It is listed in the password vault under "VIRTUAL INVENTORY ACCOUNT".

    2. The following data from the configuration JSON file is used to connect to xClarity.
    
        "xClarity":  {
            "Server":  "xclarity.powereng.com",
            "UserName":  "SRVC-VIRT-INV",
            "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c0000000100000001c51c3f1d2e2c40a99a63d58b8c7c2c90000000004800000a0000000100000008d4987ce3529a4feb20483b114e4546328000000df513ba37ef309f8a29075a1d851f3cbc661ee47f968bb486bdd3c285d4a1c48d0b966a55e567ad114000000daad8c0ea7d8abf51409a367c14e680d6c7b02bb"
        }        

Connect to vCenter to update the operating system versions for Cisco and Lenovo ESXi servers and to add "unregistered" servers to 
   the export data.

    1. The following data from the configuration JSON file is used to connect to vCenter.

        "vCenter":  {
            "Server":  "tdcprdvctr1.powereng.com",
            "UserName":  "POWERENG\\SRVCvCenterReadAll",
            "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c00000001000000040868bac941de9ed5da912a61b71a79f0000000004800000a000000010000000b493f24a0bc917fc4d31d7b0e8f16b5c20000000b51b032d73d4666b8d8bfa15fa8b95b80200f82aa0af8b94c19cc847d2c633d114000000e0289424e956a763d4a5986977a141e89339601b"
        }

Connect to all the listed NetApp filers (Clustered Mode and 7-Mode) listed in the configuration data to collect inventory data
   from them.

    1. Cluster, node, intercluster switch and shelf data is collected for Clustered DataONTAP.  For 7-Mode, only node information is collected.  Without granting extra
        permissions, I was unable to acquire shelf data from the 7-mode filers.

    2. The following data from the configuration JSON file is used to connect to the clusters and filers.

        "Filers":  {
            "CDOT":  {
                "UserName":  "POWERENG\\SRVC-AllStorage-RO",
                "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c0000000100000001f3739e5e88e6213749e9510aa6392840000000004800000a0000000100000005d6e0fb6486d2fe4c778b9b425f017e92800000037ce61310d3f60aa4a87c19f39dbb11eafa4f8967a094a0d0dfdc0680187eb7304d8a23d2bc5e228140000002b897f8f8ad6f58c0132c37a8e8524ed40c93117",
                "Controllers":  [
                    "adc-cdotclst01.powereng.com",
                    "apl-cdotclst01.powereng.com",
                    "ast-cdotclst01.powereng.com",
                    "aus-cdotclst01.powereng.com",
                    "bdc-cdotclst01.powereng.com",
                    "bdcd-cdotclst01.powereng.com",
                    "bil-cdotclst01.powereng.com",
                    "boi-cdotclst01.powereng.com",
                    "cdc-cdotclst01.powereng.com",
                    "clk-cdotclst01.powereng.com",
                    "den-cdotclst01.powereng.com",
                    "fmc-cdotclst01.powereng.com",
                    "fre-cdotclst01.powereng.com",
                    "hou-cdotclst01.powereng.com",
                    "ito-cdotclst01.powereng.com",
                    "lax-cdotclst01.powereng.com",
                    "min-cdotclst01.powereng.com",
                    "opk-cdotclst01.powereng.com",
                    "phx-cdotclst01.powereng.com",
                    "plv-cdotclst01.powereng.com",
                    "ptl-cdotclst01.powereng.com",
                    "san-cdotclst01.powereng.com",
                    "slc-cdotclst01.powereng.com"
                ]
            },
            "SM":  {
                "UserName":  "POWERENG\\SRVC-AllStorage-RO",
                "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c0000000100000007f400d7882181bb31317b8907638d5200000000004800000a00000001000000096fc394a4bd64a8bb5671ecdb8525970280000003c333c08616d540817ee99e9e39d66a01c5363e3cec169e045a9f79b8968f7e7fe43fdbffe5ce38014000000bb0e91f471c835c2f594c2e5da8b19d108846cb3",
                "Nodes":  [
                    "arbprdnas1.powereng.com",
                    "atlprdnas2.powereng.com",
                    "atlprdnas3.powereng.com",
                    "bosprdnas1.powereng.com",
                    "cinprdnas1.powereng.com",
                    "edpprdnas1.powereng.com",
                    "ftwprdnas1.powereng.com",
                    "hamprdnas1.powereng.com",
                    "hlyprdnas2.powereng.com",
                    "hlyprdnas3.powereng.com",
                    "msnnas1.powereng.com",
                    "mtlprdnas1.powereng.com",
                    "orasan1.powereng.com",
                    "orasan2.powereng.com",
                    "orlprdnas1.powereng.com",
                    "orlprdnas2.powereng.com",
                    "stlprdnas2.powereng.com",
                    "stlprdnas3.powereng.com",
                    "syrnas1.powereng.com",
                    "tdcprdnas1.powereng.com",
                    "vanprdnas1.powereng.com"
                ]
            }
        }

Connect to Statseeker to collect inventory data for Juniper and Riverbed devices.

    1. The account, SRVC-VIRT-INV is a local account created on the statseeker server.  Its password matches the AD user account's password (at least
       at the time this script and documentation was created).

    2. The following data from the configuration JSON file is used to connect to Statseeker.
    
        "Statseeker":  {
            "URL":  "https://statseeker.powereng.com",
            "APIBase":  "/api/v2.1",
            "UserName":  "SRVC-VIRT-INV",
            "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c000000010000000670c9d20d6866b022c5438e67067a6a20000000004800000a0000000100000001a1b00dec8512fcec01478ec9f9e72ed28000000f9fefa81197f74117bfb4dea51bba845682af23b757db729ce95ea5eb461d4449697e7b7bc02fadb140000002901a84a5fb2e8e4208cb116af5e107ce61e352d"
        }

Device location is determined by looking up its IP address in the IPAM DB using the following data from the configuration JSON file:

        "IPAMDB":  {
            "Server":  "ddc-ipam01.powereng.com",
            "Port":  3306,
            "Database":  "gestioip",
            "UserName":  "gestioip",
            "Password":  "01000000d08c9ddf0115d1118c7a00c04fc297eb010000005bda5f25fb227c4b95a60230bdd986590000000002000000000003660000c000000010000000c4d13aeb7a38249fda3279dbc22080ab0000000004800000a000000010000000fdb237e455afaa7e289860423d8bd416180000004b4cc2f146f88f3536da9c609361ecb29d03d96d9a6a4c841400000088d19a92dfea7787c11b583e0a7ba92438562f26"
        }

Export all data to the following path as specified in the configuration file:

        "ExportPath": "E:\\Scripts\\VirtualInventory\\Exports"
        
Script logging is written to a file save in the path as specified in the configuration file:

        "LogPath":  "\\\\CDC-MGMT01\\VIExports",

Passwords in the configuration file are encrypted using EncryptConfig.ps1.  This script takes one argument -JSONArgsFile.  The file is loaded, passwords are encrypted, then the data is written back out to the same file.  See EncryptConfig.ps1 for more details.

