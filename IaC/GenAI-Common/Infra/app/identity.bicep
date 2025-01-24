metadata description = 'Create identity resources.'

param identityName string
param location string = resourceGroup().location
param tags object = {}

// Single identity module that we'll use as a template for both identities
module frontendIdentity '../core/security/identity/user-assigned.bicep' = {
  name: 'frontend-identity'
  params: {
    name: '${identityName}-frontend'
    location: location
    tags: tags
  }
}

module backendIdentity '../core/security/identity/user-assigned.bicep' = {
  name: 'backend-identity'
  params: {
    name: '${identityName}-backend'
    location: location
    tags: tags
  }
}

// Outputs matching the expected property names
output frontendIdentity object = {
  name: frontendIdentity.outputs.name
  resourceId: frontendIdentity.outputs.resourceId
  principalId: frontendIdentity.outputs.principalId
  clientId: frontendIdentity.outputs.clientId
}

output backendIdentity object = {
  name: backendIdentity.outputs.name
  resourceId: backendIdentity.outputs.resourceId
  principalId: backendIdentity.outputs.principalId
  clientId: backendIdentity.outputs.clientId
}
