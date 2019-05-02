<#
 Azure Runbook to create and purge snapshots for every blob in a storage account

 Azure Automation Account needs the following modules updated/imported prior to
 executing this Runbook (typically available in the Modules gallery):
 Azure, AzureRM.Storage (default modules in new Automation Accounts)

 Azure Automation Account Variables need to be created before execution, with 
 names 'SubscriptionId' - String (unencrypted) and
 'StorageAccountKey' - String (encrypted)
#>

###update the below variables
$environmentName = '<AzureCloud or AzureUSGovernment>'
$storageAccountName = '<storageaccountname>'
$BackupRetentionDays = 30
$BackupLastDayOfMonthRetentionDays = 180
###update the above variables

#Do Not modify these variables
$SubId = Get-AutomationVariable -Name 'SubscriptionId'
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

#Uncomment to Login as interactive user (comment out Login as Runbook login section)
#Write-Output "Logging in...";
#$context = Get-AzureRmContext
#if ($context.Name -like "Default") 
#{
#    Login-AzureRmAccount -EnvironmentName $environmentName
#}
#elseif (!$context)
#{
#    Login-AzureRmAccount -EnvironmentName $environmentName
#}
# select subscription
#Write-Output "Selecting subscription '$subscriptionId'";
#Select-AzureRmSubscription -SubscriptionID $subscriptionId;

#Login as Runbook
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
        -EnvironmentName $environmentName
 }
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Set-AzureRmContext -SubscriptionId $SubId
#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************
Write-Output "----STARTING SNAPSHOT CREATION STEP----"

# ref - https://blogs.msdn.microsoft.com/cie/2016/05/17/using-blob-snapshots-with-powershell/
# creates snapshot of all blobs in all storage account containers
#get storage acct key - update can't appear to store as array in runbook, stores $keys as System.Object
#$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName
#Write-Output $keys[0].Value
#Create storage acct context
#$ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keys[0].Value
$keyvar = Get-AutomationVariable -Name 'StorageAccountKey'
$ctx = (New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keyvar)

#get containers
$containers = Get-AzureStorageContainer -Context $ctx

foreach ($container in $containers)
{
  $x=0
  $thiscontainer = $container[$x].Name
  Write-Output "Working in container... $thiscontainer"
  $container = Get-AzureStorageContainer -Context $Ctx -Name $container[$x].Name
  $ListOfBlobs = $container.CloudBlobContainer.ListBlobs($BlobName, $true, "Snapshots")

  foreach ($CloudBlockBlob in $ListOfBlobs)
  {
    if (-Not $CloudBlockBlob.IsSnapshot)
    {
      Write-Output "Working on blob... "$CloudBlockBlob.Name"."
      Try
      {
        $thisblob = Get-AzureStorageBlob -Context $ctx -Container $container[$x].Name -Blob $CloudBlockBlob.Name
        $thisblob.ICloudBlob.CreateSnapshot()
        Write-Output "Successfully CREATED a snapshot of blob "$CloudBlockBlob.Name"."
      }
      Catch
      {
      Write-Output "Failed to CREATE a snapshot of blob "$CloudBlockBlob.Name"." -ForegroundColor Red
      }
    }
  }
  $x++
}

Write-Output "----CREATION STEP COMPLETE----"
Write-Output "----"
Write-Output "----STARTING SNAPSHOT PURGE STEP----"

# ref - https://dzone.com/articles/automate-azure-blob-snapshot
# Delete snapshots older than BackupRetentionDays
# Keeps at least one snapshot (the latest)
# Keep snapshot from last day of month until snapshot is older than BackupLastDayOfMonthRetentionDays
# Assumes there is no need to keep manual (outside of BackupRetentionDays window) snapshots - would have to copy snapshot to new blob in a different container

# If BackupRetentionDays is set to -1 script should delete all snapshots but the latest

#repeating here in case runbook separated into two distinct runbooks
#get storage acct key - update can't appear to store as array in runbook, stores $keys as System.Object
#$keys = Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName
#Write-Output $keys[0].Value
#Create storage acct context
#$ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keys[0].Value
$keyvar = Get-AutomationVariable -Name 'StorageAccountKey'
$ctx = (New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $keyvar)
#get containers
$containers = Get-AzureStorageContainer -Context $ctx

$varBackupRetentionDays = $BackupRetentionDays
$varBackupLastDayOfMonthRetentionDays = $BackupLastDayOfMonthRetentionDays

if( $varBackupRetentionDays -ge $varBackupLastDayOfMonthRetentionDays )
{
  $message = "Argument Exception: BackupRetentionDays cannot be greater than or equal to BackupLastDayOfMonthRetentionDays"
  throw $message
}

foreach ($container in $containers)
{
  $x=0
  $thiscontainer = $container[$x].Name
  Write-Output "Working in container... $thiscontainer"
  $currentcontainer = Get-AzureStorageContainer -Context $Ctx -Name $container[$x].Name
  $ListOfBlobs = $currentcontainer.CloudBlobContainer.ListBlobs($BlobName, $true, "Snapshots")
  #Get all blobs with more than one snapshot
  $baseBlobWithMoreThanOneSnapshot = $container.CloudBlobContainer.ListBlobs($BlobName, $true, "Snapshots") | Group-Object Name | Where-Object {$_.Count -gt 1} | Select Name
  #Filter blobs with more than one snapshot and only get snapshots.
  $blobs = $ListOfblobs | Where-Object {$baseBlobWithMoreThanOneSnapshot  -match $_.Name -and $_.SnapshotTime -ne $null} | Sort-Object SnapshotTime -Descending

  foreach ($baseBlob in $baseBlobWithMoreThanOneSnapshot )
  {
    $count = 0
    foreach ( $blob in $blobs | Where-Object {$_.Name -eq $baseBlob.Name } )
      {
        $count +=1
        $ageOfSnapshot = [System.DateTime]::UtcNow - $blob.SnapshotTime.UtcDateTime
        #Write-Output $ageOfSnapshot
        $blobAddress = $blob.Uri.AbsoluteUri + "?snapshot=" + $blob.SnapshotTime.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
        #Write-Output $blobAddress

        #Fail safe double check to ensure we only delete a snapshot.
        if($null -ne $blob.SnapShotTime)
        {
          #Never delete the latest snapshot, so we always have at least one backup irrespective of retention period.
          if($ageOfSnapshot.Days -gt $varBackupRetentionDays -and $count -eq 1)
          {
            Write-Output "Skipped Purging Latest Snapshot"  $blobAddress
            continue
          }

          if($ageOfSnapshot.Days -gt $varBackupRetentionDays -and $count -gt 1 )
          {
            #Do not backup last day of month backups
            if($blob.SnapshotTime.Month -eq $blob.SnapshotTime.AddDays(1).Month)
            {
              Write-Output "Purging Snapshot "  $blobAddress
              $blob.Delete()
              continue
            }
            #Purge last day of month backups based on monthly retention.
            elseif($blob.SnapshotTime.Month -ne $blob.SnapshotTime.AddDays(1).Month)
            {
              if($ageOfSnapshot.Days -gt $varBackupLastDayOfMonthRetentionDays)
              {
                Write-Output "Purging Last Day of Month Snapshot "  $blobAddress
                $blob.Delete()
                continue
              }
            }
            else
            {
              Write-Output "Skipped Purging Last Day Of Month Snapshot"  $blobAddress
              continue
            }
          }

          #Not sure why this is here
          if($count % 5 -eq 0)
          {
            Write-Output "Processing..."  
          }
        }
        else
        {
          Write-Output "Found Blob instead of Snapshot...Skipped Purging "  $blobAddress
        }
      }
  }
}
  
###Delete snapshots created between min and max date
### If the the Min date is set to the oldest snapshot and Max date is set to a 
### future date/time, all snapshots are deleted
###ref - https://blogs.msdn.microsoft.com/cie/2016/05/17/using-blob-snapshots-with-powershell/
  
#foreach ($container in $containers)
#{
#  $x=0
#  $thiscontainer = $container[$x].Name
#  Write-Output "Working in container... $thiscontainer"
#  $container = Get-AzureStorageContainer -Context $Ctx -Name $container[$x].Name
#  $ListOfBlobs = $container.CloudBlobContainer.ListBlobs($BlobName, $true, "Snapshots")

#  $minDate = [datetime]"06/05/2018 9:00 AM"
#  $maxDate = [datetime]"06/08/2018 9:00 PM"

#  foreach ($CloudBlockBlob in $ListOfBlobs)
#  {
#    if ($CloudBlockBlob.IsSnapshot)
#    {
#      Write-Output "Working on blob... "$CloudBlockBlob.Name"."
#      if ($CloudBlockBlob.SnapshotTime -le $maxDate -and $CloudBlockBlob.SnapshotTime -ge $minDate )
#      {
#        Try
#        {
#          $CloudBlockBlob.Delete()
#          Write-Output "Successfully DELETED snapshot of blob "$CloudBlockBlob.Name"."
#        }
#        Catch
#        {
#          Write-Output "Failed to DELETE a snapshot of blob "$CloudBlockBlob.Name"." -ForegroundColor Red
#        }
#      }
#    }
#  }
#  $x++
#}

Write-Output "----PURGE STEP COMPLETE----"