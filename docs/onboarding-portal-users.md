# Onboarding Portal Users

What to do when someone reports they cannot access the **API Center discovery portal**. This is the operational companion to the README's [Sharing with people who don't use Azure](../README.md#sharing-with-people-who-dont-use-azure) section, which explains *why* access works the way it does.

> For the step-by-step commands — and to have GitHub Copilot run them and draft a Japanese message for the user — use the [`onboard-portal-user`](../skills/onboard-portal-user/SKILL.md) Agent Skill. This doc is the human-readable summary.

## The symptom

A user signs in and sees:

> You don't have permission to access this developer portal. Please contact this developer portal's administrator for assistance.

The portal uses `azureRbac` auth, so signing in is not enough: the identity also needs the **Azure API Center Data Reader** role on the API Center service.

## What an admin needs to do

1. **Prerequisites.** Be signed in with `az login` to the tenant/subscription hosting the API Center, with permission to assign roles (Owner or User Access Administrator at the resource/resource-group scope).
2. **Grant the role — prefer a group.** Per-user assignments don't scale. Assign **Azure API Center Data Reader** once to an Entra group (the `CATALOG_READERS_PRINCIPAL_ID` group from README step 2) and onboard people by adding them to it; assign to a single user only for one-offs.
3. **External users first need a guest invite.** Portal sign-in is tenant-scoped: a user from a different tenant must be invited as a guest and **accept** before any role assignment lets them in.
4. **Verify and follow up.** Confirm the assignment, then tell the user role propagation can take a few minutes and to **sign out and back in** if the error persists.

The `onboard-portal-user` skill (linked above) carries the exact `az` commands for each of these.
