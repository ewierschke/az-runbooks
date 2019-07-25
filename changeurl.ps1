<# 
.SYNOPSIS 
   Within a storage account container search blob contents for blobs with specific extension and replace original string with new string (ie url component which includes storage acct and container) 
.DESCRIPTION 
   

<#
Azure Automation Account needs the following modules updated/imported prior to
executing this Runbook (typically available in the Modules gallery):
#need to verify
Az.Accounts, Az.Automation, Az.Storage 

Azure Automation Account Variables need to be created before execution, with 
names 'SubscriptionId' - String (unencrypted) 
Additional Variables can be populated and then called via Get-AzAutomationVariable instead of populating the below variables
#>

###update the below variables
$StorageRg = "<resourcegroupname>"
$StorageAccountName = "<storageaccountname>"
$containerName = "<containername>"
$blobendpointsuffix = "<.blob.core.usgovcloudapi.net or blob.core.windows.net>"
$originalstring = "<ie https://s3.amazonaws.com/watchmaker>"
###update the above variables
$newstring = "https://${StorageAccountName}"+"${blobendpointsuffix}/${containerName}"

#Do Not modify these variables
$SubId = Get-AzAutomationVariable -Name 'SubscriptionId'
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

#Login as Automation Account's Run As Account
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
#$subId = $azSubscription
Set-AzContext -Subscription $SubId

### Create the source storage account context ### 
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageRg -Name $StorageAccountName
$stgContext = $StorageAccount.Context
 
### Start the asynchronous copy - specify the source authentication with -SrcContext ### 
$blobsArray = Get-AzStorageBlob -Container $containerName -Context $stgContext
#foreach blob in blobs loop
$tempspace = "$env:Temp"
$countupdatedblobs=0
$countcontainsstring=0
$extensions = @(".repo")
foreach($blob in $blobsArray) {
    # use name as identifier
    $blobName = $blob.name;
  
    # get extension
    $extension = [System.IO.Path]::GetExtension($blobName).ToLower();
 
    # update blob if extension is affected
    if($extensions.Contains($extension))
    {
        try {
            $dontsendtoscreen1 = Get-AzStorageBlobContent -Blob $blobName -Container $containerName -Destination $tempspace -Context $stgContext -Force:$true
            $newname = $blobName.replace("/", "\")
            $lclpath = $tempspace + '\' + $newname
            #check each blob contents for presence of $originalstring string and replace with $newstring string
            $file = Get-Content $lclpath
            $containsstring = $file | ForEach-Object{$_ -match $originalstring}
            if ($containsstring -contains $true) {
                $countcontainsstring++
                (Get-Content $lclpath).replace("$originalstring", "$newstring") | Set-Content $lclpath
                $dontsendtoscreen2 = Set-AzStorageBlobContent -File $lclpath -Blob $blobName -Container $containerName -Context $stgContext -Force
                if ($? -eq "True") {
                   $countupdatedblobs++
                }
            }
        } catch {
            # Report any other error
            Write-Error $Error[0].Exception;
        }
    }
}
Write-Output "##########"
Write-Output "Script Complete.  ${countcontainsstring} blobs had original string: ${originalstring}, ${countupdatedblobs} blobs updated with new string: ${newstring}"
