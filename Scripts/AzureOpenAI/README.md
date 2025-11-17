# Here are some useful script for Azure OpenAI Resources.
## Get-AzureOpenAIquota.ps1
This script allows you to quickly check the quota for a deployment and filter by model, region, quota type and subscription.  It will also generate a Markdown file with the details as well.

## Examples

```
   .\Get-AzureOpenAIQuota.ps1 -ModelFilter "4.1" 
   .\Get-AzureOpenAIQuota.ps1 -RegionFilter "swedencentral"
   .\Get-AzureOpenAIQuota.ps1 -QuotaTypeFilter "GlobalStandard" 
   .\Get-AzureOpenAIQuota.ps1 -RegionFilter "sweden" -ModelFilter "4.1" -QuotaTypeFilter "GlobalStandard`" 
   .\Get-AzureOpenAIQuota.ps1 -SubscriptionId `"your-sub-id`"
```
