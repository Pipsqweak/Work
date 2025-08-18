function RandomName($len)
{
    $randStr = ""
    $lCaseLtrCodes = @(([int][char]'a')..[int][char]'z')

    for($i = 0; $i -lt $len; $i++)
    {
        $cCode = Get-Random -Minimum 0 -Maximum $lCaseLtrCodes.Length
        $c = [char] $lCaseLtrCodes[$cCode]

        $randStr += $c
    }

    return $randStr
}

function EmptyRecycleBin()
{
    $deletedObjects = @(Get-ADObject -Filter 'isDeleted -eq $true' -IncludeDeletedObjects)

    if($deletedObjects.Length -gt 0)
    {
        # Not sure why, but even though the following line work, for some reason, it throws
        # try { $deletedObjects | Remove-ADObject -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    }
}

function Show-RecycledWithName($testName)
{
    # Try to find a deleted object with $testName in its name...
    $deletedObjects = @(Get-ADObject -Filter ('isDeleted -eq $true -and Name -like "{0}*DEL:*"' -f @($testName)) -IncludeDeletedObjects)
    if($deletedObjects.Length -gt 0)
    {
        foreach($deletedObject in $deletedObjects)
        {
            Write-Host ("Got deleted object: {0}" -f @($deletedObject.DistinguishedName))
        }
    }

    return $deletedObjects
}

function TestRecycleBin($testType)
{
    $testPassed = $false
    $domain = Get-ADDomain
    $testName = RandomName 15

    Write-Host ("Testing creation/recycling/deleting {0} with random name {1}" -f @($testType, $testName))
    if(@(Show-RecycledWithName($testName)).Length -eq 0)
    {
        Write-Host ("Passed: no recycled {0}s with name {1}" -f @($testType, $testName))
        $existingObject = $null
        try
        {
            $existingObject = Get-ADObject -Identity $testName -ErrorAction SilentlyContinue
        }
        catch { }
        if($null -eq $existingObject)
        {
            Write-Host ("Passed: No active {0}s found with name {1}`r`n" -f @($testType, $testName))
            Write-Host ("Creating test {0} with name {1}" -f @($testType, $testName))
            # Create test Object
            if($testType -eq "user")
            {
                $newADObject = New-ADUser -Name $testName -Path $domain.UsersContainer -PassThru
            }
            else
            {
                $newADObject = New-ADGroup -Name $testName -Path $domain.UsersContainer -GroupCategory Security -GroupScope Global -PassThru
            }

            if($null -ne $newADObject)
            {
                Write-Host ("Passed: Successfully created {0} with name {1}`r`n" -f @($testType, $testName))

# Get the DirectoryEntry for the test object
                $deObject = [System.DirectoryServices.DirectoryEntry]::new("LDAP://{0}" -f @($newADObject.DistinguishedName))

                if($null -ne $deObject.NativeObject)
                {
                    Write-Host ("Passed: Successfully connected to {0} DirectoryEntry {1}`r`n" -f @($testType, $deObject.Path))
                    Write-Host ("Deleting {0} DirectoryEntry with call to DeleteTree()" -f @($testType))

                    # Delete the test object



                    # Now try to show the test object in the recycle bin
                    $deletedObjects = @(Show-RecycledWithName $testName)
                    $testPassed = ($deletedObjects.Length -gt 0)
                    if($testPassed)
                    {
                        Write-Host ("Passed: Successfully created test {0}, then delete sent it to the recycle bin." -f @($testType))
                    }
                    else
                    {
                        Write-Host ("Failed: Successfully created test {0}, however, delete did not send the test {0} to the recycle bin." -f @($testType))
                    }

                    if($deletedObjects.Length -eq 1)
                    {
                        Write-Host ("Permanently deleting {0} {1}" -f @($testType, $testName))
                        # Permanently delete the test object
                        $deletedObjects | Remove-ADObject -Confirm:$false

                        $deletedObjects = @(Show-RecycledWithName $testName)
                        if($deletedObjects.Length -eq 0)
                        {
                            Write-Host ("Successfully removed {0} {1} from the recycle bin" -f @($testType, $testName))
                        }
                        else
                        {
                            Write-Host ("Failed to remove {0} {1} from the recycle bin" -f @($testType, $testName))
                        }
                    }
                    elseif($deletedObjects.Length -gt 1)
                    {
                        Write-Host ("{0} objects found in the recycle bin with {1} in their name.  Not permanently deleting them." -f @($deletedObjects.Length, $testName))
                    }
                }
                else
                {
                    Write-Host ("Failed to attach to {0} DirectoryEntry for {0}." -f @($testType, $testName))
                }
            }
            else
            {
                Write-Host ("Failed to create test {0} with name {1}." -f @($testType, $testName))
            }
        }
        else
        {
            Write-Host ("Oops!  There is already an object with name {0}." -f @($testName))
        }
    }
    else
    {
        Write-Host ("Oops!  There is already an object with name {0} in the recycle bin." -f @($testName))
    }

    return $testPassed
}


foreach($test in @("user","group"))
{
    $result = TestRecycleBin $test
    Write-Host ("`r`nTest {0} Passed: {1}`r`n`r`n" -f @($test, $result))
}


<#
    I'd like to create a tool that compares AD groups to look to group similarity.  Not sure exactly how to do it, but I'll start here...
#>
