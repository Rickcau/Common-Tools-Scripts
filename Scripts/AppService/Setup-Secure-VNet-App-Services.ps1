# Set variables
$RESOURCE_GROUP = "rg-it-ops"  # Existing resource group in centralus
$APP_LOCATION = "canadacentral"  # Location for VNet and App Services
$VNET_NAME = "it-ops-vnet"
$FRONTEND_SUBNET_NAME = "frontend-subnet"
$BACKEND_SUBNET_NAME = "backend-subnet"
$FRONTEND_APP_NAME = "it-ops-app"
$BACKEND_APP_NAME = "it-ops-backend"
$FRONTEND_PLAN_NAME = "frontend-plan"
$BACKEND_PLAN_NAME = "backend-plan"

# Function for logging
function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Host $logMessage -ForegroundColor Green
}

# Function for error logging
function Write-ErrorLog {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): ERROR - $Message"
    Write-Host $logMessage -ForegroundColor Red
    return $false
}

# Function to check if resource exists
function Test-ResourceExists {
    param (
        [string]$ResourceType,
        [string]$ResourceName
    )
    
    Write-Log "Checking if $ResourceType '$ResourceName' exists..."
    try {
        switch ($ResourceType) {
            "VNet" { 
                $resource = az network vnet show --name $ResourceName --resource-group $RESOURCE_GROUP 2>$null 
            }
            "WebApp" { 
                $resource = az webapp show --name $ResourceName --resource-group $RESOURCE_GROUP 2>$null 
            }
            "AppServicePlan" { 
                $resource = az appservice plan show --name $ResourceName --resource-group $RESOURCE_GROUP 2>$null 
            }
        }
        if ($resource) {
            Write-Log "$ResourceType '$ResourceName' exists."
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to cleanup resources
function Remove-Resources {
    Write-Log "Starting cleanup process..."
    
    # Remove Backend Web App
    if (Test-ResourceExists "WebApp" $BACKEND_APP_NAME) {
        Write-Log "Removing Backend Web App..."
        az webapp delete --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP
    }

    # Remove Frontend Web App
    if (Test-ResourceExists "WebApp" $FRONTEND_APP_NAME) {
        Write-Log "Removing Frontend Web App..."
        az webapp delete --name $FRONTEND_APP_NAME --resource-group $RESOURCE_GROUP
    }

    # Remove Backend App Service Plan
    if (Test-ResourceExists "AppServicePlan" $BACKEND_PLAN_NAME) {
        Write-Log "Removing Backend App Service Plan..."
        az appservice plan delete --name $BACKEND_PLAN_NAME --resource-group $RESOURCE_GROUP --yes
    }

    # Remove Frontend App Service Plan
    if (Test-ResourceExists "AppServicePlan" $FRONTEND_PLAN_NAME) {
        Write-Log "Removing Frontend App Service Plan..."
        az appservice plan delete --name $FRONTEND_PLAN_NAME --resource-group $RESOURCE_GROUP --yes
    }

    # Remove VNet (this will also remove subnets and private endpoints)
    if (Test-ResourceExists "VNet" $VNET_NAME) {
        Write-Log "Removing Virtual Network..."
        az network vnet delete --name $VNET_NAME --resource-group $RESOURCE_GROUP
    }

    Write-Log "Cleanup completed."
}

# Main deployment script
try {
    $success = $true
    
    # Create virtual network with two subnets in Canada Central
    Write-Log "Creating Virtual Network..."
    az network vnet create `
        --resource-group $RESOURCE_GROUP `
        --name $VNET_NAME `
        --location $APP_LOCATION `
        --address-prefix 10.0.0.0/16 `
        --subnet-name $FRONTEND_SUBNET_NAME `
        --subnet-prefix 10.0.1.0/24
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Virtual Network" }

    Write-Log "Creating Backend Subnet..."
    az network vnet subnet create `
        --resource-group $RESOURCE_GROUP `
        --vnet-name $VNET_NAME `
        --name $BACKEND_SUBNET_NAME `
        --address-prefix 10.0.2.0/24
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Backend Subnet" }

    # Create frontend App Service Plan
    Write-Log "Creating Frontend App Service Plan..."
    az appservice plan create `
        --name $FRONTEND_PLAN_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $APP_LOCATION `
        --sku B1 `
        --is-linux
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Frontend App Service Plan" }

    # Create frontend Web App
    Write-Log "Creating Frontend Web App..."
    az webapp create `
        --name $FRONTEND_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --plan $FRONTEND_PLAN_NAME `
        --runtime "NODE:20-lts"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Frontend Web App" }

    # Enable VNet integration for frontend
    Write-Log "Enabling VNet integration for Frontend Web App..."
    az webapp vnet-integration add `
        --name $FRONTEND_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --vnet $VNET_NAME `
        --subnet $FRONTEND_SUBNET_NAME
    if ($LASTEXITCODE -ne 0) { throw "Failed to enable VNet integration for Frontend Web App" }

    # Enable Easy Auth
    Write-Log "Enabling Easy Auth for Frontend Web App..."
    az webapp auth update `
        --name $FRONTEND_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --enabled true `
        --action LoginWithAzureActiveDirectory `
        --aad-allowed-token-audiences "https://${FRONTEND_APP_NAME}.azurewebsites.net/.auth/login/aad/callback"
    if ($LASTEXITCODE -ne 0) { throw "Failed to enable Easy Auth for Frontend Web App" }

    # Create backend App Service Plan
    Write-Log "Creating Backend App Service Plan..."
    az appservice plan create `
        --name $BACKEND_PLAN_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $APP_LOCATION `
        --sku P1V2 `
        --is-linux
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Backend App Service Plan" }

    # Create backend Web App
    Write-Log "Creating Backend Web App..."
    az webapp create `
        --name $BACKEND_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --plan $BACKEND_PLAN_NAME `
        --runtime "NODE:20-lts"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Backend Web App" }

    # Get backend app ID
    Write-Log "Getting Backend Web App ID..."
    $backendAppId = (az webapp show --name $BACKEND_APP_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
    if (-not $backendAppId) { throw "Failed to get Backend Web App ID" }

    # Create private endpoint
    Write-Log "Creating Private Endpoint..."
    az network private-endpoint create `
        --name "${BACKEND_APP_NAME}-endpoint" `
        --resource-group $RESOURCE_GROUP `
        --vnet-name $VNET_NAME `
        --subnet $BACKEND_SUBNET_NAME `
        --private-connection-resource-id "$backendAppId" `
        --group-id sites `
        --connection-name "${BACKEND_APP_NAME}-connection" `
        --location $APP_LOCATION
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Private Endpoint" }

    # Disable public access
    Write-Log "Disabling public access for Backend Web App..."
    az webapp update `
        --name $BACKEND_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --set publicNetworkAccess="Disabled"
    if ($LASTEXITCODE -ne 0) { throw "Failed to disable public access for Backend Web App" }

    Write-Log "Setup completed successfully!"
}
catch {
    $success = $false
    Write-ErrorLog $_.Exception.Message
    Write-Log "An error occurred during deployment. Starting cleanup..."
    Remove-Resources
}

if (-not $success) {
    Write-ErrorLog "Deployment failed. All resources have been cleaned up."
    exit 1
}