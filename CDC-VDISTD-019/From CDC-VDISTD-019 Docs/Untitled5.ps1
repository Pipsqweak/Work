$newFileNames = [System.Collections.Generic.SortedDictionary[int, string]]::new()

function SetPublicFolderConversationObjectsFileNames
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [System.Collections.Generic.List[System.Object]]
        $pfObjs,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $conversationIdx,

        [Parameter(Mandatory = $true, Position = 2)]
        [Int32]
        $conversationCount
    )

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
                            # $pfObjs[$c].FileName = $newFileName
                            $newFileNames.Add($pfObjs[$c].TempFileIndex, $newFileName)
                        } `
                        else # NOT (-not [String]::IsNullOrEmpty($newFileName))
                        {
                            # LogError ("Null/empty file name created for: {0}/{1}" -f @($pfObjs[$c].EntryID, $pfObjs[$c].Subject))
                            # $pfObjs[$c].Good2Go = $false
                            # UpdatePublicFolderObjectStatus -pfObj $pfObjs[$c] -status "Null file name created."
                        }
                    }
                    $c++
                }
            } `
            else # NOT (@($pfObjs | Where-Object { $_.ConversationID -ne $pfObjs[0].ConversationID }).Length -eq 0)
            {
                # $Script:ReturnObject.Good2Go = $false
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
        # $Script:ReturnObject.Good2Go = $false
    }
}
