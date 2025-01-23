metadata description = 'Create AI accounts.'

param accountName string
param location string = resourceGroup().location
param tags object = {}

param completionModelName string = 'gpt-4o'
param completionsDeploymentName string = 'gpt-4o'
param embeddingsModelName string = 'text-embedding-ada-002'
param embeddingsDeploymentName string = 'text-embedding-ada-002'

var deployments = [
  {
    name: completionsDeploymentName
    skuCapacity: 10
    modelName: completionModelName
    modelVersion: '2024-08-06'  // Updated model version for gpt-4o
  }
  {
    name: embeddingsDeploymentName
    skuCapacity: 5
    modelName: embeddingsModelName
    modelVersion: '2'     // Version for text-embedding-ada-002
  }
]

module openAiAccount '../core/ai/cognitive-services/account.bicep' = {
  name: 'openai-account'
  params: {
    name: accountName
    location: location
    tags: tags
    kind: 'OpenAI'
    sku: 'S0'
  }
}

@batchSize(1)
module openAiModelDeployments '../core/ai/cognitive-services/deployment.bicep' = [for deployment in deployments: {
  name: 'openai-model-deployment-${deployment.name}'
  params: {
    name: deployment.name
    parentAccountName: openAiAccount.outputs.name
    skuName: 'Standard'
    skuCapacity: deployment.skuCapacity
    modelName: deployment.modelName
    modelVersion: deployment.modelVersion
    modelFormat: 'OpenAI'
  }
}]

output name string = openAiAccount.outputs.name
output endpoint string = openAiAccount.outputs.endpoint
output deployments array = [for (deployment, index) in deployments: {
  name: openAiModelDeployments[index].outputs.name
}]
