metadata description = 'Create role assignment and definition resources.'

param databaseAccountName string
@description('Id of the backend managed identity principal to assign database roles.')
param appPrincipalId string
param principalType string

resource database 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: databaseAccountName
}

module nosqlDefinition '../core/database/cosmos-db/nosql/role/definition.bicep' = {
  name: 'nosql-role-definition'
  params: {
    targetAccountName: database.name
    definitionName: 'Write to Azure Cosmos DB for NoSQL data plane'
    permissionsDataActions: [
      'Microsoft.DocumentDB/databaseAccounts/readMetadata'
      'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
      'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
    ]
  }
}

module nosqlBackendAssignment '../core/database/cosmos-db/nosql/role/assignment.bicep' = {
  name: 'nosql-role-assignment-backend'
  params: {
    targetAccountName: database.name
    roleDefinitionId: nosqlDefinition.outputs.id
    principalId: appPrincipalId
  }
}

// OpenAI Role Assignment for Backend
module openaiBackendAssignment '../core/security/role/assignment.bicep' = {
  name: 'openai-role-assignment-backend'
  params: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')  // Cognitive Services OpenAI User built-in role
    principalId: appPrincipalId
    principalType: principalType
  }
}

output roleDefinitionId string = nosqlDefinition.outputs.id
