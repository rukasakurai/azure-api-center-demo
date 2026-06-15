@description('Azure region for Azure API Center resources. Defaults to the resource group region used by azd.')
param location string = resourceGroup().location

@description('Name of the Azure API Center service.')
param apiCenterName string = 'apic-${uniqueString(subscription().id, resourceGroup().id)}'

@description('Azure API Center SKU. Free is default for low-cost demo environments.')
@allowed([
  'Free'
  'Standard'
])
param apiCenterSku string = 'Free'

@description('Optional tags applied to all resources in this demo.')
param tags object = {}

resource apiCenter 'Microsoft.ApiCenter/services@2024-06-01-preview' = {
  name: apiCenterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: apiCenterSku
  }
  tags: tags
  properties: {}
}

@description('The default workspace is created automatically with the service; declare it so assets can be parented to it.')
resource workspace 'Microsoft.ApiCenter/services/workspaces@2024-06-01-preview' = {
  parent: apiCenter
  name: 'default'
  properties: {
    title: 'Default workspace'
    description: 'Default workspace'
  }
}

@description('Skill asset: a reusable capability that AI agents can discover and consume.')
resource skill 'Microsoft.ApiCenter/services/workspaces/skills@2024-06-01-preview' = {
  parent: workspace
  name: 'code-review-skill'
  properties: {
    title: 'Code Review Skill'
    summary: 'Performs automated code reviews using static analysis.'
    description: 'Demonstrates how Azure API Center can register reusable agent skills in an Entra-protected internal catalog.'
    lifecycleStage: 'production'
  }
}

@description('Agent asset (for example, an A2A agent) registered in the API Center inventory.')
resource agent 'Microsoft.ApiCenter/services/workspaces/agents@2024-06-01-preview' = {
  parent: workspace
  name: 'help-desk-agent'
  properties: {
    title: 'Help Desk Agent'
    summary: 'Answers common help desk questions.'
    description: 'Demonstrates how Azure API Center can register agents (including A2A agents) in an Entra-protected internal catalog.'
  }
}

@description('MCP server asset, modeled as an API of kind "mcp".')
resource mcpServer 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = {
  parent: workspace
  name: 'github-mcp'
  properties: {
    title: 'GitHub MCP Server'
    kind: 'mcp'
    summary: 'Remote Model Context Protocol server exposing GitHub tools.'
    description: 'Demonstrates how Azure API Center can register MCP servers in an Entra-protected internal catalog.'
    lifecycleStage: 'production'
  }
}

@description('Plugin asset that bundles already-registered skills and MCP servers via workspace-relative resource IDs.')
resource plugin 'Microsoft.ApiCenter/services/workspaces/plugins@2024-06-01-preview' = {
  parent: workspace
  name: 'dev-toolkit'
  properties: {
    title: 'Dev Toolkit'
    summary: 'A plugin that bundles a skill and an MCP server.'
    description: 'Demonstrates how Azure API Center can bundle registered skills and MCP servers into a higher-level plugin.'
    resourceIds: [
      '/workspaces/default/skills/code-review-skill'
      '/workspaces/default/apis/github-mcp'
    ]
  }
  dependsOn: [
    skill
    mcpServer
  ]
}

output apiCenterResourceId string = apiCenter.id
output apiCenterNameOutput string = apiCenter.name
output skillName string = skill.name
output agentName string = agent.name
output mcpServerName string = mcpServer.name
output pluginName string = plugin.name
