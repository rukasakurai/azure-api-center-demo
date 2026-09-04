---
name: onboard-portal-user
description: Onboard a person to the Azure API Center Entra-protected discovery portal through the configured reader security group (optionally after an Entra B2B guest invite), verify effective access, and draft a Japanese usage message. Use when someone needs portal access or reports the "You don't have permission to access this developer portal" error.
argument-hint: The user's email/UPN (and optionally their display name) to onboard
---

# Onboard Portal User

Grant a person access to the Azure API Center discovery portal and tell them how to use it. The supported model requires a ready portal app/consent configuration and **Azure API Center Data Reader** through the configured reader security group. This skill verifies the baseline, adds the resource-tenant user object to that group, checks effective access, and drafts a Japanese message.

## When to Use

- Someone asks for access to the API Center discovery portal.
- A user reports the error *"You don't have permission to access this developer portal. Please contact this developer portal's administrator for assistance."*
- A user hits an external-user sign-in error because their identity is not yet in the tenant.

## Non-Negotiables (must follow)

1. **Confirm before every external mutation.** Sending a guest invitation and adding a group member both change directory state. Show the exact command and the resolved target identity, then ask the operator to confirm before running it.
2. **Never expose non-public details in committed artifacts.** This repository is public. Real names, email addresses, object IDs, tenant/subscription IDs, resource IDs, and hostnames may appear in your live session output, but must never be written into files, commits, issues, or PRs. Use placeholders there.
3. **Privileged operation.** The operator must be signed in to the portal's resource tenant with permission to inspect the portal baseline and manage membership of the configured reader group (and invite guests, if needed).
4. **Group-only onboarding.** Do not create a direct per-user API Center role assignment. If the configured group or its Data Reader assignment is missing, stop and route the baseline failure to the appropriate directory or Azure RBAC administrator.
5. **No consent mutation.** Do not grant delegated consent or change enterprise-application assignment in this skill. Report those as administrator prerequisites.

## Inputs

- The user's **email / UPN** (required) and **display name** (helpful for lookup and the message).
- Optionally, the **API Center resource ID**, **portal URL**, and **reader group ID**. If omitted, read them from the azd environment:

  ```bash
  azd env get-values | grep -E 'apiCenterResourceId|portalHostname|CATALOG_READERS_PRINCIPAL_ID'
  ```

## Procedure

### 1. Verify the protected portal baseline

```powershell
pwsh ./scripts/check-portal-readiness.ps1
```

Continue only when the result is `ready`. `failed` identifies a known missing or
unsafe setting. `unverified` means the current identity could not inspect a
directory prerequisite; it is not permission to continue.

### 2. Find the user's identity

Requests usually arrive as a **display name** (e.g. from Teams), and some accounts have no `mail` set, so search by display name first (or by email/UPN if that's what you were given: `--filter "mail eq '<email>' or userPrincipalName eq '<email>'"`):

```bash
az ad user list \
  --filter "startswith(displayName,'<name>')" \
  --query "[].{name:displayName, upn:userPrincipalName, id:id, mail:mail}" -o table
```

- **Exactly one match** → note the resource-tenant object `id` and continue to step 4.
- **Multiple matches** → disambiguate with the operator (e.g. by UPN) and use the correct `id`.
- **No match** → the user is external to the tenant; go to step 3 first.

### 3. Invite as a guest (only if not found)

External users must be invited and must **accept** the invitation before they can sign in. Confirm with the operator, then:

```bash
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/invitations" \
  --body '{"invitedUserEmailAddress":"<email>","inviteRedirectUrl":"<portal-url>","sendInvitationMessage":true}'
```

Tell the operator that **the user must accept the invitation** before group membership can produce a usable sign-in. Re-run step 2 and use the resulting resource-tenant guest object ID.

### 4. Add the user to the configured reader group

Resolve the configured group and confirm it is the expected security group before
mutating membership:

```bash
az ad group show --group "<configured-reader-group-object-id>" \
  --query "{name:displayName,id:id,securityEnabled:securityEnabled}" -o table
```

Show the resolved user and group to the operator and confirm, then:

```bash
az ad group member add \
  --group "<configured-reader-group-object-id>" \
  --member-id "<resource-tenant-user-object-id>"
```

If the portal enterprise application has "assignment required" enabled, a tenant
application administrator must also ensure this same group is assigned there.
Nested group membership does not satisfy enterprise-application assignment.

### 5. Verify effective access

Confirm direct group membership:

```bash
az ad group member check \
  --group "<configured-reader-group-object-id>" \
  --member-id "<resource-tenant-user-object-id>"
```

Then confirm group-derived Data Reader:

```bash
az role assignment list \
  --assignee "<resource-tenant-user-object-id>" \
  --scope "<api-center-resource-id>" \
  --include-groups \
  --include-inherited \
  --all \
  --query "[?roleDefinitionName=='Azure API Center Data Reader'].roleDefinitionName" \
  -o tsv
```

Finally, ask the user to sign in through a clean browser profile and confirm that
catalog search and asset details load. A role listing alone does not exercise
consent, Conditional Access, MFA, guest redemption, or browser token acquisition.

### 6. Draft the Japanese message

Produce a short, friendly Japanese message for the user. Write from the **recipient's** perspective — avoid internal/admin concepts such as "tenant" or RBAC. Choose the variant that matches the user's situation rather than asking them to figure out which case applies: include the invitation-acceptance step **only** if you invited them as a guest. Remind them that access may take a few minutes to take effect and a fresh sign-in may be needed. Use the portal URL from the azd environment.

Template (fill the placeholders):

```
<name> さん

API Center ポータルへのアクセス権を付与しました。
以下の手順でご利用いただけます。

1. こちらのポータルを開いてください: <portal-url>
2. お使いのアカウントでサインインしてください。
3. 「MCP servers」から目的のサーバーを見つけ、エンドポイント URL をコピーします。
4. そのエンドポイントを MCP 対応クライアントに登録してご利用ください。

※ アクセスが有効になるまで数分かかることがあります。エラーが続く場合は、一度
   サインアウトして再度サインインしてみてください。

ご不明点があればお気軽にお知らせください。
```

If you invited the user as a guest, add a first step before signing in, in plain terms (no "tenant" jargon):

```
0. まず、お送りした招待メールを開き、リンクから承諾をお願いします。
```

## Notes

- This is an administrator tool. It is intentionally not registered in the public discovery catalog.
- Background and the equivalent manual runbook live in [docs/onboarding-portal-users.md](../../docs/onboarding-portal-users.md).
- The evidence and readiness-state definitions live in [docs/portal-access-model.md](../../docs/portal-access-model.md).
