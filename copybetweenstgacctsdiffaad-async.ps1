<# 
.SYNOPSIS 
   Copy blobs in a container from the one storage account in one AAD tenant to a different storage account in a different AAD tenant.
   Updates blob if source has newer version. 
.DESCRIPTION 
   Start's an asynchronous copy of blob to a different storage account. 
.EXAMPLE (need to update)
   .\copybetweenstgacctsdiffaad-async.ps1  
         -AzSubscription "Azure Subscription"  
         -srcStorageAccount "Source Storage Account name" 
         -srcStorageRg "Source Storage Resource Group" 
         -destStorageAccount "Target Storage Account name" 
         -destStorageRg "Target Storage Resource Group" 
#> 
<#
param  
( 
    [Parameter(Mandatory = $true)] 
    [String]$azureSubscription, 
 
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
 
#source variables
$source_Tenant_Id = "<sourceAADtenant>"
$source_Subscription_Id = "<sourceSubscriptionID>"
$source_Environment_Name = "<AzureCloud or AzureUSGovernment>"

$srcStorageRg = "<sourceresourcegroupname>"
$srcStorageAccountName = "<sourcestorageaccountname>"

#destination variables
$dest_Tenant_Id = "<destinationAADtenant>"
$dest_Subscription_Id = "<destinationSubscriptionID>"
$dest_Environment_Name = "<AzureCloud or AzureUSGovernment>"

$destStorageRg = "<destinationresourcegroupname>"
$destStorageAccountName = "<destinationstorageaccountname>"

### Source/Dest Container Name ### 
$containerName = "<sourceanddestinationcontainername>"

#Context file variables
$scriptRoot = "$env:Temp"
$sourcecontextpath = "${scriptRoot}\sourcecontext.json"
$destcontextpath = "${scriptRoot}\destcontext.json"

#create source context
Write-Output "Checking for source context...";
if (Test-Path $sourcecontextpath -PathType Leaf) {
    Import-AzContext -Path ${sourcecontextpath}
}
$current_Context = Get-AzContext
if($null -ne $current_Context){
    if(!(($current_Context.Subscription.TenantId -match $source_Tenant_Id) -and ($current_Context.Subscription.Id -match $source_Subscription_Id))){
        do{
            Remove-AzAccount -ErrorAction SilentlyContinue | Out-Null
            $current_Context = Get-AzContext
        } until($null -eq $current_Context)
        Login-AzAccount -EnvironmentName $source_Environment_Name -TenantId $source_Tenant_Id -Subscription $source_Subscription_Id
    }
} elseif ($null -eq $current_Context) {
  Login-AzAccount -EnvironmentName $source_Environment_Name -TenantId $source_Tenant_Id -Subscription $source_Subscription_Id
}
Write-Output "Writing source context to disk...";
Save-AzContext -Path ${sourcecontextpath} -Force

### Create the source storage account context ### 
$srcStorageAccount = Get-AzStorageAccount -ResourceGroupName $srcStorageRg -Name $srcStorageAccountName
$srcContext = $srcStorageAccount.Context
#troubleshooting
#Write-Output "Source storage context...";
#$srcContext

#create dest context
Write-Output "Checking for destination context...";
if (Test-Path $destcontextpath -PathType Leaf) {
    Import-AzContext -Path ${destcontextpath}
}
$current_Context = Get-AzContext
if($null -ne $current_Context){
    if(!(($current_Context.Subscription.TenantId -match $dest_Tenant_Id) -and ($current_Context.Subscription.Id -match $dest_Subscription_Id))){
        do{
            Remove-AzAccount -ErrorAction SilentlyContinue | Out-Null
            $current_Context = Get-AzContext
        } until($null -eq $current_Context)
        Login-AzAccount -EnvironmentName $dest_Environment_Name -TenantId $dest_Tenant_Id -Subscription $dest_Subscription_Id
    }
} elseif ($null -eq $current_Context) {
  Login-AzAccount -EnvironmentName $dest_Environment_Name -TenantId $dest_Tenant_Id -Subscription $dest_Subscription_Id
}
Write-Output "Writing destination context to disk...";
Save-AzContext -Path ${destcontextpath} -Force

### Create the destination storage account context ### 
$destStorageAccount = Get-AzStorageAccount -ResourceGroupName $destStorageRg -Name $destStorageAccountName
$destContext = $destStorageAccount.Context
#troubleshooting
#Write-Output "Destination storage context...";
#$destContext

### Create the container in the destination ### 
try {
    #test if container exists
    $dontsendtoscreen = Get-AzStorageContainer -Name $containerName -Context $destContext -ErrorAction Stop
} catch {
    Write-Output "Creating destination container...";
    New-AzStorageContainer -Name $containerName -Context $destContext 
}
### need to catch if container is being deleted
### how to check for exception name $_.exception.GetType().FullName
### exception name if dest container is still being deleted Microsoft.WindowsAzure.Storage.StorageException

#troubleshooting
#Write-Output "Source storage context...";
#$srcContext
#Write-Output "Destination storage context...";
#$destContext


### Start the asynchronous copy - specify the source authentication with -SrcContext ### 
$blobsArray = Get-AzStorageBlob -Container $containerName -Context $srcContext

#count total blobs in source pre-copy
$sourceblobcount=0
foreach($blob in $blobsArray) {
    $sourceblobcount++
}
Write-Output "##########"
Write-Output "There are ${sourceblobcount} total blobs in the source container."

#foreach blob in blobs loop to copy blobs
Write-Output "##########"
Write-Output "Checking for existance and potential newer blobs and copying blobs that don't exist in destination..."
$newblobs=0
$updatedblobs=0
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
                                 -DestContext $destContext | out-null
        if ($? -eq 1) {
            $newblobs++
        }
        # Add logic to check if copy state even exists, potentially adjust to just record that a long copy started
        ### Check the current status of the copy operation ###
       # $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
        ### Print out status ### 
        #Write-Output $status 
        ### Loop until complete ###                                    
       # While($status.Status -eq "Pending"){
       #     $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
       #     Start-Sleep 5
       #     ### display the formatted status information 
       #     (Get-Date).ToString() + ":" + ( "{0: P0}"  -f ( $status.BytesCopied / $status.TotalBytes))
       #     ### Print out status ###
       #     #Write-Output $status
       #     Write-Output "Waiting for long running copy to complete..." 
       # }
       # Write-Output "Long Running Azure Copy Successfully Complete!"
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
                                 -Force | out-null
        if ($? -eq 1) {
            $updatedblobs++
        }
        # Add logic to check if copy state even exists, potentially adjust to just record that a long copy started
        ### Check the current status of the copy operation ###
       # $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
        ### Print out status ### 
        #Write-Output $status 
        ### Loop until complete ###                                    
       # While($status.Status -eq "Pending"){
       #     $status = Get-AzStorageBlobCopyState -Blob $blob.Name -Container $containerName -Context $destContext
       #     Start-Sleep 5
       #     ### display the formatted status information 
       #     (Get-Date).ToString() + ":" + ( "{0: P0}"  -f ( $status.BytesCopied / $status.TotalBytes))
       #     ### Print out status ###
       #     #Write-Output $status
       #     Write-Output "Waiting for long running copy to complete..." 
       # }
       # Write-Output "Long Running Azure Copy Successfully Complete!"
    }
}
Write-Output "##########"
Write-Output "Blob Copies Complete.  ${newblobs} new blobs copied to container, ${updatedblobs} blobs updated to container"

#add count dest blobs and compare

#display a list of blobs that exist in destination but not source
$destblobsArray = Get-AzStorageBlob -Container $containerName -Context $destContext
$onlyindest = Compare-Object -ReferenceObject $blobsArray.Name -DifferenceObject $destblobsArray.Name -Passthru
if ($onlyindest) {
    Write-Output "##########"
    Write-Output "***The following files were pre-existing in the destination but were not in the source."
    Write-Output "***Investigate whether the files are still needed." 
    foreach($destblob in $onlyindest) {
        $destblobname = $destblob
        Write-Output "- $destblobname"
    }
    Write-Output "##########"
}

Remove-Item ${sourcecontextpath} -Force
Remove-Item ${destcontextpath} -Force