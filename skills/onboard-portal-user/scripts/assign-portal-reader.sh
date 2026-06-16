#!/usr/bin/env bash
# Assign the "Azure API Center Data Reader" role to a user or group on the
# API Center service, so the principal can browse the Entra-protected
# discovery portal.
#
# This is the deterministic, reviewable part of the portal onboarding flow:
# it performs the privileged RBAC mutation. Identity discovery, guest-invite
# decisions, and the user-facing message are handled by the orchestrating
# skill (SKILL.md), not here.
#
# Usage:
#   assign-portal-reader.sh --assignee <email|object-id> \
#       [--type User|Group] [--scope <api-center-resource-id>]
#
# Notes:
#   * --type defaults to User. Groups must be passed as an object id.
#   * If --scope is omitted, the script reads apiCenterResourceId from the
#     current azd environment (azd env get-values).
#   * The operation is idempotent: an existing assignment is left untouched.
set -euo pipefail

ROLE="Azure API Center Data Reader"
TYPE="User"
ASSIGNEE=""
SCOPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assignee) ASSIGNEE="${2:-}"; shift 2 ;;
    --type)     TYPE="${2:-}"; shift 2 ;;
    --scope)    SCOPE="${2:-}"; shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ASSIGNEE" ]]; then
  echo "Error: --assignee is required (user email/UPN/object-id or group object-id)." >&2
  exit 2
fi

if [[ "$TYPE" != "User" && "$TYPE" != "Group" ]]; then
  echo "Error: --type must be 'User' or 'Group' (got '$TYPE')." >&2
  exit 2
fi

# Resolve scope from the azd environment when not provided explicitly.
if [[ -z "$SCOPE" ]]; then
  if command -v azd >/dev/null 2>&1; then
    SCOPE="$(azd env get-values 2>/dev/null | sed -n 's/^apiCenterResourceId="\(.*\)"$/\1/p')"
  fi
fi
if [[ -z "$SCOPE" ]]; then
  echo "Error: could not determine --scope and no apiCenterResourceId found in the azd environment." >&2
  exit 2
fi

# Resolve a User email/UPN to an object id. Groups must already be an object id.
OBJECT_ID="$ASSIGNEE"
if [[ "$TYPE" == "User" && "$ASSIGNEE" == *"@"* ]]; then
  MATCHES="$(az ad user list \
    --filter "mail eq '${ASSIGNEE}' or userPrincipalName eq '${ASSIGNEE}'" \
    --query "[].id" -o tsv 2>/dev/null || true)"
  COUNT="$(printf '%s' "$MATCHES" | grep -c . || true)"
  if [[ "${COUNT:-0}" -eq 0 ]]; then
    echo "Error: no user found for '${ASSIGNEE}' in this tenant." >&2
    echo "If they are external, invite them as a guest and have them accept the invitation first." >&2
    exit 1
  fi
  if [[ "${COUNT}" -gt 1 ]]; then
    echo "Error: '${ASSIGNEE}' matched ${COUNT} users; pass the exact object id via --assignee instead." >&2
    exit 1
  fi
  OBJECT_ID="$MATCHES"
fi

# Idempotency: do nothing if the assignment already exists.
EXISTING="$(az role assignment list \
  --assignee "$OBJECT_ID" --scope "$SCOPE" \
  --query "[?roleDefinitionName=='${ROLE}'] | length(@)" -o tsv 2>/dev/null || echo 0)"
if [[ "${EXISTING:-0}" != "0" ]]; then
  echo "Already assigned: '${ROLE}' to ${OBJECT_ID} on the API Center scope. Nothing to do."
  exit 0
fi

echo "Assigning '${ROLE}' to ${TYPE} ${OBJECT_ID}"
echo "  scope: ${SCOPE}"
az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type "$TYPE" \
  --role "$ROLE" \
  --scope "$SCOPE" \
  --query "{principalId:principalId, role:roleDefinitionName, scope:scope}" -o jsonc

echo "Done. Role propagation can take a few minutes; the user may need to sign out and back in."
