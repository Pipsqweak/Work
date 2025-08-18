function NewNode
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Microsoft.Teams.ConfigAPI.Cmdlets.Generated.Models.SkypeTelephoneNumberMgmtCmdletAcquiredTelephoneNumber]
        $pnAssignment,

        [Parameter(Mandatory=$true, Position=0)]
        [System.Object]
        $user
    )

    $d = [PSCustomObject]@{
        PhoneNumber = $pnAssignment.TelephoneNumber.Replace("+","")
        User = $user.UserPrincipalName
        Country = $user.Country
        State = $user.StateOrProvince
        City = $user.City
        Street = $user.Street
        LocationID = $pnAssignment.LocationId
        CivicAddressID = $pnAssignment.CivicAddressId
    }

    if([String]::IsNullOrEmpty($d.Country))
    {
        $d.Country = $pnAssignment.IsoCountryCode
        if($d.Country -eq "US")
        {
            $d.Country = "United States"
        }
        elseif($d.Country -eq "CA")
        {
            $d.Country = "Canada"
        }
    }

    if([String]::IsNullOrEmpty($d.State))
    {
        $d.State = $pnAssignment.IsoSubdivision
    }
    elseif($states.ContainsKey($d.State))
    {
        $d.State = $states[$d.State]
    }

    if([String]::IsNullOrEmpty($d.City))
    {
        $d.City = $pnAssignment.City
    }

    if(-not [String]::IsNullOrEmpty($d.Street))
    {
        $l = $d.Street -split "`n"
        $d.Street = @($l | Foreach-Object { $_.Trim() }) -join ", "
    }

    return $d
}

Connect-MicrosoftTeams

$states = @{
    "AB" = "Alberta"
    "AL" = "Alabama"
    "AK" = "Alaska"
    "AZ" = "Arizona"
    "AR" = "Arkansas"
    "CA" = "California"
    "CO" = "Colorado"
    "CT" = "Connecticut"
    "DE" = "Delaware"
    "DC" = "District of Columbia"
    "EN" = "England"
    "FL" = "Florida"
    "GA" = "Georgia"
    "HI" = "Hawaii"
    "ID" = "Idaho"
    "IL" = "Illinois"
    "IN" = "Indiana"
    "IA" = "Iowa"
    "KS" = "Kansas"
    "KY" = "Kentucky"
    "LA" = "Louisiana"
    "ME" = "Maine"
    "MD" = "Maryland"
    "MA" = "Massachusetts"
    "MI" = "Michigan"
    "MN" = "Minnesota"
    "MS" = "Mississippi"
    "MO" = "Missouri"
    "MT" = "Montana"
    "NE" = "Nebraska"
    "NV" = "Nevada"
    "NH" = "New Hampshire"
    "NJ" = "New Jersey"
    "NM" = "New Mexico"
    "NY" = "New York"
    "NC" = "North Carolina"
    "ND" = "North Dakota"
    "OH" = "Ohio"
    "OK" = "Oklahoma"
    "ON" = "Ontario"
    "OR" = "Oregon"
    "PA" = "Pennsylvania"
    "RI" = "Rhode Island"
    "SC" = "South Carolina"
    "SD" = "South Dakota"
    "TN" = "Tennessee"
    "TX" = "Texas"
    "UT" = "Utah"
    "VT" = "Vermont"
    "VA" = "Virginia"
    "WA" = "Washington"
    "WV" = "West Virginia"
    "WI" = "Wisconsin"
    "WY" = "Wyoming"
}

Write-Host "Getting all phone number assignments...."
$phoneNumberAssignments = [System.Collections.Generic.SortedDictionary[[System.String], [Microsoft.Teams.ConfigAPI.Cmdlets.Generated.Models.SkypeTelephoneNumberMgmtCmdletAcquiredTelephoneNumber]]]::new()

do
{
    try
    {
        $t = @(Get-CsPhoneNumberAssignment -Skip $phoneNumberAssignments.Count -ErrorAction Stop)
        if($t.Length -gt 0)
        {
            Write-Host ("`tGot {0} records..." -f @($t.Length))
            $t | Foreach-Object {
                $telNumber = "tel:{0}" -f @($_.TelephoneNumber)
                if(-not $phoneNumberAssignments.ContainsKey($telNumber))
                {
                    $phoneNumberAssignments.Add($telNumber, $_)
                }
                else
                {
                    Write-Host -ForegroundColor Red ("Duplicate telephone number: {0}" -f @($telNumber))
                }
            }
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red ("Failed to acquire block of phone number assignment after {0}." -f @($phoneNumberAssignments.Count))
        $phoneNumberAssignments = $null
    }
}
while(($null -ne $phoneNumberAssignments) -and ($t.Length -gt 0))

$usersWithTelephoneNumbers = [System.Collections.Generic.SortedDictionary[[System.String], [System.Object]]]::new()

if($null -ne $phoneNumberAssignments)
{
    Write-Host "Getting all CS Online Users...."
    try
    {
        $users = @(Get-CSOnlineUser -ErrorAction Stop)
        $users | Foreach-Object {
            if(-not [String]::IsNullOrEmpty($_.LineUri))
            {
                if(-not $usersWithTelephoneNumbers.ContainsKey($_.LineUri))
                {
                    $usersWithTelephoneNumbers.Add($_.LineUri, $_)
                }
            }
        }
    }
    catch
    {
        Write-Host -ForegroundColor Red "Failed to acquire CS Online Users..."
        $users = @()
    }

    if($usersWithTelephoneNumbers.Length -gt 0)
    {
        Write-Host ("`tLoaded {0} users whom have phone numbers." -f @($usersWithTelephoneNumbers.Count))
        $data = [System.Collections.Generic.List[System.Object]]::new()
        $failedLookup = [System.Collections.Generic.List[System.Object]]::new()
        $a = 0
        $telephoneNumbers = @($phoneNumberAssignments.Keys)
        while($a -lt $telephoneNumbers.Length)
        {
            if((($a+1) % 10) -eq 0)
            {
                Write-Host ("A: {0} Data: {1} Failed: {2}" -f @($a, $data.Count, $failedLookup.Count))
            }

            if($usersWithTelephoneNumbers.ContainsKey($telephoneNumbers[$a]))
            {
                $node = NewNode -pnAssignment $phoneNumberAssignments[$telephoneNumbers[$a]] -user $usersWithTelephoneNumbers[$telephoneNumbers[$a]]

                # $user = GetPhoneNumberLocationData -pn $phoneNumberAssignments[$a].TelephoneNumber.Replace("+","")

                $data.Add($node)
            }
            else
            {
                $failedLookup.Add($telephoneNumbers[$a] )
            }
            $a++
        }

        $data | Convertto-CSV -Delimiter "`t" -NoTypeInformation | Set-Clipboard
        Write-Host ("{0} records loaded into clipboard..." -f @($data.Count))
    }
}
