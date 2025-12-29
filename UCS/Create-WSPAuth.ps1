$ucs = $labUCS
$ldapProviders = [System.Collections.Generic.List[Object]]::new()

<# --------------------------------------- 1 ------------------------------------------- #>
# Create the provider
$cmdParams = @{
    Ucs = $ucs;
    Name = "DCAME100DOM05.corp.pbwan.net";
    Basedn = "DC=corp,DC=pbwan,DC=net";
    Rootdn = "CN=SVC-US-UCSLDAP,OU=SVC Users,OU=_Resource Mgmt,OU=WSPObjects,DC=corp,DC=pbwan,DC=net";
    EnableSSL = "yes";
    FilterValue = "sAMAccountName=`$userid";
    Vendor = "MS-AD";
    Order = 4;
    Key = "cJ4qbgqkz%Yx"
}

$ldapProvider = Add-UcsLdapProvider @cmdParams

# Add the provider to the list
$ldapProviders.Add($ldapProvider)

# Create the provider group rule
$cmdParams = @{
    Ucs = $ucs;
    LdapProvider = $ldapProvider;
    ModifyPresent = $true;
    Authorization = "enable";
    Descr = "";
    Name = "";
    TargetAttr = "memberOf";
    Traversal = "recursive";
    UsePrimaryGroup = "no"
}
$groupRule = Add-UcsLdapGroupRule @cmdParams

<# --------------------------------------- 2 ------------------------------------------- #>

# Create the provider
$cmdParams = @{
    Ucs = $ucs;
    Name = "DCAME200DOM04.corp.pbwan.net";
    Basedn = "DC=corp,DC=pbwan,DC=net";
    Rootdn = "CN=SVC-US-UCSLDAP,OU=SVC Users,OU=_Resource Mgmt,OU=WSPObjects,DC=corp,DC=pbwan,DC=net";
    EnableSSL = "yes";
    FilterValue = "sAMAccountName=`$userid";
    Vendor = "MS-AD";
    Order = 5;
    Key = "cJ4qbgqkz%Yx"
}

$ldapProvider = Add-UcsLdapProvider @cmdParams

# Add the provider to the list
$ldapProviders.Add($ldapProvider)

# Create the provider group rule
$cmdParams = @{
    Ucs = $ucs;
    LdapProvider = $ldapProvider;
    ModifyPresent = $true;
    Authorization = "enable";
    Descr = "";
    Name = "";
    TargetAttr = "memberOf";
    Traversal = "recursive";
    UsePrimaryGroup = "no"
}
$groupRule = Add-UcsLdapGroupRule @cmdParams

<# --------------------------------------- 3 ------------------------------------------- #>

# Create the provider
$cmdParams = @{
    Ucs = $ucs;
    Name = "DCCAN100DOM02.corp.pbwan.net";
    Basedn = "DC=corp,DC=pbwan,DC=net";
    Rootdn = "CN=SVC-CA-UCSLDAP,OU=SVC Users,OU=_Resource Mgmt,OU=WSPObjects,DC=corp,DC=pbwan,DC=net";
    EnableSSL = "yes";
    FilterValue = "sAMAccountName=`$userid";
    Vendor = "MS-AD";
    Order = 6;
    Key = "Gql!&dGE8B*p"
}

$ldapProvider = Add-UcsLdapProvider @cmdParams

# Add the provider to the list
$ldapProviders.Add($ldapProvider)

# Create the provider group rule
$cmdParams = @{
    Ucs = $ucs;
    LdapProvider = $ldapProvider;
    ModifyPresent = $true;
    Authorization = "enable";
    Descr = "";
    Name = "";
    TargetAttr = "memberOf";
    Traversal = "recursive";
    UsePrimaryGroup = "no"
}
$groupRule = Add-UcsLdapGroupRule @cmdParams

<# --------------------------------------- 4 ------------------------------------------- #>

# Create the provider
$cmdParams = @{
    Ucs = $ucs;
    Name = "DCCAN500DOM4.corp.pbwan.net";
    Basedn = "DC=corp,DC=pbwan,DC=net";
    Rootdn = "CN=SVC-CA-UCSLDAP,OU=SVC Users,OU=_Resource Mgmt,OU=WSPObjects,DC=corp,DC=pbwan,DC=net";
    EnableSSL = "yes";
    FilterValue = "sAMAccountName=`$userid";
    Vendor = "MS-AD";
    Order = 7;
    Key = "Gql!&dGE8B*p"
}

$ldapProvider = Add-UcsLdapProvider @cmdParams

# Add the provider to the list
$ldapProviders.Add($ldapProvider)

# Create the provider group rule
$cmdParams = @{
    Ucs = $ucs;
    LdapProvider = $ldapProvider;
    ModifyPresent = $true;
    Authorization = "enable";
    Descr = "";
    Name = "";
    TargetAttr = "memberOf";
    Traversal = "recursive";
    UsePrimaryGroup = "no"
}
$groupRule = Add-UcsLdapGroupRule @cmdParams

<# ------------------------------------------------------------------------------------- #>


# Create the LDAP provider group
$ldapGlobalConfig = Get-UcsLdapGlobalConfig -Ucs $ucs

$cmdParams = @{
    UCS = $ucs;
    Name = "WSP DCs";
    LdapGlobalConfig = $ldapGlobalConfig
}
$ldapProviderGroup = Add-UcsProviderGroup @cmdParams

# Add the LDAP providers to the LDAP Provider Group
$ldapProviders = @($ldapProviders | Sort-Object Order)
$a = 0
while($a -lt $ldapProviders.Length)
{
    $cmdParams = @{
        Ucs = $ucs;
        ProviderGroup = $ldapProviderGroup;
        ModifyPresent = $true;
        Descr = "";
        Name = $ldapProviders[$a].Name;
        Order = $ldapProviders[$a].Order
    }
    $null = Add-UcsProviderReference @cmdParams

    $a++
}

# Create the LDAP Group Map
$cmdParams = @{
    Ucs = $ucs;
    Name = "CN=SRV-UCS-ADM,OU=Security,OU=Groups,OU=US,OU=DirSync,OU=PWR,OU=Integrations,DC=corp,DC=pbwan,DC=net";
}
$ldapGroupMap = Add-UcsLdapGroupMap @cmdParams

# Add the roles to the LDAP Group Map

$roles = @("read-only","admin")
$a = 0
while($a -lt $roles.Length)
{
    $cmdParams = @{
        Ucs = $ucs;
        Name = $roles[$a];
        LdapGroupMap = $ldapGroupMap;
        Descr = ""
    }
    $newLDAPGroupMapRole = Add-UcsUserRole @cmdParams
    $a++
}

# Creating authentication domain: CORP..."
$cmdParams = @{
    Ucs = $ucs;
    Name = "CORP"
}
$corpAuthDomain = Add-UcsAuthDomain @cmdParams

$cmdParams =  @{
    Ucs = $ucs;
    AuthDomain = $corpAuthDomain;
    Realm = "ldap";
    ProviderGroup = "WSP DCs";
    Use2Factor = "no";
    Confirm = $false;
    Force = $true
}
$null = Set-UcsAuthDomainDefaultAuth @cmdParams
