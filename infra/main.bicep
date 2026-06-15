@description('Azure region for Azure API Center resources. Defaults to the resource group region used by azd.')
param location string = resourceGroup().location

@description('Name of the Azure API Center service.')
param apiCenterName string = 'apic-${uniqueString(subscription().id, resourceGroup().id)}'

@description('Optional tags applied to all resources in this demo.')
param tags object = {}

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01-preview' = {
  name: apiCenterName
  location: location
  sku: {
    name: 'Free'
  }
  tags: tags
  properties: {}
}

resource a2aApi 'Microsoft.ApiCenter/services/apis@2024-03-01-preview' = {
  parent: apiCenter
  name: 'a2a-servers'
  properties: {
    title: 'A2A Servers'
    kind: 'rest'
    summary: 'Registry entry representing enterprise A2A server endpoints and metadata.'
    description: 'Demonstrates how Azure API Center can organize A2A server APIs in an Entra-protected internal catalog.'
  }
}

resource mcpApi 'Microsoft.ApiCenter/services/apis@2024-03-01-preview' = {
  parent: apiCenter
  name: 'mcp-servers'
  properties: {
    title: 'MCP Servers'
    kind: 'rest'
    summary: 'Registry entry representing enterprise Model Context Protocol servers.'
    description: 'Demonstrates how Azure API Center can organize MCP server APIs in an Entra-protected internal catalog.'
  }
}

resource skillsApi 'Microsoft.ApiCenter/services/apis@2024-03-01-preview' = {
  parent: apiCenter
  name: 'agent-skills'
  properties: {
    title: 'Agent Skills'
    kind: 'rest'
    summary: 'Registry entry representing reusable enterprise agent skills.'
    description: 'Demonstrates how Azure API Center can organize skill APIs in an Entra-protected internal catalog.'
  }
}

resource pluginsApi 'Microsoft.ApiCenter/services/apis@2024-03-01-preview' = {
  parent: apiCenter
  name: 'plugins'
  properties: {
    title: 'Plugins'
    kind: 'rest'
    summary: 'Registry entry representing enterprise plugin APIs.'
    description: 'Demonstrates how Azure API Center can organize plugin APIs in an Entra-protected internal catalog.'
  }
}

output apiCenterResourceId string = apiCenter.id
output apiCenterNameOutput string = apiCenter.name
output demoApiNames array = [
  a2aApi.name
  mcpApi.name
  skillsApi.name
  pluginsApi.name
]
