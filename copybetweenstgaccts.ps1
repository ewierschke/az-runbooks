<# 
.SYNOPSIS 
   Copy blobs in a container from the one storage account to a different storage account.  Updates blob if source has newer version. 
.DESCRIPTION 
   Start's an asynchronous copy of blob to a different storage account. 
.EXAMPLE 
   .\copybetweenstgaccts.ps1  
         -azSubscription "Azure Subscription"  
         -srcStorageAccount "Source Storage Account name" 
         -srcStorageRg "Source Storage Resource Group" 
         -destStorageAccount "Destination Storage Account name" 
         -destStorageRg "Destination Storage Resource Group" 
         -containername "Source and Destination Container Name"
#> 
<#
param  
( 
    [Parameter(Mandatory = $true)] 
    [String]$azSubscription, 
 
    [Parameter(Mandatory = $true)] 
    [String]$srcStorageAccount, 
 
    [Parameter(Mandatory = $true)] 
    [String]$srcStorageRg,

    [Parameter(Mandatory = $true)] 
    [String]$destStorageAccount, 
 
    [Parameter(Mandatory = $true)] 
    [String]$destStorageRg,
    
    [Parameter(Mandatory = $true)] 
    [String]$containerName
) #>
##Uncomment above param block if running as script requesting parameters

<#
Azure Automation Account needs the following modules updated/imported prior to
executing this Runbook (typically available in the Modules gallery):
Az.Accounts, AzureRM.Storage (default modules in new Automation Accounts)

Azure Automation Account Variables need to be created before execution, with 
names 'SubscriptionId' - String (unencrypted) 
#>

###comment out below if running as script requesting parameters
###update the below variables
$srcStorageRg = "<sourceresourcegroupname>"
$srcStorageAccountName = "<sourcestorageaccountname>"
$destStorageRg = "<destinationresourcegroupname>"
$destStorageAccountName = "<destinationstorageaccountname>"
### Source/Dest Container Name ### 
$containerName = "<sourceanddestinationcontainername>"
###update the above variables

#Do Not modify these variables
$SubId = Get-AutomationVariable -Name 'SubscriptionId'
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

#Login as Runbook
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName

    "Logging in to Azure..."
    Add-AzAccount `
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
###Uncomment above if switching to script requesting parameters
$subId = $azSubscription
Set-AzContext -Subscription $SubId

### Create the source storage account context ### 
$srcStorageAccount = Get-AzStorageAccount -ResourceGroupName $srcStorageRg -Name $srcStorageAccountName
$srcContext = $srcStorageAccount.Context
 
### Create the destination storage account context ### 
$destStorageAccount = Get-AzStorageAccount -ResourceGroupName $destStorageRg -Name $destStorageAccountName
$destContext = $destStorageAccount.Context
 
### Create the container on the destination ### 
try {
    #test if container exists
    $dontsendtoscreen = Get-AzStorageContainer -Name $containerName -Context $destContext -ErrorAction Stop
} catch {
    New-AzStorageContainer -Name $containerName -Context $destContext 
}

### how to check for exception name $_.exception.GetType().FullName
### exception name if dest container is still being deleted Microsoft.WindowsAzure.Storage.StorageException
 
### Start the asynchronous copy - specify the source authentication with -SrcContext ### 
$blobsArray = Get-AzStorageBlob -Container $containerName -Context $srcContext
#foreach blob in blobs loop
$newfiles=0
$updatedfiles=0
foreach($blob in $blobsArray) {
    try {   
        #test if blob exists (does not download content)
        $dontsendtoscreen2 = Get-AzStorageBlob -Blob $blob.Name -Container $containerName -Context $destContext -ErrorAction Stop
    } catch [Microsoft.WindowsAzure.Commands.Storage.Common.ResourceNotFoundException] {
        # Or Add logic here to remember that the blob doesn't exist...
        $blobname = $blob.Name
        Write-Output "Blob '${blobname}' Not Found, copying..."
        # if blob doesn't exist, Copy blob
        $dontsendtoscreen3 = Start-AzStorageBlobCopy -CloudBlob $blob.ICloudBlob `
                                 -SrcContext $srcContext `
                                 -DestContainer $containerName `
                                 -DestContext $destContext
        if ($? -eq 1) {
            $newfiles++
        }
        # Add logic to check if copy state even exists, potentially adjust to just record that a long copy started
        ### Check the current status of the copy operation ###
        $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
        ### Print out status ### 
        Write-Output $status 
        ### Loop until complete ###                                    
        While($status.Status -eq "Pending"){
            $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
            Start-Sleep 5
            ### display the formatted status information 
            (Get-Date).ToString() + ":" + ( "{0: P0}"  -f ( $status.BytesCopied / $status.TotalBytes))
            ### Print out status ###
            Write-Output $status
        }
        Write-Output "Long Running Azure Copy Successfully Complete!"
    } catch {
        # Report any other error
        Write-Error $Error[0].Exception;
    }
    #compare LastModified
    $destblob = Get-AzStorageBlob -Container $containerName -Blob $blob.Name -Context $destContext
    $destblobutcticks = $destblob.LastModified.UtcTicks
    $srcblobutcticks = $blob.LastModified.UtcTicks
    #if source is newer than dest, copy
    if ( $srcblobutcticks -gt $destblobutcticks ) {
        $blobname = $blob.Name
        Write-Output "Newer Blob '${blobname}' found in source, copying..."
        $dontsendtoscreen5 = Start-AzStorageBlobCopy -CloudBlob $blob.ICloudBlob `
                                 -SrcContext $srcContext `
                                 -DestContainer $containerName `
                                 -DestContext $destContext `
                                 -Force
        if ($? -eq 1) {
            $updatedfiles++
        }
        # Add logic to check if copy state even exists, potentially adjust to just record that a long copy started
        ### Check the current status of the copy operation ###
        $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
        ### Print out status ### 
        Write-Output $status 
        ### Loop until complete ###                                    
        While($status.Status -eq "Pending"){
            $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
            Start-Sleep 5
            ### display the formatted status information 
            (Get-Date).ToString() + ":" + ( "{0: P0}"  -f ( $status.BytesCopied / $status.TotalBytes))
            ### Print out status ###
            Write-Output $status
        }
        Write-Output "Long Running Azure Copy Successfully Complete!"
    }
}
Write-Output "Script Complete.  ${newfiles} New files copied to container, ${updatedfiles} Files updated to container"