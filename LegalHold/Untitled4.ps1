    # Create an array of command line parameters for 7-zip
    $cmdArgs = @(
        "a",                       # Add files to archive
        "-i@e:\tmp\lhtmp\filelist.txt",                      # Recurse subdirectories
        ".\archive.7z"
    )




    # Create an array of command line parameters for 7-zip
    $cmdArgs = @(
        "a",                       # Add files to archive
        ".\archive.7z",
        "*.log"
    )
