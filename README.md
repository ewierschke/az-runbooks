# az-runbooks
Various Azure Automation Runbooks

# storageaccountsnapshotmgmt.ps1

A combination of various scripts made into an Azure Automation Runbook; used to creates daily snapshots of all blobs in all storage account containers and then deletes snapshots older than $BackupRetentionDays

# copybetweenstgacctsdiffaadscvpirnc-async.ps1

Azure Automation Runbook used to copy all the contents of a storage account container from one storage account to another in different subscriptions controlled by different Azure Active Directory tenants, using a service principal with credentials stored in a key vault.