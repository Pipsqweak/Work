$ucsCreds = Get-Credential -Message 'Provide admin account used to connect to UCS Managers'
$bindDN = 'CN=SRVC-UCSLDAP,OU=Service Accounts,OU=IT,OU=PEI,DC=powereng,DC=com'
$bindPassword = 'WhatEver!!'

$ucsManagerNames = @(
    'lab-ucs01.powereng.com',
    'ddc-ucs01.powereng.com',
    'cdc-ucs01.powereng.com',
    'cdc-ucs02.powereng.com',
    'ch3-ucs01.powereng.com',
    'se4-ucs01.powereng.com',
    'ny7-ucs01.powereng.com',
    'at4-ucs01.powereng.com',
    'da11-ucs01.powereng.com',
    'las04-ucs01.powereng.com',
    'yyc01-ucs01.powereng.com'
)

$a = 0
while($a -lt $ucsManagerNames.Length)
{
    try
    {
        $k = Connect-Ucs -Name $ucsManagerNames[$a] -Credential $ucsCreds -NotDefault -Verbose:$false -ErrorAction Stop
        try
        {
            $ldapProviders = @(Get-UcsLdapProvider -UCS $k -ErrorAction Stop)
            $b = 0
            while($b -lt $ldapProviders.Length)
            {
                try
                {
                    $l = Set-UcsLdapProvider -Ucs $k -LdapProvider $ldapProviders[$b] -Rootdn $bindDN -Key $bindPassword -Confirm:$false -ErrorAction Stop
                    Write-Host ("Successfully set bind DN and password for {0}." -f @($ucsManagerNames[$a]))
                }
                catch
                {
                    Write-Error ("Failed to set bind RootDN/Password for {0} provider order {1}" -f @($ucsManagerNames[$a], $ldapProviders[$b].Order))
                }
                $b++
            }
        }
        catch
        {
            Write-Error ("Failed to retrieve LDAP Providers for {0}." -f @($ucsManagerNames[$a]))
        }
    }
    catch
    {
        Write-Error ("Failed to authenticate to {0}." -f @($ucsManagerNames[$a]))
    }
    $a++
}
