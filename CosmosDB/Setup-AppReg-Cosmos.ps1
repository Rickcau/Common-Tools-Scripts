# Ensure you have the required Az modules installed
# Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
# Install-Module -Name Az.CosmosDB -Force
# 1/20/2025 - RDC - This script is working as expected.

#  .\Setup-AppReg-Cosmos.ps1 `
#     -SubscriptionId "00000000-0000-0000-0000-000000000000" `
#     -ResourceGroupName "rg-cosmos-test" `
#     -CosmosDBAccountName "cosmos-test-account" `
#     -AppRegistrationName "cosmos-test-app"

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$CosmosDBAccountName,

    [Parameter(Mandatory=$true)]
    [string]$AppRegistrationName,
    
    [Parameter(Mandatory=$false)]
    [string]$CosmosDBName = "my-app-db",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "centralus"
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
    Write-Host $logMessage
}

try {
    Write-Log "Connecting to Azure..." -Level Info
    Connect-AzAccount -ErrorAction Stop
    Set-AzContext -SubscriptionId $SubscriptionId

    # Check if the resource group exists
    Write-Log "Checking if resource group '$ResourceGroupName' exists..." -Level Info
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

    if (-not $resourceGroup) {
        Write-Log "Resource group '$ResourceGroupName' not found. Creating it..." -Level Info
        $resourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Write-Log "Resource group '$ResourceGroupName' created successfully." -Level Success
    } else {
        Write-Log "Resource group '$ResourceGroupName' exists. Using it." -Level Success
    }

    # Create App Registration
    Write-Log "Creating App Registration: $AppRegistrationName..." -Level Info
    $appRegistration = New-AzADApplication -DisplayName $AppRegistrationName -SignInAudience "AzureADMyOrg"
    if (-not $appRegistration -or -not $appRegistration.Id) {
        throw "Failed to create App Registration: $AppRegistrationName"
    }
    Write-Log "App Registration created successfully. AppId: $($appRegistration.AppId)" -Level Success

    # Ensure Service Principal (Enterprise Application) Exists
    Write-Log "Ensuring Service Principal is created for App Registration..." -Level Info
    $sp = Get-AzADServicePrincipal -ApplicationId $appRegistration.AppId -ErrorAction SilentlyContinue
    if (-not $sp) {
        Write-Log "Service Principal not found. Creating it explicitly..." -Level Info
        $sp = New-AzADServicePrincipal -ApplicationId $appRegistration.AppId
    }
    if (-not $sp -or -not $sp.Id) {
        throw "Service Principal creation failed for AppId: $($appRegistration.AppId)"
    }
    Write-Log "Service Principal created successfully. ObjectId: $($sp.Id)" -Level Success

    # Create Client Secret
    Write-Log "Creating client secret for App Registration..." -Level Info
    $secret = New-AzADAppCredential -ApplicationId $appRegistration.AppId -EndDate (Get-Date).AddYears(1)
    Write-Log "Client secret created successfully." -Level Success

    # Setup Cosmos DB
    Write-Log "Setting up Cosmos DB Account: $CosmosDBAccountName..." -Level Info
    $cosmosDBAccount = Get-AzCosmosDBAccount -ResourceGroupName $ResourceGroupName -Name $CosmosDBAccountName -ErrorAction SilentlyContinue
    if (-not $cosmosDBAccount) {
        Write-Log "Cosmos DB Account not found. Creating it..." -Level Info
        $cosmosDBAccount = New-AzCosmosDBAccount `
            -ResourceGroupName $ResourceGroupName `
            -Name $CosmosDBAccountName `
            -Location $Location `
            -EnableAutomaticFailover `
            -DefaultConsistencyLevel "Session"
        Write-Log "Cosmos DB Account created successfully." -Level Success
    } else {
        Write-Log "Using existing Cosmos DB Account: $CosmosDBAccountName." -Level Success
    }

    # Create Database
    Write-Log "Creating database '$CosmosDBName'..." -Level Info
    New-AzCosmosDBSqlDatabase -ResourceGroupName $ResourceGroupName -AccountName $CosmosDBAccountName -Name $CosmosDBName
    Write-Log "Database created successfully." -Level Success

    # Create Containers
    Write-Log "Creating Cosmos DB Containers..." -Level Info
    New-AzCosmosDBSqlContainer -ResourceGroupName $ResourceGroupName -AccountName $CosmosDBAccountName -DatabaseName $CosmosDBName `
        -Name "Users" -PartitionKeyPath "/userInfo/email" -PartitionKeyKind "Hash"
    New-AzCosmosDBSqlContainer -ResourceGroupName $ResourceGroupName -AccountName $CosmosDBAccountName -DatabaseName $CosmosDBName `
        -Name "ChatHistory" -PartitionKeyPath "/SessionId" -PartitionKeyKind "Hash"
    Write-Log "Containers created successfully." -Level Success

    # Assign Control Plane Roles
    Write-Log "Assigning control plane roles..." -Level Info
    $roles = @(
        "Cosmos DB Account Reader Role",
        "Cosmos DB Operator",
        "DocumentDB Account Contributor"
    )
    foreach ($roleName in $roles) {
        New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $roleName -Scope $cosmosDBAccount.Id
    }
    Write-Log "Control plane roles assigned successfully." -Level Success

    # Assign Data Plane Role
    Write-Log "Assigning Cosmos DB Data Plane Role..." -Level Info
    New-AzCosmosDBSqlRoleAssignment `
        -AccountName $CosmosDBAccountName `
        -ResourceGroupName $ResourceGroupName `
        -RoleDefinitionId "00000000-0000-0000-0000-000000000002" `
        -Scope "/" `
        -PrincipalId $sp.Id
    Write-Log "Data plane role assigned successfully." -Level Success

    # Generate Environment Variables File (.env.local)
    Write-Log "Generating environment variables file (.env.local)..." -Level Info
    $envVars = @"
AZURE_SUBSCRIPTION_ID=$SubscriptionId
AZURE_RESOURCE_GROUP=$ResourceGroupName
AZURE_COSMOS_DB_ACCOUNT=$CosmosDBAccountName
AZURE_APP_REGISTRATION_ID=$($appRegistration.Id)
AZURE_SERVICE_PRINCIPAL_ID=$($sp.Id)
AZURE_APP_ID=$($appRegistration.AppId)
AZURE_TENANT_ID=$((Get-AzContext).Tenant.Id)
AZURE_CLIENT_SECRET=$($secret.SecretText)
"@
    $envVars | Out-File -FilePath ".env.local" -Encoding utf8
    Write-Log "Environment variables saved to .env.local" -Level Success

    # Generate Configuration File
    Write-Log "Generating configuration file (azure-config.json)..." -Level Info
    $config = @{
        SubscriptionId = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        CosmosDBAccountName = $CosmosDBAccountName
        AppRegistrationId = $appRegistration.Id
        ServicePrincipalId = $sp.Id
        AppId = $appRegistration.AppId
        TenantId = (Get-AzContext).Tenant.Id
        ClientSecret = $secret.SecretText
    } | ConvertTo-Json -Depth 10
    $config | Out-File -FilePath "azure-config.json"
    Write-Log "Configuration file saved to azure-config.json" -Level Success

    Write-Log "Setup completed successfully!" -Level Success
}
catch {
    Write-Log "An error occurred: $_" -Level Error
    throw
}