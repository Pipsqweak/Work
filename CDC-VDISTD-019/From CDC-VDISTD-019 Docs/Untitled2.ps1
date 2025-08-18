
$Script:ItemsByConversation = [System.Collections.Generic.SortedDictionary[System.String, System.Collections.Generic.List[System.Object]]]::new()


$Script:UniqueImportFileNames = [System.Collections.Generic.List[System.String]]::new()


function SetPublicFolderObjectFileNames
{
    if($Script:ReturnObject.Good2Go)
    {
        if($null -ne $Script:ItemsByConversation)
        {
            if($Script:ItemsByConversation.Count -gt 0)
            {
                LogInfo ("Calculating actual file names...")
                # Now rename all the files using conversation number, message number, item sender and subject.
                $uniqueConversationIDs = @(@($Script:ItemsByConversation.Keys) | Where-Object { $_ -ne "NO_CONVERSATION" })
                $conversationCount = $uniqueConversationIDs.Length
                LogInfo ("Unique conversations: {0}" -f @($conversationCount))

                <#
                    When renaming the message files, do so by conversation in creation time (or last modified time if creation time isn't available) order.

                    The idea here is to have Conv 1 = the oldest conversation, even if some of its messages are newer than others.
                #>

                # Create a dictionary of conversation IDs by SortTime.  Exclude messages which are not part of a conversation
                #   Key = creation/last mod date/time (.SortTime) of the first message in the conversation.
                #   Value = List of all the conversation IDs whose first conversation message has the same .SortTime
                $conversationIDsBySortTime = [System.Collections.Generic.SortedDictionary[DateTime, System.Collections.Generic.List[String]]]::new()

                $a = 0
                while($a -lt $uniqueConversationIDs.Length)
                {
                    # Find the oldest message in the conversation which has .ConversationID -eq $uniqueConversationIDs[$a]
                    #    $Script:ItemsByConversation[$uniqueConversationIDs[$a]] is guaranteed to always have at least 1 item in the list, or we'd not have had $uniqueConversationIDs[$a] as a key use...
                    #    Also, since we are building $Script:ItemsByConversation[$uniqueConversationIDs[$a]] in .ConversationIndex order, [0] will always be the first.
                    $firstConversationItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]][0]
#                            $firstConversationItem = $Script:ItemsByConversation[$uniqueConversationIDs[$a]] | Sort-Object -Property SortTime | Select-Object -First 1
                    if(-not $conversationIDsBySortTime.ContainsKey($firstConversationItem.SortTime))
                    {
                        $conversationIDsBySortTime.Add($firstConversationItem.SortTime, [System.Collections.Generic.List[String]]::new())
                    } `
                    else
                    {
                        # Nothing
                    }

                    # $uniqueConversationIDs is already sorted since it's based on the keys from $Script:ItemsByConversation, so adding it will result in a sorted list.
                    #  Since we are looping through $uniqueConversationIDs, $uniqueConversationIDs[$a] will only ever get added to 1 list.
                    $conversationIDsBySortTime[$firstConversationItem.SortTime].Add($uniqueConversationIDs[$a])

                    $a++
                }
                <#
                    After the above code, we might have a conversation date which matches a message which is NOT part of a conversation.  However, we will not have any .ConversationIDs in
                        $conversationIDsBySortTime which are "NO_CONVERSATION"

                    Therefore, when I use $conversationIDsBySortTime.Keys ($conversationDates) as a loop counter, I will never end up in a situation where:

                        $Script:ItemsByConversation[$conversationIDsBySortTime[$conversationDates[$a]][$b]] results in an item with "NO_CONVERSATION" as its .ConversationID.

                    Furthermore, since the above is true, when I rename the items which do NOT have .ConversationID -eq "NO_CONVERSATION", it's safe to assume every item is
                        part of a conversation, so for every conversation ID in $conversationIDsBySortTime is a new conversation, so increment $conversationIdx every time.
                #>

                # If there are messages which are not part of a conversation, rename them first.
                if($Script:ItemsByConversation.ContainsKey("NO_CONVERSATION"))
                {
                    # Since these messages are not part of a conversation, $conversationIdx and $conversationCount don't mean anything.
                    SetPublicFolderConversationObjectsFileNames -pfObjs $Script:ItemsByConversation["NO_CONVERSATION"] -conversationIdx 0 -conversationCount 0
                } `
                else # NOT ($Script:ItemsByConversation.ContainsKey("NO_CONVERSATION"))
                {
                    # Nothing.
                }

                if($Script:ReturnObject.Good2Go)
                {
                    # Loop through the conversations, oldest to newest...
                    $conversationDates = @($conversationIDsBySortTime.Keys)
                    # $a in the loop index for all the various .SortTime values found in the first message of each conversation.  It's not a representation
                    #     of the conversation number.  Multiple conversations' first messages could share the same .SortTime.
                    $a = 0

                    # Unlike $a, $conversationIdx is the conversation number for a particular list of messages.
                    $conversationIdx = 1

                    while($a -lt $conversationDates.Length)
                    {
                        # Process all the conversations where the first message in the conversation has a .SortTime -eq $conversationDates[$a]
                        $b = 0
                        while($b -lt $conversationIDsBySortTime[$conversationDates[$a]].Count)
                        {
                            # Process all the messages that are part of conversation ID: $conversationIDsBySortTime[$conversationDates[$a]][$b]
                            $conversationMessages = $Script:ItemsByConversation[$conversationIDsBySortTime[$conversationDates[$a]][$b]]

                            SetPublicFolderConversationObjectsFileNames -pfObjs $conversationMessages -conversationIdx $conversationIdx -conversationCount $conversationCount

                            # See above (and good luck understanding) why incrementing $conversationIdx each time is safe.
                            $conversationIdx++

                            $b++
                        }
                        $a++
                    }
                } `
                else # NOT ($Script:ReturnObject.Good2Go)
                {
                    # Nothing, already logged an error.
                }
            } `
            else # NOT ($Script:ItemsByConversation.Count -gt 0)
            {
                LogError "No item conversations in RenameLocalFiles."
                $Script:ReturnObject.Good2Go = $false
            }
        } `
        else # NOT ($null -ne $Script:ItemsByConversation)
        {
            LogError "No items by conversation in RenameLocalFiles."
            $Script:ReturnObject.Good2Go = $false
        }
    } `
    else # NOT ($Script:ReturnObject.Good2Go)
    {
        # Nothing, already logged an error
    }
}
