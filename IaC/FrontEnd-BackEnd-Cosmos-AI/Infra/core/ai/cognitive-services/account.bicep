metadata description = 'Creates an Azure OpenAI service account.'

param name string
param location string = resourceGroup().location
param tags object = {}

@allowed([
  'OpenAI'
])
@description('The kind of cognitive service to create.')
param kind string = 'OpenAI'

@allowed([
  'S0'
])
@description('The SKU of the cognitive service account.')
param sku string

@description('Specifies whether public network access is allowed.')
param enablePublicNetworkAccess bool = true

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
  }
}

output name string = account.name
output id string = account.id
output endpoint string = account.properties.endpoint