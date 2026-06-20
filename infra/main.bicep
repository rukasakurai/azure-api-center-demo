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

@description('Runtime endpoint (Streamable HTTP) of the usecase-coach MCP server (source: https://github.com/rukasakurai/usecase-coach). Leave empty to register only the catalog entry. Set it with "azd env set USECASE_COACH_MCP_ENDPOINT <url>" so the endpoint is never committed to this public repository.')
param usecaseCoachMcpEndpoint string = ''

var hasMcpEndpoint = !empty(usecaseCoachMcpEndpoint)

@description('Optional Microsoft Entra object ID (a group is recommended) granted read access to the catalog so people in your tenant can discover the registered assets. Leave empty to skip. Set it with "azd env set CATALOG_READERS_PRINCIPAL_ID <objectId>" so no tenant-specific ID is committed to this public repository.')
param catalogReadersPrincipalId string = ''

@description('Principal type of catalogReadersPrincipalId. Use "Group" for an Entra group (recommended) or "User" for a single user.')
@allowed([
  'Group'
  'User'
  'ServicePrincipal'
])
param catalogReadersPrincipalType string = 'Group'

var hasCatalogReaders = !empty(catalogReadersPrincipalId)

@description('Microsoft Entra application (client) ID used by the API Center portal for user sign-in. When set, the deployment publishes the Entra-protected discovery portal so people in your tenant can browse and connect to registered assets (including the MCP server) without an Azure subscription. Set it with "azd env set PORTAL_ENTRA_CLIENT_ID <appId>"; leave empty to skip publishing the portal. The app registration is created separately (see README) because it requires Microsoft Entra directory permissions.')
param portalEntraClientId string = ''

@description('Microsoft Entra tenant ID for portal sign-in. Defaults to the deployment tenant so only members of your tenant can sign in.')
param portalEntraTenantId string = tenant().tenantId

@description('Allow anonymous (unauthenticated) access to the API Center portal/registry visibility. Keep false for Entra-protected ("production") environments. Set true ONLY for a dedicated environment used to test the GitHub Copilot MCP allowlist, whose registry fetch cannot present an Entra token. Set it with "azd env set PORTAL_ALLOW_ANONYMOUS_ACCESS true".')
param portalAllowAnonymousAccess bool = false

var configurePortal = !empty(portalEntraClientId)

@description('GitHub repository (tree URL) whose Agent Skills are automatically synchronized into the API Center inventory. Leave empty to use the default public rukasakurai/agent-skills repo. Each skill is discovered by the "**/SKILL.md" file pattern per the Agent Skills specification (https://agentskills.io); the rest of the standard skill files and folders belong to that skill. Because this repository is public, only a public repository URL belongs here. Set it with "azd env set AGENT_SKILLS_REPOSITORY_URL <url>".')
param agentSkillsRepositoryUrl string = ''

var agentSkillsRepositoryUrlEffective = empty(agentSkillsRepositoryUrl) ? 'https://github.com/rukasakurai/agent-skills/tree/main/skills' : agentSkillsRepositoryUrl

// Built-in role: Azure API Center Data Reader
var apiCenterDataReaderRoleId = 'c7244dfb-f447-457d-b2ba-3999044d1706'

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

@description('MCP server asset for the usecase-coach MCP server, modeled as an API of kind "mcp". The source code is public; the runtime endpoint is supplied at deploy time.')
resource mcpServer 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = {
  parent: workspace
  name: 'usecase-coach-mcp'
  properties: {
    title: 'Usecase Coach MCP Server'
    kind: 'mcp'
    summary: 'Model Context Protocol server providing use-case coaching tools.'
    description: 'Registers the usecase-coach MCP server (source: https://github.com/rukasakurai/usecase-coach) so people in the tenant can discover it. The runtime endpoint is supplied at deploy time.'
  }
}

@description('Deployment environment representing the Azure host of the MCP server. Created only when a runtime endpoint is supplied.')
resource mcpEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview' = if (hasMcpEndpoint) {
  parent: workspace
  name: 'mcp-azure'
  properties: {
    title: 'Azure (Entra-protected)'
    kind: 'production'
    server: {
      type: 'Azure'
    }
  }
}

@description('Version of the usecase-coach MCP server. Created only when a runtime endpoint is supplied.')
resource mcpVersion 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview' = if (hasMcpEndpoint) {
  parent: mcpServer
  name: 'v1'
  properties: {
    title: 'v1'
    lifecycleStage: 'production'
  }
}

@description('MCP definition (Streamable HTTP) for the version. Created only when a runtime endpoint is supplied.')
resource mcpDefinition 'Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview' = if (hasMcpEndpoint) {
  parent: mcpVersion
  name: 'mcp-streamable'
  properties: {
    title: 'MCP (Streamable HTTP)'
  }
}

@description('Deployment that records the runtime endpoint of the MCP server so users can connect. Created only when a runtime endpoint is supplied.')
resource mcpDeployment 'Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview' = if (hasMcpEndpoint) {
  parent: mcpServer
  name: 'primary'
  properties: {
    title: 'Primary'
    environmentId: '/workspaces/default/environments/mcp-azure'
    definitionId: '/workspaces/default/apis/usecase-coach-mcp/versions/v1/definitions/mcp-streamable'
    server: {
      runtimeUri: [
        usecaseCoachMcpEndpoint
      ]
    }
  }
  dependsOn: [
    mcpEnvironment
    mcpDefinition
  ]
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
      '/workspaces/default/apis/usecase-coach-mcp'
    ]
  }
  dependsOn: [
    skill
    mcpServer
  ]
}

@description('Deployment environment representing the GitHub repository that the Agent Skills are synchronized from.')
resource agentSkillsEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview' = {
  parent: workspace
  name: 'github-agent-skills'
  properties: {
    title: 'Agent Skills (GitHub)'
    kind: 'production'
  }
}

@description('Git integration (API source) that continuously synchronizes Agent Skills from the public GitHub repository into the API Center inventory. Note: the "gitSource" shape is accepted by the live API Center resource provider but is not yet part of the published apiSources ARM type, so Bicep emits BCP037 "property not allowed" warnings on apiSourceType and gitSource; these are expected and the deployment succeeds.')
resource agentSkillsSource 'Microsoft.ApiCenter/services/workspaces/apiSources@2024-06-01-preview' = {
  parent: workspace
  name: 'github-agent-skills'
  properties: {
    #disable-next-line BCP037
    apiSourceType: 'Git'
    #disable-next-line BCP037
    gitSource: {
      repositoryUrl: agentSkillsRepositoryUrlEffective
      gitProvider: 'github'
      assetTypes: [
        {
          assetType: 'skill'
          filesToInclude: '**/SKILL.md'
        }
      ]
    }
    importSpecification: 'ondemand'
    targetEnvironmentId: '/workspaces/default/environments/github-agent-skills'
    targetLifecycleStage: 'production'
  }
  dependsOn: [
    agentSkillsEnvironment
  ]
}

@description('Optional: grant a group (or user) read access to the catalog so its members can discover the registered assets in the Azure portal and tooling. Created only when a principal ID is supplied.')
resource catalogReadersAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (hasCatalogReaders) {
  name: guid(apiCenter.id, catalogReadersPrincipalId, apiCenterDataReaderRoleId)
  scope: apiCenter
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', apiCenterDataReaderRoleId)
    principalId: catalogReadersPrincipalId
    principalType: catalogReadersPrincipalType
  }
}

@description('Optional: publish the Entra-protected API Center discovery portal so people without Azure access can find and connect to the registered assets. Sign-in is restricted to the configured tenant; access to asset data is governed by the "Azure API Center Data Reader" role. Created only when portalEntraClientId is supplied.')
resource portal 'Microsoft.ApiCenter/services/portals@2024-06-01-preview' = if (configurePortal) {
  parent: apiCenter
  name: 'default'
  properties: {
    title: apiCenter.name
    enabled: true
    allowAnonymousAccess: portalAllowAnonymousAccess
    authentication: {
      clientId: portalEntraClientId
      tenantId: portalEntraTenantId
      authMode: 'azureRbac'
    }
  }
}

output apiCenterResourceId string = apiCenter.id
output apiCenterNameOutput string = apiCenter.name
output skillName string = skill.name
output agentName string = agent.name
output mcpServerName string = mcpServer.name
output mcpEndpointConfigured bool = hasMcpEndpoint
output catalogReadersConfigured bool = hasCatalogReaders
output portalConfigured bool = configurePortal
output portalHostname string = any(apiCenter.properties).portalHostname
output pluginName string = plugin.name
output agentSkillsRepositoryUrlOutput string = agentSkillsRepositoryUrlEffective
