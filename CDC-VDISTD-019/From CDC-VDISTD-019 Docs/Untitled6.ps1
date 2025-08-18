function MakeMessagePath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [Int32]
        $conversationIdx,

        [Parameter(Mandatory = $true, Position = 1)]
        [Int32]
        $conversationCount,

        [Parameter(Mandatory = $true, Position = 2)]
        [Int32]
        $itemIdx,

        [Parameter(Mandatory = $true, Position = 3)]
        [Int32]
        $itemCount,

        [Parameter(Mandatory = $true, Position = 4)]
        [Object]
        $pfObj,

        [Parameter(Mandatory = $true, Position = 5)]
        [bool]
        $isPartOfConversation
    )
    <#
        .SYNOPSIS
        Creates a file name from the parameters provided.

        .DESCRIPTION
        Creates a well formed file name using the paramaters.

        If $conversationCount is greater than 1, the file name will contain "Conv X".  Where X is left padded with spaces to ensure all numbers align and sort correctly.
        If $itemCount is greater than 1, the file name will contain "Msg X of Y".  Where X and Y are left padded with spaces to ensure all numbers align and sort correctly.
        All invalid characters in $subject will be replaced with "_".  Additionally, spaces will be trimmed from the start and end of the subject.  If $subject is null or empty "NO_SUBJECT" will be used.
        Finally, file name will begin with the full path of $Script:WorkingFolder.

        See the examples below.

        .PARAMETER conversationIdx
        The nth conversation in the folder (1 based)

        .PARAMETER conversationCount
        The number of conversations

        .PARAMETER itemIdx
        The nth item of the conversation (0 based)

        .PARAMETER itemCount
        The number of items in the conversation

        .PARAMETER pfObj
        Data take from the mail item we are working with.  See NewConversationObjectFromItem

        .INPUTS
        None.  You can't pipe objects to MakeMessagePath.

        .OUTPUTS
        [String] A well formed file name

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 6 -itemIdx 3 -itemCount 12 -subject "Final call for reports"
        C:\TEMP\Conv 1 of 6 | Msg  4 of 12 | Final call for reports.msg"

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 1 -itemIdx 0 -itemCount 212 -subject "Final call for reports"
        C:\TEMP\Msg   1 of 212 | Final call for reports.msg"

        .EXAMPLE
        PS> $fileName = MakeMessagePath -conversationIdx 0 -conversationCount 1 -itemIdx 0 -itemCount 1 -subject "Final call for reports"
        C:\TEMP\Final call for reports.msg"
    #>

    # Already fixed up .SenderName when we made $pfObj
    $senderName = $pfObj.SenderName
    if(-not [String]::IsNullOrEmpty($senderName))
    {
        $senderName = "{0} {1} " -f @($senderName, [char] 9474)
    } `
    else # NOT (-not [String]::IsNullOrEmpty($pfObj.SenderName))
    {
        # Nothing
    }

    $prefix = [String]::Empty
    if($isPartOfConversation)
    {
        $conversationCntLength = $conversationCount.ToString().Length
        $itemCountLength = $itemCount.ToString().Length

        if($conversationCount -gt 1)
        {
            $prefix = $Script:ConversationPrefix -f @($conversationCntLength, [char] 9474)   # [char] 9474 is a vertical line character.  However, putting the character itself in the script causes PS some issues.
            $prefix = $prefix -f @($conversationIdx)
        }

        $prefix = "{0}{1}" -f @($prefix, ($Script:MessagePrefix -f @($itemCountLength, [char] 9474)))
        $prefix = $prefix -f @(($itemIdx + 1), $itemCount)
    } `
    else # NOT ($isPartOfConversation)
    {
        # Nothing, no conversation, no prefix.
    }

    # Add different extensions as needed...
    $extension = "msg"
    if($pfObj.SaveType -eq [Microsoft.Office.Interop.Outlook.olSaveAsType]::olVCard)
    {
        $extension = "vcf"
    } `
    else
    {
        # Nothing, stick with msg
    }

    # Already fixed up .Subject when we created $pfObj
    $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $pfObj.Subject -extension $extension
    $fileName = "{0}\{1}{2}{3}.{4}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $extension)

    $i = $Script:UniqueImportFileNames.BinarySearch($fileName, [System.StringComparer]::CurrentCultureIgnoreCase)

    # Append (x) to the file name if a file is already tagged to be named $fileName
    $idxNum = 1

    # If $i -ge 0, then the perspective file name has already been used.
    while($i -ge 0)
    {
        $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $pfObj.Subject -idxNum $idxNum -extension $extension
        $fileName = "{0}\{1}{2}{3} ({4}).{5}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $idxNum, $extension)
        $i = $Script:UniqueImportFileNames.BinarySearch($fileName, [System.StringComparer]::CurrentCultureIgnoreCase)
        $idxNum++
    }

    if($i -lt 0)
    {
        $Script:UniqueImportFileNames.Insert(-bnot $i, $fileName)
    } `
    else # NOT ($i -lt 0)
    {
        LogError ("Unable to create a unique file name for: {0}")
        $pfObj.Good2Go = $false
        UpdatePublicFolderObjectStatus -pfObj $pfObj -status "Unable to create a unique file name"
        $fileName = [String]::Empty
    }

    <#   OLD WAY
    while(@($Script:ItemsByConversation.Values | Where-Object { $_.FileName -eq $fileName }).Length -gt 0)
    {
        $subject = SetSubjectForPWPath -prefix $prefix -senderName $senderName -subject $originalSubject -idxNum $idxNum -extension $extension
        $fileName = "{0}\{1}{2}{3} ({4}).{5}" -f @($Script:WorkingFolder, $prefix, $senderName, $subject, $idxNum, $extension)
        $idxNum++
    }
    #>

    return $fileName
}
