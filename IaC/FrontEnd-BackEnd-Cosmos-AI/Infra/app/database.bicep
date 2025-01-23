metadata description = 'Create database accounts.'

param accountName string
param location string = resourceGroup().location
param tags object = {}

var database = {
  name: 'my-app-db'
}

var containers = [
  {
    name: 'ChatHistory'
    partitionKeyPaths: [
      '/SessionID'
    ]
    indexingPolicy: {
      automatic: true
      indexingMode: 'consistent'
      includedPaths: [
        {
          path: '/*'
        }
      ]
      excludedPaths: []
    }
  }
  {
    name: 'Users'
    partitionKeyPaths: [
      '/userinfo/email'
    ]
    indexingPolicy: {
      automatic: true
      indexingMode: 'consistent'
      includedPaths: [
        {
          path: '/*'
        }
      ]
      excludedPaths: []
    }
  }
]

module cosmosDbAccount '../core/database/cosmos-db/nosql/account.bicep' = {
  name: 'cosmos-db-account'
  params: {
    name: accountName
    location: location
    tags: tags
    enableServerless: true
    disableKeyBasedAuth: true
  }
}

module cosmosDbDatabase '../core/database/cosmos-db/nosql/database.bicep' = {
  name: 'cosmos-db-database-${database.name}'
  params: {
    name: database.name
    parentAccountName: cosmosDbAccount.outputs.name
    tags: tags
    setThroughput: false
  }
}

module cosmosDbContainers '../core/database/cosmos-db/nosql/container.bicep' = [for container in containers: {
  name: 'cosmos-db-container-${container.name}'
  params: {
    name: container.name
    parentAccountName: cosmosDbAccount.outputs.name
    parentDatabaseName: cosmosDbDatabase.outputs.name
    tags: tags
    setThroughput: false
    partitionKeyPaths: container.partitionKeyPaths
    indexingPolicy: container.indexingPolicy
  }
}]

output endpoint string = cosmosDbAccount.outputs.endpoint
output accountName string = cosmosDbAccount.outputs.name
output database object = {
  name: cosmosDbDatabase.outputs.name
}
output containers array = [for (container, i) in containers: {
  name: cosmosDbContainers[i].outputs.name
}]
