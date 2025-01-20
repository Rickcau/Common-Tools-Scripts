# Clean Up Script
# Cleanup script for Stacks Guru Azure resources

param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "azure-config.json"
)

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
    Write-Log "Starting cleanup process..." -Level Info

    # Perform az login if not already logged in
    Write-Log "Checking Azure login status..." -Level Info
    if (-not (Get-AzContext)) {
        Write-Log "No Azure account logged in. Prompting for login..." -Level Info
        az login | Out-Null  # Log in using the Azure CLI
    }

    # List available subscriptions
    Write-Log "Retrieving available subscriptions..." -Level Info
    $subscriptions = az account list --output json | ConvertFrom-Json

    # Display subscription choices
    Write-Log "Available subscriptions:" -Level Info
    $subscriptions | ForEach-Object {
        Write-Host "$($_.id): $_.name"
    }

    # Allow the user to select a subscription
    $selectedSubscriptionId = Read-Host "Enter the Subscription ID you want to use"

    # Set the selected subscription
    Write-Log "Setting Azure context to subscription ID: $selectedSubscriptionId" -Level Info
    Set-AzContext -SubscriptionId $selectedSubscriptionId

    # Load configuration
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at: $ConfigPath"
    }

    Write-Log "Loading configuration from $ConfigPath" -Level Info
    $config = Get-Content $ConfigPath | ConvertFrom-Json

    # Remove Cosmos DB role assignments
    Write-Log "Removing Cosmos DB role assignments..." -Level Info
    $roleAssignments = Get-AzCosmosDBSqlRoleAssignment `
        -AccountName $config.CosmosDBAccountName `
        -ResourceGroupName $config.ResourceGroupName

    foreach ($assignment in $roleAssignments) {
        if ($assignment.PrincipalId -eq $config.ServicePrincipalId) {
            Write-Log "Removing role assignment: $($assignment.Id)" -Level Info
            Remove-AzCosmosDBSqlRoleAssignment `
                -AccountName $config.CosmosDBAccountName `
                -ResourceGroupName $config.ResourceGroupName `
                -Id $assignment.Id
        }
    }

    # Remove service principal
    try {
        Write-Log "Removing service principal..." -Level Info
        Remove-AzADServicePrincipal -ObjectId $config.ServicePrincipalId
        Write-Log "Service principal removed successfully" -Level Success
    } catch {
        Write-Log "Failed to remove service principal: $_" -Level Error
    }

    # Remove app registration
    try {
        Write-Log "Removing app registration..." -Level Info
        Remove-AzADApplication -ObjectId $config.AppRegistrationId
        Write-Log "App registration removed successfully" -Level Success
    } catch {
        Write-Log "Failed to remove app registration: $_" -Level Error
    }

    # Optional: Remove Cosmos DB Account
    $response = Read-Host "Do you want to remove the Cosmos DB account? (y/n)"
    if ($response -eq 'y') {
        Write-Log "Removing Cosmos DB account..." -Level Warning
        Remove-AzCosmosDBAccount `
            -ResourceGroupName $config.ResourceGroupName `
            -Name $config.CosmosDBAccountName
        Write-Log "Cosmos DB account removed successfully" -Level Success
    } else {
        Write-Log "Keeping Cosmos DB account" -Level Info
    }

    # Remove configuration file
    Remove-Item $ConfigPath -Force
    Write-Log "Configuration file removed" -Level Success

    # Remove .env.local file if it exists
    if (Test-Path ".env.local") {
        Remove-Item ".env.local" -Force
        Write-Log "Environment file removed" -Level Success
    }

    Write-Log "Cleanup completed successfully!" -Level Success

} catch {
    Write-Log "An error occurred during cleanup: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    throw
}
