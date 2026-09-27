#!/bin/sh
# Print the CHANGELOG.md section of a version (release notes for Gitea and GitHub).
# Usage: scripts/release-notes.sh 2.0.0
set -eu
VERSION="${1:?usage: release-notes.sh VERSION}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
awk -v v="## $VERSION" '
    $0 == v { found = 1; next }
    found && /^## / { exit }
    found { print }
' "$ROOT/CHANGELOG.md" | sed '/./,$!d'
