[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $JSONArgsFile
)

<#
    This script pulls a list of snaplock volumes from the filer, then uses the retention options set on the volume
    to determine which snapshots are safe to remove.  This is likely overkill since I *should* be able to *try* to
    delete all snapshots and the filer should simply prevent it since some of the snapshots will not be older than
    their retention period.  I don't like errors, so I'll just select which ones to delete and go one at a time.

    The script loads setting from a provide .json file.  The following are the setting expected in the file.


    *NOTE* If the following information is used to seed a .json file, remove any line starting with "--"

    {
        -- This is the only *required* parameter.  All other parameters have default values
        "SMSnaplockFilerName":  "TDCPRDNAS1",

        -- Volume names to ignore.  Default: none
        "VolumesToIgnore":  [
                                "lockvault_log_29032021_162237"
                            ],

        -- Where to write log messages to:  Default: Scriptfolder\ScriptName.log
        "LogPath":  "E:\\Scripts\\Logs\\SnaplockCleaner\\Log.txt",

        -- How many days of log messages to retain in the log file:  Default: 365
        "LogRetention":  7,

        -- SMTP server used to send email alerts.  Default: smtp.powereng.com
        "SMTPServer":  "smtp.powereng.com",

        -- Email alerts will be sent from this address.  Default: Snaplock Snapshot Cleaner <snapcleaner@powereng.com>
        "FromAddress":  "Snaplock Snapshot Cleaner <snapcleaner@powereng.com>",

        -- Email alerts will be sent to these addresses:  Default: itstorage@powereng.com
        "ToAddresses":  [
                            "IT Storage <itstorage@powereng.com>"
                        ]
    }
#>
#>


# Keep track of whether or not we have all the config parameters we need.
$haveRunConfig = $false

# The first time Log is called after configuration data is loaded, it tries to clean
#  up the log by removing old entries from the log.  Keep track of whether that has
#  been completed or not.
$Global:logCleaned = $false

# If an error or warning is logged, keep track of that so we can send an email
#    alerting admins to take a look.
$Global:loggedErrorOrWarning = $false

# Global StringBuilder to log message in until we can write to the log file.
#  If no connection to the log file is established, the logged messages
#  are emailed to administrators.
$Global:sbLogBuffer = [System.Text.Stringbuilder]::new()

function Log($message)
{
    if(($Global:haveRunConfig) -and (-not $Global:logCleaned))
    {
        # Keep log entries from the last $Global:config.LogRetention days
        $retainAfter = [DateTime]::Now.AddDays(-($Global:config.LogRetention)).ToString("yyyyMMdd")

        # Read the log, and filter out old entries, then overwrite the log with the newer content
        @(Get-Content -Path $Global:config.LogPath | Where-Object { $_ -gt $retainAfter }) | Set-Content -Path $Global:config.LogPath -Force
        
        # Only clean the log once per run
        $Global:logCleaned = $true
    }

    if(-not [String]::IsNullOrEmpty($message))
    {
        # Append the new message to the log.
        $logMessage = "{0}: {1}" -f @([DateTime]::Now.ToString("yyyyMMdd HH:mm:ss"), $message)

        # Try to log the message to $Global:config.LogPath, but if it fails, capture the message in a StringBuilder.
        try
        {
            # If there is anything in the StringBuilder, then try to dump it to the log file.
            if($Global:sbLogBuffer.Length -gt 0)
            {
                # Strip cr-lf off the end of the string...
                $Global:sbLogBuffer.ToString().TrimEnd(@([char]13, [char]10)) | Out-File -Encoding ascii -Append -FilePath $Global:config.LogPath -ErrorAction Stop
                [void] $Global:sbLogBuffer.Clear()
            }
            $logMessage | Out-File -Encoding ascii -Append -FilePath $Global:config.LogPath -ErrorAction Stop
        }
        catch
        {
            # If we fail to write to the log file, then just append the message to the StringBuilder and echo the message to the console.
            if($null -ne $Global:sbLogBuffer)
            {
                [void] $Global:sbLogBuffer.AppendLine($logMessage)
                Write-Output $logMessage
            }
        }

        $Global:loggedErrorOrWarning = $Global:loggedErrorOrWarning -or ($message -match "error|warning")
    }
}

# Initialize $config to an empty object.
$Global:config = "" | Select-Object SMSnaplockFilerName, VolumesToIgnore, LogPath, LogRetention, SMTPServer, FromAddress, ToAddresses

# Flag to signal configuration data load success
$configOk = $true

# Try to load the configuration data.
if(-not [String]::IsNullOrEmpty($JSONArgsFile))
{
    if(Test-Path -Path $JSONArgsFile)
    {
        try
        {
            $Global:config = Get-Content -Path $JSONArgsFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            Log ("[INFO   ] Loaded configuration from {0}" -f @($JSONArgsFile))
        }
        catch
        {
            Log ("[ERROR  ] Failed to load configuration data from {0}." -f @($JSONArgsFile))
        }
    }
    else
    {
        Log ("[ERROR ] Configuration .json file: {0} does not exist." -f @($JSONArgsFile))
    }
}
else
{
    Log "[ERROR ] Missing argument for .json configuration file."
}

# Check to see if LogPath was defined in the configuration data
if(-not ([String]::IsNullOrEmpty($Global:config.LogPath)))
{
    Log ("[INFO   ] Logging to {0}" -f @($Global:config.LogPath))
}
else
{
    Log "[WARNING] Configuration data missing 'LogPath'."
    if((-not [String]::IsNullOrEmpty($PSScriptRoot)) -and (-not ([String]::IsNullOrEmpty($MyInvocation.MyCommand.Name))))
    {
        $Global:config.LogPath = "{0}\{1}.log" -f @($PSScriptRoot, [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name))
        Log ("[WARNING] Defaulting to [{0}]" -f @($Global:config.LogPath))
    }
}

# Check to see if LogRetention was defined in the configuration data
if(($null -ne $Global:config.LogRetention) -and ($Global:config.LogRetention -is [int]))
{
    Log ("[INFO   ] Log retention {0} days" -f @($Global:config.LogRetention))
}
else
{
    Log "[WARNING] Configuration data missing 'LogRetention'. Defaulting to 365 days."
    $Global:config.LogRetention = 365
}

# Check to see if SMSnaplockFilerName was defined in the configuration data
if(-not [String]::IsNullOrEmpty($Global:config.SMSnaplockFilerName))
{
    Log ("[INFO   ] 7-Mode Snaplock filer: {0}" -f @($Global:config.SMSnaplockFilerName))
}
else
{
    Log "[ERROR  ] Configuration data missing 'SMSnaplockFilerName'."

    # This is the one parameter that is a must.  No 7-mode snaplock filer, we can do nothing.
    $configOk = $false
}

# Check to see if VolumesToIgnore was defined in the configuration data
if($null -eq $Global:config.VolumesToIgnore)
{
    Log "[WARNING] Configuration data missing 'VolumesToIgnore'.  Defaulting to none."
    $Global:config.VolumesToIgnore = @()
}
elseif($Global:config.VolumesToIgnore -is [Array])
{
    foreach($v2i in $Global:config.VolumesToIgnore)
    {
        Log ("[INFO   ] Ignoring volume [{0}]" -f @($v2i))
    }
}
else
{
    Log "[WARNING] Configuration data problem with 'VolumesToIgnore'. Defaulting to none."
    $Global:config.VolumesToIgnore = @()
}

# Check to see if ToAddresses was defined in the configuration data
if($null -eq $Global:config.ToAddresses)
{
    Log "[WARNING] Configuration data missing 'ToAddresses'.  Defaulting to itstorage@powereng.com."
    # $Global:config.ToAddresses = @("IT Storage <itstorage@powereng.com>")
    $Global:config.ToAddresses = @("Briney,Ken <ken.briney@powereng.com>")
}
elseif($Global:config.ToAddresses -is [Array])
{
    foreach($recipient in $Global:config.ToAddresses)
    {
        Log ("[INFO   ] Email recipient: {0}" -f @($recipient))
    }
}
else
{
    Log "[WARNING] Problem with 'ToAddresses'. Defaulting to itstorage@powereng.com."
    # $Global:config.ToAddresses = @("IT Storage <itstorage@powereng.com>")
    $Global:config.ToAddresses = @("Briney,Ken <ken.briney@powereng.com>")
}

# Check to see if SMTPServer was defined in the configuration data
if(-not [String]::IsNullOrEmpty($Global:config.SMTPServer))
{
    Log ("[INFO   ] SMTP Relay: {0}" -f @($Global:config.SMTPServer))
}
else
{
    Log "[WARNING] Configuration data missing 'SMTPServer'.  Defaulting to smtp.powereng.com."
    $Global:config.SMTPServer = "smtp.powereng.com"
}

# Check to see if FromAddress was defined in the configuration data
if(-not [String]::IsNullOrEmpty($Global:config.FromAddress))
{
    Log ("[INFO   ] Email From: {0}" -f @($Global:config.FromAddress))
}
else
{
    Log "[WARNING] Configuration data missing 'FromAddress'.  Defaulting to snapcleaner@powereng.com."
    $Global:config.FromAddress = "Snaplock Snapshot Cleaner <snapcleaner@powereng.com>"
}

$Global:haveRunConfig = $configOk

<#
    Used to seed the configuration .json file

    $config = "" | Select-Object SMSnaplockFilerName, VolumesToIgnore, LogPath, LogRetention, SMTPServer, FromAddress, ToAddresses
    $Global:config.SMSnaplockFilerName = "TDCPRDNAS1"
    $Global:config.VolumesToIgnore = @("lockvault_log_29032021_162237")
    $Global:config.LogPath = "E:\Scripts\Logs\SnaplockCleaner\Log.txt"
    $Global:config.LogRetention = 7
    $Global:config.SMTPServer = "smtp.powereng.com"
    $Global:config.FromAddress = "Snaplock Snapshot Cleaner <snapcleaner@powereng.com>"
    $Global:config.ToAddresses = @("Briney,Ken <ken.briney@powereng.com>")
#>


# Connect to the 7-mode filer using the credentials the script is running under.
$snaplockFiler = $null
try
{
    $snaplockFiler = Connect-NaController -Name $Global:config.SMSnaplockFilerName -RPC -Transient -ErrorAction Stop
}
catch
{
    Log ("[ERROR  ] unable to connect to {0}." -f @($Global:config.SMSnaplockFilerName))
}

if($null -ne $snaplockFiler)
{
    Log ("[INFO   ] Connected to {0}." -f @($Global:config.SMSnaplockFilerName))

    # Get an array of all snaplock volumes
    $snaplockVolumes = @()
    try
    {
        @(Get-NaVol -Controller $snaplockFiler -ErrorAction Stop | Where-Object { ($null -ne $_.SnaplockType) -and ($Global:config.VolumesToIgnore -notcontains $_.Name) }) | ForEach-Object { $snaplockVolumes += $_ }
    }
    catch
    {
        Log ("[ERROR  ] Failed to get a list of volumes from {0}." -f @($Global:config.SMSnaplockFilerName))
    }

    if($snaplockVolumes.Length -gt 0)
    {
        Log ("[INFO   ] {0} snaplock volumes found." -f @($snaplockVolumes.Length))
        <#
            The following loop processes each snaplock volume determining which snapshots should be removed based on the retention.
            options assigned to the volume.  If a snapshot is selected to be removed, it is added the the list $snapshotsToRemove.
        #>

        $snapshotsToRemove = [System.Collections.Generic.List[Object]]::new()

        $a = 0
        while($a -lt $snaplockVolumes.Length)
        {
            Log ("[INFO   ] Checking {0} snapshots..." -f @($snaplockVolumes[$a].Name))

            # Retrieve the options set on the volume in the form of a hashtable
            $volOptions = $null
            try
            {
                $volOptions = Get-NaVolOption -Controller $snaplockFiler -Name $snaplockVolumes[$a].Name -Hashtable -ErrorAction Stop
            }
            catch
            {
                Log ("[ERROR  ] Unable to retrieve volume options for {0}." -f @($snaplockVolumes[$a].Name))
            }

            if($null -ne $volOptions)
            {
                if($volOptions -is [Hashtable])
                {
                <#
                    From: https://library.netapp.com/ecmdocs/ECMP1511537/html/man1/na_vol.1.html

                    snaplock_default_period: min | max | infinite <count>d|m|y
                        min: snaplock_minimum_period is used as the default retention period
                        max: snaplock_maximum_period is used as the default retention period
                        infinite: a retention period that never expires will be used
                        ^([0-9]+)([shdmy])$: an explicit value defines the retention period
                #>
                    if($volOptions.ContainsKey('snaplock_default_period'))
                    {
                        $defaultRetentionPeriod = $volOptions['snaplock_default_period']
                        Log ("[INFO   ] ... retention period: {0}" -f @($defaultRetentionPeriod))

                        $volRetention = $null
                        if($defaultRetentionPeriod -match "^min|max$")
                        {
                            # Construct the name of the key that defines the retention period
                            $retentionOption = "snaplock_{0}imum_period" -f @($defaultRetentionPeriod)
                            Log ("[INFO   ] ... retention option: {0}" -f @($retentionOption))
                            
                            if($volOptions.ContainsKey($retentionOption))
                            {
                                $volRetention = $volOptions[$retentionOption]
                            }
                            else
                            {
                                Log ("[WARNING] Volume options for {0} does not contain a value for {1}." -f @($snaplockVolumes[$a].Name, $retentionOption))
                            }
                        }
                        else
                        {
                            # $volRetention might end up being set to infinite.  If that is the cause, then code below will log a warning
                            #   because "infinite" will not -match "^([0-9]+)\s*([shdmy])$".  So I decided not to use more code to filter
                            #   out "infinite" specifically.
                            $volRetention = $defaultRetentionPeriod
                        }

                        if($null -ne $volRetention)
                        {
                            Log ("[INFO   ] ... volume retention: {0}" -f @($volRetention))

                            # Parse $volRetention with a regular expression
                            #   $Matches[1] = numeric value defining the number of periods
                            #   $Matches[2] = retention period (s: seconds, h: hours, d: days, m: months, y: years)
                            if($volRetention -match "^([0-9]+)\s*([shdmy])$")
                            {
                                <#
                                    To calculate the retention date, I'll use 2 datetime objects and a timespan object
                                        $dtNow: Now
                                        $dtFuture: Now + $volRetention
                                        $retentionTimeSpan: $dtFuture - $dtNow

                                    When processing a snapshot, I'll add $retentionTimespan to the date/time the snapshot was created and if
                                    the resulting value is prior to now, the snapshot is expired and can be deleted.
                                #>

                                # Initialize date/time objects used to calculate retention dates.
                                $dtNow = [DateTime]::Now
                                $dtFuture = [DateTime]::Now   # Initialize here so it exists outside the switch statement
                                switch($Matches[2])
                                {
                                    "y" { $dtFuture = $dtNow.AddYears($Matches[1]) }
                                    "m" { $dtFuture = $dtNow.AddMonths($Matches[1]) }
                                    "d" { $dtFuture = $dtNow.AddDays($Matches[1]) }
                                    "h" { $dtFuture = $dtNow.AddHours($Matches[1]) }
                                    "s" { $dtFuture = $dtNow.Addseconds($Matches[1]) }
                                }

                                # Just making sure $dtFuture really is in the future
                                if($dtFuture -gt $dtNow)
                                {
                                    # Get a timespan object we can use to add to the creation date/time for each snapshot to determine if it should be deleted or not.
                                    $retentionTimeSpan = $dtFuture - $dtNow
                                    Log ("[INFO   ] ... retention timespan: {0}" -f @($retentionTimeSpan.ToString()))

                                    # Get an array of all the snapshots for the current volume
                                    $volSnapshots = @()
                                    try
                                    {
                                        @(Get-NaSnapshot -Controller $snaplockFiler -TargetName $snaplockVolumes[$a].Name -ErrorAction Stop) | ForEach-Object { $volSnapshots += $_ }
                                        Log ("[INFO   ] ... {0} snapshots..." -f @($volSnapshots.Length))
                                    }
                                    catch
                                    {
                                        Log ("[ERROR  ] Unable to retrieve snapshots for {0}." -f @($snaplockVolumes[$a].Name))
                                    }

                                    # Loop through this volume's snapshots, recording which ones are expired.
                                    $b = 0
                                    while($b -lt $volSnapshots.Length)
                                    {
                                        # If the snapshot is expired, then add it to the list of snapshots to delete.
                                        if(($volSnapshots[$b].Created + $retentionTimeSpan) -lt $dtNow)
                                        {
                                            Log ("[INFO   ] ... {0}) {1} : Created: {2} : Expired: {3}  -- to be removed." -f @(($snapshotsToRemove.Count + 1), $volSnapshots[$b].Name, $volSnapshots[$b].Created.ToString("yyyy-MM-dd HH:mm:ss"), ($volSnapshots[$b].Created + $retentionTimeSpan).ToString("yyyy-MM-dd HH:mm:ss")))
                                            $snapshotsToRemove.Add($volSnapshots[$b])
                                        }
                                        $b++
                                    }
                                }
                                else
                                {
                                    # unable to calculate retention timespan
                                    Log ("[WARNING] Unable to calculate retention timespan for {0}" -f @($snaplockVolumes[$a].Name))
                                }
                            }
                            else
                            {
                                # Decide to alter the message for infinite retention because I thought it might be interesting.  And besides, it's not like
                                #   the retention couldn't be determined, we did determine the retention -- it's INFINITE!   OUCH!!
                                if($volRetention -eq "infinite")
                                {
                                    Log ("[INFO   ] Skipping volume {0} with infinite retention!  OUCH!!" -f @($snaplockVolumes[$a].Name))
                                }
                                else
                                {
                                    Log ("[WARNING] Unable to determine volume retention for {0} using retention value {1}" -f @($snaplockVolumes[$a].Name, $volRetention))
                                }
                            }
                        }
                        else
                        {
                            Log ("[WARNING] Unable to determine volume retention for {0}" -f @($snaplockVolumes[$a].Name))
                        }
                    }
                    else
                    {
                        Log ("[WARNING] Volume options for {0} does not contain a value for {1}." -f @($snaplockVolumes[$a].Name, "snaplock_default_period"))
                    }
                }
                else
                { 
                    Log ("[WARNING] Get-NaVolOption for {0} did not return a hashtable." -f  @($snaplockVolumes[$a].Name))
                }
            }

            $a++
        }

        # Now that we have a list of snapshots to remove, let's do so...
        #   This could have been completed when the snapshots were initially processed, but I did it this
        #   way so I could separate the determination of expired or not from the deletion so I could more easily debug.
        #   And I just decided to leave it this way.
        $a = 0
        while($a -lt $snapshotsToRemove.Count)
        {
            # Let's be cautious and make sure the snapshot isn't busy (or wasn't busy when its info was retrieved from the filer.
            if(-not $volSnapshots[$b].Busy)
            {
                try
                {
                    Remove-NaSnapshot -Controller $snaplockFiler -TargetName $snapshotsToRemove[$a].TargetName -SnapName $snapshotsToRemove[$a].Name -Confirm:$false -ErrorAction Stop
                    Log ("[INFO   ] Removed snapshot: {0}:{1}..." -f @($snapshotsToRemove[$a].TargetName, $snapshotsToRemove[$a].Name))
                }
                catch
                {
                    Log ("[ERROR  ] Failed to remove snapshot: {0}:{1}..." -f @($snapshotsToRemove[$a].TargetName, $snapshotsToRemove[$a].Name))
                }
            }
            else
            {
                Log ("[INFO   ] Skipped busy snapshot: {0}:{1}..." -f @($snapshotsToRemove[$a].TargetName, $snapshotsToRemove[$a].Name))
            }
            $a++
        }
    }
}

# If there were any errors or warnings, or there's something left in the log buffer, send an email alert.
if($Global:loggedErrorOrWarning -or ($Global:sbLogBuffer.Length -gt 0))
{
    # Direct the recipient to the logs to check for issues.
    $emailBody = "Check log."

    # Unless there is something in the log buffer, then send the log buffer instead...
    if($Global:sbLogBuffer.Length -gt 0)
    {
        $emailBody = $Global:sbLogBuffer.ToString()
    }
    Send-MailMessage -From $Global:config.FromAddress -To $Global:config.ToAddresses -Subject ("{0}: Trouble with Snapshot cleaner" -f @([DateTime]::Now.ToString("yyyy-MM-dd HH:mm"))) -Body $emailBody -SmtpServer $Global:config.SMTPServer
}