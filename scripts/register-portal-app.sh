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

APP_NAME="${1:-}"

# azd stores Bicep outputs under their literal output name, so this is
# 'portalHostname' (camelCase), not PORTAL_HOSTNAME.
HOST="$(azd env get-value portalHostname 2>/dev/null || true)"
if [ -z "${HOST}" ] || [ "${HOST}" = "null" ]; then
  echo "ERROR: portalHostname not found in the azd environment. Run 'azd provision' (or 'azd up') first." >&2
  exit 1
fi
# The portal's MSAL client uses the page URL (with a trailing slash) as the
# redirect URI, e.g. https://<host>/. Register both the trailing-slash and
# bare forms so sign-in can't fail with AADSTS50011 (redirect URI mismatch).
REDIRECT_URI="https://${HOST}/"
REDIRECT_URI_BARE="https://${HOST}"

if [ -z "${APP_NAME}" ]; then
  SERVICE_NAME="${HOST%%.*}"
  APP_NAME="api-center-portal-${SERVICE_NAME}"
fi

echo "Portal redirect URI : ${REDIRECT_URI}"
echo "App display name    : ${APP_NAME}"

APP_CREATED="false"
APP_ID="$(az ad app list \
  --display-name "${APP_NAME}" \
  --query "[?contains(to_string(spa.redirectUris), '${REDIRECT_URI}') || contains(to_string(spa.redirectUris), '${REDIRECT_URI_BARE}')].appId | [0]" \
  -o tsv 2>/dev/null | tr -d '\r' || true)"
if [ -z "${APP_ID}" ]; then
  APP_COUNT="$(az ad app list --display-name "${APP_NAME}" --query "length(@)" -o tsv | tr -d '\r')"
  if [ "${APP_COUNT}" = "1" ]; then
    APP_ID="$(az ad app list --display-name "${APP_NAME}" --query "[0].appId" -o tsv | tr -d '\r')"
  elif [ "${APP_COUNT}" -gt 1 ]; then
    echo "ERROR: multiple app registrations named '${APP_NAME}' exist, but none use this portal redirect URI. Use a unique app name or remove the duplicates." >&2
    exit 1
  else
    echo "Creating app registration..."
    APP_ID="$(az ad app create --display-name "${APP_NAME}" --query appId -o tsv | tr -d '\r')"
    APP_CREATED="true"
  fi
fi

if [ -z "${APP_ID}" ]; then
  echo "ERROR: failed to create or resolve the app registration." >&2
  exit 1
elif [ "${APP_CREATED}" != "true" ]; then
  echo "Reusing existing app registration ${APP_ID}"
fi

# Entra is eventually consistent: a freshly created app may not be queryable for
# a few seconds. Retry until it resolves before configuring it.
OBJ_ID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  OBJ_ID="$(az ad app show --id "${APP_ID}" --query id -o tsv 2>/dev/null | tr -d '\r' || true)"
  [ -n "${OBJ_ID}" ] && break
  sleep 3
done
if [ -z "${OBJ_ID}" ]; then
  echo "ERROR: app ${APP_ID} did not become queryable in time. Re-run the script." >&2
  exit 1
fi

# Ensure the single-page-application redirect URI is set (API Center portal is a SPA).
az rest --method PATCH \
  --url "https://graph.microsoft.com/v1.0/applications/${OBJ_ID}" \
  --headers "Content-Type=application/json" \
  --body "{\"spa\":{\"redirectUris\":[\"${REDIRECT_URI}\",\"${REDIRECT_URI_BARE}\"]}}" >/dev/null
echo "Redirect URI configured."

# Ensure a service principal exists so role assignments can target the app.
az ad sp show --id "${APP_ID}" >/dev/null 2>&1 || az ad sp create --id "${APP_ID}" >/dev/null

azd env set PORTAL_ENTRA_CLIENT_ID "${APP_ID}"
echo
echo "Done. Client ID ${APP_ID} stored in the azd environment."
echo "Run 'azd up' to publish the Entra-protected API Center portal."
