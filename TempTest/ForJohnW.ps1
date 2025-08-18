$text = Get-Clipboard


$sdsTypes = @("Resubmitted","FOC","Rejected","Completed")
$sds = $text -match "^SD\d+"

$copyOfText = $text.Clone()

$recs = [System.Collections.Generic.List[System.Object]]::new()
$sb = [System.Text.StringBuilder]::new()
$a = 0
while($a -lt $sds.Length)
{
    # Write-Host ("A: {0}" -f @($a))
    $null = $sb.Clear()
    $null = $sb.AppendLine($sds[$a])

    $sdStart = $text.IndexOf($sds[$a])
    $d = "" | Select-Object Title, Comment, Date, Time, Type, Record, LocationPhoneNumbers, LocalDateTime

    if($sds[$a] -match "^([^:]+):\s+(\d+/\d+)\s+([\d:ap]+\s+[^\s]+)\s+-\s+(.*)")
    {
        RemoveFromCopy -str $sds[$a]

        $d.Title = $Matches[1]
        $d.Comment = $Matches[4]
        $sdsTypes | ForEach-Object {
            if($d.Comment.Contains($_))
            {
                # Write-Host ("Type: {0}" -f @($_))
                $d.Type = $_
                # break
            }
        }

        $d.Date = $Matches[2]
        $d.Time = $Matches[3]


        $dStr = "{0}/{1}" -f @($d.Date, [DateTime]::Now.Year)

        if($d.Time -match "(\d+)((:)(\d+))?([ap])\s+(.*)")
        {

            $hr = [int32] $Matches[1]
            $min = 0
            if ($null -ne $Matches[4])
            {
                $min = [int32] $Matches[4]
            } `
            else # NOT ($null -ne $Matches[4])
            {
                # Nothing
            }

            if ($Matches[5] -eq "p")
            {
                $hr += 12
            } `
            else # NOT ($Matches[5] -eq "p")
            {
                # Nothing.
            }

            $tStr = "{0}:{1:D2}" -f @($hr, $min)

            $tz = [System.TimeZoneInfo]::Local
            switch($Matches[6])
            {
                "PT" { $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time") }
                Default
                {
                    Write-Host -ForegroundColor Yellow ("Unknown timezone: {0}. Using local time." -f @($Matches[6]))
                }
            }

            $dtStr = "{0} {1}" -f @($dStr, $tStr)

            try
            {
                $dt = [DateTime]::Parse($dtStr)

                try
                {
                    $dt = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($dt, $tz.Id)
                    $d.LocalDateTime = $dt
                }
                catch
                {
                    Write-Host -ForegroundColor Yellow ("Unable to adjust {0} {1} to local time." -f @($dt.ToString(), $tz.DisplayName))
                }
            }
            catch
            {
                Write-Host -ForegroundColor Yellow ("Unable to parse date/time from {0}." -f @($dtStr))
            }
        }

        # Write-Host ("D: {0} T: {1}" -f $Matches[2], $Matches[3])
        $phoneNumbers = [System.Collections.Generic.List[System.String]]::new()
        $d.LocationPhoneNumbers = [System.Collections.Generic.SortedDictionary[System.String, [System.Collections.Generic.List[System.String]]]]::new()
        $location = [String]::Empty
        $i = $sdStart + 1    # Skip the SD definition...
        while(($i -lt $text.Length) -and (-not [String]::IsNullOrEmpty($text[$i].Trim())))
        {
            RemoveFromCopy -str $text[$i]
            $null = $sb.AppendLine($text[$i].Trim())

            if($text[$i] -match "^(\d{11})(-(\d+))?")
            {
                $pStr = ExpandPhoneNumberRange -phoneNumberStr $text[$i]
                if(-not [String]::IsNullOrEmpty($pStr))
                {
                    @($pStr -split ",") | ForEach-Object {
                        $pn = $_.Trim()
                        $h = $phoneNumbers.BinarySearch($pn)
                        if($h -lt 0)
                        {
                            $phoneNumbers.Insert(-bnot $h, $pn)
                        }
                    }
                } `
                else
                {
                    $null = $sb.AppendLine("MALFORMED PHONE NUMBER LIST")
                }
            } `
            else
            {
                $location = $text[$i].Trim()

                AddRecordPhoneNumbers -location $location -phoneNumbers $phoneNumbers -record $d
            }
            $i++
        }

        if($phoneNumbers.Count -gt 0)
        {
            AddRecordPhoneNumbers -location $location -phoneNumbers $phoneNumbers -record $d
        }

        $d.Record = $sb.ToString()
        $recs.Add($d)
        # Write-Host ("Recs: {0}" -f @($recs.Count))
    }
    else
    {
        Write-Host ("Unknown SD??  {0}" -f @($sds[$a]))
    }
    $a++
}

$str = ($copyOfText -join "`r`n").Trim(@("`r","`n"))
while($str.IndexOf("`r`n`r`n`r`n") -ge 0)
{
    $str = $str.Replace("`r`n`r`n`r`n","`r`n`r`n")
}

$null = $sb.Clear()
$copyOfText = $str -split "`r`n"
$copyOfText | ForEach-Object {
    $s = $_.Trim()
    $skipLine = $false
    if (-not [String]::IsNullOrEmpty($s))
    {
        $sdsTypes | ForEach-Object {
            if($s -match ("^{0}" -f @($_)))
            {
                $skipLine = $true
            }
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($s))
    {
        # Nothing.
    }

    if (-not $skipLine)
    {
        $null = $sb.AppendLine($s)
    } `
    else # NOT (-not $skipLine)
    {
        # Nothing.
    }
}
$str = $sb.ToString()
$str = $str.Trim(@("`r","`n"))
while($str.IndexOf("`r`n`r`n`r`n") -ge 0)
{
    $str = $str.Replace("`r`n`r`n`r`n","`r`n`r`n")
}

$str | Set-Clipboard

function RemoveFromCopy
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyString()]
        [System.String]
        $str
    )

    if (-not [String]::IsNullOrEmpty($str))
    {
        $i = $Global:copyOfText.IndexOf($str)
        if ($i -ge 0)
        {
            $Global:copyOfText[$i] = [String]::Empty
        } `
        else # NOT ($i -ge 0)
        {
            # Nothing.
        }
    } `
    else # NOT (-not [String]::IsNullOrEmpty($str))
    {
        # Nothing.
    }
}

function AddRecordPhoneNumbers
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyString()]
        [System.String]
        $location,

        [Parameter(Mandatory=$true, Position=1)]
        [System.Collections.Generic.List[System.String]]
        $phoneNumbers,

        [Parameter(Mandatory=$true, Position=2)]
        [System.Object]
        $record
    )

    if ([String]::IsNullOrEmpty($location))
    {
        $location = "NotSpecified"
    } `
    else
    {
        # Nothing. use $location as is...
    }

    if (-not $record.LocationPhoneNumbers.ContainsKey($location))
    {
        $record.LocationPhoneNumbers.Add($location, [System.Collections.Generic.List[System.String]]::new())
    } `
    else
    {
        # Nothing, already have a location = $location.
    }

    $phoneNumbers | Foreach-Object {
        $h = $record.LocationPhoneNumbers[$location].BinarySearch($_)
        if($h -lt 0)
        {
            $record.LocationPhoneNumbers[$location].Insert(-bnot $h, $_)
        }
    }
    $phoneNumbers.Clear()
}

function ExpandPhoneNumberRange
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [System.String]
        $phoneNumberStr
    )

    $isError = $false
    $phoneNumberStr = $phoneNumberStr.TrimEnd(@(',', ' '))
    $pnStrs = @($phoneNumberStr -split "," | ForEach-Object { $_.Trim() })
    $pnList = [System.Collections.Generic.List[System.String]]::new()
    $retval = $null

    $a = 0
    while((-not $isError) -and ($a -lt $pnStrs.Length))
    {
        <#
            Ensure $pnStrs[$a] is either:
                1) a single phone number, or
                2) a range of phone numbers in the form:
        #>
        if($pnStrs[$a] -match "(\d{11})(-(\d+))?")
        {
            $startNumber = $Matches[1]     # This is the phone number starting range.
            if ($Matches.Count -eq 4)
            {
                <#
                    13466991284-1285
                        1346699 = $startRangePrefix
                           1284 = $startRangeDigits
                           1285 = $endRangeDigits
                #>
                $endRangeDigits = $Matches[3]
                $startRangeDigits = $startNumber.SubString($startNumber.Length - $endRangeDigits.Length)
                $startRangePrefix = $startNumber.SubString(0, $startNumber.Length - $endRangeDigits.Length)

                # Convert the strings to integers
                try
                {
                    $endRange = [int32] $endRangeDigits
                    $startRange = [int32] $startRangeDigits

                    if($endRange -gt $startRange)
                    {
                        # Create a format string to deal with leading zeroes in $startRangeDigits
                        $fmtStr = "{{0}}{{1:D{0}}}" -f @($startRangeDigits.Length)
                        # Add all the phone numbers in the range to the list of phone numbers
                        while($startRange -le $endRange)
                        {
                            $pnList.Add(($fmtStr -f @($startRangePrefix, $startRange)))
                            $startRange++
                        }
                    } `
                    else
                    {
                        Write-Host -ForegroundColor Red ("ERROR: phone number range is malformed. {0} -lt {1}" -f @($endRange, $startRange))
                        $isError = $true
                    }
                }
                catch
                {
                    Write-Host -ForegroundColor Red ("ERROR: phone number range is malformed. Failed to convert digits to integers.  `$pnStrs[{0}]: [{1}]" -f @($a, $pnStrs[$a]))
                    $isError = $true
                }
            } `
            else # NOT ($Matches.Count -eq 4)
            {
                $pnList.Add($startNumber)
            }
        } `
        else
        {
            Write-Host -ForegroundColor Red ("ERROR: phone number range is malformed. `$pnStrs[{0}]: [{1}] does not match regular expression." -f @($a, $pnStrs[$a]))
            $isError = $true
        }

        $a++
    }
#Write-Host ("`$isError: {0}" -f @($isError))
    # If there was no error, then return a new string where all the ranges have been expanded.
    if (-not $isError)
    {
        $retval = $pnList -join ", "
    } `
    else # NOT ($isError)
    {
        Write-Host -ForegroundColor Red ("`$phoneNumberStr: {0}" -f @($phoneNumberStr))
    }

    return $retval
}


<#

# Define the input string
$input = "5/18 9 PT"

# Parse the date and time
$pattern = "M/dd h tt z"
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$timeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")

# Convert the input string to DateTime
$dateTime = [datetime]::ParseExact($input, $pattern, $culture)

# Adjust for the time zone
$dateTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($dateTime, $timeZone.Id)

# Output the DateTime object
Write-Output $dateTime
#>

<#
# Import the CSV file
$csvData = Import-Csv -Path "E:\jwilliams\Batch2\updated_file.csv" -Delimiter ","

# Loop through each row and assign UPN to phone number
foreach ($row in $csvData) {
    Write-Host -NoNewline ("Getting user with phone number: {0}..." -f @($row.PhoneNumber))
    try
    {
        $user = Get-CSOnlineUser -Filter ("LineUri -eq 'tel:+{0}'" -f @($row.PhoneNumber))
    }
    catch
    {
        Write-Host -ForegroundColor Red ("`r`n`tException occurred getting user with phone number: {0}" -f @($row.PhoneNumber))
    }

    if($null -ne $user)
    {
        $row.UPN = $user.UserPrincipalName
        Write-Host -ForegroundColor Green $user.UserPrincipalName
    }
    else
    {
        Write-Host -ForegroundColor Red "not found"
    }
}

# Export the updated data back to the CSV file

$csvData | Export-Csv -Path "E:\jwilliams\Batch2\updated_file.csv" -Delimiter "," -NoTypeInformation



$phoneNumberAssignments = [System.Collections.Generic.List[System.Object]]::new()

do
{
    Write-Host ("Skipping for {0} records." -f @($phoneNumberAssignments.Count))
    $t = @(Get-CsPhoneNumberAssignment -Skip $phoneNumberAssignments.Count)
    if($t.Length -gt 0)
    {
        Write-Host ("Got {0} records..." -f @($t.Length))
        $t | Foreach-Object {
            $phoneNumberAssignments.Add($_)
        }
    }
}
while($t.Length -gt 0)

$data = [System.Collections.Generic.List[System.Object]]::new()
$failedLookup = [System.Collections.Generic.List[System.Object]]::new()
$a = 0
while($a -lt $phoneNumberAssignments.Count)
{
    if((($a+1) % 10) -eq 0)
    {
        Write-Host ("A: {0} Data: {1} Failed: {2}" -f @($a, $data.Count, $failedLookup.Count))
    }

    $user = GetPhoneNumberLocationData -pn $phoneNumberAssignments[$a].TelephoneNumber.Replace("+","")

    if($null -ne $user)
    {
        $data.Add($d)
    }
    else
    {
        $failedLookup.Add($phoneNumberAssignments[$a])
    }
    $a++
}

# $phoneNumberAssignments[$a].TelephoneNumber.Replace("+","")

function GetPhoneNumberLocationData
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [String]
        $pn
    )

    $d = $null
    $pnRecord = $phoneNumberAssignments | Where-Object { $_.TelephoneNumber -match $pn }
    if($null -ne $pnRecord)
    {
        try
        {
            $user = Get-CSOnlineUser -Filter ("LineUri -eq 'tel:{0}'" -f @($pnRecord.TelephoneNumber)) -ErrorAction Stop
            $d = Select-Object PhoneNumber, User, Country, State, City, Street, LocationID, CivicAddressID
            $d = [PSCustomObject]@{
                PhoneNumber = $pnRecord.TelephoneNumber.Replace("+","")
                User = $user.UserPrincipalName
                Country = $user.Country
                State = $user.StateOrProvince
                City = $user.City
                Street = $user.Street
                LocationID = $pnRecord.LocationId
                CivicAddressID = $pnRecord.CivicAddressId
            }

            if([String]::IsNullOrEmpty($d.Country))
            {
                $d.Country = $pnRecord.IsoCountryCode
            }

            if([String]::IsNullOrEmpty($d.State))
            {
                $d.State = $pnRecord.IsoSubdivision
            }

            if([String]::IsNullOrEmpty($d.City))
            {
                $d.State = $pnRecord.City
            }
        }
        catch
        {
            # $failedLookup.Add($phoneNumberAssignments[$a])
        }
    }

    return $d
}
#>
