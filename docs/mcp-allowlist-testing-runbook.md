# Testing runbook: GitHub Copilot MCP allowlist against the API Center registry

Exact, reproducible steps to verify **discovery → enforcement** end to end, without relying on an AI assistant. For the concepts and tradeoffs behind these steps, see [mcp-allowlist-github-copilot.md](mcp-allowlist-github-copilot.md).

> [!IMPORTANT]
> This repository is public. **Never commit real values** — subscription/tenant/client IDs, account emails, live API Center hostnames, or MCP server URLs. Use your own values locally; the placeholders below (`<…>`) are intentional.

> [!CAUTION]
> The GitHub allowlist policy is **enterprise-wide and applies to seat holders immediately**. Only run the enforcement step against a **dedicated test enterprise**, signed in as that enterprise's identity — never your production Copilot seat. See [Step 4](#step-4--isolate-the-test-identity-critical).

## Why a dedicated environment

Enabling anonymous access drops Entra auth on the registry **listing endpoint** (catalog metadata only). To avoid weakening your Entra-protected ("production") deployment, this runbook stands up a **separate azd environment** with anonymous access on. Production stays `PORTAL_ALLOW_ANONYMOUS_ACCESS=false`.

## Step 1 — Provision a dedicated anonymous test environment

```bash
# From the repo root, signed in to the tenant that owns the target subscription:
azd auth login --tenant-id <target-tenant-id>

azd env new <test-env-name> --subscription <subscription-id> --location <region>
azd env set PORTAL_ENTRA_CLIENT_ID <portal-app-client-id>   # required: the portal must exist for the anonymous toggle to apply
azd env set PORTAL_ALLOW_ANONYMOUS_ACCESS true              # this env only; production stays false
azd env set USECASE_COACH_MCP_ENDPOINT <mcp-runtime-url>    # so the registry actually lists a server
azd provision
```

Notes:
- `PORTAL_ALLOW_ANONYMOUS_ACCESS` is wired to the portal resource's `allowAnonymousAccess` in [infra/main.bicep](../infra/main.bicep). It is the **only** anonymous-access lever in the ARM surface (the service/workspace resources have none).
- Without `USECASE_COACH_MCP_ENDPOINT`, the MCP asset has no version/deployment and the registry returns `"count": 0`.

## Step 2 — Verify the registry is anonymously readable

```bash
# Get the deployed API Center name:
APIC=$(azd env get-values | sed -n 's/^apiCenterNameOutput="\(.*\)"$/\1/p')
URL="https://${APIC}.data.<region>.azure-apicenter.ms/workspaces/default/v0.1/servers"

# Anonymous request (no auth header) — expect HTTP 200 and count >= 1:
curl -sS -o /tmp/reg.json -w "HTTP %{http_code}\n" "$URL"
python3 -m json.tool /tmp/reg.json | head -40
```

Expected: `HTTP 200` with your server in `servers[]` and `"count": 1`. (Before enabling anonymous access, the same request returns `401`.)

> Verified on 2026-06-19: anonymous request returned **HTTP 200** and listed **1 server** (`usecase-coach-mcp`).

## Step 3 — Point GitHub Copilot at the registry

1. In your **test enterprise**: **AI Controls → MCP**.
2. Ensure **MCP servers in Copilot** is enabled.
3. Set **MCP Registry URL** to the **base workspace URL** — **without** the `/v0.1/servers` suffix:
   ```text
   https://<apic-name>.data.<region>.azure-apicenter.ms/workspaces/default
   ```
4. Leave **Restrict MCP access to registry servers** = **Allow all** for now (discovery phase).

## Step 4 — Isolate the test identity (CRITICAL)

The policy follows the **GitHub identity/seat**, not the machine. A data-residency (`*.ghe.com`) enterprise uses **Enterprise Managed Users** — a separate identity from your production `github.com` Copilot license, so the policy cannot reach production **as long as you test under the test-enterprise account**.

The real risk is **editor session collision**: signing your editor into the test account replaces your production Copilot session there. Isolate it:

```bash
# Launch a separate VS Code with its own auth + extension stores.
# IMPORTANT: run this from a shell NOT attached to a running VS Code window
# (launching from an existing VS Code terminal can re-attach to the same instance
# and ignore these flags — symptoms: settings already preset, Copilot preinstalled).
code --user-data-dir ~/.vscode-ghe-test --extensions-dir ~/.vscode-ghe-test-ext -n
```

In the new window:
1. **Check the Accounts menu (bottom-left).** If it already shows your production `github.com` account, it is **not** isolated — stop and relaunch from outside any running VS Code (or use VS Code Insiders). Only proceed when it is signed out or shows only the test account.
2. Install **GitHub Copilot** + **GitHub Copilot Chat**.
3. Set `github-enterprise.uri` = `https://<your-enterprise>.ghe.com` and sign in with the **test-enterprise** account.

For **Copilot CLI**, auth is a single stored token: dedicate one environment (e.g. WSL2) to the test account and keep your production environment on your company account, or sign back in afterward.

## Step 5 — Discovery check (policy still "Allow all")

In the isolated editor signed into the test enterprise, confirm the registry's server (`usecase-coach-mcp`) appears as an available/registry MCP server. Record the surface and version.

## Step 6 — Enforcement check (flip to "Registry only")

1. In **AI Controls → MCP**, set **Restrict MCP access to registry servers → Registry only**.
2. Re-test the matrix below on **VS Code Stable** and **Copilot CLI** at minimum.

## Verification matrix (record observed results)

For each surface, record what you observed, the **surface version**, and the date. **Transport**: a *remote* server is validated by name/ID against the remote entry; a *local* server must be listed with an exactly matching server ID. Expected behavior is from GitHub's docs — confirm it, since preview behavior shifts.

| # | Case | Transport | Expected | Observed (VS Code Stable) | Observed (Copilot CLI) | Version / Date |
| - | ---- | --------- | -------- | ------------------------- | ---------------------- | -------------- |
| 1 | Server present in registry | Remote | **Allow** — connects normally | | | |
| 2 | Server **not** in registry | Remote | **Block** — fails to connect with a "blocked by policy" message | | | |
| 3 | Remote server with the **same name/ID as a registry entry but a different install URL** | Remote | **Confirm** — enforcement is name/ID matching; test whether a mismatched URL is still allowed (spoof/bypass) | | | |
| 4 | Local server **with** matching server ID in registry | Local | **Allow** | | | |
| 5 | Local server **not** in registry | Local | **Block** | | | |
| 6 | Local server with **same name but mismatched ID** | Local | **Block** | | | |
| 7 | Local server whose name/ID is **edited to match** a registry entry (config spoof) | Local | **Bypass risk** — may connect; documents the name/ID-matching limitation | | | |
| 8 | Local server whose **command/path is changed** while name/ID still matches the registry | Local | **Confirm** — only name/ID is checked, so a swapped command may still connect (bypass risk) | | | |
| 9 | *Installation* of a non-registry server | Either | **Not blocked yet** — only connection is enforced | | | |

### Recording results

For each tested surface, summarize: (1) which cases enforced as expected, (2) any deviation from documented behavior, and (3) the surface version and date. That observed summary — by surface and transport, including limitations and bypass risks — is what lets issues [#17](https://github.com/rukasakurai/azure-api-center-demo/issues/17) and [#19](https://github.com/rukasakurai/azure-api-center-demo/issues/19) be closed.

## Step 7 — Clean up

```bash
# Revert the GitHub policy: set Restrict MCP access back to "Allow all" (and clear the MCP Registry URL if desired).

# Tear down the test environment (leaves production untouched):
azd env select <test-env-name>
azd down

# Remove the isolated VS Code stores:
rm -rf ~/.vscode-ghe-test ~/.vscode-ghe-test-ext
```
