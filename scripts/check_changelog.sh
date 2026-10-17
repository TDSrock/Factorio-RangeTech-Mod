#!/usr/bin/env bash
# Checks that changelog.txt has an entry with actual changes.
#
# Usage: check_changelog.sh [expected_version]
#
#   Without argument (PR mode): looks for a MANUAL entry for the upcoming
#     version, i.e. a top entry NEWER than the version in info.json (info.json
#     still holds the last release while a PR is open; the pipeline bumps it
#     after merge). If there is no such entry, that is not a problem: the
#     release pipeline generates one from commit messages (exit code 2).
#   With argument (release mode, run after generation): the top entry must be
#     exactly that version (the version the pipeline just bumped to).
#
# In both modes the top entry must contain at least one change line, e.g.
#   "    - Fixed something."
#
# Prints one problem per line.
# Exit codes: 0 ok, 1 problem(s) found, 2 (PR mode only) no manual entry.
# Callers decide whether a problem is blocking (the pipelines only warn).
set -uo pipefail

CHANGELOG="changelog.txt"
expected="${1:-}"
problems=0

problem() {
  echo "$1"
  problems=$((problems + 1))
}

# A missing or entry-less changelog is fine in PR mode: it gets generated.
missing_rc=1
[[ -z "$expected" ]] && missing_rc=2

if [[ ! -f "$CHANGELOG" ]]; then
  echo "changelog.txt is missing."
  exit "$missing_rc"
fi

# Strip CR so files saved with Windows line endings parse the same.
content=$(tr -d '\r' < "$CHANGELOG")

top_version=$(grep -m1 -E '^Version:' <<< "$content" | sed -E 's/^Version:[[:space:]]*//; s/[[:space:]]+$//')
if [[ -z "$top_version" ]]; then
  echo "changelog.txt has no \"Version:\" entry."
  exit "$missing_rc"
fi

# Top entry = lines after the first "Version:" up to the next dashed separator.
entry=$(awk '/^Version:/ { found=1; next } found && /^-{20,}$/ { exit } found { print }' <<< "$content")
bullets=$(grep -cE '^[[:space:]]+- [^[:space:]]' <<< "$entry")

if [[ -n "$expected" ]]; then
  if [[ "$top_version" != "$expected" ]]; then
    problem "Top changelog entry is ${top_version}, but this release is ${expected}. Add an entry for ${expected}."
  fi
else
  current=$(jq -r '.version' info.json)
  newest=$(printf '%s\n%s\n' "$top_version" "$current" | sort -V | tail -n1)
  if [[ "$top_version" == "$current" || "$newest" == "$current" ]]; then
    echo "No manual changelog entry for the upcoming version (top entry is ${top_version}, last release is ${current})."
    exit 2
  fi
fi

if [[ "$bullets" -eq 0 ]]; then
  problem "The changelog entry for ${top_version} lists no changes (expected lines like \"    - Fixed something.\" under a category such as Features or Bugfixes)."
fi

[[ "$problems" -eq 0 ]]
