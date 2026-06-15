#!/usr/bin/env bash
#
# Registers (idempotently) the Microsoft Entra application that the Azure API
# Center self-service portal uses for user sign-in, then stores its client ID in
# the azd environment so the next `azd up` publishes the Entra-protected portal.
#
# This is the ONLY step that needs Microsoft Entra *directory* permissions
# (creating an app registration), which is why it lives in a helper script
# rather than in the Bicep template that anyone with Azure resource access runs.
#
# Usage:
#   azd up                       # first provision (creates the API Center; portal skipped)
#   ./scripts/register-portal-app.sh [app-display-name]
#   azd up                       # publishes the portal using the new client ID
#
set -euo pipefail

APP_NAME="${1:-api-center-portal}"

HOST="$(azd env get-value PORTAL_HOSTNAME 2>/dev/null || true)"
if [ -z "${HOST}" ] || [ "${HOST}" = "null" ]; then
  echo "ERROR: PORTAL_HOSTNAME not found in the azd environment. Run 'azd provision' (or 'azd up') first." >&2
  exit 1
fi
REDIRECT_URI="https://${HOST}"

echo "Portal redirect URI : ${REDIRECT_URI}"
echo "App display name    : ${APP_NAME}"

APP_ID="$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv 2>/dev/null || true)"
if [ -z "${APP_ID}" ]; then
  echo "Creating app registration..."
  APP_ID="$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv)"
else
  echo "Reusing existing app registration ${APP_ID}"
fi

# Ensure the single-page-application redirect URI is set (API Center portal is a SPA).
OBJ_ID="$(az ad app show --id "${APP_ID}" --query id -o tsv)"
az rest --method PATCH \
  --url "https://graph.microsoft.com/v1.0/applications/${OBJ_ID}" \
  --headers "Content-Type=application/json" \
  --body "{\"spa\":{\"redirectUris\":[\"${REDIRECT_URI}\"]}}" >/dev/null
echo "Redirect URI configured."

# Ensure a service principal exists so role assignments can target the app.
az ad sp show --id "${APP_ID}" >/dev/null 2>&1 || az ad sp create --id "${APP_ID}" >/dev/null

azd env set PORTAL_ENTRA_CLIENT_ID "${APP_ID}"
echo
echo "Done. Client ID ${APP_ID} stored in the azd environment."
echo "Run 'azd up' to publish the Entra-protected API Center portal."
