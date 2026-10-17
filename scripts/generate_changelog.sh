#!/usr/bin/env bash
# Generates a Factorio-format changelog entry from commit messages.
#
# Usage:
#   generate_changelog.sh <version> [--range <git-range>] [--subject <text>] [--write]
#
#   (default)   Print the generated entry to stdout. Changes no files.
#   --write     Prepend the entry to changelog.txt, unless a manual entry
#               already exists (see below).
#   --range     Git range to read commit subjects from. Default: everything
#               since the latest v* tag (or the whole history if no tag yet).
#   --subject   Use this single message instead of reading git history (used
#               by the PR workflow to preview what the PR title will generate).
#
# Manual override: if the top entry of changelog.txt is already <version>,
# --write leaves the file alone. If the top entry is NEWER than <version>
# (manual entry for a different version), --write refuses so the changelog
# does not end up out of order.
#
# Only commits with a recognised prefix land in the changelog (optional scope,
# e.g. "fix(gui): ..."):
#   feat:      -> Features
#   fix:       -> Bugfixes
#   perf:      -> Optimizations
#   balance:   -> Balancing
#   info:      -> Info
# Everything else lands nowhere: commits without a prefix, with an unknown
# prefix, or with chore/ci/docs/test/build/style/refactor. Merge commits,
# version-bump commits and subjects containing "[skip changelog]" are skipped too.
#
# Exit codes: 0 ok, 3 no qualifying commits, 4 refused (manual entry is newer).
set -uo pipefail

CHANGELOG="changelog.txt"
version=""
range=""
subject_arg=""
write=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) write=1 ;;
    --range) range="${2:-}"; shift ;;
    --subject) subject_arg="${2:-}"; shift ;;
    *) version="$1" ;;
  esac
  shift
done

if [[ -z "$version" ]]; then
  echo "usage: generate_changelog.sh <version> [--range <git-range>] [--subject <text>] [--write]" >&2
  exit 2
fi

if [[ -z "$subject_arg" && -z "$range" ]]; then
  prev_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
  if [[ -n "$prev_tag" ]]; then range="${prev_tag}..HEAD"; else range="HEAD"; fi
fi

declare -A buckets=()

add_to() { # <category> <text>
  buckets["$1"]+="    - $2"$'\n'
}

commit_re='^([A-Za-z]+)(\([^)]*\))?!?:[[:space:]]*(.+)$'

while IFS= read -r subject; do
  subject=$(tr -d '\r' <<< "$subject")
  [[ -z "$subject" ]] && continue
  grep -qiF "[skip changelog]" <<< "$subject" && continue
  [[ "$subject" == Merge\ * ]] && continue
  [[ "$subject" =~ ^chore:\ bump\ version ]] && continue

  # Remove pipeline tags and a trailing GitHub PR reference like " (#12)".
  subject=$(sed -E 's/\[(major|minor|skip ci)\]//Ig; s/ \(#[0-9]+\)$//; s/[[:space:]]+/ /g; s/^ //; s/ $//' <<< "$subject")
  [[ -z "$subject" ]] && continue

  # No recognised "type: text" shape -> lands nowhere.
  [[ "$subject" =~ $commit_re ]] || continue
  type="${BASH_REMATCH[1],,}"
  text="${BASH_REMATCH[3]}"

  case "$type" in
    feat|feature)      category="Features" ;;
    fix|bugfix)        category="Bugfixes" ;;
    perf)              category="Optimizations" ;;
    balance|balancing) category="Balancing" ;;
    info)              category="Info" ;;
    *) continue ;;   # chore/ci/docs/... and unknown prefixes land nowhere
  esac

  text="${text^}"
  [[ "$text" =~ [.!?]$ ]] || text="${text}."
  add_to "$category" "$text"
done < <(
  if [[ -n "$subject_arg" ]]; then
    printf '%s\n' "$subject_arg"
  else
    git log --no-merges --reverse --format=%s "$range" 2>/dev/null
  fi
)

body=""
for category in Features Optimizations Balancing Bugfixes Info; do
  if [[ -n "${buckets[$category]:-}" ]]; then
    body+="  ${category}:"$'\n'"${buckets[$category]}"
  fi
done

if [[ -z "$body" ]]; then
  echo "No commit message qualifies for the changelog (needs a prefix: feat:, fix:, perf:, balance: or info:)." >&2
  exit 3
fi

separator=$(printf -- '-%.0s' {1..99})
entry="${separator}"$'\n'"Version: ${version}"$'\n'"Date: $(date -u +%F)"$'\n'"${body}"

if [[ "$write" -eq 0 ]]; then
  printf "%s" "$entry"
  exit 0
fi

if [[ -f "$CHANGELOG" ]]; then
  top_version=$(tr -d '\r' < "$CHANGELOG" | grep -m1 -E '^Version:' | sed -E 's/^Version:[[:space:]]*//; s/[[:space:]]+$//')
  if [[ -n "$top_version" ]]; then
    if [[ "$top_version" == "$version" ]]; then
      echo "changelog.txt already has an entry for ${version}; keeping the manual entry."
      exit 0
    fi
    newest=$(printf '%s\n%s\n' "$top_version" "$version" | sort -V | tail -n1)
    if [[ "$newest" == "$top_version" ]]; then
      echo "changelog.txt's top entry is ${top_version}, which is newer than the release ${version}. Not generating an entry; fix the changelog by hand." >&2
      exit 4
    fi
  fi
  existing=$(cat "$CHANGELOG")
  printf "%s%s\n" "$entry" "$existing" > "$CHANGELOG"
else
  printf "%s" "$entry" > "$CHANGELOG"
fi

echo "Generated changelog entry for ${version} from commit messages."
exit 0
