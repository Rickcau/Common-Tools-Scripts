# Ensure you have the required Az modules installed
# Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
# Install-Module -Name Az.CosmosDB -Force
# 1/20/2025 - RDC - Cleanup script for Azure resources created by Setup-AppReg-Cosmos.ps1

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Gray }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Also save to a log file
    $logMessage | Out-File -FilePath "cleanup_log.txt" -Append
}

try {
    # Read configuration file
    Write-Log "Reading configuration from azure-config.json..." -Level Info
    if (-not (Test-Path "azure-config.json")) {
        throw "Configuration file 'azure-config.json' not found!"
    }
    $config = Get-Content "azure-config.json" | ConvertFrom-Json

    # Connect to Azure using service principal
    Write-Log "Connecting to Azure..." -Level Info
    $secureSecret = ConvertTo-SecureString $config.ClientSecret -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($config.AppId, $secureSecret)
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $config.TenantId
    Set-AzContext -SubscriptionId $config.SubscriptionId

    # Remove Data Plane Role Assignment
    Write-Log "Removing Cosmos DB Data Plane Role Assignment..." -Level Info
    $roleAssignments = Get-AzCosmosDBSqlRoleAssignment `
        -AccountName $config.CosmosDBAccountName `
        -ResourceGroupName $config.ResourceGroupName
    foreach ($assignment in $roleAssignments) {
        if ($assignment.PrincipalId -eq $config.ServicePrincipalId) {
            Remove-AzCosmosDBSqlRoleAssignment `
                -AccountName $config.CosmosDBAccountName `
                -ResourceGroupName $config.ResourceGroupName `
                -Name $assignment.Name
            Write-Log "Removed Data Plane Role Assignment." -Level Success
        }
    }

    # Remove Control Plane Role Assignments
    Write-Log "Removing Control Plane Role Assignments..." -Level Info
    $roleAssignments = Get-AzRoleAssignment -ObjectId $config.ServicePrincipalId
    foreach ($assignment in $roleAssignments) {
        Remove-AzRoleAssignment -ObjectId $config.ServicePrincipalId `
            -RoleDefinitionName $assignment.RoleDefinitionName `
            -Scope $assignment.Scope
    }
    Write-Log "Removed Control Plane Role Assignments." -Level Success

    # Remove Cosmos DB Account
    Write-Log "Removing Cosmos DB Account: $($config.CosmosDBAccountName)..." -Level Info
    Remove-AzCosmosDBAccount -ResourceGroupName $config.ResourceGroupName `
        -Name $config.CosmosDBAccountName `
        -Force
    Write-Log "Removed Cosmos DB Account." -Level Success

    # Remove App Registration and Service Principal
    Write-Log "Removing App Registration and Service Principal..." -Level Info
    Remove-AzADApplication -ApplicationId $config.AppId -Force
    Write-Log "Removed App Registration and associated Service Principal." -Level Success

    # Remove Resource Group
    Write-Log "Removing Resource Group: $($config.ResourceGroupName)..." -Level Info
    Remove-AzResourceGroup -Name $config.ResourceGroupName -Force
    Write-Log "Removed Resource Group." -Level Success

    # Clean up local configuration files
    Write-Log "Cleaning up local configuration files..." -Level Info
    if (Test-Path "azure-config.json") {
        Remove-Item "azure-config.json"
    }
    if (Test-Path ".env.local") {
        Remove-Item ".env.local"
    }
    Write-Log "Removed local configuration files." -Level Success

    Write-Log "Cleanup completed successfully!" -Level Success
}
catch {
    Write-Log "An error occurred during cleanup: $_" -Level Error
    throw
}