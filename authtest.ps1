$dest_Environment_Name = "AzureUSGovernment"

###update the above variables
# Do the work...
#create dest context using Run As Account
Write-Output "Login as Run As Account to get key vault values...";

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
        -EnvironmentName $dest_Environment_Name
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

$context = Get-AzContext
Write-Output $context

$keyvaults = Get-AzKeyVault
Write-Output $keyvaults