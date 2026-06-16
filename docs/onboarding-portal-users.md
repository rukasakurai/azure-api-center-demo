# Onboarding Portal Users

A runbook for granting someone access to the **API Center discovery portal** when they report they cannot get in.

This is the operational companion to the README's [Sharing with people who don't use Azure](../README.md#sharing-with-people-who-dont-use-azure) section: the README explains *why* access works the way it does; this doc is the *what to do* when a request comes in.

> To run this flow with GitHub Copilot — including drafting a Japanese message for the user — use the [`onboard-portal-user`](../skills/onboard-portal-user/SKILL.md) Agent Skill, which wraps the steps below.

## The symptom

A user signs into the portal and sees:

> You don't have permission to access this developer portal. Please contact this developer portal's administrator for assistance.

This is expected for any identity that has **not** been granted the required role. The portal uses `azureRbac` auth, so signing in successfully is not enough — the identity also needs the **Azure API Center Data Reader** role on the API Center service.

## Prerequisites for the administrator

- The `az` CLI, logged in to the tenant and subscription that hosts the API Center (`az login`).
- Permission to create role assignments on the API Center resource (e.g., Owner or User Access Administrator at the resource/resource-group scope).

## Recommended: grant access via an Entra group

Per-user role assignments do not scale. Prefer assigning **Azure API Center Data Reader** **once** to an Entra group, then onboarding people by adding them to that group. This is the same group wired into the template as `CATALOG_READERS_PRINCIPAL_ID` (see README step 2).

```bash
# One-time: assign the role to the readers group (object ID), if not already done.
az role assignment create \
  --assignee-object-id "<entra-group-object-id>" \
  --assignee-principal-type Group \
  --role "Azure API Center Data Reader" \
  --scope "<api-center-resource-id>"

# Per user: add them to the group.
az ad group member add --group "<group-id-or-name>" --member-id "<user-object-id>"
```

To find the API Center resource ID from an `azd` environment:

```bash
azd env get-values | grep apiCenterResourceId
```

## Alternative: grant a single user directly

When a one-off assignment is appropriate (e.g., a single guest), assign the role directly to the user.

1. **Find the user's object ID.** Guests appear with an `#EXT#` UPN once they have accepted the invitation to the tenant.

   ```bash
   az ad user list \
     --filter "startswith(displayName,'<name>')" \
     --query "[].{name:displayName, upn:userPrincipalName, id:id, mail:mail}" -o table
   ```

2. **Assign the role on the API Center service.**

   ```bash
   az role assignment create \
     --assignee-object-id "<user-object-id>" \
     --assignee-principal-type User \
     --role "Azure API Center Data Reader" \
     --scope "<api-center-resource-id>"
   ```

## Guest users in a separate tenant

Portal sign-in is **tenant-scoped**. If the portal lives in a different Entra tenant than the user's home tenant, the user must first be invited as a **guest** into the portal's tenant and accept the invitation. Being a guest alone does **not** grant portal access — the **Azure API Center Data Reader** role still has to be assigned (to the guest identity or a group the guest belongs to) in the portal's tenant.

## Verify and follow up

- Confirm the assignment exists:

  ```bash
  az role assignment list \
    --assignee "<user-object-id>" \
    --scope "<api-center-resource-id>" \
    --query "[].roleDefinitionName" -o tsv
  ```

- Tell the user that **role propagation can take a few minutes**. If they still see the error afterward, have them **fully sign out and sign back in** so a fresh token is issued.
- Once in, they open `https://<service>.portal.<region>.azure-apicenter.ms`, find the registered MCP server, and copy its endpoint into any MCP-capable client.
