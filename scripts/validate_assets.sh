#!/usr/bin/env bash
# Build-time check of the images that belong to THIS mod. The data stage cannot open image
# files, so this is where their real size and format are verified (CI runs it).
#
# - If lib/icons.lua enables M.CUSTOM_OVERLAY, that file must exist and be a 128x128 PNG
#   with an alpha channel.
# - Every PNG under graphics/ must be a real PNG.
set -uo pipefail

status=0
fail() {
  echo "::error::$1"
  status=1
}

# Ignore commented-out lines (the example in the comment must not count as enabled).
overlay=$(grep -v '^[[:space:]]*--' lib/icons.lua 2>/dev/null \
  | grep -oP 'M\.CUSTOM_OVERLAY\s*=\s*"__range-tech__/\K[^"]+' || true)

if [[ -n "$overlay" ]]; then
  if [[ ! -f "$overlay" ]]; then
    fail "lib/icons.lua points M.CUSTOM_OVERLAY at '$overlay', but that file does not exist."
  else
    info=$(file -b "$overlay")
    echo "$overlay: $info"
    [[ "$info" == PNG\ image\ data* ]] || fail "$overlay is not a PNG image."
    [[ "$info" == *"128 x 128"* ]] || fail "$overlay must be 128 x 128 pixels."
    [[ "$info" == *RGBA* ]] || fail "$overlay needs an alpha channel (transparent background, RGBA)."
  fi
else
  echo "No custom overlay enabled (M.CUSTOM_OVERLAY is nil); the vanilla range symbol is used."
fi

if [[ -d graphics ]]; then
  while IFS= read -r -d '' png; do
    info=$(file -b "$png")
    [[ "$info" == PNG\ image\ data* ]] || fail "$png is not a valid PNG image ($info)."
  done < <(find graphics -type f -iname '*.png' -print0)
fi

exit "$status"
