<#
Synopsis:
This script is designed to collect and list all files in a backup. 

Due to potential size of files, this script will break the output files into managable sizes.

The script may also allow searching for specific file names... TBD


1. Select Job
2. Select restore point
3. Start FLR with restore point
4. Get all files from FLR
5. Store into chunked files
6. Prompt for search function
7. Take user input for search string
8. Try to find file


#>

##############################################################################################
#Functions

# write a function to close the FLR session and print a message
function Close-FLRSession($flr) {
    Write-Host "Closing FLR session..." -ForegroundColor Yellow
    Stop-VBRUnstructuredBackupFLRSession -Session $flr
}
function Select-ItemsPerCSV {
    $validInput = $false
    while (-not $validInput) {
        $splitOption = Read-Host "Select the number of items per CSV file (10K, 100K, 500K)(default: 100K)"
        switch ($splitOption) {
            "10K" { $fCount = 10000; $validInput = $true }
            "100K" { $fCount = 100000; $validInput = $true }
            "500K" { $fCount = 500000; $validInput = $true }
            default { $fCount = 100000; $validInput = $true }
        }
    }
    return $fCount
}
# function to log message to console with timestamp
function Log-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Red", "Green", "Yellow", "Blue", "Cyan", "Magenta", "White")]
        [string]$color = "White"
    )

    Write-Host "$(Get-Date) - $message" -ForegroundColor $color
}

# function to get content of folders
function Get-FLRContent($folder) {
    $files = New-Object System.Collections.Generic.List[Object]
    foreach ($item in $folder) {
        $res = Get-VBRUnstructuredBackupFLRItem -Session $flr -folder $item
        # foreach item in $res, if type is file add to $files

        $fi = $res | Where-Object { $_.Type -eq "File" }
        if($fi.Count -eq 1) {
            # echo found file count
            Log-Message("New files found: " + $fi.Count)
            $files.Add($fi)
        }
        elseif($fi.Count -gt 1) {
            # echo files count
            Log-Message("New files found: " + $fi.Count)
        $files.AddRange($fi)
        }
        $global:TotalFileCount += $fi.Count

        #if global total equal to or greater than 1 million, export to csv and flush $files variable
        if ($global:TotalFileCount -ge 1000000) {
            $files = Export-FLRContent $files $destination $fCount
            $files = New-Object System.Collections.Generic.List[Object]
        }

        $fo = $res | Where-Object { $_.Type -eq "Folder" }
        if ($fo.Count -gt 0) {
            # echo folders count
            $message = "Folders To Sort: "+ $fo.Count
           Log-Message -message $message -color "Yellow"
            $f = Get-FLRContent $fo
                if ($f.count -gt 1) {
                    #echo files count
                    Log-Message("New files found: "+ $f.Count)
                    $files.AddRange($f)
                }
                elseif ($f.count -eq 1) {
                    #echo files count
                    Log-Message("New files found: " + $f.Count)
                    $files.add($f)

                }
        }



        # foreach ($r in $res) {
        #     if ($r.Type -eq "File") {
        #         $files.add($r)
        #         # add total to global totals variable
        #         $global:TotalFileCount++

        #         #if global total equal to or greater than 1 million, export to csv and flush $files variable
        #         if ($global:TotalFileCount -ge 1000000) {
        #             $files = Export-FLRContent $files $destination $fCount
        #             $files = New-Object System.Collections.Generic.List[Object]
        #         }
        #     }
        #     elseif ($r.Type -eq "Folder") {
        #         $f = Get-FLRContent $r
        #         if ($f.count -gt 1) {
        #             $files.AddRange($f)
        #         }
        #         elseif ($f.count -eq 1) {
        #             $files.add($f)

        #         }
        #         #$files.AddRange((Get-FLRContent $r))
        #     }        
        # }
    }
    #$files = Export-FLRContent $files $destination $fCount
    $message = "Total Files Counted: " + $global:TotalFileCount
    Log-Message -message $message -color "Green"
    return $files

    # }

}
# function Export-FLRContent($files, $destination, $fCount) {
#     #check for files in $desintation and count the lines in the newest file
#     $outputFiles = Get-ChildItem $destination | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    
#     $n = $job.Name
#     #if files exist, get the line count, if no files exist, create a new file
#     if ($outputFiles.Count -gt 0) {
#         $lines = (Get-Content $outputFiles.FullName).Count
#         if ($lines -gt $fCount) {
#             $fileName = Create-NewOutpuFile $destination $n
#         }
#         else {
#             $fileName = $outputFiles.FullName
#         }
#     }
#     else {
#         $lines = 0
#         $fileName = Create-NewOutpuFile $destination $n
#     }
#     #if the line count is greater than $fCount, create a new file

#     $files | Export-Csv -Path $fileName -NoTypeInformation -Append

#     # zero out the $files variable

#     $files = @()
#     return $files
# }
# write a function similar to Export-FLRContent but splits the files into chunks of $fCount
function Export-FLRContent($files, $destination, $fCount) {
    $n = $job.Name
    $date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
    $fileCounter = 0
    if ($files.Count -gt $fCount) {
        for ($i = 0; $i -lt $files.Count; $i += $fCount) {
            $fileName = "$destination\files_$($n)_$($date)_$($fileCounter).csv"
            $files[$i..($i + $fCount)] | Export-Csv -Path $fileName -NoTypeInformation
            $fileCounter++
        }
    }
    else {
        $fileName = "$destination\files_$($n)_$($date).csv"
        $files | Export-Csv -Path $fileName -NoTypeInformation
    }
    $files = @()
    return $files
}
function Create-NewOutpuFile($destination, $jobName) {
    $date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
    $fileName = "$destination\files_$($jobName)_$($date).csv"
    return $fileName

}
function Set-DestinationDirectory {
    param (
        [string]$defaultDestination = "C:\temp\NAS-Files"
    )

    $destination = Read-Host "Enter the destination directory for the files (default: $defaultDestination)"
    if ([string]::IsNullOrWhiteSpace($destination)) {
        $destination = $defaultDestination
    }
    $destination = $destination + "\\" + $job.Name + "_" + (Get-Date -Format "yyyy-MM-dd-HH-mm-ss")
    if (-not (Test-Path $destination)) {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }

    return $destination
}
#End Functions
##############################################################################################
#print start time
Write-Host "Script started at: $(Get-Date)" -ForegroundColor Green
$fileCounter = 0
# 1. Get all unstructured jobs into $jobs variable
$jobs = Get-VBRJob | Where-Object { $_.JobType -eq "NasBackup" }

# List all jobs with option for user to select which job to choose as $job variable
$jobs | ForEach-Object -Begin { $index = 1 } -Process { $_ | Add-Member -NotePropertyName Index -NotePropertyValue $index -PassThru; $index++ } | Select-Object -Property Index, Name | Sort-Object -Property Index | Format-Table -AutoSize
$validInput = $false
while (-not $validInput) {
    $jobInput = Read-Host "Select Job by Index"

    if ($jobInput -match '^\d+$') {
        $jobIndex = [int]$jobInput
        if ($jobIndex -ge 1 -and $jobIndex -le $jobs.Count) {
            $validInput = $true
        } 
    }
    else {
        Write-Host "Invalid input. Please enter a valid index."
    }
}
$job = $jobs[$jobIndex - 1]

# echo to the user which job name they selected
Write-Host "You selected job: $($job.Name)"

# 2. Get all restore points for the selected job
$backup = Get-VBRUnstructuredBackup | Where-Object { $_.jobid -eq $job.Id }
$restorepoints = Get-VBRUnstructuredBackupRestorePoint -Backup $backup

#from the $restorepoints, get all objects but only if they have a unique ServerName. I need to preserve all other details about the restore point
# Extract unique server names from $restorepoints
$uniqueServers = $restorepoints | Select-Object -ExpandProperty ServerName -Unique

if ($uniqueServers.Count -gt 1) {
    # Create a list of unique server names with an index
    $indexedServers = @()
    $indexedServers = $uniqueServers | ForEach-Object -Begin { $index = 1 } -Process {
        [PSCustomObject]@{
            Index      = $index
            ServerName = $_
        }
        $index++
    }

    # Display the indexed list to the user
    $indexedServers | Format-Table -Property Index, ServerName
    Write-Host "Select the server to restore files from"
    $validInput = $false
    while (-not $validInput) {
        $serverInput = Read-Host "Select Server by Index"
        if ($serverInput -match '^\d+$') {
            $serverIndex = [int]$serverInput - 1
            if ($serverIndex -ge 0) {
                if ($serverIndex -lt $indexedServers.Count) {
                    $validInput = $true
                }
            } 
        }
        else {
            Write-Host "Invalid input. Please enter a valid index."
        }
    }

    #after selecting the server, I need to get all $restorepoints that have the selected server name
    $selectedServer = $indexedServers[$serverIndex].ServerName
    $restorepoints = $restorepoints | Where-Object { $_.ServerName -eq $selectedServer }

    Write-Host "You selected server: $selectedServer"
}





# 3. List all restore points by date
#sort $restorepoints by creation time 
$restorepoints = $restorepoints | Sort-Object -Property CreationTime 
$restorepoints | ForEach-Object -Begin { $index = 1 } -Process { $_ | Add-Member -NotePropertyName Index -NotePropertyValue $index -PassThru; $index++ } | Select-Object -Property Index, CreationTime | Format-Table -AutoSize

# 4. Ask user to select restore point by number
$validInput = $false
while (-not $validInput) {
    $restorePointIndex = Read-Host "Select Restore Point by Index"
    if ($restorePointIndex -match '^\d+$' -and $restorePointIndex -ge 1 -and $restorePointIndex -le $restorepoints.Count) {
        $validInput = $true
    }
    else {
        Write-Host "Invalid input. Please enter a valid index."
    }
}

# 5. Get the selected restore point
$selectedRestorePoint = $restorepoints[$restorePointIndex - 1]

# echo to the user which restore point they selected
Write-Host "You selected restore point created on: $($selectedRestorePoint.CreationTime)"

# Get the number of items per CSV file
$fCount = Select-ItemsPerCSV

# 6. Set the destination directory for the files
$destination = Set-DestinationDirectory



#Start the FLR Session:
Write-Host "Starting FLR session..."
$flr = Start-VBRUnstructuredBackupFLRSession -RestorePoint $selectedRestorePoint



# Get all files in backup:
Write-Host "Getting all files in backup...This may take a while" -ForegroundColor Yellow
# echo start time
Write-Host "Files Counting started at: $(Get-Date)" -ForegroundColor Green

# start timer
$timer = [System.Diagnostics.Stopwatch]::StartNew()
# get base source from the backup:
$baseName = Get-VBRUnstructuredBackupFLRItem -Session $flr

$global:TotalFileCount = 0
$filesResult = Get-FLRContent $baseName

# if $filesResult count is not 0, export the remaining files to a csv file
if ($filesResult.Count -gt 0) {
    $filesResult = Export-FLRContent $filesResult $destination $fCount
}
#stop timer and print time taken
$timer.Stop()
Write-Host "Time taken to get files: $($timer.Elapsed.TotalMinutes) minutes" 
# echo file count
#get file count from destination by counting lines in all files
#$filesCount = Get-ChildItem $destination -Recurse | Measure-Object -Line | Select-Object -ExpandProperty Lines

Write-Host "Number of files found: $($global:TotalFileCount)" -ForegroundColor Green



if ($global:TotalFileCount -eq 0) {
    Write-Host "No files found in backup"
    Close-FLRSession $flr
    Exit
}
else {
    Close-FLRSession $flr
}





# # Export files to destination directory
# Write-Host "Exporting files to $destination..."
# $n = $job.Name
# $files = $filesResult 
# $date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
# if ($files.Count -gt $fCount) {
#     for ($i = 0; $i -lt $files.Count; $i += $fCount) {
        
#         $fileName = "$destination\files_$($n)_$($date)_$($i).csv"
#         $files[$i..($i + $fCount)] | Export-Csv -Path $fileName -NoTypeInformation
#     }
# }
# else {
#     $fileName = "$destination\files_$($n)_$($date).csv"
#     $files | Export-Csv -Path $fileName -NoTypeInformation
# }

# Write-Host "Files exported to $fileName" -ForegroundColor Green


# #print end time
# Write-Host "Script ended at: $(Get-Date)" -ForegroundColor Green
# # Search for files

# while ($true) {
#     # Prompt for search files or exit and close FLR session
#     $search = Read-Host "Do you want to search for a file? (Y/N)"
#     if ($search -eq "N") {
#         Write-Host "Closing FLR session..." -ForegroundColor Yellow
#         Stop-VBRUnstructuredBackupFLRSession -Session $flr

#         break
#     }
#     if ($search -eq "Y") {
#         $searchString = Read-Host "Enter search string"
#         $searchResults = $files | Where-Object { $_.Name -like "*$searchString*" }
        
#         $date2 = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"

#         Write-Host "Number of search results found: $($searchResults.Count)" -foregroundcolor green
#         $searchResults | Export-Csv -Path "$destination\searchResults_$($n)_$($date2).csv" -NoTypeInformation
#         Write-Host "Search results saved to $destination\searchResults_$($n).$($date2).csv"
#     }
#     else {
#         Write-Host "Invalid input. Please enter Y or N"
#     }

# }

