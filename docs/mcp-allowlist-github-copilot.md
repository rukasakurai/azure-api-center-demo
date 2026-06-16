# Using this demo to test the GitHub Copilot MCP allowlist

How to use the API Center registry provisioned by this demo as the **MCP registry** behind GitHub Copilot's *MCP server allowlist*, so that Copilot users in an organization or enterprise can be restricted to the MCP servers catalogued here.

> [!WARNING]
> **Untested draft.** The steps below were assembled from vendor documentation (see [Sources](#sources)) and have **not been executed end-to-end** against a live GitHub enterprise + API Center at the time of writing. Treat this as a directional guide, not a verified runbook. Validate each step against the current documentation before relying on it.

> [!IMPORTANT]
> **Preview status (as of 2026-06-16).** Several pieces below are in **public preview** and subject to change:
> - GitHub's **MCP Registry URL** and **allowlist** policy are explicitly **public preview and subject to change** ([GitHub docs](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)). They are available for **Copilot Business and Copilot Enterprise**.
> - Allowlist **enforcement** is, as of this date, fully available in **VS Code Stable**; **Visual Studio** supports registry *discovery* only, with enforcement "coming in a future release" ([changelog, 2025-11-18](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/)). Check the live [Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces) for the current matrix.
> - Azure API Center's partner-MCP **Discover → MCP** experience is labelled **(preview)** in the Azure portal.
> - The underlying [MCP registry API](https://github.com/modelcontextprotocol/registry) is at **v0.1** (an API freeze ahead of a future v1 GA), i.e. pre-GA.

## How the GitHub feature works

GitHub Copilot exposes MCP policy under **Settings → AI Controls → MCP** (at the enterprise or organization level):

- **MCP servers in Copilot** — turn MCP on/off for seat holders.
- **MCP Registry URL** — the URL of a [specification-compliant MCP registry](https://github.com/modelcontextprotocol/registry). Servers listed there become discoverable to members in supported editors.
- **Restrict MCP access to registry servers** — choose **Allow all** (registry servers are recommendations; any server may run) or **Registry only** (only servers in the registry may run; all others are blocked). The chosen policy applies to developers **immediately**.

Key properties of the enforcement ([GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)):

- **Runtime, client-side, at server-connect time.** With *Registry only*, the Copilot integration in each supported surface blocks, **at runtime**, any server not in the registry — evaluated when a server is loaded/connected, not on every tool call (so no per-call latency). A previously-configured, non-allowed server stops connecting once the policy is set.
- **Supported surfaces only.** Per the [Supported surfaces table](https://docs.github.com/en/copilot/concepts/mcp-management#supported-surfaces): VS Code, Visual Studio, JetBrains IDEs, Eclipse, Xcode, and Copilot CLI. **Not** the Copilot cloud agent, and nothing outside Copilot (a standalone MCP client is unaffected). Enforcement maturity varies by surface — see the preview note above.
- **Remote vs. local strictness.** Remote servers are validated against **both the server name and the remote install URL** (strict). Local servers are validated against **server name only**, so local config can be edited to bypass the check. For strict requirements, GitHub recommends configuring **remote** servers only. *Installation* of non-registry servers is not yet blocked.

## Where API Center fits

GitHub documents **Azure API Center as a supported option** for hosting the MCP registry ("a fully managed MCP registry with automatic CORS configuration"). The servers you register in this demo (for example `usecase-coach-mcp`) are exactly the catalog you would point the **MCP Registry URL** at.

Two specifics that are easy to get wrong:

1. **Use the base workspace URL — do not append `/v0.1/servers`.** Per GitHub's docs, the **MCP Registry URL** for API Center must be the workspace base URL:

   ```text
   https://<service>.data.<region>.azure-apicenter.ms/workspaces/<workspace-name>
   ```

   Example shape: `https://contoso-apic.data.eastus.azure-apicenter.ms/workspaces/default`. **Including a suffix like `/v0.1/servers` will cause the registry to error out**, because Copilot appends the MCP v0.1 path automatically.

2. **The registry must be anonymously readable.** GitHub Copilot fetches the registry **without authentication**. By default this demo's API Center data plane is **Entra-protected**: an anonymous request to the data-plane registry returns `401 Unauthorized` (RFC 9728 `WWW-Authenticate: Bearer …`, scope `https://azure-apicenter.net/user_impersonation`). To let Copilot read it, GitHub's documentation instructs you to **enable anonymous access in your API Center's visibility settings** ([Configure an MCP registry → Option 2](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)).

   > [!CAUTION]
   > Enabling anonymous access makes the **server listing world-readable** (the listing is catalog metadata; each MCP server still enforces its own runtime auth). This **conflicts with the tenant-scoped, public-safe defaults** the rest of this demo deliberately follows — the README notes that `allowAnonymousAccess: true` is intentionally *not* used. Treat anonymous access as a deliberate, opt-in step taken only to exercise the GitHub allowlist, and assume all registry metadata may be public.

## Testing checklist

> Unverified — see the warning at the top of this page.

1. Provision the demo (`azd up`) so at least one MCP server (e.g. `usecase-coach-mcp`) is registered. See the [README](../README.md).
2. Enable **anonymous access** in your API Center's visibility settings (see the caution above about the trade-off).
3. Confirm the base workspace URL is now anonymously readable:
   ```bash
   curl -sS -o /dev/null -w "%{http_code}\n" \
     "https://<service>.data.<region>.azure-apicenter.ms/workspaces/<workspace-name>/v0.1/servers"   # expect 200
   ```
   (Before enabling anonymous access this returns `401`.)
4. In GitHub **Settings → AI Controls → MCP**, ensure **MCP servers in Copilot** is *Enabled*, then set **MCP Registry URL** to the **base** workspace URL — `…/workspaces/<workspace-name>`, **without** the `/v0.1/servers` suffix — and **Save**.
5. Switch **Restrict MCP access to registry servers** to **Registry only**.
6. In a supported editor signed into a governed seat (VS Code Stable has full enforcement as of this date), confirm that registry servers are usable and a non-registry server fails to connect with a "blocked by policy" message.

## Sources

Verified against the following on 2026-06-16:

- [GitHub: Configure an MCP registry for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [GitHub: Configure MCP server access for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)
- [GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [GitHub: MCP server usage in your company (supported surfaces)](https://docs.github.com/en/copilot/concepts/mcp-management)
- [GitHub Changelog: MCP registry and allowlist controls for VS Code Stable in public preview (2025-11-18)](https://github.blog/changelog/2025-11-18-internal-mcp-registry-and-allowlist-controls-for-vs-code-stable-in-public-preview/)
- [Azure API Center: Inventory and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
- [MCP Registry specification (v0.1)](https://github.com/modelcontextprotocol/registry)
