param(
    [string]$SubscriptionId = "",   # Optional: Specific subscription ID
    [string]$ModelFilter = "",       # Optional: Filter by model name (e.g., "4.1", "gpt-4")
    [string]$QuotaTypeFilter = "",   # Optional: Filter by quota type (e.g., "GlobalStandard", "Standard", "Batch")
    [string]$RegionFilter = "",      # Optional: Filter by region (e.g., "swedencentral", "eastus")
    [string]$OutputFile = "AzureOpenAI-Quota.md"
)

# Show usage examples if no filters are provided
if (-not $ModelFilter -and -not $QuotaTypeFilter -and -not $RegionFilter -and -not $SubscriptionId) {
    Write-Host "`n=== Azure OpenAI Quota Script ===" -ForegroundColor Cyan
    Write-Host "Running with no filters - showing all quota information.`n" -ForegroundColor Yellow
    Write-Host "TIP: Use filters to narrow down results:" -ForegroundColor Green
    Write-Host "  Examples:" -ForegroundColor White
    Write-Host "    .\Get-AzureOpenAIQuota.ps1 -ModelFilter `"4.1`"" -ForegroundColor Gray
    Write-Host "    .\Get-AzureOpenAIQuota.ps1 -RegionFilter `"swedencentral`"" -ForegroundColor Gray
    Write-Host "    .\Get-AzureOpenAIQuota.ps1 -QuotaTypeFilter `"GlobalStandard`"" -ForegroundColor Gray
    Write-Host "    .\Get-AzureOpenAIQuota.ps1 -RegionFilter `"sweden`" -ModelFilter `"4.1`" -QuotaTypeFilter `"GlobalStandard`"" -ForegroundColor Gray
    Write-Host "    .\Get-AzureOpenAIQuota.ps1 -SubscriptionId `"your-sub-id`"" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Fetching Azure OpenAI quota information..." -ForegroundColor Cyan

# Set subscription if provided
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}

# Get current subscription info
$subscription = az account show | ConvertFrom-Json
Write-Host "Subscription: $($subscription.name) ($($subscription.id))" -ForegroundColor Gray

# Get all Azure OpenAI accounts
$accounts = az cognitiveservices account list --query "[?kind=='OpenAI']" | ConvertFrom-Json

if (-not $accounts) {
    Write-Host "No Azure OpenAI resources found in this subscription." -ForegroundColor Yellow
    exit
}

Write-Host "Found $($accounts.Count) Azure OpenAI resource(s)" -ForegroundColor Gray

# Collect quota data by region and model
$quotaData = @()

# List of regions to check (based on Azure OpenAI availability)
$regions = @(
    "australiaeast", "brazilsouth", "canadaeast", "eastus", "eastus2", 
    "francecentral", "germanywestcentral", "japaneast", "koreacentral",
    "northcentralus", "norwayeast", "polandcentral", "southafricanorth",
    "southcentralus", "southindia", "southeastasia", "spaincentral",
    "swedencentral", "switzerlandnorth", "uaenorth", "uksouth",
    "westeurope", "westus", "westus3"
)

# Get deployments from all resources first to map region usage
$deploymentsByRegion = @{}

foreach ($account in $accounts) {
    Write-Host "  Checking resource: $($account.name) in $($account.location)..." -ForegroundColor DarkGray
    
    $deployments = az cognitiveservices account deployment list `
        --name $account.name `
        --resource-group $account.resourceGroup | ConvertFrom-Json
    
    foreach ($deployment in $deployments) {
        # Only track Global Standard deployments
        if ($deployment.sku.name -eq 'GlobalStandard') {
            $region = $account.location
            $model = $deployment.properties.model.name
            $key = "$region|$model"
            
            if (-not $deploymentsByRegion.ContainsKey($key)) {
                $deploymentsByRegion[$key] = @{
                    Region = $region
                    Model = $model
                    ModelVersion = $deployment.properties.model.version
                    Resource = $account.name
                    UsedTPM = 0
                    Deployments = @()
                }
            }
            
            $deploymentsByRegion[$key].UsedTPM += $deployment.sku.capacity
            $deploymentsByRegion[$key].Deployments += @{
                Name = $deployment.name
                TPM = $deployment.sku.capacity
            }
        }
    }
}

# Now fetch quota limits from Azure
Write-Host "`nFetching quota limits from Azure regions..." -ForegroundColor Cyan

foreach ($region in $regions) {
    # Apply region filter if specified
    if ($RegionFilter -and $region -notlike "*$RegionFilter*") {
        continue
    }
    
    try {
        $usageResult = az cognitiveservices usage list --location $region 2>$null
        
        if ($LASTEXITCODE -eq 0 -and $usageResult) {
            $usage = $usageResult | ConvertFrom-Json
            
            # Process all quota entries
            foreach ($item in $usage) {
                $name = $item.name.value
                $localizedName = $item.name.localizedValue
                
                # Determine quota type and model from the usage entry
                $quotaType = ""
                $modelName = ""
                $version = ""
                
                # Parse different quota patterns
                if ($name -match "Batch" -or $localizedName -match "Batch") {
                    # Batch quota (e.g., GlobalBatch, DataZoneBatch)
                    if ($localizedName -match "GlobalBatch") {
                        $quotaType = "GlobalBatch"
                    } elseif ($localizedName -match "DataZoneBatch") {
                        $quotaType = "DataZoneBatch"
                    } else {
                        $quotaType = "Batch"
                    }
                    
                    # Extract model from localized name (e.g., "GPT-4.1")
                    if ($localizedName -match "(GPT-[\d\.]+(?:-\w+)?|o\d)") {
                        $modelName = $matches[1]
                    }
                } elseif ($name -match "OpenAI\.Standard\.(.*)" -or $localizedName -match "Tokens Per Minute.*- (.*) - .*") {
                    # Standard/GlobalStandard quota
                    $quotaType = "GlobalStandard"
                    
                    # Try to extract model from name or localizedValue
                    if ($name -match "OpenAI\.Standard\.(.*)") {
                        $modelName = $matches[1]
                    } elseif ($localizedName -match "- (GPT-[\d\.]+(?:-\w+)?|gpt-[\d\.]+(?:-\w+)?|o\d) -") {
                        $modelName = $matches[1]
                    }
                }
                
                # Skip if we couldn't determine type or model
                if (-not $quotaType -or -not $modelName) {
                    continue
                }
                
                # Extract version if available
                if ($localizedName -match "(\d+\.\d+)") {
                    $version = $matches[1]
                }
                
                # Normalize model name for matching (handle different formats)
                $normalizedModel = $modelName -replace "GPT-", "gpt-" -replace "gpt", "gpt"
                
                # Apply filters
                if ($ModelFilter -and $normalizedModel -notlike "*$ModelFilter*") {
                    continue
                }
                
                if ($QuotaTypeFilter -and $quotaType -notlike "*$QuotaTypeFilter*") {
                    continue
                }
                
                # Try to find matching deployment
                # Create possible keys to check
                $possibleKeys = @(
                    "$region|$modelName",
                    "$region|$normalizedModel",
                    "$region|gpt-$($ModelFilter)"
                )
                
                $usedTPM = 0
                $resource = ""
                $deployments = @()
                $foundMatch = $false
                
                foreach ($key in $possibleKeys) {
                    if ($deploymentsByRegion.ContainsKey($key)) {
                        $usedTPM = $deploymentsByRegion[$key].UsedTPM
                        $resource = $deploymentsByRegion[$key].Resource
                        $deployments = $deploymentsByRegion[$key].Deployments
                        if (-not $version) {
                            $version = $deploymentsByRegion[$key].ModelVersion
                        }
                        $foundMatch = $true
                        break
                    }
                }
                
                # Also check if any deployment in this region matches by model name similarity
                if (-not $foundMatch) {
                    foreach ($key in $deploymentsByRegion.Keys) {
                        if ($key.StartsWith("$region|")) {
                            $deployModel = $key.Split('|')[1]
                            # Check for model name match (case insensitive, handle variations)
                            if ($deployModel -like "*$($ModelFilter)*" -or $normalizedModel -like "*$deployModel*") {
                                $usedTPM = $deploymentsByRegion[$key].UsedTPM
                                $resource = $deploymentsByRegion[$key].Resource
                                $deployments = $deploymentsByRegion[$key].Deployments
                                if (-not $version) {
                                    $version = $deploymentsByRegion[$key].ModelVersion
                                }
                                break
                            }
                        }
                    }
                }
                
                $limitTPM = $item.limit
                $availableTPM = $limitTPM - $usedTPM
                
                $quotaData += [PSCustomObject]@{
                    Region = $region
                    Model = $modelName
                    Version = $version
                    QuotaType = $quotaType
                    Resource = $resource
                    QuotaAllocation = "$($usedTPM.ToString('N0'))K of $($limitTPM.ToString('N0'))K TPM"
                    UsedTPM = $usedTPM
                    LimitTPM = $limitTPM
                    AvailableTPM = $availableTPM
                    UsedFormatted = "$($usedTPM.ToString('N0'))K"
                    LimitFormatted = "$($limitTPM.ToString('N0'))K"
                    AvailableFormatted = "$($availableTPM.ToString('N0'))K"
                    Deployments = $deployments
                    RawName = $name
                    RawLocalizedName = $localizedName
                }
            }
        }
    }
    catch {
        # Skip regions that don't support OpenAI or have access issues
        continue
    }
}

if ($quotaData.Count -eq 0) {
    Write-Host "No Global Standard quota data found." -ForegroundColor Yellow
    exit
}

# Sort by region and model
$quotaData = $quotaData | Sort-Object Region, Model

# Generate Markdown Report
$markdown = @"
# Azure OpenAI Model Quota Report

**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Subscription:** $($subscription.name)  
**Subscription ID:** $($subscription.id)

This report shows Global Standard quota allocation across all Azure regions, matching the Azure Portal's quota view.

> **Note:** TPM = Tokens Per Minute (in thousands, K)  
> Each region typically has 1,000K TPM (1M TPM) quota for Global Standard deployments.

---

## Quota by Region (Standard + Batch View)

| Region | Model | Version | Quota Type | Quota Allocation | Resource | Deployments |
|--------|-------|---------|------------|------------------|----------|-------------|

"@

foreach ($quota in $quotaData) {
    $deploymentInfo = if ($quota.Deployments.Count -gt 0) {
        ($quota.Deployments | ForEach-Object { "$($_.Name) ($($_.TPM)K)" }) -join ", "
    } else {
        "-"
    }
    
    $resourceName = if ($quota.Resource) { $quota.Resource } else { "-" }
    
    $markdown += "| $($quota.Region) | $($quota.Model) | $($quota.Version) | $($quota.QuotaType) | $($quota.QuotaAllocation) | $resourceName | $deploymentInfo |`n"
}

# Summary by usage status
$markdown += @"

---

## Summary

**Total Regions with Quota:** $($quotaData.Count)  
**Regions with Active Deployments:** $(($quotaData | Where-Object { $_.UsedTPM -gt 0 }).Count)  
**Regions with Available Quota:** $(($quotaData | Where-Object { $_.AvailableTPM -gt 0 }).Count)

### Regions with Active Deployments

| Region | Model | Used | Available | Resource |
|--------|-------|------|-----------|----------|

"@

$activeRegions = $quotaData | Where-Object { $_.UsedTPM -gt 0 } | Sort-Object -Descending UsedTPM

foreach ($quota in $activeRegions) {
    $markdown += "| $($quota.Region) | $($quota.Model) | $($quota.UsedFormatted) TPM | $($quota.AvailableFormatted) TPM | $($quota.Resource) |`n"
}

$markdown += @"

### Regions with Available Quota (No Deployments)

| Region | Model | Available Quota |
|--------|-------|-----------------|

"@

$availableRegions = $quotaData | Where-Object { $_.UsedTPM -eq 0 -and $_.LimitTPM -gt 0 } | Sort-Object Region, Model

foreach ($quota in $availableRegions) {
    $markdown += "| $($quota.Region) | $($quota.Model) | $($quota.LimitFormatted) TPM |`n"
}

# Save to file
$markdown | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "`n✓ Report generated: $OutputFile" -ForegroundColor Green
Write-Host "  Total quota entries: $($quotaData.Count)" -ForegroundColor Green
Write-Host "  Regions with deployments: $(($activeRegions).Count)" -ForegroundColor Green
Write-Host "  Regions with available quota: $(($availableRegions).Count)" -ForegroundColor Green

if ($ModelFilter) {
    Write-Host "  Model filter applied: $ModelFilter" -ForegroundColor Gray
}
if ($QuotaTypeFilter) {
    Write-Host "  Quota type filter applied: $QuotaTypeFilter" -ForegroundColor Gray
}
if ($RegionFilter) {
    Write-Host "  Region filter applied: $RegionFilter" -ForegroundColor Gray
}

# Display summary in console
Write-Host "`n=== Quota Summary (Active Deployments) ===" -ForegroundColor Cyan
if ($activeRegions.Count -gt 0) {
    $activeRegions | Select-Object Region, Model, Version, @{N='Used';E={$_.UsedFormatted}}, @{N='Limit';E={$_.LimitFormatted}}, @{N='Available';E={$_.AvailableFormatted}}, Resource | Format-Table -AutoSize
} else {
    Write-Host "No active deployments found." -ForegroundColor Yellow
}

Write-Host "`n=== Available Quota (Sample - First 10 regions) ===" -ForegroundColor Cyan
if ($availableRegions.Count -gt 0) {
    $availableRegions | Select-Object -First 10 Region, Model, @{N='Available';E={$_.LimitFormatted}} | Format-Table -AutoSize
    if ($availableRegions.Count -gt 10) {
        Write-Host "... and $($availableRegions.Count - 10) more regions with available quota (see markdown file for full list)" -ForegroundColor Gray
    }
} else {
    Write-Host "No available quota found." -ForegroundColor Yellow
}
