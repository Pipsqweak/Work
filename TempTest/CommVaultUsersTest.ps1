$metallicUsers = Import-CSV -Path 'C:\Users\kbriney-adm\Downloads\Subscription Usage Month-to-Date_Microsoft 365 - Enterprise_2025-07-02-17-0-52.csv'
$adObjs = Get-ADObject -Filter {mail -like "*"} -Properties *
# $adObjectsWithMailAttr = Get-ADObject -LDAPFilter "(&(objectClass=*)(mail=*))" -Property LastLogonDate,mail,whenCreated
$onMSUsers = @($metallicUsers | Where-Object { $_.'Email address' -match "powereng0.onmicrosoft" })

$sADUsers = [System.Collections.Generic.SortedDictionary[[System.String],[System.Object]]]::new([System.StringComparer]::OrdinalIgnoreCase)

$a = 0
while($a -lt $adObjs.Length)
{
    if(-not $sADUsers.ContainsKey($adObjs[$a].mail))
    {
        $sADUsers.Add($adObjs[$a].mail, $adObjs[$a])
    } `
    else
    {
        Write-Host -ForegroundColor Red ("Duplicate mail: {0}" -f @($adObjs[$a].mail))
    }

    $a++
}

$a = 0
$notFound = [System.Collections.Generic.List[System.Object]]::new()


while($a -lt $metallicUsers.Length)
{
    if($sADUsers.ContainsKey($metallicUsers[$a].EmailAddress))
    {
        if($null -ne $sADUsers[$metallicUsers[$a].EmailAddress].lastLogonTimestamp)
        {
            $metallicUsers[$a].LastLogin = [DateTime]::FromFileTime($sADUsers[$metallicUsers[$a].EmailAddress].lastLogonTimestamp)    # $sADUsers[$metallicUsers[$a].EmailAddress].LastLogonDate
        }
        $metallicUsers[$a].WhenCreated = $sADUsers[$metallicUsers[$a].EmailAddress].whenCreated
    } `
    else
    {
        $notFound.Add($metallicUsers[$a])
    }

    $a++

    if($a % 100 -eq 0)
    {
        Write-Host -NoNewline "."
    }
}

Write-Host



$adObjs = Get-ADObject -Filter {mail -like "*"} -Properties * | Select-Object Name, mail


"(|(objectClass=user)(objectClass=group))"


Get-ADObject "(&((|(objectClass=user)(objectClass=group)))(mail=*))"
