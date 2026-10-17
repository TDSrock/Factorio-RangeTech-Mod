#!/usr/bin/env bash
# Bumps the version in info.json.
# Usage: bump_version.sh [major|minor|release]
# Defaults to "release" (the 3rd number) if no argument is given.
set -euo pipefail

INFO_JSON="info.json"
BUMP_TYPE="${1:-release}"

current_version=$(jq -r '.version' "$INFO_JSON")
IFS='.' read -r major minor release <<< "$current_version"

case "$BUMP_TYPE" in
  major)
    major=$((major + 1))
    minor=0
    release=0
    ;;
  minor)
    minor=$((minor + 1))
    release=0
    ;;
  release)
    release=$((release + 1))
    ;;
  *)
    echo "Unknown bump type: $BUMP_TYPE (expected major, minor, or release)" >&2
    exit 1
    ;;
esac

new_version="${major}.${minor}.${release}"

tmp=$(mktemp)
jq --arg v "$new_version" '.version = $v' "$INFO_JSON" > "$tmp"
mv "$tmp" "$INFO_JSON"

echo "previous_version=$current_version"
echo "new_version=$new_version"
