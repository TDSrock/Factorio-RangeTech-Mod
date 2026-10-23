#!/usr/bin/env bash
# Kept as a thin wrapper. Changelog entries now come from the "Changelog:" section of each pull
# request description, handled by scripts/changelog.py (see "Changelog" in the README).
# Usage: generate_changelog.sh --version X.Y.Z [--repo owner/name] [--write]
exec python3 "$(dirname "$0")/changelog.py" release "$@"
