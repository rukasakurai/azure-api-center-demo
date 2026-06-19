# Using this demo to test the GitHub Copilot MCP allowlist

How to use the API Center registry provisioned by this demo as the **MCP registry** behind GitHub Copilot's *MCP server allowlist*, so that Copilot users in an organization or enterprise can be restricted to the MCP servers catalogued here.

> [!WARNING]
> **Untested draft.** The steps below were assembled from vendor documentation (see [Sources](#sources)) and have **not been executed end-to-end** against a live GitHub enterprise + API Center at the time of writing. Treat this as a directional guide, not a verified runbook. Validate each step against the current documentation before relying on it.

> [!IMPORTANT]
> **Preview status (as of 2026-06-19).** Several pieces below are in **public preview** and subject to change:
> - GitHub's **MCP Registry URL** and **allowlist** policy are explicitly **public preview and subject to change** ([GitHub docs](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)). They are available for **Copilot Business and Copilot Enterprise**.
> - Allowlist **enforcement** has expanded since the original [changelog, 2025-11-18](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/). Always check the live [Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces) for the current matrix — see [Supported surfaces](#supported-surfaces) below for the values current as of this date.
> - Azure API Center's partner-MCP **Discover → MCP** experience is labelled **(preview)** in the Azure portal.
> - The underlying [MCP registry API](https://github.com/modelcontextprotocol/registry) is at **v0.1** (an API freeze ahead of a future v1 GA), i.e. pre-GA.

## How the GitHub feature works

GitHub Copilot exposes MCP policy under **Settings → AI Controls → MCP** (at the enterprise or organization level):

- **MCP servers in Copilot** — turn MCP on/off for seat holders.
- **MCP Registry URL** — the URL of a [specification-compliant MCP registry](https://github.com/modelcontextprotocol/registry). Servers listed there become discoverable to members in supported editors.
- **Restrict MCP access to registry servers** — choose **Allow all** (registry servers are recommendations; any server may run) or **Registry only** (only servers in the registry may run; all others are blocked). The chosen policy applies to developers **immediately**.

Key properties of the enforcement ([GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)):

- **Runtime, client-side, at server-connect time.** With *Registry only*, the Copilot integration in each supported surface blocks, **at runtime**, any server not in the registry — evaluated when a server is loaded/connected, not on every tool call (so no per-call latency). A previously-configured, non-allowed server stops connecting once the policy is set.
- **Supported surfaces only.** See [Supported surfaces](#supported-surfaces) below. Enforcement applies to supported IDEs and Copilot CLI — **not** the Copilot cloud agent, and nothing outside Copilot (a standalone MCP client is unaffected).
- **Name/ID matching, which is bypassable.** As of this date GitHub documents two enforcement limitations: enforcement is **based only on server name/ID matching, which can be bypassed by editing configuration files**, and **strict enforcement that prevents *installation* of non-registry servers is not yet available**. For the highest security GitHub suggests disabling MCP servers in Copilot until strict enforcement ships.
- **Local servers.** With *Registry only*, a local server must be listed in the registry with the **correct server ID, exactly matching the installed server ID** (a server's canonical ID is usually in its documentation or manifest).
- **Multiple seats → one resolved policy.** When a user holds seats in more than one org/enterprise, GitHub resolves to a single active policy: **enterprise scope overrides org**, then **`Registry only` beats `Allow all`**, then the **most recently uploaded registry** wins.

## Supported surfaces

The matrix below reflects the [GitHub Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces) **as of 2026-06-19**. It changes as the preview expands — re-check the live table before relying on it.

| Surface             | Registry display | Allowlist enforcement |
| ------------------- | :--------------: | :-------------------: |
| Copilot CLI         |        ✅        |          ✅           |
| VS Code             |        ✅        |          ✅           |
| Visual Studio       |        ✅        |          ✅           |
| JetBrains IDEs      |        ✅        |          ✅           |
| Eclipse             |        ✅        |          ✅           |
| Xcode               |        ✅        |          ✅           |
| Copilot cloud agent |        ❌        |          ❌           |

> [!NOTE]
> Visual Studio now reports **full enforcement**; an earlier version of this doc (and the 2025-11-18 changelog) listed it as discovery-only. This is exactly the kind of value that shifts during preview, which is why the verification matrix below records the surface and date actually observed. GitHub also lists **VS Code Insiders** separately, and support on some surfaces (Eclipse, JetBrains, Xcode) may require pre-release IDE/plugin builds — confirm against the live table for the exact surface and build you test.

## Where API Center fits

GitHub documents **Azure API Center as a supported option** for hosting the MCP registry ("a fully managed MCP registry with automatic CORS configuration"). The servers you register in this demo (for example `usecase-coach-mcp`) are exactly the catalog you would point the **MCP Registry URL** at. Because Copilot fetches the registry from the browser/editor, the endpoint must return CORS headers on `/v0.1/servers`; **API Center sets these automatically**, so this demo needs no extra work — only a **self-hosted** registry would have to add `Access-Control-Allow-Origin/Methods/Headers` itself.

Two specifics that are easy to get wrong:

1. **Use the base workspace URL — do not append `/v0.1/servers`.** Per GitHub's docs, the **MCP Registry URL** for API Center must be the workspace base URL:

   ```text
   https://<service>.data.<region>.azure-apicenter.ms/workspaces/<workspace-name>
   ```

   Example shape: `https://contoso-apic.data.eastus.azure-apicenter.ms/workspaces/default`. **Including a suffix like `/v0.1/servers` will cause the registry to error out**, because Copilot appends the MCP v0.1 path automatically.

2. **The registry must be anonymously readable.** GitHub Copilot fetches the registry **without authentication**. By default this demo's API Center data plane is **Entra-protected**: an anonymous request to the data-plane registry returns `401 Unauthorized` (RFC 9728 `WWW-Authenticate: Bearer …`, scope `https://azure-apicenter.net/user_impersonation`). To let Copilot read it, GitHub's documentation instructs you to **enable anonymous access in your API Center's visibility settings** ([Configure an MCP registry → Option 2](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)).

   > [!CAUTION]
   > Enabling anonymous access makes the **server listing world-readable** (the listing is catalog metadata; each MCP server still enforces its own runtime auth). This **conflicts with the tenant-scoped, public-safe defaults** the rest of this demo deliberately follows — the README notes that `allowAnonymousAccess: true` is intentionally *not* used. Treat anonymous access as a deliberate, opt-in step taken only to exercise the GitHub allowlist, and assume all registry metadata may be public.

## End-to-end verification: discovery → enforcement

> [!WARNING]
> The **expected** results below come from vendor documentation; the **observed** columns are intentionally blank because they require a live GitHub Business/Enterprise tenant plus the deployed API Center, which are not available in every environment. Fill them in on a connected machine and date each row.

The value of this setup is the full path: **(A) discovery** — point Copilot at the API Center registry and confirm catalogued servers appear — then **(B) enforcement** — turn on *Registry only* and confirm non-registry servers are blocked. Verify both halves; testing them separately is where ambiguity creeps in.

### Step A — Discovery

1. Provision the demo (`azd up`) so at least one MCP server (e.g. `usecase-coach-mcp`) is registered. See the [README](../README.md).
2. Enable **anonymous access** in your API Center's visibility settings (see the caution above about the trade-off).
3. Confirm the base workspace URL is now anonymously readable:
   ```bash
   curl -sS -o /dev/null -w "%{http_code}\n" \
     "https://<service>.data.<region>.azure-apicenter.ms/workspaces/<workspace-name>/v0.1/servers"   # expect 200
   ```
   (Before enabling anonymous access this returns `401`.)
4. In GitHub **Settings → AI Controls → MCP**, ensure **MCP servers in Copilot** is *Enabled*, then set **MCP Registry URL** to the **base** workspace URL — `…/workspaces/<workspace-name>`, **without** the `/v0.1/servers` suffix — and **Save**.
5. In a supported editor signed into a governed seat, confirm the registry's servers are **discoverable** (the catalogued server appears as available).

### Step B — Enforcement

6. Switch **Restrict MCP access to registry servers** to **Registry only**.

   > [!CAUTION]
   > This policy **applies to developers immediately** and blocks any non-registry MCP server they have already configured. Test in a non-production organization (or a dedicated test enterprise) before applying it where people are actively working.
7. Re-test the cases in the matrix below — **at minimum on VS Code Stable and Copilot CLI** (the two surfaces issues #17/#19 require), plus any other surface you care about.

### Verification matrix (fill in per surface)

For each surface, record what you observed, the **surface version**, and the date. **Transport** distinguishes a *remote* MCP server (validated by name/ID against the remote entry) from a *local* server (must be listed with an exactly matching server ID). Expected behavior is from GitHub's docs — confirm it, since preview behavior shifts.

| # | Case | Transport | Expected | Observed (VS Code Stable) | Observed (Copilot CLI) | Version / Date |
| - | ---- | --------- | -------- | ------------------------- | ---------------------- | -------------- |
| 1 | Server present in registry | Remote | **Allow** — connects normally | | | |
| 2 | Server **not** in registry | Remote | **Block** — fails to connect with a "blocked by policy" message | | | |
| 3 | Remote server with the **same name/ID as a registry entry but a different install URL** | Remote | **Confirm** — docs say enforcement is name/ID matching; test whether a mismatched URL is still allowed (potential spoof/bypass) | | | |
| 4 | Local server **with** matching server ID in registry | Local | **Allow** | | | |
| 5 | Local server **not** in registry | Local | **Block** | | | |
| 6 | Local server with **same name but mismatched ID** | Local | **Block** | | | |
| 7 | Local server whose name/ID is **edited to match** a registry entry (config spoof) | Local | **Bypass risk** — may connect; documents the name/ID-matching limitation | | | |
| 8 | Local server whose **command/path is changed** while name/ID still matches the registry | Local | **Confirm** — only name/ID is checked, so a swapped command may still connect (bypass risk) | | | |
| 9 | *Installation* of a non-registry server | Either | **Not blocked yet** — only connection is enforced | | | |

### Recording results

When the observed columns are filled in, summarize for each tested surface: (1) which cases enforced as expected, (2) any deviation from the documented behavior, and (3) the surface version and date. That summary is the deliverable that lets the related issues be closed — it states *observed* allow/block behavior by surface and transport, including known limitations and bypass risks, rather than restating the docs.

## Sources

Verified against the following on 2026-06-19:

- [GitHub: Configure an MCP registry for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [GitHub: Configure MCP server access for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)
- [GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [GitHub: MCP server usage in your company (supported surfaces)](https://docs.github.com/en/copilot/concepts/mcp-management)
- [GitHub Changelog: MCP registry and allowlist controls for VS Code Stable in public preview (2025-11-18)](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/)
- [Azure API Center: Inventory and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
- [MCP Registry specification (v0.1)](https://github.com/modelcontextprotocol/registry)
