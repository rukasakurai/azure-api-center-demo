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

> The Bicep template can also **publish the Entra-protected discovery portal** (see [Sharing with colleagues who don't use Azure](#sharing-with-colleagues-who-dont-use-azure) below).

> Note: The Bicep template defaults to the `Free` API Center SKU for low-cost exploration. For broader evaluation (capacity/features), set `apiCenterSku` to `Standard`.

### Sharing with colleagues who don't use Azure

A colleague in your Microsoft Entra tenant who has **no Azure access** can still discover and connect to your registered MCP server through the **API Center self-service portal** — an Azure-managed website where they sign in with their normal Entra account. This repo can publish that portal as part of `azd up`.

The portal is the `Microsoft.ApiCenter/services/portals` resource (`infra/main.bicep`). It is configured for `azureRbac` auth and sign-in is restricted to your tenant. Two pieces are required:

1. **A Microsoft Entra app registration** for the portal sign-in (needs Entra *directory* permissions, which a plain Azure subscription owner may not have — so it is a separate, idempotent helper script rather than part of the template):

   ```bash
   azd up                              # first provision creates the API Center (portal skipped)
   ./scripts/register-portal-app.sh    # registers the Entra app, stores its client ID in azd
   #   PowerShell: ./scripts/register-portal-app.ps1
   azd up                              # publishes the Entra-protected portal
   ```

   The script reads the portal hostname from the deployment, registers (or reuses) an app with the correct single-page-application redirect URI, and sets `PORTAL_ENTRA_CLIENT_ID` in your azd environment. You can also bring your own app and set it directly:

   ```bash
   azd env set PORTAL_ENTRA_CLIENT_ID <app-client-id>
   azd up
   ```

2. **Reader access for colleagues.** Portal data is governed by the **Azure API Center Data Reader** role. Grant a colleague group so they can browse assets:

   ```bash
   azd env set CATALOG_READERS_PRINCIPAL_ID <entra-group-object-id>
   azd up
   ```

Once published, colleagues open `https://<service>.portal.<region>.azure-apicenter.ms`, sign in with their Entra account, find the `usecase-coach-mcp` server, and copy its runtime endpoint to register it in any MCP-capable HTTP client (for example a Microsoft 365 Copilot agent built in [Copilot Studio](https://learn.microsoft.com/microsoft-copilot-studio/) or the [Microsoft 365 Agents Toolkit](https://learn.microsoft.com/microsoft-365-copilot/extensibility/)). Your server's own Entra protection still applies when they connect.

> Fully hands-off alternative: the app registration can instead be created in the same deployment with the [Microsoft Graph Bicep extension](https://learn.microsoft.com/graph/templates/bicep/overview-bicep-templates-for-graph) (`Microsoft.Graph/applications` + `servicePrincipals`), giving a true single-`azd up`. It is not the default here because it requires the preview extension plus directory permissions for every deployer.

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
azd env set PORTAL_ENTRA_CLIENT_ID <portal-app-client-id>
azd env set CATALOG_READERS_PRINCIPAL_ID <entra-group-object-id>
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
- `infra/main.bicep` - Infrastructure for Azure API Center and the demo agent, MCP server, skill, and plugin assets, plus the optional Entra-protected discovery portal
- `infra/main.parameters.json` - Maps azd environment variables (`USECASE_COACH_MCP_ENDPOINT`, `CATALOG_READERS_PRINCIPAL_ID`, `PORTAL_ENTRA_CLIENT_ID`) to the deployment (keeps tenant-specific values out of source control)
- `scripts/register-portal-app.sh` / `.ps1` - Idempotently registers the Microsoft Entra app for the discovery portal and stores its client ID in the azd environment
