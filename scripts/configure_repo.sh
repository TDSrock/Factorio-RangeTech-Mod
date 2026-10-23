#!/usr/bin/env bash
# Squash-only merging, with the PR title as the commit subject and the PR description as the
# commit body (so the "Changelog:" section is also kept in the git history), and delete head
# branches after merge.
#
# Repo settings are NOT copied when you create a repo from a template, so run
# this once per new repo.
#
# Usage: scripts/configure_repo.sh [owner/repo]
# Defaults to the repo of the current directory. Requires the GitHub CLI
# (gh), logged in as someone with admin rights on the repo.
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

echo "Configuring ${REPO}..."

gh api -X PATCH "repos/${REPO}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true \
  --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, squash_merge_commit_title, squash_merge_commit_message, delete_branch_on_merge}'

echo
echo "Done. Squash merge is now the only merge method; its commit subject is the PR title."
echo "Note: this does NOT set up branch protection / rulesets. If you require pull"
echo "requests on master, make sure the release workflow's version-bump push is"
echo "allowed (it pushes directly to master)."
