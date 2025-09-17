## This script is designed to create a Veeam Backup Job to a VDC Vault repository.
## It creates a job to a base repository, then clones it to the vault repo, and removes the base job.
## It also sets encryption on the job with a key, and disables synthetic fulls.
## Modify the variables below to suit your environment. 
# Set your encryption key here
$keys = Get-VbrEncryptionKey
$key = $keys[0] # select whichever key you want to use from the list
# Set your VM name here
$VmName = "Your VM Name"
# Set your Job name here
$TempJobName = "Your Job Name" # temporary job name used during creation
$FinalJobName = "Your Final Job Name" # final job name after cloning
# Set your Job description here
$Description = "Your Job Description"
# Set your default repository name here
$defaultRepo = "Your Default Repo Name"
# Set your vault repository name here
$vaultRepo = "Your Vault Repo Name"


# Set base / default repo to allow job to be created without encryption
$baseRepo = Get-VBRBackupRepository -Name $defaultRepo
# Check the repo exists
if ($baseRepo -eq $null) {
    Write-Host "Base repository $defaultRepo not found. Exiting script."
    exit
}
# default VDC Vault repo
$vault = Get-VBRBackupRepository -Name $vaultRepo
# Check the repo exists
if ($vault -eq $null) {
    Write-Host "Vault repository $vaultRepo not found. Exiting script."
    exit
}

# Create the job to default repo, set encryption on with Key, disable synthetic full.
$job = Find-VBRViEntity -Name $VmName | Add-VBRViBackupJob -Name $TempJobName  -Description $Description -BackupRepository $baseRepo  | Set-VBRJobAdvancedStorageOptions -EnableEncryption $True -EncryptionKey $key | Set-VBRJobAdvancedBackupOptions -TransformFullToSynthetic $false 
# I'm giving a new name to my vault job instead of the default "_clone"
$newName = $FinalJobName
# clone the job, redirecting to Vault repo
Copy-VBRJob -Job $job -Repository $vault -Name $newName
# remove the base job.
Remove-VBRJob -Job $job -Confirm:$false