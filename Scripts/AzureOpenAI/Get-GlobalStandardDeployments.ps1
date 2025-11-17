param(
    [string]$ModelFilter = "",  # Optional: Filter by model name (e.g., "gpt-4", "gpt-35-turbo")
    [string]$OutputFile = "GlobalStandardDeployments.md",
    [switch]$ShowAllDeployments  # Show all deployments, not just Global Standard
)

Write-Host "Fetching Azure OpenAI resources..." -ForegroundColor Cyan

# Get all Azure OpenAI accounts
$accounts = az cognitiveservices account list --query "[?kind=='OpenAI']" | ConvertFrom-Json

if (-not $accounts) {
    Write-Host "No Azure OpenAI resources found in this subscription." -ForegroundColor Yellow
    exit
}

# Track quota by region and model
$quotaByRegion = @{}
$allDeployments = @()
$totalTPM = 0
$totalGlobalStandardTPM = 0

foreach ($account in $accounts) {
    Write-Host "Checking resource: $($account.name) in $($account.location)..." -ForegroundColor Gray
    
    # Get all deployments for this account
    $deployments = az cognitiveservices account deployment list `
        --name $account.name `
        --resource-group $account.resourceGroup | ConvertFrom-Json
    
    foreach ($deployment in $deployments) {
        $modelName = $deployment.properties.model.name
        $isGlobalStandard = $deployment.sku.name -eq 'GlobalStandard'
        
        # Apply filters
        if (-not $ShowAllDeployments -and -not $isGlobalStandard) {
            continue
        }
        
        if ($ModelFilter -and $modelName -notlike "*$ModelFilter*") {
            continue
        }
        
        # Determine deployment region
        # Global Standard deployments serve globally (not region-specific)
        # Regional deployments use the resource's location as their serving region
        $deploymentRegion = if ($isGlobalStandard) { 
            "Global (serves all regions)" 
        } else { 
            $account.location 
        }
        
        # TPM capacity is in thousands (K)
        # e.g., 1000 = 1,000K TPM = 1 Million TPM
        $tpmInK = $deployment.sku.capacity
        $tpmFormatted = "$($tpmInK.ToString('N0'))K"
        
        # Quota scope explanation
        $quotaScope = if ($isGlobalStandard) {
            "Shared globally across all regions"
        } else {
            "Region-specific ($($account.location))"
        }
        
        $deploymentInfo = [PSCustomObject]@{
            ResourceName = $account.name
            ResourceGroup = $account.resourceGroup
            ResourceLocation = $account.location
            DeploymentName = $deployment.name
            DeploymentRegion = $deploymentRegion
            Model = $modelName
            Version = $deployment.properties.model.version
            SKU = $deployment.sku.name
            IsGlobalStandard = if ($isGlobalStandard) { "Yes" } else { "No" }
            TPMRaw = $deployment.sku.capacity
            TPMFormatted = $tpmFormatted
            QuotaScope = $quotaScope
        }
        
        $allDeployments += $deploymentInfo
        $totalTPM += $deployment.sku.capacity
        
        if ($isGlobalStandard) {
            $totalGlobalStandardTPM += $deployment.sku.capacity
            
            # Track Global Standard quota usage by region and model
            $region = $account.location
            $key = "$region|$modelName"
            
            if (-not $quotaByRegion.ContainsKey($key)) {
                $quotaByRegion[$key] = @{
                    Region = $region
                    Model = $modelName
                    UsedTPM = 0
                    TotalTPM = 1000  # Default 1M TPM per region for Global Standard
                    Deployments = @()
                }
            }
            
            $quotaByRegion[$key].UsedTPM += $deployment.sku.capacity
            $quotaByRegion[$key].Deployments += $deployment.name
        }
    }
}

if ($allDeployments.Count -eq 0) {
    $deploymentType = if ($ShowAllDeployments) { "deployments" } else { "Global Standard deployments" }
    Write-Host "No $deploymentType found." -ForegroundColor Yellow
    if ($ModelFilter) {
        Write-Host "Try removing the model filter: $ModelFilter" -ForegroundColor Yellow
    }
    exit
}

# Generate Markdown content
$title = if ($ShowAllDeployments) { "Azure OpenAI Deployments" } else { "Azure OpenAI Global Standard Deployments" }
$markdown = @"
# $title

**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Total Deployments:** $($allDeployments.Count)  
**Total TPM Allocated:** $($totalTPM.ToString('N0'))K TPM ($(($totalTPM / 1000).ToString('N1'))M tokens/min)  
**Global Standard TPM:** $($totalGlobalStandardTPM.ToString('N0'))K TPM ($(($totalGlobalStandardTPM / 1000).ToString('N1'))M tokens/min)

> **Note:** TPM values are shown in thousands (K). For example, 1,000K = 1 Million TPM.
> 
> **Global Standard** deployments have quota allocated per region (typically 1M TPM per region).  
> **Regional** (Standard) deployments are region-specific with separate quota limits.

"@

if ($ModelFilter) {
    $markdown += "**Model Filter:** $ModelFilter`n`n"
}

# Add quota summary section (like Azure Portal view)
if ($quotaByRegion.Count -gt 0) {
    $markdown += @"
---

## Global Standard Quota by Region (Azure Portal View)

This view mirrors the Azure Portal's quota display, showing quota allocation and usage per region.

| Region | Model | Quota Allocation | Used | Available | Resource | Deployments |
|--------|-------|------------------|------|-----------|----------|-------------|

"@
    
    foreach ($key in ($quotaByRegion.Keys | Sort-Object)) {
        $quota = $quotaByRegion[$key]
        $usedFormatted = "$($quota.UsedTPM.ToString('N0'))K"
        $totalFormatted = "$($quota.TotalTPM.ToString('N0'))K"
        $availableTPM = $quota.TotalTPM - $quota.UsedTPM
        $availableFormatted = "$($availableTPM.ToString('N0'))K"
        $allocationText = "$usedFormatted of $totalFormatted TPM"
        
        # Find resource name for this region
        $resourceName = ($allDeployments | Where-Object { $_.ResourceLocation -eq $quota.Region -and $_.Model -eq $quota.Model } | Select-Object -First 1).ResourceName
        
        $deploymentsList = $quota.Deployments -join ", "
        
        $markdown += "| $($quota.Region) | $($quota.Model) | $allocationText | $usedFormatted | $availableFormatted | $resourceName | $deploymentsList |`n"
    }
    
    $markdown += "`n"
}

$markdown += @"
---
"@

$markdown += @"
---

## Deployment Summary

| Resource Name | Resource Group | Resource Location | Deployment Name | Deployment Region | Model | Version | SKU | Global Std | TPM | Quota Scope |
|--------------|----------------|-------------------|-----------------|-------------------|-------|---------|-----|-----------|-----|-------------|

"@

foreach ($dep in $allDeployments | Sort-Object ResourceName, DeploymentName) {
    $markdown += "| $($dep.ResourceName) | $($dep.ResourceGroup) | $($dep.ResourceLocation) | $($dep.DeploymentName) | $($dep.DeploymentRegion) | $($dep.Model) | $($dep.Version) | $($dep.SKU) | $($dep.IsGlobalStandard) | $($dep.TPMFormatted) | $($dep.QuotaScope) |`n"
}

# Group by model
$markdown += @"

---

## By Model

"@

$byModel = $allDeployments | Group-Object Model | Sort-Object Name

foreach ($group in $byModel) {
    $modelTPM = ($group.Group | Measure-Object -Property TPMRaw -Sum).Sum
    $globalCount = ($group.Group | Where-Object { $_.IsGlobalStandard -eq "Yes" }).Count
    $markdown += @"

### $($group.Name)
**Count:** $($group.Count) deployment(s) ($globalCount Global Standard)  
**Total TPM:** $($modelTPM.ToString('N0'))K TPM ($(($modelTPM / 1000).ToString('N1'))M tokens/min)

| Resource Name | Deployment Name | Version | Deployment Region | Global Std | SKU | TPM | Quota Scope |
|--------------|-----------------|---------|-------------------|-----------|-----|-----|-------------|

"@
    
    foreach ($dep in $group.Group | Sort-Object ResourceName) {
        $markdown += "| $($dep.ResourceName) | $($dep.DeploymentName) | $($dep.Version) | $($dep.DeploymentRegion) | $($dep.IsGlobalStandard) | $($dep.SKU) | $($dep.TPMFormatted) | $($dep.QuotaScope) |`n"
    }
}

# Group by resource
$markdown += @"

---

## By Resource

"@

$byResource = $allDeployments | Group-Object ResourceName | Sort-Object Name

foreach ($group in $byResource) {
    $resourceTPM = ($group.Group | Measure-Object -Property TPMRaw -Sum).Sum
    $globalCount = ($group.Group | Where-Object { $_.IsGlobalStandard -eq "Yes" }).Count
    $markdown += @"

### $($group.Name)
**Resource Group:** $($group.Group[0].ResourceGroup)  
**Location:** $($group.Group[0].ResourceLocation)  
**Deployments:** $($group.Count) ($globalCount Global Standard)  
**Total TPM:** $($resourceTPM.ToString('N0'))K TPM ($(($resourceTPM / 1000).ToString('N1'))M tokens/min)

| Deployment Name | Model | Version | Deployment Region | Global Std | SKU | TPM | Quota Scope |
|-----------------|-------|---------|-------------------|-----------|-----|-----|-------------|

"@
    
    foreach ($dep in $group.Group | Sort-Object DeploymentName) {
        $markdown += "| $($dep.DeploymentName) | $($dep.Model) | $($dep.Version) | $($dep.DeploymentRegion) | $($dep.IsGlobalStandard) | $($dep.SKU) | $($dep.TPMFormatted) | $($dep.QuotaScope) |`n"
    }
}

# Save to file
$markdown | Out-File -FilePath $OutputFile -Encoding UTF8

$globalStandardCount = ($allDeployments | Where-Object { $_.IsGlobalStandard -eq "Yes" }).Count

Write-Host "`n✓ Report generated: $OutputFile" -ForegroundColor Green
Write-Host "  Total deployments: $($allDeployments.Count)" -ForegroundColor Green
Write-Host "  Global Standard deployments: $globalStandardCount" -ForegroundColor Green
Write-Host "  Total TPM allocated: $($totalTPM.ToString('N0'))" -ForegroundColor Green
Write-Host "  Global Standard TPM: $($totalGlobalStandardTPM.ToString('N0'))" -ForegroundColor Green

# Display summary in console
Write-Host "`n=== Quick Summary ===" -ForegroundColor Cyan
$allDeployments | Select-Object ResourceName, DeploymentName, Model, DeploymentRegion, IsGlobalStandard, SKU, TPMFormatted, QuotaScope | Format-Table -AutoSize
