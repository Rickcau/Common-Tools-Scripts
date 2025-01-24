targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention.')
param environmentName string

@minLength(1)
@description('Primary location for all resources.')
param location string

// Optional parameters
param cosmosDbAccountName string = ''
param openAiAccountName string = ''
param frontendAppServicePlanName string = ''
param backendAppServicePlanName string = ''
param frontendAppName string = ''
param backendAppName string = ''

@allowed([
  'dotnet'
  'node'
  'python'
])
param frontendStack string = 'node'

@allowed([
  'dotnet'
  'node'
  'python'
])
param backendStack string = 'dotnet'

param enableAiSearch bool = false
param aiSearchSku string = 'standard'

var abbreviations = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
}

var stackVersions = {
  dotnet: {
    runtime: 'dotnetcore'
    version: '8.0'
  }
  node: {
    runtime: 'node'
    version: '20-lts'
  }
  python: {
    runtime: 'python'
    version: '3.12'
  }
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: environmentName
  location: location
  tags: tags
}

module identity 'app/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    identityName: '${abbreviations.userAssignedIdentity}-${resourceToken}'
    location: location
    tags: tags
  }
}

module ai 'app/ai.bicep' = {
  name: 'ai'
  scope: rg
  params: {
    accountName: !empty(openAiAccountName) ? openAiAccountName : '${abbreviations.openAiAccount}-${resourceToken}'
    location: location
    tags: tags
  }
}

module search 'app/search.bicep' = if (enableAiSearch) {
  name: 'search'
  scope: rg
  params: {
    name: '${abbreviations.searchService}-${resourceToken}'
    location: location
    sku: aiSearchSku
    tags: tags
  }
}

module database 'app/database.bicep' = {
  name: 'database'
  scope: rg
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbreviations.cosmosDbAccount}-${resourceToken}'
    location: location
    tags: tags
  }
}

// Get search service name reference for admin key
resource searchService 'Microsoft.Search/searchServices@2023-11-01' existing = if (enableAiSearch) {
  name: '${abbreviations.searchService}-${resourceToken}'
  scope: rg
}

module web 'app/web.bicep' = {
  name: 'web'
  scope: rg
  params: {
    frontendAppName: !empty(frontendAppName) ? frontendAppName : '${abbreviations.appServiceWebApp}-fe-${resourceToken}'
    backendAppName: !empty(backendAppName) ? backendAppName : '${abbreviations.appServiceWebApp}-be-${resourceToken}'
    frontendPlanName: !empty(frontendAppServicePlanName) ? frontendAppServicePlanName : '${abbreviations.appServicePlan}-fe-${resourceToken}'
    backendPlanName: !empty(backendAppServicePlanName) ? backendAppServicePlanName : '${abbreviations.appServicePlan}-be-${resourceToken}'
    frontendStack: frontendStack
    frontendRuntime: stackVersions[frontendStack].runtime
    frontendRuntimeVersion: stackVersions[frontendStack].version
    backendStack: backendStack
    backendRuntime: stackVersions[backendStack].runtime
    backendRuntimeVersion: stackVersions[backendStack].version
    databaseAccountEndpoint: database.outputs.endpoint
    databaseName: database.outputs.database.name
    chatHistoryContainer: database.outputs.containers[0].name
    usersContainer: database.outputs.containers[1].name
    openAiSettings: {
      endpoint: ai.outputs.endpoint
      completionDeploymentName: ai.outputs.deployments[0].name
      embeddingDeploymentName: ai.outputs.deployments[1].name
    }
    searchSettings: enableAiSearch ? {
      endpoint: search.outputs.endpoint
      adminKey: searchService.listAdminKeys().primaryKey
    } : {}
    frontendManagedIdentity: identity.outputs.frontendIdentity
    backendManagedIdentity: identity.outputs.backendIdentity
    location: location
    tags: tags
  }
}

module security 'app/security.bicep' = {
  name: 'security'
  scope: rg
  params: {
    databaseAccountName: database.outputs.accountName
    appPrincipalId: identity.outputs.backendIdentity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Infrastructure Outputs
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId

// Identity Outputs
output AZURE_FRONTEND_IDENTITY_CLIENT_ID string = identity.outputs.frontendIdentity.clientId
output AZURE_BACKEND_IDENTITY_CLIENT_ID string = identity.outputs.backendIdentity.clientId

// Cosmos DB Outputs
output AZURE_COSMOS_DB_ENDPOINT string = database.outputs.endpoint
output AZURE_COSMOS_DB_DATABASE_NAME string = database.outputs.database.name
output AZURE_COSMOS_DB_CHAT_CONTAINER_NAME string = database.outputs.containers[0].name
output AZURE_COSMOS_DB_USERS_CONTAINER_NAME string = database.outputs.containers[1].name

// OpenAI Outputs
output AZURE_OPENAI_ENDPOINT string = ai.outputs.endpoint
output AZURE_OPENAI_COMPLETION_DEPLOYMENT string = ai.outputs.deployments[0].name
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = ai.outputs.deployments[1].name

// App Service Outputs
output AZURE_FRONTEND_APP_NAME string = web.outputs.frontendAppName
output AZURE_FRONTEND_APP_URL string = web.outputs.frontendEndpoint
output AZURE_BACKEND_APP_NAME string = web.outputs.backendAppName
output AZURE_BACKEND_APP_URL string = web.outputs.backendEndpoint
