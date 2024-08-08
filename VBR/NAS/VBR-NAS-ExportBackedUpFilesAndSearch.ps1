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

# write a function to close the FLR session and print a message
function Close-FLRSession($flr){
    Write-Host "Closing FLR session..." -ForegroundColor Yellow
    Stop-VBRUnstructuredBackupFLRSession -Session $flr
}

# 1. Get all unstructured jobs into $jobs variable
$jobs = Get-VBRJob | Where-Object {$_.JobType -eq "NasBackup"}

# List all jobs with option for user to select which job to choose as $job variable
$jobs | ForEach-Object -Begin { $index = 1 } -Process { $_ | Add-Member -NotePropertyName Index -NotePropertyValue $index -PassThru; $index++ } | Select-Object -Property Index, Name, Id | Sort-Object -Property Index | Format-Table -AutoSize
$validInput = $false
while (-not $validInput) {
    $jobIndex = Read-Host "Select Job by Index"
    if ($jobIndex -match '^\d+$' -and $jobIndex -ge 1 -and $jobIndex -le $jobs.Count) {
        $validInput = $true
    } else {
        Write-Host "Invalid input. Please enter a valid index."
    }
}
$job = $jobs[$jobIndex - 1]

# echo to the user which job name they selected
Write-Host "You selected job: $($job.Name)"

# 2. Get all restore points for the selected job
$backup = Get-VBRUnstructuredBackup | Where-Object {$_.jobid -eq $job.Id }
$restorepoints = Get-VBRUnstructuredBackupRestorePoint -Backup $backup

# 3. List all restore points by date
$restorepoints | ForEach-Object -Begin { $index = 1 } -Process { $_ | Add-Member -NotePropertyName Index -NotePropertyValue $index -PassThru; $index++ } | Select-Object -Property Index, CreationTime | Format-Table -AutoSize

# 4. Ask user to select restore point by number
$validInput = $false
while (-not $validInput) {
    $restorePointIndex = Read-Host "Select Restore Point by Index"
    if ($restorePointIndex -match '^\d+$' -and $restorePointIndex -ge 1 -and $restorePointIndex -le $restorepoints.Count) {
        $validInput = $true
    } else {
        Write-Host "Invalid input. Please enter a valid index."
    }
}

# 5. Get the selected restore point
$selectedRestorePoint = $restorepoints[$restorePointIndex - 1]

# echo to the user which restore point they selected
Write-Host "You selected restore point created on: $($selectedRestorePoint.CreationTime)"



#Get Latest Restore Point:
#$restorepoint = Get-VBRUnstructuredBackupRestorePoint | Sort-Object -Property CreationTime | Select-Object -Last 1

#Start the FLR Session:
Write-Host "Starting FLR session..."
$flr = Start-VBRUnstructuredBackupFLRSession -RestorePoint $selectedRestorePoint

# Get all files in backup:
Write-Host "Getting all files in backup...This may take a while" -ForegroundColor Yellow
$files = Get-VBRUnstructuredBackupFLRItem -Session $flr -Recurse
if($files.Count -eq 0){
    Write-Host "No files found in backup"
    Close-FLRSession $flr
    Exit
}
if($files.Count -gt 1000){
    Write-Host "There are $($files.Count) files in the backup. This may take a while to process."
}
# Export files to CSV
Write-Host "Exporting files to CSV..."

$name = $job.Name
$fileName = "C:\temp\files_$($name)_$($date).csv"
$fCount = 100000
if($files.Count -gt $fCount){
    for ($i=0; $i -lt $files.Count; $i+=$fCount){
        $date = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
        $fileName = "C:\temp\files_$($name)_$($date)_$($i).csv"
        $files[$i..($i+$fCount)] | Export-Csv -Path $fileName -NoTypeInformation
    }
}
else{
    $files | Export-Csv -Path $fileName -NoTypeInformation
}
Write-Host "Files exported to $fileName" -ForegroundColor Green

# Search for files

while($true){
    # Prompt for search files or exit and close FLR session
    $search = Read-Host "Do you want to search for a file? (Y/N)"
    if($search -eq "N"){
        Write-Host "Closing FLR session..." -ForegroundColor Yellow
        Stop-VBRUnstructuredBackupFLRSession -Session $flr

        break
    }
    if($search -eq "Y"){
        $searchString = Read-Host "Enter search string"
        $searchResults = $files | Where-Object {$_.Name -like "*$searchString*"}
        
        $date2 = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"

        Write-Host "Number of search results found: $($searchResults.Count)" -foregroundcolor green
        $searchResults | Export-Csv -Path "C:\temp\searchResults_$($name)_$($date2).csv" -NoTypeInformation
        Write-Host "Search results saved to C:\temp\searchResults_$($name).$($date2).csv"
    }
    else{
        Write-Host "Invalid input. Please enter Y or N"
    }

}

