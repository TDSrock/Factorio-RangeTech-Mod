#!/usr/bin/env bash
# Publishes a new release to the Factorio Mod Portal via the official
# Mod Upload API (https://wiki.factorio.com/Mod_upload_API).
#
# NOTE: this only works for mods that already exist on the portal -- the
# API does not support creating a brand new mod listing. The first-ever
# release must be submitted manually via the "Submit mod" button on
# factorio.com/profile before this script can be used for anything.
#
# Requires FACTORIO_API_KEY env var (create one at factorio.com/profile).
#
# This has not been exhaustively verified against the live API -- if the
# init_upload or upload step errors out, check the response body for the
# actual expected field names and adjust below.
set -euo pipefail

MOD_NAME="$1"
ZIP_PATH="$2"

if [[ -z "${FACTORIO_API_KEY:-}" ]]; then
  echo "FACTORIO_API_KEY is not set, skipping mod portal publish." >&2
  exit 1
fi

INIT_URL="https://mods.factorio.com/api/v2/mods/releases/init_upload"

echo "Requesting upload URL for ${MOD_NAME}..."
INIT_RESPONSE=$(curl -s -X POST "$INIT_URL" \
  -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
  -F "mod=${MOD_NAME}")

UPLOAD_URL=$(echo "$INIT_RESPONSE" | jq -r '.upload_url // empty')

if [[ -z "$UPLOAD_URL" ]]; then
  echo "Failed to get upload URL. Full response:" >&2
  echo "$INIT_RESPONSE" >&2
  exit 1
fi

echo "Uploading ${ZIP_PATH}..."
UPLOAD_RESPONSE=$(curl -s -X POST "$UPLOAD_URL" \
  -F "file=@${ZIP_PATH}")

echo "Upload response: $UPLOAD_RESPONSE"

# Basic sanity check -- adjust the key checked here once you've seen a real
# successful response shape.
if echo "$UPLOAD_RESPONSE" | jq -e '.success == false' > /dev/null 2>&1; then
  echo "Mod portal reported failure." >&2
  exit 1
fi

echo "Published ${MOD_NAME} successfully (or at least, the portal didn't report failure -- double check the mod page)."
