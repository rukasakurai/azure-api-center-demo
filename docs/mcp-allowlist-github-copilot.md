# Using this demo to test the GitHub Copilot MCP allowlist

How to use the API Center registry provisioned by this demo as the **MCP registry** behind GitHub Copilot Enterprise's *MCP server allowlist*, so that Copilot users in an enterprise can be restricted to the MCP servers catalogued here.

> This is the **governance** companion to the README's registry/discovery story. The README explains how people *discover* registered MCP servers; this doc explains how an enterprise can *restrict* which MCP servers its Copilot users may use, sourced from the same registry.

## How the GitHub feature works

GitHub Copilot Enterprise (and Organization) exposes MCP policy under **Settings → AI Controls → MCP**:

- **MCP servers in Copilot** — turn MCP on/off for seat holders.
- **MCP Registry URL** — the URL of a [specification-compliant MCP registry](https://github.com/modelcontextprotocol/registry). Servers listed there become discoverable to members in supported editors.
- **Restrict MCP access to registry servers** — switch from *Allow all* to *Registry only* to limit members to the servers in that registry.

Key properties of the enforcement (see [GitHub's MCP allowlist enforcement reference](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)):

- **Client-side, at connect time.** The Copilot integration in each supported surface evaluates the policy when an MCP server is loaded/connected — not on every tool call, so there is no per-call latency. A previously-configured, non-allowed server stops connecting after *Registry only* is set.
- **Supported surfaces only.** VS Code, Visual Studio, JetBrains IDEs, Eclipse, Xcode, and Copilot CLI. **Not** the Copilot cloud agent, and nothing outside Copilot (a standalone MCP client is unaffected).
- **Name/ID matching, bypassable.** Matching is by server name/ID and can be bypassed by editing local config; *installation* of non-registry servers is not yet blocked. Treat it as governance steering, not an airtight security boundary.

## Where API Center fits

API Center implements the [v0.1 MCP registry API](https://github.com/modelcontextprotocol/registry). The data-plane registry endpoint of the service this demo provisions is:

```
https://<service>.data.<region>.azure-apicenter.ms/workspaces/default/v0.1/servers
```

It supports the v0.1 read routes (`GET /v0.1/servers`, `.../servers/{serverName}/versions/latest`, `.../servers/{serverName}/versions/{version}`) and returns `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Methods: GET` — the CORS shape GitHub's allowlist requires.

So conceptually, the MCP servers you register in this demo (for example `usecase-coach-mcp`) are exactly the catalog you would point the **MCP Registry URL** at to govern Copilot usage.

## The integration gap to be aware of

The native data-plane endpoint is an **OAuth 2.0 protected resource**. An anonymous request returns:

```
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer resource_metadata="https://<service>.data.<region>.azure-apicenter.ms/.well-known/oauth-protected-resource"
```

The advertised metadata requires a Microsoft Entra Bearer token (authorization server = the tenant's `login.microsoftonline.com/<tenant>/v2.0`, scope = `https://azure-apicenter.net/user_impersonation`). This keeps discovery tenant-scoped, which is the point of the rest of this demo.

GitHub Copilot's allowlist, however, **fetches the MCP Registry URL anonymously**. It therefore cannot read the Entra-protected endpoint directly — pointing the registry URL at the raw `…/v0.1/servers` host yields a 401 on GitHub's side.

The server *listing* is non-sensitive catalog metadata (each MCP server still enforces its own runtime auth), so the way to test the GitHub feature end-to-end is to expose an **anonymously-readable** `v0.1/servers` listing in front of API Center — for example via an API gateway (Azure API Management) that proxies the v0.1 read routes and serves them without the Entra challenge while preserving the `*`/`GET` CORS headers. That gateway URL is what you put in **MCP Registry URL**.

> This front door is intentionally **not** wired into this template: it would expose the catalog listing publicly, which conflicts with the tenant-scoped, public-safe defaults the rest of the demo follows. Add it deliberately, and only the read listing, when you want to exercise the GitHub allowlist.

## Testing checklist

1. Provision the demo (`azd up`) so at least one MCP server (e.g. `usecase-coach-mcp`) is registered. See the [README](../README.md).
2. Confirm the data-plane endpoint shape and that anonymous access is challenged:
   ```bash
   curl -sS -o /dev/null -w "%{http_code}\n" \
     "https://<service>.data.<region>.azure-apicenter.ms/workspaces/default/v0.1/servers"   # expect 401
   ```
3. Stand up an anonymously-readable proxy for the v0.1 read routes (e.g. API Management) that preserves `Access-Control-Allow-Origin: *` and `Access-Control-Allow-Methods: GET`.
4. In GitHub **Settings → AI Controls → MCP**, set **MCP Registry URL** to the proxy's `…/v0.1/servers` URL and **Save**.
5. Switch **Restrict MCP access to registry servers** to *Registry only*.
6. In a supported editor signed into a seat governed by that org/enterprise, confirm that registry servers are usable and a non-registry server fails to connect with a "blocked by policy" indication.

## Related

- [README — registering and discovering the MCP server](../README.md#registering-the-mcp-server-endpoint)
- [GitHub: Configure an MCP registry](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [GitHub: MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [Azure API Center: Inventory and discover MCP servers](https://learn.microsoft.com/azure/api-center/register-discover-mcp-server)
- [MCP Registry specification](https://github.com/modelcontextprotocol/registry)
