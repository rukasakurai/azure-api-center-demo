---
name: onboard-portal-user
description: Onboard a person to the Azure API Center Entra-protected discovery portal. Grants the required Azure RBAC role (optionally via an Entra guest invite) and drafts a Japanese message telling the user how to sign in and use the portal. Use when someone needs access to the API Center portal or reports the "You don't have permission to access this developer portal" error.
argument-hint: The user's email/UPN (and optionally their display name) to onboard
---

# Onboard Portal User

Grant a person access to the Azure API Center discovery portal and tell them how to use it. The portal uses `azureRbac` auth, so a viewer must (a) exist in the portal's Entra tenant and (b) hold the **Azure API Center Data Reader** role on the API Center service. This skill walks an administrator through satisfying both, then drafts a Japanese message for the user.

## When to Use

- Someone asks for access to the API Center discovery portal.
- A user reports the error *"You don't have permission to access this developer portal. Please contact this developer portal's administrator for assistance."*
- A user hits an external-user sign-in error because their identity is not yet in the tenant.

## Non-Negotiables (must follow)

1. **Confirm before every external mutation.** Sending a guest invitation and creating a role assignment both change directory/Azure state. Show the exact command and the resolved target identity, then ask the operator to confirm before running it.
2. **Never expose non-public details in committed artifacts.** This repository is public. Real names, email addresses, object IDs, tenant/subscription IDs, resource IDs, and hostnames may appear in your live session output, but must never be written into files, commits, issues, or PRs. Use placeholders there.
3. **Privileged operation.** The operator must be signed in (`az login`) to the tenant/subscription that hosts the API Center, with permission to assign roles (and to invite guests, if needed).
4. **Prefer groups at scale.** A one-off direct user assignment is fine, but if a readers group exists, prefer adding the user to it over a per-user role assignment.
5. **Grant only the read-only role.** The only role this skill assigns is **Azure API Center Data Reader**. Never substitute a broader role or run other grant commands.

## Inputs

- The user's **email / UPN** (required) and **display name** (helpful for lookup and the message).
- Optionally, the **API Center resource ID** and **portal URL**. If omitted, read them from the azd environment:

  ```bash
  azd env get-values | grep -E 'apiCenterResourceId|portalHostname'
  ```

## Procedure

### 1. Find the user's identity

Requests usually arrive as a **display name** (e.g. from Teams), and some accounts have no `mail` set, so search by display name first (or by email/UPN if that's what you were given: `--filter "mail eq '<email>' or userPrincipalName eq '<email>'"`):

```bash
az ad user list \
  --filter "startswith(displayName,'<name>')" \
  --query "[].{name:displayName, upn:userPrincipalName, id:id, mail:mail}" -o table
```

- **Exactly one match** → note the `id` and continue to step 3.
- **Multiple matches** → disambiguate with the operator (e.g. by UPN) and use the correct `id`.
- **No match** → the user is external to the tenant; go to step 2 first.

### 2. Invite as a guest (only if not found)

External users must be invited and must **accept** the invitation before they can sign in. Confirm with the operator, then:

```bash
az rest --method POST \
  --url "https://graph.microsoft.com/v1.0/invitations" \
  --body '{"invitedUserEmailAddress":"<email>","inviteRedirectUrl":"<portal-url>","sendInvitationMessage":true}'
```

Tell the operator that **the user must accept the invitation** (and that acceptance is manual and asynchronous) before the role assignment will let them in. Re-run step 1 to confirm the guest object now exists.

### 3. Assign the Data Reader role

Grant the **Azure API Center Data Reader** role on the API Center service, using the object `id` you confirmed in step 1.

```bash
SCOPE="$(azd env get-values | sed -n 's/^apiCenterResourceId="\(.*\)"$/\1/p')"

# Per-user (USER_ID is the object id from step 1):
az role assignment create --assignee-object-id "<user-object-id>" --assignee-principal-type User \
  --role "Azure API Center Data Reader" --scope "$SCOPE"

# Group-based (preferred at scale; pass the group object id):
az role assignment create --assignee-object-id "<group-object-id>" --assignee-principal-type Group \
  --role "Azure API Center Data Reader" --scope "$SCOPE"
```

If the assignment already exists, `create` returns an "already exists" error — treat that as success.

For the group path, also add the user to the group:

```bash
az ad group member add --group "<group-id-or-name>" --member-id "<user-object-id>"
```

### 4. Verify

The `create` response reports `roleDefinitionName` as `null`, so it looks inconclusive — this list command is the real confirmation. It should print `Azure API Center Data Reader`:

```bash
az role assignment list \
  --assignee "<user-object-id>" \
  --scope "<api-center-resource-id>" \
  --query "[].roleDefinitionName" -o tsv
```

### 5. Draft the Japanese message

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
