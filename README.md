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
  - An **MCP server** (`usecase-coach-mcp`, an API of kind `mcp`) that registers the internally deployed [usecase-coach](https://github.com/rukasakurai/usecase-coach) MCP server — see [Register and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
  - A **skill** (`code-review-skill`) — see [Register and discover skills](https://learn.microsoft.com/azure/api-center/register-discover-skills)
  - A **plugin** (`dev-toolkit`) that bundles the skill and the MCP server — see [Register and discover plugins](https://learn.microsoft.com/azure/api-center/register-discover-plugins)

These assets are intentionally lightweight and serve as a starting registry model you can extend with versions, definitions, environments, metadata, and governance policies.

### Registering the internal MCP server endpoint

The `usecase-coach-mcp` asset is always registered as a catalog entry. To also record its **live runtime endpoint** (so colleagues can connect, not just discover the entry), supply the endpoint at deploy time. The endpoint is read from an azd environment variable and is **never committed to this repository**:

```bash
azd env set USECASE_COACH_MCP_ENDPOINT https://<your-internal-mcp-host>/mcp
azd up
```

When set, the deployment additionally provisions an `internal-azure` environment plus a version, a Streamable HTTP definition, and a deployment that points at your endpoint. Leave the variable unset to register only the catalog entry.

The endpoint itself is protected by Microsoft Entra (the deployed server enforces sign-in), and the API Center inventory is only visible to identities granted Azure RBAC access on the service within your tenant — so discovery stays tenant-scoped.

> **Enabling the self-service discovery portal** needs one extra piece: a Microsoft Entra app registration (single-tenant, with the portal URL as an SPA redirect) so the managed portal website can read the catalog on behalf of the signed-in user. This *can* be automated — either with the [Microsoft Graph Bicep extension](https://learn.microsoft.com/graph/templates/bicep/overview) (declares `Microsoft.Graph/applications` + `servicePrincipals`) or an `azd` [`postprovision` hook](https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-extensibility) running `az ad app create` / `az ad app permission admin-consent`. It's left out of this template by default because it requires the deployer to hold **Microsoft Entra directory permissions** (e.g. Application Administrator) beyond Azure resource ownership, and binding the app and publishing the portal is a per-org choice. See [Set up the API Center portal](https://learn.microsoft.com/azure/api-center/set-up-api-center-portal) (it also offers a one-click automatic app-registration option). Until you enable it, colleagues discover assets through the Azure portal's **Assets** view, which is already Entra/RBAC-gated.

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
azd env set USECASE_COACH_MCP_ENDPOINT https://<your-internal-mcp-host>/mcp
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
- `infra/main.parameters.json` - Maps the `USECASE_COACH_MCP_ENDPOINT` azd environment variable to the deployment (keeps the internal endpoint out of source control)
