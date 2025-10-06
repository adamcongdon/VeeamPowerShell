<#
.SYNOPSIS
Sends Veeam ONE alerts to NTFY via their API.
.DESCRIPTION
This script takes parameters from Veeam ONE alerting and formats them for NTFY's API.
It includes debug logging to a file for troubleshooting.
.PARAMETER AlarmName
The name of the alarm.

.PARAMETER NodeName
The name of the node.

.PARAMETER Summary
A brief summary of the alarm.

.PARAMETER AlarmTime
The time the alarm was triggered.

.PARAMETER AlarmStatus
The current status of the alarm.

.PARAMETER PreviousStatus
The previous status of the alarm.

.PARAMETER AlarmID
The unique identifier for the alarm.

.PARAMETER ChildObjectType
The type of the child object associated with the alarm.
.EXAMPLE
.\VeeamOne_Ntfy.ps1 -AlarmName "Disk Space Low" -NodeName "Server01" -Summary "Disk space on C: drive is below threshold." -AlarmTime "10/1/2025 10:59:03 AM" -AlarmStatus "Error" -PreviousStatus "Warning" -AlarmID "12345" -ChildObjectType "Disk"
This example sends a "Disk Space Low" alert for "Server01" to NTFY.
.NOTES
This script is best adapted by adding the "Run Script" action to the desired Alarm(s) in the Notification settings of Veeam ONE.
Ensure that the script has the necessary permissions to execute and access the network.

REQUIRED ENVIRONMENT VARIABLES:
- NTFY_SERVER_URL: Your NTFY server URL (e.g., https://ntfy.sh or your self-hosted instance)
- NTFY_TOPIC: The NTFY topic to publish alerts to
- NTFY_AUTH_TOKEN: Your NTFY authentication token (optional, for private topics)

Suggested values:
Action = Run Script
Value = powershell.exe VeeamOne_Ntfy.ps1 '%1' '%2' '%3' '%4' '%5' '%6' '%7' '%8'
Condition = Any State

Author: Adam Congdon
Date: 2024-10-01

With a special thanks to GitHub Copilot for assistance in debug logging implementation.

#>



param (
    [string]$AlarmName,
    [string]$NodeName,
    [string]$Summary,
    [string]$AlarmTime,
    [string]$AlarmStatus,
    [string]$PreviousStatus,
    [string]$AlarmID,
    [string]$ChildObjectType

)


# Debug logging setup
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Cross-platform temp directory
if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $tempDir = "C:\temp"
} else {
    $tempDir = "/tmp"
}

$logFile = Join-Path $tempDir "NtfyDebug_$timestamp.log"

# Ensure the temp directory exists
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force
}

# Function to write debug log
function Write-DebugLog {
    param([string]$Message)
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $logFile -Value $logEntry
    Write-Output $logEntry
}

# NTFY Configuration
$ntfyServerUrl = $env:NTFY_SERVER_URL
$ntfyTopic = $env:NTFY_TOPIC
$ntfyAuthToken = $env:NTFY_AUTH_TOKEN  # Optional for private topics



if (-not $ntfyServerUrl -or -not $ntfyTopic) {
    Write-DebugLog "ERROR: NTFY configuration not found in environment variables"
    Write-Error "Please set NTFY_SERVER_URL and NTFY_TOPIC environment variables"
    exit 1
}
Write-DebugLog "NTFY configuration loaded - Server: $ntfyServerUrl, Topic: $ntfyTopic"

# Function to write debug log



Write-DebugLog "Script started with parameters:"
Write-DebugLog "  AlarmName: $AlarmName"
Write-DebugLog "  NodeName: $NodeName"
Write-DebugLog "  Summary: $Summary"
Write-DebugLog "  AlarmTime: $AlarmTime"
Write-DebugLog "  AlarmStatus: $AlarmStatus"
Write-DebugLog "  PreviousStatus: $PreviousStatus"
Write-DebugLog "  AlarmID: $AlarmID"
Write-DebugLog "  ChildObjectType: $ChildObjectType"
Write-DebugLog "Original AlarmStatus: $AlarmStatus"


# Map alarm statuses to NTFY priority levels and tags
$ntfyPriority = 3  # Default priority
$ntfyTags = @()

if ($AlarmStatus -eq "Error") {
    $ntfyPriority = 5  # Max priority
    $ntfyTags = @("rotating_light", "veeam", "error")
}
elseif ($AlarmStatus -eq "Acknowledged") {
    $ntfyPriority = 3  # Default priority
    $ntfyTags = @("white_check_mark", "veeam", "acknowledged")
}
elseif ($AlarmStatus -eq "Reset/resolved") {
    $ntfyPriority = 2  # Low priority
    $ntfyTags = @("green_circle", "veeam", "resolved")
}
elseif ($AlarmStatus -eq "Warning") {
    $ntfyPriority = 4  # High priority
    $ntfyTags = @("warning", "veeam", "warning")
}

Write-DebugLog "Mapped AlarmStatus '$AlarmStatus' to NTFY priority: $ntfyPriority, tags: $($ntfyTags -join ',')"
# Construct NTFY API URL
$ntfyUrl = "$ntfyServerUrl/$ntfyTopic"
Write-DebugLog "NTFY URL configured: $ntfyUrl"

# Parse AlarmTime with explicit format, fallback to now if fails

Write-DebugLog "Parsing alarm time: $AlarmTime"
$timestamp = 0

try {
    # Try multiple format patterns to handle different date formats
    $formats = @(
        "M/d/yyyy h:mm:ss tt",     # 10/1/2025 10:59:03 AM
        "MM/dd/yyyy hh:mm:ss tt",  # 10/01/2025 10:59:03 AM
        "M/d/yyyy hh:mm.ss tt",    # 10/1/2025 10:59.03 AM
        "MM/dd/yyyy hh:mm.ss tt"   # 10/01/2025 10:59.03 AM
    )
    $parsed = $false

    foreach ($format in $formats) {
        try {
            $dateTime = [datetime]::ParseExact($AlarmTime, $format, $null)
            $dateTimeLocal = [DateTime]::SpecifyKind($dateTime, [DateTimeKind]::Local)
            $timestamp = [int]([datetimeoffset]$dateTimeLocal).ToUnixTimeSeconds()
            Write-DebugLog "Successfully parsed alarm time using format '$format'. Unix timestamp: $timestamp (treated as UTC)"
            $parsed = $true
            break
        }

        catch {
            # Continue to next format
        }

    }

    if (-not $parsed) {
        throw "No format matched"

    }
}

catch {
    $timestamp = [int](Get-Date -UFormat %s)
    Write-DebugLog "Failed to parse alarm time with all formats, using current time. Unix timestamp: $timestamp. Error: $($_.Exception.Message)"

}

Write-DebugLog "Building NTFY message..."

# Create the message title and body for NTFY
$messageTitle = "[$NodeName] $AlarmName"
$messageBody = @"
$Summary

Status: $AlarmStatus
Node: $NodeName
Alarm ID: $AlarmID
Child Object: $ChildObjectType
Previous Status: $PreviousStatus
Time: $AlarmTime
"@

Write-DebugLog "NTFY message created:"
Write-DebugLog "Title: $messageTitle"
Write-DebugLog "Body: $messageBody"
Write-DebugLog "Priority: $ntfyPriority"
Write-DebugLog "Tags: $($ntfyTags -join ',')"

# Prepare headers for NTFY
$headers = @{
    "Title" = $messageTitle
    "Priority" = $ntfyPriority.ToString()
    "Tags" = ($ntfyTags -join ",")
}

# Add authentication if token is provided
if ($ntfyAuthToken) {
    $headers["Authorization"] = "Bearer $ntfyAuthToken"
    Write-DebugLog "Authentication header added"
}

Write-DebugLog "Headers configured for NTFY request"

Write-DebugLog "Sending request to NTFY API..."

try {
    $response = Invoke-WebRequest -Uri $ntfyUrl -Method Post -Headers $headers -Body $messageBody -ContentType "text/plain; charset=utf-8"

    Write-DebugLog "Alert sent successfully to NTFY. Status Code: $($response.StatusCode)"
    Write-DebugLog "Response Content: $($response.Content)"
    Write-Output "Alert sent successfully to NTFY: $($response.StatusCode)"
}
catch {
    Write-DebugLog "Failed to send alert to NTFY. Error: $($_.Exception.Message)"
    Write-DebugLog "Full Error Details: $($_ | Out-String)"
    Write-Error "Failed to send alert to NTFY: $_"
}

Write-DebugLog "NTFY notification script execution completed"
Write-DebugLog "Log file location: $logFile"