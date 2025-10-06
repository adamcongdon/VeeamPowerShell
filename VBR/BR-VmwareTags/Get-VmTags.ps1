#<
.SYNOPSIS
Get VMware tags for automated job management in VBR

.EXAMPLE
Get-VmTags.ps1
This example gets VMware tags for automated job management in VBR

.NOTES
Author: Adam Congdon


>#

$vCenterServer = ""

# Get the VMware entities from the VC, specify tags to pull tags
$vms = Find-VBRViEntity -Server $vCenterServer -Tags

#create a new list to add tags to
$vmTags = @()

# sort the entities and create a list of tags
foreach($v in $vms){
    if($v.Type -eq "Tag"){
        $vmTags += $v
        }
    }

#view tags
$vmTags.Name

# use tags however: i.e. create a job
#$repo = Get-VBRBackupRepository
#Add-VBRViBackupJob -Name "Job" -Entity $vmTags[0] -BackupRepository $repo[2]