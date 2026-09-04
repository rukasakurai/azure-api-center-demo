# Onboarding Portal Users

What to do when someone reports they cannot access the **API Center discovery portal**. This is the operational companion to the README's [Sharing with people who don't use Azure](../README.md#sharing-with-people-who-dont-use-azure) section, which explains *why* access works the way it does.

> For the step-by-step commands — and to have GitHub Copilot run them and draft a Japanese message for the user — use the [`onboard-portal-user`](../skills/onboard-portal-user/SKILL.md) Agent Skill. This doc is the human-readable summary.

## The symptom

A user signs in and sees:

> You don't have permission to access this developer portal. Please contact this developer portal's administrator for assistance.

The portal uses delegated API Center permission and `azureRbac`, so signing in is not enough. Tenant-wide consent must cover the portal app, and the identity must receive **Azure API Center Data Reader** through the configured reader security group.

## Confirm the portal is ready first

Run the read-only check with an identity allowed to inspect the relevant app,
consent, group, and Azure RBAC state:

```powershell
pwsh ./scripts/check-portal-readiness.ps1
```

Stop if the result is `failed` or `unverified`. Fixing app permission or consent
belongs to a tenant application administrator. Fixing the group RBAC assignment
belongs to an Azure RBAC administrator. Do not work around either failure with a
direct per-user role assignment.

## Onboard the user

1. **Resolve the user object.** Use the object in the portal's resource tenant.
2. **External users must redeem an invitation.** Invite the user through normal
   Microsoft Entra B2B processes and wait for redemption before continuing.
3. **Add the user to the configured reader group.** A group owner or directory
   administrator performs this directory mutation. Do not create a different
   group or add a direct API Center role for one user.
4. **If enterprise-app assignment is required,** confirm that the reader group is
   assigned to the portal enterprise application. This is separate from API
   Center RBAC; nested group membership does not satisfy enterprise-app
   assignment.
5. **Verify effective RBAC** after propagation:

   ```bash
   az role assignment list \
     --assignee "<resource-tenant-user-object-id>" \
     --scope "<api-center-resource-id>" \
     --include-groups \
     --include-inherited \
     --all \
     --query "[?roleDefinitionName=='Azure API Center Data Reader'].roleDefinitionName" \
     --output tsv
   ```

6. **Verify the actual experience.** Have the user start a clean browser session,
   sign in to the exact portal, search the catalog, and open an asset. A role
   listing alone does not prove that consent, Conditional Access, MFA, guest
   redemption, token acquisition, and live data-plane authorization all work.

Tell the user that propagation can take a few minutes and that a fresh sign-in
may be needed. The [`onboard-portal-user`](../skills/onboard-portal-user/SKILL.md)
skill carries the generic commands and public-safety rules.

See [API Center portal access model](portal-access-model.md) for the evidence and
the positive/negative acceptance controls.
