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
# function to get content of folders
function Get-FLRContent($folder) {
    $files = New-Object System.Collections.Generic.List[Object]
    foreach ($item in $folder) {
        $res = Get-VBRUnstructuredBackupFLRItem -Session $flr -folder $item
        # foreach item in $res, if type is file add to $files
        foreach ($r in $res) {
            if ($r.Type -eq "File") {
                $files.add($r)# += $r
            }
            elseif ($r.Type -eq "Folder") {
                $f = Get-FLRContent $r
                if($f.count -gt 1){
                    $files.AddRange($f)
                }
                elseif($f.count -eq 1){
                    $files.add($f)

                }
                #$files.AddRange((Get-FLRContent $r))
            }        
        }
    }
    # if($files.count -eq 0){
    #     return $null    
    # }
    # if($files.Count -eq 1){
    #     return @($files)
    # }
    # else{
        return $files

    # }

}
function Set-DestinationDirectory {
    param (
        [string]$defaultDestination = "C:\temp\NAS-Files"
    )

    $destination = Read-Host "Enter the destination directory for the files (default: $defaultDestination)"
    if ([string]::IsNullOrWhiteSpace($destination)) {
        $destination = $defaultDestination
    }

    if (-not (Test-Path $destination)) {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }

    return $destination
}
#End Functions
##############################################################################################
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

if($uniqueServers.Count -gt 1){
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
        $serverIndex = [int]$serverInput -1
        if ($serverIndex -ge 0){
            if($serverIndex -lt $indexedServers.Count){
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


#Get Latest Restore Point:
#$restorepoint = Get-VBRUnstructuredBackupRestorePoint | Sort-Object -Property CreationTime | Select-Object -Last 1

#Start the FLR Session:
Write-Host "Starting FLR session..."
$flr = Start-VBRUnstructuredBackupFLRSession -RestorePoint $selectedRestorePoint



# Get all files in backup:
Write-Host "Getting all files in backup...This may take a while" -ForegroundColor Yellow

# start timer
$timer = [System.Diagnostics.Stopwatch]::StartNew()
# get base source from the backup:
$baseName = Get-VBRUnstructuredBackupFLRItem -Session $flr

$filesResult = Get-FLRContent $baseName

#stop timer and print time taken
$timer.Stop()
Write-Host "Time taken to get files: $($timer.Elapsed.TotalMinutes) minutes" 
# echo file count
Write-Host "Number of files found: $($filesResult.Count)" -ForegroundColor Green
# get the name of the folder:
#$name = Get-VBRUnstructuredBackupFLRItem -Session $flr -Name $baseName.Name

# Get the base files and folders from the root and loop through folders to get all files
#$folder = Get-VBRUnstructuredBackupFLRItem -Session $flr -folder $name




#foreach item of type Folder in $folder, get all files in the folder
# $filesResult = @()
# foreach ($item in $folder) {
#     if ($item.Type -eq "File") {
#         $filesResult += $item
#     }
#     elseif ($item.Type -eq "Folder") {
#         $res = Get-FLRContent $item
#         foreach ($item in $res) {
#             if ($item.Type -eq "File") {
#                 $filesResult += $item
#             }
#             elseif ($item.Type -eq "Folder") {
#                 $filesResult += Get-FLRContent $item
#             }
#         }

#     }
#     Write-Host "Number of files found: $($filesResult.Count)"

# }


#$files = Get-VBRUnstructuredBackupFLRItem -Session $flr -Recurse




if ($filesResult.Count -eq 0) {
    Write-Host "No files found in backup"
    Close-FLRSession $flr
    Exit
}






# Export files to destination directory
Write-Host "Exporting files to $destination..."
$n = $job.Name
$files = $filesResult 
$date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
if ($files.Count -gt $fCount) {
    for ($i = 0; $i -lt $files.Count; $i += $fCount) {
        
        $fileName = "$destination\files_$($n)_$($date)_$($i).csv"
        $files[$i..($i + $fCount)] | Export-Csv -Path $fileName -NoTypeInformation
    }
}
else {
    $fileName = "$destination\files_$($n)_$($date).csv"
    $files | Export-Csv -Path $fileName -NoTypeInformation
}

Write-Host "Files exported to $fileName" -ForegroundColor Green

# Search for files

while ($true) {
    # Prompt for search files or exit and close FLR session
    $search = Read-Host "Do you want to search for a file? (Y/N)"
    if ($search -eq "N") {
        Write-Host "Closing FLR session..." -ForegroundColor Yellow
        Stop-VBRUnstructuredBackupFLRSession -Session $flr

        break
    }
    if ($search -eq "Y") {
        $searchString = Read-Host "Enter search string"
        $searchResults = $files | Where-Object { $_.Name -like "*$searchString*" }
        
        $date2 = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"

        Write-Host "Number of search results found: $($searchResults.Count)" -foregroundcolor green
        $searchResults | Export-Csv -Path "$destination\searchResults_$($n)_$($date2).csv" -NoTypeInformation
        Write-Host "Search results saved to $destination\searchResults_$($n).$($date2).csv"
    }
    else {
        Write-Host "Invalid input. Please enter Y or N"
    }

}

