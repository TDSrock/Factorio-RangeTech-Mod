#!/usr/bin/env bash
# Builds a NON-BLOCKING reminder (markdown) about optional mod files, leftover
# template placeholders and the changelog.
#
# Usage: check_optional_files.sh <output-markdown-file>
# Optional env: PR_TITLE  the pull request title. With squash merges it becomes
#               the commit message on master, which is what the generated
#               changelog is built from (the PR workflow passes it).
# Prints "missing_count=N" on stdout (same style as the other scripts, so it
# can be appended to $GITHUB_OUTPUT). Always exits 0: this is a reminder, never
# a gate.
set -uo pipefail

OUT="${1:?usage: check_optional_files.sh <output-markdown-file>}"

MARKER="<!-- optional-files-reminder -->"
missing=0
rows=""
changelog_preview=""
title_hint=0

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

# --- changelog.txt -----------------------------------------------------------
# The release pipeline generates the entry from commit messages unless a manual
# entry for the new version already exists (the manual entry wins).
changelog_msg=$(bash scripts/check_changelog.sh 2>&1)
changelog_rc=$?
case "$changelog_rc" in
  0)
    add_row 1 "\`changelog.txt\`" "Manual entry for the upcoming version found. It will be used instead of auto-generation."
    ;;
  1)
    add_row 0 "\`changelog.txt\`" "$(paste -sd' ' <<< "$changelog_msg")"
    ;;
  *)
    # No manual entry: the release will generate one from the merge message.
    # With squash merges that is the PR title, so that is what we check.
    if [[ -n "${PR_TITLE:-}" ]]; then
      skip_re='^(chore|ci|docs|test|tests|build|style|refactor)(\([^)]*\))?!?:'
      if changelog_preview=$(bash scripts/generate_changelog.sh "next release" --subject "$PR_TITLE" 2>/dev/null); then
        add_row 1 "PR title" "Will appear in the generated changelog (preview below)."
      elif [[ "${PR_TITLE,,}" == *"[skip changelog]"* || "${PR_TITLE,,}" =~ $skip_re ]]; then
        changelog_preview=""
        add_row 2 "PR title" "Marked as an internal change, so it stays out of the changelog. Fine if players don't need to know."
      else
        changelog_preview=""
        add_row 0 "PR title" "No changelog prefix, so this PR will **not** appear in the changelog. If it matters to players, rename the PR to \`type: description\` (see below). Otherwise ignore this."
        title_hint=1
      fi
    fi
    ;;
esac

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
  if [[ -n "$changelog_preview" ]]; then
    echo "<details><summary>Changelog preview (from this PR's title)</summary>"
    echo
    echo '```text'
    printf "%s\n" "$changelog_preview"
    echo '```'
    echo
    echo "</details>"
    echo
  fi
  if [[ "$title_hint" -eq 1 ]]; then
    echo "**PR title format.** When this PR is squash-merged, its title becomes the commit message and the changelog is generated from that, so the title is the one that counts (the commits inside the PR don't). Use \`type: description\`, written for players:"
    echo
    echo "| Prefix | Changelog category |"
    echo "| --- | --- |"
    echo "| \`feat:\` | Features |"
    echo "| \`fix:\` | Bugfixes |"
    echo "| \`perf:\` | Optimizations |"
    echo "| \`balance:\` | Balancing |"
    echo "| \`info:\` | Info |"
    echo "| \`chore:\` \`ci:\` \`docs:\` \`test:\` \`build:\` \`style:\` \`refactor:\` | kept out of the changelog |"
    echo
    echo "Example: \`fix: Demolishers no longer damage themselves\`. Renaming the PR updates this comment."
    echo
  fi
  echo "**Only if your mod needs them** (not checked): \`control.lua\` (runtime scripting), \`settings.lua\` (mod settings), \`data-updates.lua\` / \`data-final-fixes.lua\` (changing other mods' prototypes), and Space Age guards (\`if mods[\"space-age\"] then\`) when \`space-age\` is an optional dependency."
  echo
  echo "**Manual, on the mod portal** (cannot be checked from the repo): summary, description, tags, license, source URL and screenshots on your mod's portal page."
  echo
  echo "**Docs**"
  echo "- Mod structure (info.json, thumbnail, changelog, locale): https://lua-api.factorio.com/latest/auxiliary/mod-structure.html"
  echo "- Changelog format: see \`changelog.txt\` in this repo for the layout (dashed separator, \`Version:\`, \`Date:\`, category, \`- change\` lines)"
  echo "- Localised strings: https://lua-api.factorio.com/latest/auxiliary/localised-strings.html"
  echo "- Mod upload API: https://wiki.factorio.com/Mod_upload_API"
} > "$OUT"

echo "missing_count=${missing}"
exit 0
