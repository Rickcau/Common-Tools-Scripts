// New file: app/search.bicep
param name string
param location string
param sku string
param tags object = {}

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    semanticSearch: 'free'
  }
}

output endpoint string = 'https://${search.name}.search.windows.net'
output name string = search.name
