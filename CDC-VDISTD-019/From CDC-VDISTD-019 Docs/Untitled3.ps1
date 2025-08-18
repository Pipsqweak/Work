$Script:ItemsByConversation = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()
#$Script:PublicFolderItems = [System.Collections.Generic.List[System.Object]]::new()
#@(Get-Content -Path "\\boifs1\ITxchange\KLBTest\PFExportResults\000000001A447390AA6611CD9BC800AA002FC45A030012225CC57BF01F4EA8CCA87A792FF35F00076765951D0000-20250331-145127-PFObjects.json" | ConvertFrom-Json)[0].ForEach({ $Script:PublicFolderItems.Add($_) })
$Script:PFObjectConversationIndexComparer = [PFObjectComparerByConversationIndex]::new()

            $a = 0
            while($a -lt $pfObjs.Count)
            {
                $pfObj = $pfObjs[$a]


                    # Create a new list of public folder objects for $pfObj.ConversationID if one doesn't already exist.
                    #   NOTE:  $pfObj will always have a .ConversationID since NewPublicFolderObjectFromItem ensure it is set.
                    if(-not $Script:ItemsByConversation.ContainsKey($pfObj.ConversationID))
                    {
                        $Script:ItemsByConversation.Add($pfObj.ConversationID, [System.Collections.Generic.List[System.Object]]::new())
                    } `
                    else
                    {
                        # Nothing, $Script:ItemsByConversation already has a conversation list for this conversation.
                    }
                    # Add $pfObj to $Script:ItemsByConversation[$pfObj.ConversationID]

                    $i = $Script:ItemsByConversation[$pfObj.ConversationID].BinarySearch($pfObj, $Script:PFObjectConversationIndexComparer)
                    if($i -lt 0)
                    {
                        $i = -bnot $i
                    }
                    $Script:ItemsByConversation[$pfObj.ConversationID].Insert($i, $pfObj)

<#
                    if($pfObj.Saved2Temp)
                    {
                        UpdateTempFileStats -pfObj $pfObj -item $item
                    } `
                    else # NOT ($pfObj.Saved2Temp)
                    {
                        LogWarning ("Not updating file information for unsaved item: {0}" -f @($pfObj.TempFileName))
                    }
#>

                $a++
            }

$pfObjs = $Script:ItemsByConversation["NO_CONVERSATION"]
$conversationIdx = 0
$conversationCount = 0 
$Script:UniqueImportFileNames = [System.Collections.Generic.List[System.String]]::new()

    if($null -ne $pfObjs)
    {
        if($pfObjs.Count -gt 0)
        {
            $uniqueConversationIDs = @($pfObjs | Select-Object -Unique -ExpandProperty ConversationID)

            # Make sure all pfObjs have the same .ConversationID
            if($uniqueConversationIDs.Length -eq 1)
            {
                $isPartOfConversation = $pfObjs[0].ConversationID -ne "NO_CONVERSATION"
                $c = 0
                while($c -lt $pfObjs.Count)
                {
                    if($pfObjs[$c].Saved2Temp)
                    {
                        $newFileName = MakeMessagePath -conversationIdx $conversationIdx -conversationCount $conversationCount -itemIdx $c -itemCount $pfObjs.Count -pfObj $pfObjs[$c] -isPartOfConversation $isPartOfConversation

                        if(-not [String]::IsNullOrEmpty($newFileName))
                        {
                            Write-Host $newFileName
                            # $pfObjs[$c].FileName = $newFileName
                        } `
                        else # NOT (-not [String]::IsNullOrEmpty($newFileName))
                        {
                            Write-Host ("Null/empty file name created for: {0}/{1}" -f @($pfObjs[$c].EntryID, $pfObjs[$c].Subject))
                            # $pfObjs[$c].Good2Go = $false
                            # UpdatePublicFolderObjectStatus -pfObj $pfObjs[$c] -status "Null file name created."
                        }
                    }
                    $c++
                }
            } `
            else # NOT (@($pfObjs | Where-Object { $_.ConversationID -ne $pfObjs[0].ConversationID }).Length -eq 0)
            {
                $Script:ReturnObject.Good2Go = $false
                LogError ("Mismatched conversation IDs in SetMessageFileNames.  Conversation IDs: {0}" -f @(($uniqueConversationIDs -join ", ")))
            }
        } `
        else # NOT ($pfObjs.Length -gt 0)
        {
            LogWarning ("No public folder objects to set file names.")
        }
    } `
    else # NOT ($null -ne $pfObjs)
    {
        LogError ("Null message list in SaveMessages.")
        $Script:ReturnObject.Good2Go = $false
    }