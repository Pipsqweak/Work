$Script:validFunctions = [System.Collections.Generic.List[System.String]]::new()
$Script:maxOperationRetries = 3
$Script:actionRetriesWaitSeconds = 5

# Need to make sure the logging functions are included...

function CatchActionException
{
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false, Position=0)]
        [Int32]
        $tries = 1,

        [Parameter(Mandatory=$false, Position=1)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=3)]
        [Switch]
        $IgnoreException = $false
    )

    $good2Go = $true
    if($tries -lt $maxTries)
    {
        if(($tries -eq 1) -and (-not $IgnoreException))
        {
            LogWarning "Operation failed."
            if($maxTries -gt 1)
            {
                LogWarning ("Pausing {0} seconds before retrying (max {1} attempts)" -f @($secondsToPause, $maxTries))
            } `
            else
            {
                # Nothing only show the message if we are going to retry.
            }
        } `
        else
        {
            # Nothing, only want to display a message once.
        }
        Start-Sleep -Seconds $secondsToPause
    } `
    else
    {
        $good2Go = $false

        if(-not $IgnoreException)
        {
            LogError "Operation failed" -NewLine -NoNewLine
            if($tries -gt 1)
            {
                LogError (" after {0} tries." -f @($tries)) -NoNewLine
            } `
            else
            {
                # Nothing
            }
            $errStr = $Error[0] | Out-String
            LogError ("{0}" -f @($errStr)) -NewLine
        } `
        else
        {
            # Nothing, do as we are told...ignore the error.
        }
    }

    return $good2Go
}

function ReTryCatch
{
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $callee,

        [Parameter(Mandatory=$false, Position=1)]
        [HashTable]
        $funcParameters,

        [Parameter(Mandatory=$false, Position=2)]
        [Int32]
        $maxTries = $Script:maxOperationRetries,

        [Parameter(Mandatory=$false, Position=3)]
        [Int32]
        $secondsToPause = $Script:actionRetriesWaitSeconds,

        [Parameter(Mandatory=$false, Position=4)]
        [Switch]
        $IgnoreException,

        [Parameter(Mandatory=$false, Position=5)]
        [Switch]
        $Simulated
    )

    if($null -eq $funcParameters)
    {
        $funcParameters = @{
            ErrorAction = [System.Management.Automation.ActionPreference]::Stop
        }
    } `
    else
    {
        # Nothing, we were provided function parameters for $callee
    }

    if(-not $funcParameters.ContainsKey("ErrorAction"))
    {
        $funcParameters.Add("ErrorAction", [System.Management.Automation.ActionPreference]::Stop)
    } `
    else
    {
        # Nothing, ErrorAction already specified.
    }

    # Capture vital information is $result which is returned to the caller.
    $result = "" | Select-Object ActionComplete, Good2Go, ReturnValue, Tries, Error
    $result.Good2Go = $true              # .Good2Go does NOT imply the result of & $callee was successful, just that & $callee did not throw an exception or the call was simulated.  It's up to the caller to check .ReturnValue
    $result.ReturnValue = $null          # ALWAYS an array of the results of calling $callee
    $result.ActionComplete = $false      # Did $callee complete without an exception?
    $result.Error = $null                # $Error[0].ErrorRecord if the call failed
    $result.Tries = 0                    # How many times was $callee called?


    $idx = $Script:validFunctions.BinarySearch($callee)
    $calleeIsValid = ($idx -ge 0)

    $Error.Clear()
    if(-not $calleeIsValid)
    {
        try
        {
            $calleeIsValid = ($null -ne (Get-Command -Name $callee -ErrorAction Stop)) -or ($null -ne (Get-Item -Path ("Function:\{0}" -f @($callee)) -ErrorAction Stop))
            if($calleeIsValid)
            {
                $Script:validFunctions.Insert(-bnot $idx, $callee)
            } `
            else
            {
                # Nothing, no need to record an invalid callee.
            }
        }
        catch
        {
            # Nothing, a message will be displayed later
        }
    } `
    else
    {
        # Nothing....
    }

    if($calleeIsValid)
    {
        do
        {
            $result.Tries++
            $Error.Clear()

            if(-not $Simulated.IsPresent)
            {
                try
                {
                    # To ensure consistency, I'll always return an array...
                    $result.ReturnValue = @(& $callee @funcParameters)
                    $result.ActionComplete = $true
                }
                catch
                {
                    $result.Error = $Error[0]
                    $result.Good2Go = CatchActionException -tries $result.Tries -maxTries $maxTries -secondsToPause $secondsToPause -IgnoreException:$IgnoreException.IsPresent
                }
            } `
            else
            {
                # Nothing, just simulating...
            }
        } while((-not $Simulated.IsPresent) -and $result.Good2Go -and (-not $result.ActionComplete) -and ($result.Tries -lt $maxTries))
    } `
    else
    {
        LogError ("No cmdlet or function named {0} found." -f @($callee))
        $result.Good2Go = $false
    }

    return $result
}
