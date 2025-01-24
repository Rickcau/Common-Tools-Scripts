@description('Creates frontend and backend web applications with separate app service plans')
metadata description = 'Create web apps with separated frontend and backend services'

// App naming parameters
param frontendAppName string
param backendAppName string
param frontendPlanName string
param backendPlanName string

// Stack selection parameters
param frontendStack string
param frontendRuntime string
param frontendRuntimeVersion string

@description('Selected technology stack for backend')
param backendStack string
param backendRuntime string
param backendRuntimeVersion string

// Added to allow support for AI Search Service
param searchSettings object = {}

// Common parameters
param location string = resourceGroup().location
param tags object = {}

@description('SKU of the App Service Plans')
param sku string = 'B1'

// Database configuration
@description('Cosmos DB configuration')
param databaseAccountEndpoint string
param databaseName string
param chatHistoryContainer string
param usersContainer string

@description('OpenAI settings')
param openAiSettings object = {
  endpoint: ''
  completionDeploymentName: ''
  embeddingDeploymentName: ''
}

// Identity configuration
type managedIdentity = {
  resourceId: string
  clientId: string
}

@description('Frontend user-assigned managed identity')
param frontendManagedIdentity managedIdentity

@description('Backend user-assigned managed identity')
param backendManagedIdentity managedIdentity

// Base app settings for both apps
var baseAppSettings = {
  // Frontend runtime settings
  WEBSITE_NODE_DEFAULT_VERSION: frontendStack == 'node' ? frontendRuntimeVersion : null
  PYTHON_VERSION: frontendStack == 'python' ? frontendRuntimeVersion : null
  
  // Backend runtime settings
  WEBSITE_NODE_DEFAULT_VERSION_BACKEND: backendStack == 'node' ? backendRuntimeVersion : null
  PYTHON_VERSION_BACKEND: backendStack == 'python' ? backendRuntimeVersion : null
}

// Frontend App Service Plan
module frontendPlan '../core/host/app-service/plan.bicep' = {
  name: 'frontend-app-service-plan'
  params: {
    name: frontendPlanName
    location: location
    tags: tags
    sku: sku
    kind: 'linux'
  }
}

// Backend App Service Plan
module backendPlan '../core/host/app-service/plan.bicep' = {
  name: 'backend-app-service-plan'
  params: {
    name: backendPlanName
    location: location
    tags: tags
    sku: sku
    kind: 'linux'
  }
}

// Frontend App Service with configurable runtime
module frontendApp '../core/host/app-service/site.bicep' = {
  name: 'frontend-web-app'
  params: {
    name: frontendAppName
    location: location
    tags: tags
    parentPlanName: frontendPlan.outputs.name
    runtimeName: frontendRuntime
    runtimeVersion: frontendRuntimeVersion
    kind: 'app,linux'
    enableSystemAssignedManagedIdentity: false
    userAssignedManagedIdentityIds: [
      frontendManagedIdentity.resourceId
    ]
  }
}

// Backend App Service with configurable runtime
module backendApp '../core/host/app-service/site.bicep' = {
  name: 'backend-web-app'
  params: {
    name: backendAppName
    location: location
    tags: tags
    parentPlanName: backendPlan.outputs.name
    runtimeName: backendRuntime
    runtimeVersion: backendRuntimeVersion
    kind: 'app,linux'
    enableSystemAssignedManagedIdentity: false
    userAssignedManagedIdentityIds: [
      backendManagedIdentity.resourceId
    ]
    allowedCorsOrigins: [
      'https://${frontendAppName}.azurewebsites.net', 'http://localhost:3000'                          
    ]
  }
}

// Backend App Settings including AI Search if enabled
module backendAppConfig '../core/host/app-service/config.bicep' = {
  name: 'backend-app-config'
  params: {
    parentSiteName: backendApp.outputs.name
    appSettings: union({
      // Identity configuration
      AZURE_CLIENT_ID: backendManagedIdentity.clientId
      
      // Cosmos DB configuration
      COSMOSDB__ENDPOINT: databaseAccountEndpoint
      COSMOSDB__DATABASE: databaseName
      COSMOSDB__CHATHISTORYCONTAINER: chatHistoryContainer
      COSMOSDB__USERSCONTAINER: usersContainer
      
      // OpenAI configuration
      OPENAI__ENDPOINT: openAiSettings.endpoint
      OPENAI__COMPLETIONDEPLOYMENTNAME: openAiSettings.completionDeploymentName
      OPENAI__EMBEDDINGDEPLOYMENTNAME: openAiSettings.embeddingDeploymentName
    }, 
    !empty(searchSettings) ? {
      // AI Search configuration
      AZURE_SEARCH_ENDPOINT: searchSettings.endpoint
      AZURE_SEARCH_ADMIN_KEY: searchSettings.adminKey
    } : {})
  }
}

// Frontend App Settings with runtime-specific configurations
module frontendAppConfig '../core/host/app-service/config.bicep' = {
  name: 'frontend-app-config'
  params: {
    parentSiteName: frontendApp.outputs.name
    appSettings: union(baseAppSettings, {
      AZURE_CLIENT_ID: frontendManagedIdentity.clientId
      BACKEND_API_URL: 'https://${backendAppName}.azurewebsites.net'
    })
  }
}

// Outputs
output frontendAppName string = frontendApp.outputs.name
output frontendEndpoint string = frontendApp.outputs.endpoint
output backendAppName string = backendApp.outputs.name
output backendEndpoint string = backendApp.outputs.endpoint
