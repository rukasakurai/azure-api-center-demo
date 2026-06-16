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
  - An **MCP server** (`usecase-coach-mcp`, an API of kind `mcp`) that registers the [usecase-coach](https://github.com/rukasakurai/usecase-coach) MCP server — see [Register and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
  - A **skill** (`code-review-skill`) — see [Register and discover skills](https://learn.microsoft.com/azure/api-center/register-discover-skills)
  - A **plugin** (`dev-toolkit`) that bundles the skill and the MCP server — see [Register and discover plugins](https://learn.microsoft.com/azure/api-center/register-discover-plugins)

These assets are intentionally lightweight and serve as a starting registry model you can extend with versions, definitions, environments, metadata, and governance policies.

In addition, the deployment provisions a **Git integration** that automatically synchronizes Agent Skills from a public GitHub repository into the inventory (see [Synchronizing Agent Skills from GitHub](#synchronizing-agent-skills-from-github)).

### Registering the MCP server endpoint

The `usecase-coach-mcp` asset is always registered as a catalog entry. To also record its **runtime endpoint** (so users can connect, not just discover the entry), supply the endpoint at deploy time. The endpoint is read from an azd environment variable and is **never committed to this repository**:

```bash
azd env set USECASE_COACH_MCP_ENDPOINT https://<your-mcp-host>/mcp
azd up
```

When set, the deployment additionally provisions an `mcp-azure` environment plus a version, a Streamable HTTP definition, and a deployment that points at your endpoint. Leave the variable unset to register only the catalog entry.

If your endpoint is protected by Microsoft Entra (the server enforces sign-in), that protection still applies when users connect; the API Center inventory is only visible to identities granted Azure RBAC access on the service within your tenant — so discovery stays tenant-scoped.

> The Bicep template can also **publish the Entra-protected discovery portal** (see [Sharing with people who don't use Azure](#sharing-with-people-who-dont-use-azure) below).

> Note: The Bicep template defaults to the `Free` API Center SKU for low-cost exploration. For broader evaluation (capacity/features), set `apiCenterSku` to `Standard`.

### Synchronizing Agent Skills from GitHub

Instead of registering skills one by one, the deployment connects a **GitHub repository as an [API source](https://learn.microsoft.com/azure/api-center/synchronize-assets-git)** so API Center continuously imports the Agent Skills it contains. Each skill is discovered by the `**/SKILL.md` file pattern defined by the [Agent Skills specification](https://agentskills.io/home); the other standard files and folders in a skill directory belong to that skill.

By default this syncs the public [`rukasakurai/agent-skills`](https://github.com/rukasakurai/agent-skills) repository. The deployment creates two resources in `infra/main.bicep`:

- an environment (`github-agent-skills`) representing the repository, and
- an API source (`github-agent-skills`) whose `gitSource` points at the repository and maps the `skill` asset type to `**/SKILL.md`.

The first synchronization runs asynchronously and can take several minutes; afterwards the skills appear under **Inventory → Assets** with a link icon.

To sync a different public repository, override the URL before deploying:

```bash
azd env set AGENT_SKILLS_REPOSITORY_URL https://github.com/<org>/<repo>/tree/main/<path>
azd up
```

(The default already points at the public repo, so no setting is required for the default behavior. Leaving `AGENT_SKILLS_REPOSITORY_URL` unset uses that default.)

> **Only public repositories belong here.** Because this repository is public, the repository URL is committed to source. Synchronizing a **private** repository additionally requires a GitHub personal access token stored in Azure Key Vault and the API Center managed identity granted **Key Vault Secrets User** — see [Synchronize API assets from a Git repo](https://learn.microsoft.com/azure/api-center/synchronize-assets-git). That private-repository path is intentionally **not** wired into this public template so no private URL or credential is exposed.

> **Free plan limit:** the `Free` API Center SKU allows a single integration source, which this public-repo integration occupies. Synchronizing additional repositories requires `Standard`.

> Implementation note: the `gitSource` property is accepted by the live API Center resource provider but is not yet part of the published `apiSources` ARM type, so `bicep build` emits expected `BCP037` warnings (suppressed inline in `infra/main.bicep`). The deployment succeeds regardless.

### Discovering and installing the synced skills

API Center is a **registry for discovery and governance**, not a skill installer. A registered Agent Skill stores the **Source URL** of its GitHub repository — API Center helps people *find* the skill and read its documentation; the skill content always lives in (and is installed from) GitHub.

Once you've discovered a skill in the inventory and noted its Source URL, install it directly from GitHub with the GitHub CLI's [agent skills](https://github.com/github/copilot-cli) commands, which place the `SKILL.md` and its accompanying files into your agent's skills directory:

```bash
gh skill search <query>            # find skills across GitHub
gh skill install <github-repo-url> # install into your agent (GitHub Copilot, Claude Code, etc.)
```

Agent Skills are installed and used **as skills** — they don't need to be packaged as plugins. The skill is installed straight from its source of truth (GitHub).

> Optional: API Center can also expose inventory items through a separate [plugin marketplace](https://learn.microsoft.com/azure/api-center/enable-api-center-plugin-marketplace) endpoint, which an agent CLI installs from with `/plugin install`. That path repackages skills as *plugins* and is unrelated to the skill-native `gh skill install` flow above; this demo focuses on Agent Skills, so it isn't required here.


### Sharing with people who don't use Azure

A person in your Microsoft Entra tenant can discover and connect to the registered MCP server through the **API Center self-service portal** — an Azure-managed website where they sign in with their normal Entra account. They never need their own Azure subscription, the Azure portal, or the `az` CLI. This repo can publish that portal as part of `azd up`.

> **They do, however, need one Azure RBAC role assignment.** The portal's only tenant-restricted auth mode is `azureRbac`, so each viewer's Entra identity must be granted the **Azure API Center Data Reader** role on this resource (step 2 below). The viewer never *uses* Azure — but you (or an admin) make a single role assignment against their identity or, better, an Entra group they belong to. The alternative auth mode, `allowAnonymousAccess: true`, would make the portal fully public and is intentionally not used here.

> **Do you even need the portal?** The MCP server is reached over a single endpoint URL, so sharing that link in a Teams channel, wiki, or doc is a perfectly valid way for people to discover and connect. The portal adds value only when you want a **governed, searchable catalog** (multiple servers/APIs, filtering, a single front door) rather than a copy-pasted link. If a link is enough today, skip the portal and just share the endpoint.

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

2. **Reader access for viewers.** Portal data is governed by the **Azure API Center Data Reader** role. Grant a group so its members can browse assets:

   ```bash
   azd env set CATALOG_READERS_PRINCIPAL_ID <entra-group-object-id>
   azd up
   ```

Once published, people open `https://<service>.portal.<region>.azure-apicenter.ms`, sign in with their Entra account, find the `usecase-coach-mcp` server, and copy its runtime endpoint to register it in any MCP-capable HTTP client (for example a Microsoft 365 Copilot agent built in [Copilot Studio](https://learn.microsoft.com/microsoft-copilot-studio/) or the [Microsoft 365 Agents Toolkit](https://learn.microsoft.com/microsoft-365-copilot/extensibility/)). Any Entra protection on the endpoint still applies when they connect.

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
azd env set USECASE_COACH_MCP_ENDPOINT https://<your-mcp-host>/mcp
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
