# Azure API Center Demo

This repository is a focused demo for understanding Azure API Center capabilities for an enterprise-grade, Microsoft Entra-protected internal registry.

It is designed to explore how Azure API Center can be used (and where additional integration may still be needed) for cataloging:
- A2A Servers ([a2a-protocol.org](https://a2a-protocol.org/))
- MCP Servers ([modelcontextprotocol.io](https://modelcontextprotocol.io/))
- Agent Skills ([agentskills.io](https://agentskills.io/home))
- Plugins

## What this demo provisions

Using `azd up`, this repo provisions:
- One Azure API Center service (with a system-assigned managed identity) and its `default` workspace
- Four real catalog assets, one of each type:
  - An **agent** (`help-desk-agent`) — see [Register and manage agents](https://learn.microsoft.com/azure/api-center/register-manage-agents)
  - An **MCP server** (`github-mcp`, an API of kind `mcp`) — see [Register and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
  - A **skill** (`code-review-skill`) — see [Register and discover skills](https://learn.microsoft.com/azure/api-center/register-discover-skills)
  - A **plugin** (`dev-toolkit`) that bundles the skill and the MCP server — see [Register and discover plugins](https://learn.microsoft.com/azure/api-center/register-discover-plugins)

These assets are intentionally lightweight and serve as a starting registry model you can extend with versions, definitions, environments, metadata, and governance policies.

> Note: The Bicep template defaults to the `Free` API Center SKU for low-cost exploration. For broader evaluation (capacity/features), set `apiCenterSku` to `Standard`.

## Prerequisites

- Azure subscription with permission to create resources
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI (`azd`)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Authenticated Azure session (`az login`)

## Quick start

From the repository root:

```bash
azd auth login
azd up
```

`azd up` will:
1. Create/select an azd environment
2. Provision infrastructure from `infra/main.bicep`
3. Output the API Center resource details

## Customize the demo

You can customize deployment values in your azd environment:

```bash
azd env set AZURE_LOCATION <region>
azd env set apiCenterName <unique-api-center-name>
azd env set apiCenterSku Standard
```

Then re-run:

```bash
azd up
```

## Clean up

To remove all provisioned resources for the current azd environment:

```bash
azd down --force --purge
```

## Repository structure

- `azure.yaml` - Azure Developer CLI project definition
- `infra/main.bicep` - Infrastructure for Azure API Center and the demo agent, MCP server, skill, and plugin assets
