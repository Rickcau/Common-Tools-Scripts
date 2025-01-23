metadata description = 'Creates an Azure OpenAI model deployment.'

param name string
param parentAccountName string

@description('The name of the Azure OpenAI model to deploy.')
param modelName string

@description('The version of the model to deploy.')
param modelVersion string

@description('The format of the model. Always "OpenAI" for now.')
@allowed(['OpenAI'])
param modelFormat string = 'OpenAI'

@description('The SKU name for the deployment.')
@allowed(['Standard'])
param skuName string = 'Standard'

@description('The number of scale units for the deployment.')
param skuCapacity int

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: parentAccountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: account
  name: name
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
  }
}

output name string = deployment.name
output resourceId string = deployment.id