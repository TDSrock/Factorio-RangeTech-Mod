#!/usr/bin/env bash
# Builds a NON-BLOCKING reminder (markdown) about optional mod files and leftover template
# placeholders. (The changelog is checked separately, by the "PR Changelog" workflow.)
#
# Usage: check_optional_files.sh <output-markdown-file>
# Prints "missing_count=N" on stdout (same style as the other scripts, so it can be appended to
# $GITHUB_OUTPUT). Always exits 0: this is a reminder, never a gate.
set -uo pipefail

OUT="${1:?usage: check_optional_files.sh <output-markdown-file>}"

MARKER="<!-- optional-files-reminder -->"
missing=0
rows=""

# add_row <status> <item> <details>
#   status 1 = done, 0 = missing (counted), 2 = informational (not counted)
add_row() {
  local mark
  case "$1" in
    1) mark="✅" ;;
    2) mark="➖" ;;
    *) mark="⬜"; missing=$((missing + 1)) ;;
  esac
  rows+="| ${mark} | $2 | $3 |"$'\n'
}

# --- thumbnail.png (144x144) -------------------------------------------------
if [[ -f thumbnail.png ]]; then
  if file thumbnail.png | grep -q "144 x 144"; then
    add_row 1 "\`thumbnail.png\`" "Present, 144x144."
  else
    add_row 0 "\`thumbnail.png\`" "Present, but not 144x144 ($(file -b thumbnail.png | grep -oE '[0-9]+ x [0-9]+' | head -n1)). The in-game mod list expects 144x144."
  fi
else
  add_row 0 "\`thumbnail.png\`" "Shown in the in-game mod list and on the portal. 144x144 PNG in the repo root."
fi

# --- locale ------------------------------------------------------------------
if [[ -f locale/en/locale.cfg ]]; then
  add_row 1 "\`locale/en/locale.cfg\`" "Present."
else
  add_row 0 "\`locale/en/locale.cfg\`" "Localised names/descriptions for your prototypes and settings. Without it, players see raw internal names."
fi

# --- portal description (optional) -------------------------------------------
if [[ -f portal-description.md ]]; then
  add_row 1 "\`portal-description.md\`" "Present. Used as the description when the mod is first published to the portal."
else
  add_row 2 "\`portal-description.md\`" "Optional markdown description for the portal. Without it the \`description\` from \`info.json\` is used."
fi

# --- range overlay image (optional) --------------------------------------------
overlay_enabled=$(grep -v '^[[:space:]]*--' lib/icons.lua 2>/dev/null | grep -c 'M\.CUSTOM_OVERLAY[[:space:]]*=[[:space:]]*"')
if [[ -f graphics/range-overlay.png ]]; then
  if [[ "$overlay_enabled" -gt 0 ]]; then
    add_row 1 "\`graphics/range-overlay.png\`" "Present and enabled in \`lib/icons.lua\`. Size is checked by the CI asset validation."
  else
    add_row 0 "\`graphics/range-overlay.png\`" "Present but not enabled: set \`M.CUSTOM_OVERLAY\` in \`lib/icons.lua\`."
  fi
else
  add_row 2 "\`graphics/range-overlay.png\`" "Optional own range symbol for the research icons (128x128 transparent PNG, see README). Until then the vanilla range symbol is used."
fi

# --- info.json placeholders --------------------------------------------------
if grep -qE 'my-mod-name|My Mod Title|Short description of what this mod does' info.json 2>/dev/null; then
  add_row 0 "\`info.json\` placeholders" "Still contains template values (\`name\`, \`title\` or \`description\`)."
else
  add_row 1 "\`info.json\` placeholders" "Replaced."
fi

# --- README still the template -----------------------------------------------
if grep -q "## Using this template" README.md 2>/dev/null; then
  add_row 0 "\`README.md\`" "Still contains the template's \"Using this template\" section. Replace it with your mod's own README."
else
  add_row 1 "\`README.md\`" "Customised."
fi

{
  echo "$MARKER"
  echo "### Optional mod files reminder"
  echo
  echo "_This is an automatic, non-blocking reminder. It never fails the build._"
  echo
  echo "| | Item | Notes |"
  echo "| --- | --- | --- |"
  printf "%s" "$rows"
  echo
  echo "**Only if your mod needs them** (not checked): \`control.lua\` (runtime scripting), \`settings.lua\` (mod settings), \`data-updates.lua\` / \`data-final-fixes.lua\` (changing other mods' prototypes), and Space Age guards (\`if mods[\"space-age\"] then\`) when \`space-age\` is an optional dependency."
  echo
  echo "**Manual, on the mod portal** (cannot be checked from the repo): summary, description, tags, license, source URL and screenshots on your mod's portal page."
  echo
  echo "**Docs**"
  echo "- Mod structure (info.json, thumbnail, changelog, locale): https://lua-api.factorio.com/latest/auxiliary/mod-structure.html"
  echo "- Changelog format: https://lua-api.factorio.com/latest/auxiliary/changelog-format.html"
  echo "- Localised strings: https://lua-api.factorio.com/latest/auxiliary/localised-strings.html"
  echo "- Mod upload API: https://wiki.factorio.com/Mod_upload_API"
} > "$OUT"

echo "missing_count=${missing}"
exit 0
