# API Center portal access model

Last reviewed against public documentation: 2026-09-03.

This repository supports an organizational discovery portal whose catalog data
requires Microsoft Entra sign-in. It does not claim that the portal is reachable
only from a private network.

## Source facts

| Area | Publicly documented behavior |
|---|---|
| Managed portal access | The Azure-managed portal supports Microsoft Entra authentication or anonymous access. With Entra configured, users sign in before accessing catalog data. The home page remains publicly reachable. |
| Portal token | The portal app accesses API Center data on behalf of the signed-in user. |
| Authorization | Each user, or a group containing the user, needs **Azure API Center Data Reader** scoped to the API Center resource. |
| Consent | The portal requests delegated API Center permission. Whether a user may consent depends on tenant consent policy; an administrator can grant consent for the tenant. |
| Visibility | API visibility filters apply to all portal users. They are not documented as per-user or per-group catalog partitions. |
| Self-hosted portal | Microsoft's starter is an MSAL browser application that calls the API Center data plane with a delegated user token. Users still need Data Reader. The customer owns maintenance and upgrades, and Azure support is limited. |
| Network isolation | API Center is not listed in the public Azure Private Link availability documentation. |

Sources:

- [Set up and customize the API Center portal](https://learn.microsoft.com/azure/api-center/set-up-api-center-portal)
- [Self-host the API Center portal](https://learn.microsoft.com/azure/api-center/self-host-api-center-portal)
- [Azure API Center Data Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/integration#azure-api-center-data-reader)
- [Configure user consent](https://learn.microsoft.com/entra/identity/enterprise-apps/configure-user-consent)
- [Grant tenant-wide admin consent](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent)
- [Azure Private Link availability](https://learn.microsoft.com/azure/private-link/availability)

## Interpretation

Public evidence does not show an authentication-only mode for the managed
portal. The documented protected path has three independent gates:

1. Microsoft Entra authenticates the user.
2. The portal obtains a delegated token for the API Center data plane.
3. Azure RBAC authorizes the user, directly or through a group.

Tenant-wide admin consent can remove per-user prompts, but it does not remove
the delegated permission. Anonymous mode removes these user gates and makes the
inventory readable without sign-in, so it is not an authentication-only
alternative.

The managed portal is identity-gated rather than network-private: a public
landing page is expected, but catalog requests must not succeed anonymously.

## Repository recommendation

Use the Azure-managed portal with:

- a single-tenant Microsoft Entra SPA registration;
- tenant-wide administrator consent for the API Center delegated scope;
- a dedicated Microsoft Entra security group;
- Azure API Center Data Reader assigned to that group at the API Center
  resource; and
- `allowAnonymousAccess: false`.

The repository accepts the group object ID through deployment configuration and
creates only the Azure RBAC assignment. A tenant administrator or group owner
retains responsibility for group creation, membership, dynamic membership
rules, guest invitations, enterprise-application assignment, and consent.
Those are directory operations with separate Microsoft Graph privileges and
cannot be inferred from Azure subscription ownership.

Do not give the normal GitHub deployment identity broad Microsoft Graph write
permissions merely to make directory bootstrap unattended. A federated
credential removes a stored secret; it does not reduce the permissions granted
to that workload identity.

## Delegated scope compatibility

Current Microsoft self-host documentation uses
`https://azure-apicenter.net/Data.Read.All`. Earlier API Center behavior recorded
in this repository used
`https://azure-apicenter.net/user_impersonation`. The managed-portal setup
article does not enumerate its current scope.

Automation therefore resolves the enabled delegated scope from the Azure API
Center service principal. It prefers `Data.Read.All`, recognizes
`user_impersonation` as a legacy compatibility value, and fails if the result is
missing or ambiguous. A successful app-registration update is not proof that
tenant consent exists.

## Readiness states

Infrastructure provisioning and user readiness are different results.

| State | Meaning |
|---|---|
| `ready` | Portal protection, app structure, tenant-wide consent, reader group, service-scoped Data Reader assignment, and anonymous denial were verified. If a test principal was supplied, effective group access was also verified. |
| `failed` | A required setting or assignment is missing or unsafe. |
| `unverified` | A directory or runtime check could not be performed with the current identity. This is not success. |

Run the read-only check after deployment:

```powershell
pwsh ./scripts/check-portal-readiness.ps1
```

The command reads the API Center resource ID, portal client ID, and reader group
ID from the selected `azd` environment. It does not grant consent or mutate
directory membership.

## Completion check with a non-owner

Static checks cannot prove Conditional Access, MFA, guest invitation redemption,
browser token acquisition, or live authorization. Before describing the portal
as operational, use a clean browser profile and a test user whose only intended
entitlement is membership in the reader group.

Verify that the user can:

1. sign in to the exact managed portal;
2. search the catalog;
3. open an asset's details; and
4. download or export a definition when the selected asset has one.

Use these negative controls:

- an authenticated tenant user without Data Reader cannot access catalog data;
- an unauthenticated request cannot return catalog data; and
- removing the test user from the reader group, followed by a fresh token/sign-in,
  removes access.

The API test console is a separate check because target API credentials and API
Center access policies are independent of catalog-read permission.

Record only the outcome and generic failure category in public artifacts. Do not
record identities, object IDs, tenant/subscription IDs, hostnames, live endpoints,
tokens, or screenshots containing them.

## B2B users

For an external user:

1. create and redeem a Microsoft Entra B2B invitation in the resource tenant;
2. add the resulting resource-tenant guest object to the reader group;
3. assign the group to the enterprise application as well if "assignment
   required" is enabled; and
4. test the actual guest sign-in, including tenant selection and applicable
   cross-tenant access or Conditional Access policies.

Use the resource-tenant object, not an email suffix, as the authorization
subject. A guest's home-tenant authentication and resource-tenant authorization
are separate stages.

## When to self-host

Use Microsoft's self-hosted starter when the requirement is UI/workflow
customization, custom hosting, release control, headers/domains, or integration
with other systems. Do not select it solely to avoid delegated consent or Azure
RBAC; the reference implementation retains both.

A backend-for-frontend that calls API Center with an application identity would
be a different architecture. Public API Center portal documentation does not
establish that model as a supported authentication-only replacement, so this
repository does not implement or recommend it without a separate spike.

## Assumptions

- The Azure-managed portal is the primary experience.
- A tenant administrator supplies a pre-existing security group.
- Tenant-wide admin consent is the prompt-free operational baseline.
- Anonymous access is reserved for explicitly isolated scenarios outside this
  private discovery-portal model.
- Enterprise-application "assignment required" is optional defense in depth,
  not a replacement for API Center RBAC.

## Unverified points

- The exact delegated scope requested by every current managed-portal
  region/version.
- The mechanism behind the documentation statement that only the first portal
  user is prompted for consent.
- Future support for API Center private endpoints, additional portal auth modes,
  or an app-only data-plane pattern suitable for a backend-for-frontend.
- Environment-specific consent policy, Conditional Access, B2B trust, group
  licensing, and propagation timing.

If one of these points would materially change an adoption decision, validate it
in an isolated spike before changing the supported model.
