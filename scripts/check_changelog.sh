#!/usr/bin/env bash
# Kept as a thin wrapper. The changelog logic lives in scripts/changelog.py
# (see "Changelog" in the README). Usage: check_changelog.sh [--file F] [--expect-version V]
exec python3 "$(dirname "$0")/changelog.py" validate "$@"
