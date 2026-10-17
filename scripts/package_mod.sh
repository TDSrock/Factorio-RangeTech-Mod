#!/usr/bin/env bash
# Packages the mod into a {name}_{version}.zip with the correct inner folder
# structure for the Factorio mod portal.
set -euo pipefail

MOD_NAME=$(jq -r '.name' info.json)
VERSION=$(jq -r '.version' info.json)
ZIP_NAME="${MOD_NAME}_${VERSION}.zip"

STAGE_DIR=$(mktemp -d)
TARGET_DIR="${STAGE_DIR}/${MOD_NAME}_${VERSION}"
mkdir -p "$TARGET_DIR"

# Copy mod files only -- exclude repo/dev-only paths.
rsync -a \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='scripts' \
  --exclude='*.zip' \
  --exclude='.gitignore' \
  ./ "$TARGET_DIR"/

(cd "$STAGE_DIR" && zip -r -q "${ZIP_NAME}" "${MOD_NAME}_${VERSION}")

mv "${STAGE_DIR}/${ZIP_NAME}" "./${ZIP_NAME}"
rm -rf "$STAGE_DIR"

echo "zip_name=${ZIP_NAME}"
echo "mod_name=${MOD_NAME}"
echo "version=${VERSION}"
