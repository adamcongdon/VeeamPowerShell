#<
.SYNOPSIS
Extracts NAS information from Veeam log files for V12.

.DESCRIPTION
This script parses Veeam log files to extract relevant NAS information for V12.

.PARAMETER logsPath
The path to the Veeam log file to parse.
.PARAMETER csvFilePath
The path to save the first CSV output file.
.PARAMETER csv2FilePath
The path to save the second CSV output file.
.EXAMPLE
.\Get-NasInfo_for_V12up.ps1
This example runs the script with default parameters.
.NOTES
Adjust the paths for logs and output files as needed.
Author: Adam Congdon
Date: 2024-10-01

>#
# VMC log path is hardcoded for now. If logs are sent elsewhere, please adjust accordingly.
 $logsPath = "C:\ProgramData\Veeam\Backup\Utils\VMC.log"

 # section identifiers
 $unstrucStart = "=====UNSTRUCTURED DATA===="
  $nasStart = "=====NAS INFRASTRUCTURE===="
 $sectionEnd = "========"
 
 #output files, feel free to rename and relocate
 $csvFilePath = 'Share Breakdown.csv'
 $csv2FilePath = 'output2.csv'
 
 #get file info and set empty containers.
 $content = Get-Content $logsPath
 $sections = @()
 $currentSection = @()
 $capturing = $false
 
 foreach($line in $content){
     if(-not $capturing -and $line -match $unstrucStart){
         $capturing = $true
         $currentSection = @()
         #$currentSection += $line.Remove(0,50)
     }
     elseif(-not $capturing -and $line -match $nasStart){
        $capturing = $true
        $currentSection = @()
        #$currentSection += $line.Remove(0,50)
    }
     elseif($capturing){
         if($line -match $sectionEnd){
             $capturing = $false
             $sections += ,($currentSection)
             $currentSection = @()
         }
         else{
             if( -not $line -match "[VmcStats]"){
                 $currentSection += $line.Remove(0,49)
             }
         }
     }
 }
 
 # Here we set a new list to only contain the final data section from the log:
 $dataLines = $sections[$sections.Count-1]
 $data = @()

 # search each line, looking for these strings: TotalObjectStorageSize, NasBackupSourceShareStats, TotalShareSize. Group each into their own list
    $totalObjectStorageSize = @()
    $nasBackupSourceShareStats = @()
    $totalShareSize = @()
    $dataLines | ForEach-Object {
        if($_ -match "TotalObjectStorageSize"){
            $totalObjectStorageSize += $_
        }
        elseif($_ -match "NasBackupSourceShareStats"){
            $nasBackupSourceShareStats += $_
        }
        elseif($_ -match "TotalShareSize"){
            $totalShareSize += $_
        }
    }

 
    # converting to CSV data based on property for readability
    $csvData = $totalObjectStorageSize | ForEach-Object {
        $properties = @{}
        # Split using comma and create key-value pairs
        $_.Trim() -split ', ' | ForEach-Object {
            $key, $value = $_.Split(':', 2).Trim()
            $properties[$key] = $value
        }
        # Output as a PSCustomObject
        [PSCustomObject]$properties
    }
# export to csv
$csvData | Export-Csv -Path totalObjectStorageSize.csv -NoTypeInformation

#convert $nasBackupSourceShareStats to CSV and export to new csv file
$csvData2 = $nasBackupSourceShareStats | ForEach-Object {
    $properties = @{}
    # Split using comma and create key-value pairs
    $_.Trim() -split ', ' | ForEach-Object {
        $key, $value = $_.Split(':', 2).Trim()
        $properties[$key] = $value
    }
    # Output as a PSCustomObject
    [PSCustomObject]$properties
}
# export to csv
$csvData2 | Export-Csv -Path nasdata.csv -NoTypeInformation

#convert $totalShareSize to CSV and export to new csv file
$csvData3 = $totalShareSize | ForEach-Object {
    $properties = @{}
    # Split using comma and create key-value pairs
    $_.Trim() -split ', ' | ForEach-Object {
        $key, $value = $_.Split(':', 2).Trim()
        $properties[$key] = $value
    }
    # Output as a PSCustomObject
    [PSCustomObject]$properties
}
# export to csv
$csvData3 | Export-Csv -Path sharesize.csv -NoTypeInformation