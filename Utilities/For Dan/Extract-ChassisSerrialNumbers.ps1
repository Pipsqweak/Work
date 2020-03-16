[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [String]
    $inputPath,

    [Parameter(Mandatory=$false,Position=1)]
    [Switch]
    $SerialOnly
)

$regexs = @(
    "^jnxVirtualChassisMemberSerialnumber\.(\d+)\s+\=\s+(.+)$",
    "^jnxBoxSerialNo\.(\d+)\s+\=\s+(.+)$"
)

$outputFiles = Get-ChildItem -Path $inputPath

$data = @(
    foreach($file in $outputFiles)
    {
        $deviceName = $file.BaseName.Replace("CLIEnterCommandsResults-","")
    
        $content = Get-Content -Path $file.FullName
        $parsed = $false

        for($i = 0; (-not $parsed) -and ($i -lt $regexs.Length); $i++)
        {
            $lines = $content -match $regexs[$i]
            $parsed = ($lines.Count -gt 0)
            if($parsed)
            {
                foreach($line in $lines)
                {
                    if($line -match $regexs[$i])
                    {
                        $device = "" | Select-Object Name,ChassisMember,SerialNumber

                        $device.Name = $deviceName
                        $device.ChassisMember = $Matches[1]
                        $device.SerialNumber = $Matches[2]

                        $device
                    }
                }
            }
        }
    }
)

if($SerialOnly.IsPresent)
{
    $data | Select-Object -ExpandProperty SerialNumber | Out-GridView
}
else
{
    $data | Out-GridView
}
