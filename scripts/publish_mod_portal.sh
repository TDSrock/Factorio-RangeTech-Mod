#!/usr/bin/env bash
# Publishes a release to the Factorio Mod Portal.
#
#   1. The "easy" way: the Mod upload API adds a release to a mod that already exists
#      (POST /api/v2/mods/releases/init_upload, then upload the zip).
#      https://wiki.factorio.com/Mod_upload_API
#   2. If the portal answers that the mod does not exist yet (error "UnknownMod") and
#      NEW_MOD_FALLBACK=true, the mod is published as a NEW mod through the Mod publish API
#      (POST /api/v2/mods/init_publish, then upload the zip together with optional details).
#      https://wiki.factorio.com/Mod_publish_API
#      Only that one specific error triggers step 2. Any other failure (bad key, version already
#      exists, ...) stops here, so a new listing is never created by accident.
#
# Usage: publish_mod_portal.sh <mod-name> <zip-path>
#
# Environment:
#   FACTORIO_API_KEY       required. Needs the "ModPortal: Upload Mods" usage, and for step 2 also
#                          "ModPortal: Publish Mods" (created at https://factorio.com/profile).
#   NEW_MOD_FALLBACK       "true" (default) / "false": allow step 2.
#   MOD_CATEGORY           new mods only, optional: portal category (e.g. content, tweaks).
#   MOD_LICENSE            new mods only, optional: license id.
#   MOD_SOURCE_URL         new mods only, optional: source code URL.
#   MOD_DESCRIPTION_FILE   new mods only, optional: markdown file used as the portal description.
#                          Without it, the description from info.json is used.
#
# Details (title, description, tags, FAQ, images) can be edited afterwards on the mod's portal page.
#
# Not exhaustively tested against the live API: if a step fails, the full response is printed.
set -euo pipefail

MOD_NAME="${1:?usage: publish_mod_portal.sh <mod-name> <zip-path>}"
ZIP_PATH="${2:?usage: publish_mod_portal.sh <mod-name> <zip-path>}"

PORTAL="https://mods.factorio.com"
NEW_MOD_FALLBACK="${NEW_MOD_FALLBACK:-true}"

if [[ -z "${FACTORIO_API_KEY:-}" ]]; then
  echo "FACTORIO_API_KEY is not set, cannot publish to the mod portal." >&2
  exit 1
fi
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip file not found: ${ZIP_PATH}" >&2
  exit 1
fi

HTTP_CODE=""
RESPONSE=""
UPLOAD_URL=""
ERROR_CODE=""

# Calls an init endpoint and fills HTTP_CODE, RESPONSE, UPLOAD_URL and ERROR_CODE.
call_init() {
  local endpoint="$1" raw
  raw=$(curl -sS -w $'\n%{http_code}' -X POST "${PORTAL}${endpoint}" \
    -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
    -F "mod=${MOD_NAME}") || { echo "Request to ${endpoint} failed." >&2; exit 1; }
  HTTP_CODE="${raw##*$'\n'}"
  RESPONSE="${raw%$'\n'*}"
  UPLOAD_URL=$(jq -r '.upload_url // empty' <<< "$RESPONSE" 2>/dev/null || true)
  ERROR_CODE=$(jq -r '.error // empty' <<< "$RESPONSE" 2>/dev/null || true)
}

MODE="release"

echo "Requesting an upload URL for a new release of '${MOD_NAME}'..."
call_init "/api/v2/mods/releases/init_upload"

if [[ -z "$UPLOAD_URL" && "$ERROR_CODE" == "UnknownMod" ]]; then
  echo "'${MOD_NAME}' does not exist on the mod portal yet."
  if [[ "$NEW_MOD_FALLBACK" != "true" ]]; then
    echo "Publishing as a new mod is disabled (NEW_MOD_FALLBACK=${NEW_MOD_FALLBACK}). Nothing was published." >&2
    exit 1
  fi
  echo "Publishing it as a NEW mod..."
  MODE="new"
  call_init "/api/v2/mods/init_publish"
fi

if [[ -z "$UPLOAD_URL" ]]; then
  echo "Could not get an upload URL (HTTP ${HTTP_CODE}). Full response:" >&2
  echo "$RESPONSE" >&2
  if [[ "$MODE" == "new" ]]; then
    echo "Publishing a new mod needs an API key with the 'ModPortal: Publish Mods' usage." >&2
  fi
  exit 1
fi

upload_args=(-sS -w $'\n%{http_code}' -X POST "$UPLOAD_URL" -F "file=@${ZIP_PATH}")

if [[ "$MODE" == "new" ]]; then
  # Optional details that are accepted together with the file of a new mod.
  description_file="${MOD_DESCRIPTION_FILE:-}"
  if [[ -n "$description_file" && -f "$description_file" ]]; then
    upload_args+=(-F "description=<${description_file}")
  else
    description=$(jq -r '.description // empty' info.json 2>/dev/null || true)
    if [[ -n "$description" ]]; then upload_args+=(-F "description=${description}"); fi
  fi
  if [[ -n "${MOD_CATEGORY:-}" ]]; then upload_args+=(-F "category=${MOD_CATEGORY}"); fi
  if [[ -n "${MOD_LICENSE:-}" ]]; then upload_args+=(-F "license=${MOD_LICENSE}"); fi
  if [[ -n "${MOD_SOURCE_URL:-}" ]]; then upload_args+=(-F "source_url=${MOD_SOURCE_URL}"); fi
fi

echo "Uploading ${ZIP_PATH}..."
raw=$(curl "${upload_args[@]}") || { echo "Upload request failed." >&2; exit 1; }
HTTP_CODE="${raw##*$'\n'}"
RESPONSE="${raw%$'\n'*}"
echo "Upload response (HTTP ${HTTP_CODE}): ${RESPONSE}"

failed=false
if [[ ! "$HTTP_CODE" =~ ^2 ]]; then failed=true; fi
if jq -e '(.success == false) or ((.error // "") != "")' <<< "$RESPONSE" > /dev/null 2>&1; then failed=true; fi
if [[ "$failed" == "true" ]]; then
  echo "The mod portal reported a failure." >&2
  exit 1
fi

if [[ "$MODE" == "new" ]]; then
  echo "Published '${MOD_NAME}' as a NEW mod. Check its page on the portal and finish its details (title, tags, images, FAQ)."
else
  echo "Published a new release of '${MOD_NAME}'. Double check the mod page."
fi
