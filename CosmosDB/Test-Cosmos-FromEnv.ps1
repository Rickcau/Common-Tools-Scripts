# Test-Cosmos-FromEnv2.ps1
# This script is used to test the Cosmos DB setup from the .env.local file.
# It uses the environment variables to connect to the Cosmos DB account and create a test user document.
# It also uses the Azure CLI to assign the necessary roles to the service principal.
# It is tested on 2025-01-20 by RDC and is working as expected.
# Install-Package Microsoft.Azure.Cosmos
# 1/19/2025 - RDC - This script is working as expected.

# Check and install required modules
if (-not (Get-Module -ListAvailable -Name 'Az.CosmosDB')) {
    Write-Host "Installing Az.CosmosDB module..."
    Install-Module -Name 'Az.CosmosDB' -Scope CurrentUser -Force
}

# Function to read .env.local file
function Get-EnvironmentVariables {
    $envFile = ".env.local"
    if (Test-Path $envFile) {
        $envVars = @{}
        Get-Content $envFile | ForEach-Object {
            if ($_ -match '(.+)=(.+)') {
                $envVars[$matches[1]] = $matches[2]
            }
        }
        return $envVars
    }
    else {
        throw "Environment file .env.local not found!"
    }
}

# Function to generate authorization signature
function Generate-MasterKeyAuthorizationSignature {
    param(
        [string]$verb,
        [string]$resourceLink,
        [string]$resourceType,
        [string]$key,
        [string]$keyType,
        [string]$tokenVersion,
        [string]$dateString
    )

    $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256
    $hmacSha256.Key = [System.Convert]::FromBase64String($key)

    # The payload should use the resource link without the /docs part for authentication
    $payLoad = "$($verb.ToLowerInvariant())`n$($resourceType.ToLowerInvariant())`n$resourceLink`n$($dateString.ToLowerInvariant())`n`n"
    $hashPayLoad = $hmacSha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payLoad))
    $signature = [System.Convert]::ToBase64String($hashPayLoad)

    # Return with proper URL encoding
    return [System.Web.HttpUtility]::UrlEncode("type=$keyType&ver=$tokenVersion&sig=$signature")
}

Add-Type -AssemblyName System.Web

try {
    # Read environment variables
    $env = Get-EnvironmentVariables
    
    # Connect to Azure using service principal
    $secureSecret = ConvertTo-SecureString $env.AZURE_CLIENT_SECRET -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($env.AZURE_APP_ID, $secureSecret)
    
    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $env.AZURE_TENANT_ID

    # Create test user document
    $userDocument = @{
        id = "basicuser@stackguru.ai"
        userInfo = @{
            email = "basicuser@stackguru.ai"
            firstName = "Basic"
            lastName = "User"
        }
        role = "user"
        tier = "trial"
        mockMode = $true
        preferences = @{
            theme = "light"
        }
    }

    # Convert document to JSON
    $documentBody = $userDocument | ConvertTo-Json -Depth 10

    # Get Cosmos DB account and keys
    $cosmosAccount = Get-AzCosmosDBAccount `
        -ResourceGroupName $env.AZURE_RESOURCE_GROUP `
        -Name $env.AZURE_COSMOS_DB_ACCOUNT

    $cosmosKeys = Get-AzCosmosDBAccountKey `
        -ResourceGroupName $env.AZURE_RESOURCE_GROUP `
        -Name $env.AZURE_COSMOS_DB_ACCOUNT

    # Set up resource links and authorization
    $databaseId = "my-app-db"
    $containerId = "Users"
    $resourceLink = "dbs/$databaseId/colls/$containerId"
    $date = [System.DateTime]::UtcNow.ToString("r")
    
    $authHeader = Generate-MasterKeyAuthorizationSignature `
        -verb "POST" `
        -resourceLink $resourceLink `
        -resourceType "docs" `
        -key $cosmosKeys.PrimaryMasterKey `
        -keyType "master" `
        -tokenVersion "1.0" `
        -dateString $date

    # Create the partition key JSON array string
    $partitionKey = '["' + $userDocument.userInfo.email + '"]'

    $headers = @{
        "Authorization" = $authHeader
        "x-ms-version" = "2018-12-31"
        "x-ms-date" = $date
        "x-ms-documentdb-partitionkey" = $partitionKey
    }

    # The full URI includes /docs for the actual request
    $uri = "$($cosmosAccount.DocumentEndpoint)$resourceLink/docs"

    Write-Host "Attempting to create document..." -ForegroundColor Yellow
    Write-Host "URI: $uri" -ForegroundColor Yellow
    Write-Host "Document Body: $documentBody" -ForegroundColor Yellow
    Write-Host "Auth Header: $authHeader" -ForegroundColor Yellow

    $result = Invoke-RestMethod `
        -Uri $uri `
        -Method Post `
        -Headers $headers `
        -Body $documentBody `
        -ContentType "application/json"

    Write-Host "Document created successfully!" -ForegroundColor Green
    Write-Host ($result | ConvertTo-Json)
}
catch {
    Write-Host "Error occurred: $_" -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd()
        Write-Host "Detailed error: $responseBody" -ForegroundColor Red
    }
    throw
}