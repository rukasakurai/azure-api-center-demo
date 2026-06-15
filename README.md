# repo-baseline

A minimal GitHub template repository providing baseline structure and conventions for new projects.

## What This Is

This is a **template repository** that provides:
- Contribution guidelines ([CONTRIBUTING.md](CONTRIBUTING.md)) and AI collaboration guidance ([AGENTS.md](AGENTS.md))
- Issue and pull request templates for structured communication
- Manual Azure OIDC validation workflow
- E2E test and azd environment management workflows
- A starting point that avoids premature technical decisions

This template is intentionally minimal and public-safe, containing no secrets, licenses, or environment-specific configuration.

## How to Use as a Template

1. Click the **"Use this template"** button on GitHub
2. Create a new repository from this template (public or private)
3. Follow the post-creation checklist below

## Post-Creation Checklist

After creating a repository from this template:

- [ ] **Choose and add a LICENSE file** - This template intentionally omits a license; add one appropriate for your project
- [ ] **Configure Azure OIDC** (if using Azure) - Set up federated credentials and add the following repository secrets:
  - `AZURE_CLIENT_ID` (repository variable)
  - `AZURE_TENANT_ID` (repository secret)
  - `AZURE_SUBSCRIPTION_ID` (repository secret)
  
  See [docs/azure-oidc-setup.md](docs/azure-oidc-setup.md) for detailed setup instructions. Then run the "Azure OIDC Connectivity Check" workflow manually to verify the configuration.
- [ ] **Enable AI agent Azure access** (if using Azure with Copilot coding agent) - Run `azd coding-agent config` to give AI agents read-time visibility into Azure state while authoring changes. See [docs/azure-coding-agent-guide.md](docs/azure-coding-agent-guide.md) for guidance.
- [ ] **Update README.md** - Replace this generic template README with repository-specific documentation
- [ ] **Review AGENTS.md** - Update or remove this file to reflect your repository's specific purpose and conventions

## Included Workflows

### Azure OIDC Connectivity Check

A manual workflow that validates your Azure OIDC configuration is working correctly. Run it after completing the OIDC setup above.

- **Trigger**: Manual (`workflow_dispatch`)
- **File**: `.github/workflows/azure-oidc-check.yml`

### E2E Test

Automates provisioning of infrastructure, application deployment, test execution, and cleanup using the Azure Developer CLI (`azd`). Creates a resource group (with optional tagging from repository secrets) before running `azd provision` and `azd deploy`.

- **Trigger**: Manual (`workflow_dispatch`) or on pull requests to `main` that modify `app/`, `infra/`, or `azure.yaml`
- **File**: `.github/workflows/e2e-test.yml`
- **Inputs** (manual trigger):
  - `cleanup` — Run `azd down` after tests (default: `true`)
  - `environment` — azd environment name (default: auto-generated from run ID)
  - `location` — Azure region (default: `japaneast`)

**Customize for your project**: Edit the "Run tests" step in the workflow to add your E2E test commands (e.g., `pytest tests/e2e/`, `npm test`, or a custom test script).

#### Required Configuration

| Name | Type | Description |
|------|------|-------------|
| `AZURE_CLIENT_ID` | Variable | Application (client) ID |
| `AZURE_TENANT_ID` | Secret | Microsoft Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Secret | Azure Subscription ID |
| `RG_TAG_NAME` | Secret | (Optional) Tag name for the resource group |
| `RG_TAG_VALUE` | Secret | (Optional) Tag value for the resource group |

### AZD Manage (Up / Down)

Enables on-demand creation (`azd up`) and destruction (`azd down`) of Azure environments using the Azure Developer CLI. Creates a resource group (with optional tagging from repository secrets) before running `azd up`. Useful for managing isolated development, test, or preview environments.

- **Trigger**: Manual (`workflow_dispatch`)
- **File**: `.github/workflows/azd-manage.yml`
- **Inputs**:
  - `action` — `up` or `down` (required)
  - `environment` — azd environment name (default: repository name, e.g. `my-project` → resource group `rg-my-project`)
  - `location` — Azure region (default: `japaneast`)

#### Usage

1. Go to **Actions** → **AZD Manage (Up / Down)**
2. Click **Run workflow**
3. Select `up` to provision or `down` to tear down
4. Optionally set a custom environment name and Azure region