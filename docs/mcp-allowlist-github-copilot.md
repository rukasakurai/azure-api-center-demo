# Using this demo to test the GitHub Copilot MCP allowlist

How to use the API Center registry provisioned by this demo as the **MCP registry** behind GitHub Copilot's *MCP server allowlist*, so that Copilot users in an organization or enterprise can be restricted to the MCP servers catalogued here.

> [!WARNING]
> **Partially verified (2026-06-20).** Discovery and the primary remote enforcement cases (registered → allow, unregistered → block) were tested against a live GitHub enterprise + API Center; see the [testing runbook](mcp-allowlist-testing-runbook.md). Local-server and spoofing cases are still unverified. These GitHub features are in public preview — validate against current docs before relying on them.

> [!IMPORTANT]
> **Preview status (as of 2026-06-19).** Several pieces below are in **public preview** and subject to change:
> - GitHub's **MCP Registry URL** and **allowlist** policy are explicitly **public preview and subject to change** ([GitHub docs](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)). They are available for **Copilot Business and Copilot Enterprise**.
> - Allowlist **enforcement** has expanded since the original [changelog, 2025-11-18](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/). Always check the live [Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces) for the current matrix.
> - Azure API Center's partner-MCP **Discover → MCP** experience is labelled **(preview)** in the Azure portal.
> - The underlying [MCP registry API](https://github.com/modelcontextprotocol/registry) is at **v0.1** (an API freeze ahead of a future v1 GA), i.e. pre-GA.

## How the GitHub feature works

GitHub Copilot exposes MCP policy under **AI Controls → MCP** (at the Enterprise level):

- **MCP servers in Copilot** — at the **enterprise** level this is a three-way policy: **Let organizations decide** (default — each org sets its own policy), **Enabled everywhere** (cannot be disabled at the org level), or **Disabled everywhere** (cannot be enabled at the org level). The actual on/off enable for seat holders is the **organization**-level *MCP servers in Copilot* setting (under Org → Settings → Copilot → Policies).
- **MCP Registry URL** — the URL of a [specification-compliant MCP registry](https://github.com/modelcontextprotocol/registry). Servers listed there become discoverable to members in supported editors.
- **Restrict MCP access to registry servers** — choose **Allow all** (registry servers are recommendations; any server may run) or **Registry only** (only servers in the registry may run; all others are blocked). The chosen policy applies to developers **immediately**.

Key properties of the enforcement ([GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)):

- **Runtime, client-side, at server-connect time.** With *Registry only*, the Copilot integration in each supported surface blocks, **at runtime**, any server not in the registry — evaluated when a server is loaded/connected, not on every tool call (so no per-call latency). A previously-configured, non-allowed server stops connecting once the policy is set.
- **Supported surfaces only.** Enforcement runs per supported Copilot surface and shifts during preview — as of 2026-06-19 the Copilot cloud agent is **not** covered; check the live [Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces) for the current matrix.
- **Name/ID matching, which is bypassable.** As of 2026-06-19, [GitHub's MCP allowlist enforcement docs](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement) document two limitations: enforcement is **based only on server name/ID matching, which can be bypassed by editing configuration files**, and **strict enforcement that prevents *installation* of non-registry servers is not yet available**. For the highest security GitHub suggests disabling MCP servers in Copilot until strict enforcement ships.
- **Local servers.** With *Registry only*, a local server must be listed in the registry with the **correct server ID, exactly matching the installed server ID** (a server's canonical ID is usually in its documentation or manifest).
- **Multiple seats → one resolved policy.** When a user holds seats in more than one org/enterprise, GitHub resolves to a single active policy: **enterprise scope overrides org**, then **`Registry only` beats `Allow all`**, then the **most recently uploaded registry** wins.

## Where API Center fits

GitHub documents **Azure API Center as a supported option** for hosting the MCP registry ("a fully managed MCP registry with automatic CORS configuration") ([Configure an MCP registry](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)). The servers you register in this demo (for example `usecase-coach-mcp`) are exactly the catalog you would point the **MCP Registry URL** at. Because Copilot fetches the registry from the browser/editor, the endpoint must return CORS headers on `/v0.1/servers`; **API Center sets these automatically**, so this demo needs no extra work — only a **self-hosted** registry would have to add `Access-Control-Allow-Origin/Methods/Headers` itself.

Two specifics that are easy to get wrong:

1. **Use the base workspace URL — do not append `/v0.1/servers`.** Per [GitHub's docs](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry), the **MCP Registry URL** for API Center must be the workspace base URL:

   ```text
   https://<service>.data.<region>.azure-apicenter.ms/workspaces/<workspace-name>
   ```

   Example shape: `https://contoso-apic.data.eastus.azure-apicenter.ms/workspaces/default`. **Including a suffix like `/v0.1/servers` will cause the registry to error out**, because Copilot appends the MCP v0.1 path automatically.

2. **The registry *listing* must be anonymously readable.** GitHub Copilot fetches the registry **without authentication**. By default this demo's API Center data plane is **Entra-protected**: an anonymous request to the data-plane registry returns `401 Unauthorized` (RFC 9728 `WWW-Authenticate: Bearer …`, scope `https://azure-apicenter.net/user_impersonation`). To let Copilot read it, GitHub's documentation instructs you to **enable anonymous access in your API Center's visibility settings** ([Configure an MCP registry → Option 2](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)). See [Why anonymous access — the Copilot client can't authenticate (the registry can)](#why-anonymous-access--the-copilot-client-cant-authenticate-the-registry-can) for exactly what this does and does not expose.

### Why anonymous access — the Copilot client can't authenticate (the registry can)

The registry **is** Entra-authenticated by default and stays that way for every consumer except one. Enabling anonymous access opens the **listing endpoint** for the GitHub Copilot allowlist client specifically, because that client can't present an Entra token. This section is explicit about why, what changes, and the limit that follows.

**Why the Copilot fetch needs an anonymous endpoint.** Copilot reads the registry **client-side from the editor**, with no way to attach an Entra bearer token. The mandatory CORS headers (`Access-Control-Allow-Origin: *` on `/v0.1/servers`) are the tell: CORS only applies to browser/editor cross-origin requests. Because the Copilot client has **no implemented way to present an Entra token** on that fetch, the endpoint *it* reads must accept **unauthenticated** reads. This is a limitation of the **Copilot client**, not the registry: every other consumer (the discovery portal, token-bearing HTTP/MCP clients) authenticates to the same registry with Entra. This is the same root cause as the plugin marketplace endpoint tracked in [#8](https://github.com/rukasakurai/azure-api-center-demo/issues/8).

**Exactly what loses Entra, and what keeps it** — two independent layers:

| Layer | After enabling anonymous access | Sensitivity |
| ----- | ------------------------------- | ----------- |
| Registry **listing endpoint** (`/v0.1/servers`: server names, URLs, descriptions) | **Entra OFF** — unauthenticated reads, readable by anyone with the URL | Catalog **metadata only** |
| The **MCP servers themselves** (tools + data) | **Entra still ON** — each server enforces its own runtime auth (e.g. App Service Entra auth with VS Code as an allowed client) | The actual sensitive surface |

The management-plane/portal Entra RBAC is also untouched. So what drops Entra is **only the registry listing endpoint** (catalog metadata); the servers and management plane stay Entra-protected.

> [!CAUTION]
> **The limit / acceptability decision.** The registry itself **is** Entra-authenticated — that is this demo's default posture (`allowAnonymousAccess: false`, `authMode: 'azureRbac'`), and Entra-authenticated clients consume it fine: the discovery portal, and any token-bearing HTTP/MCP client ([#8](https://github.com/rukasakurai/azure-api-center-demo/issues/8) confirms a correctly-scoped Entra token returns the catalog). The gap is **only on the GitHub Copilot allowlist client**, whose registry fetch has no implemented way to present an Entra token. So to use *that one feature* you must expose the listing endpoint **anonymously for that consumer** — you are not removing Entra from the registry as a whole, but you are dropping it on the endpoint Copilot reads.
>
> For many enterprises, exposing **any** unauthenticated endpoint — even one serving only catalog metadata — is unacceptable, and that is a valid position. This is **not** a permanent platform gap, but a **client implementation gap that is publicly tracked and not yet shipped**:
> - **MCP has already blessed authenticated registries.** The core-spec request [modelcontextprotocol/modelcontextprotocol#1963](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1963) was closed as completed, and [modelcontextprotocol/registry#756](https://github.com/modelcontextprotocol/registry/pull/756) added [`registry-authorization.md`](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/registry-authorization.md): a registry MAY act as an OAuth 2.1 Resource Server (scope `mcp-registry:read`), and **clients can reuse their existing MCP server-auth implementation without changes**.
> - **The remaining work is client-side**, tracked in [github/copilot-cli#3772](https://github.com/github/copilot-cli/issues/3772) (Copilot CLI) and [microsoft/vscode#282456](https://github.com/microsoft/vscode/issues/282456) (VS Code, Backlog as of 2026-06-19). Until one of these ships, an Entra-protected API Center registry returns `401` to the Copilot fetch and all servers fail closed.
>
> If your org won't allow an anonymous endpoint, the correct decision is to **not** enable anonymous access and instead track the client issues above — the Copilot allowlist feature does not fit yet, even though the Entra-authenticated registry works for every other consumer.
>
> If you *can* tolerate publishing the catalog metadata and want to test: point the **MCP Registry URL** at a **dedicated workspace** containing only servers whose names/URLs you are comfortable exposing unauthenticated, enable anonymous access there, test, then revert. This keeps the rest of the demo's tenant-scoped, Entra-protected posture intact.

## End-to-end verification: discovery → enforcement

The value of this setup is the full path: **(A) discovery** — point Copilot at the API Center registry and confirm catalogued servers appear — then **(B) enforcement** — turn on *Registry only* and confirm non-registry servers are blocked. Verify both halves; testing them separately is where ambiguity creeps in.

For exact, reproducible steps — provisioning a dedicated anonymous test environment, isolating the test identity, and the per-surface verification matrix to record observed results — see the **[testing runbook](mcp-allowlist-testing-runbook.md)**.

## Sources

Verified against the following on 2026-06-19:

- [GitHub: Configure an MCP registry for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [GitHub: Configure MCP server access for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)
- [GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [GitHub: MCP server usage in your company (supported surfaces)](https://docs.github.com/en/copilot/concepts/mcp-management)
- [GitHub Changelog: MCP registry and allowlist controls for VS Code Stable in public preview (2025-11-18)](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/)
- [Azure API Center: Inventory and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
- [MCP Registry specification (v0.1)](https://github.com/modelcontextprotocol/registry)
- [MCP registry authorization reference (`registry-authorization.md`)](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/registry-authorization.md) — registries MAY act as an OAuth 2.1 Resource Server (`mcp-registry:read`)

### Tracking issues for authenticated registry reads

The requirement to enable anonymous access is a client-side gap, tracked upstream:

- [modelcontextprotocol/modelcontextprotocol#1963](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1963) — "Add OAuth Authentication Support for MCP Registries" (closed completed; spec blessing in place)
- [modelcontextprotocol/registry#756](https://github.com/modelcontextprotocol/registry/pull/756) — merged PR that added the registry authorization spec
- [github/copilot-cli#3772](https://github.com/github/copilot-cli/issues/3772) — Copilot CLI: support authenticated reads of the MCP registry
- [microsoft/vscode#282456](https://github.com/microsoft/vscode/issues/282456) — VS Code: OAuth authentication support for MCP registry queries
