#!/bin/sh
# Print the CHANGELOG.md section of a version (release notes for Gitea and GitHub).
# The heading may be "## [X.Y.Z]", "## X.Y.Z" or "## vX.Y.Z", followed by a space or the end
# of the line (normally "## [X.Y.Z] — YYYY-MM-DD"). Prints nothing when there is no section.
# Usage: scripts/release-notes.sh 2.0.0
set -eu
VERSION="${1:?usage: release-notes.sh VERSION}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
awk -v v="$VERSION" '
    /^## / {
        if (found) exit
        h = substr($0, 4); sub(/^\[/, "", h); sub(/^v/, "", h)
        if (substr(h, 1, length(v)) == v) {
            rest = substr(h, length(v) + 1)
            if (rest == "" || rest ~ /^[] ]/) { found = 1; next }
        }
    }
    found { print }
' "$ROOT/CHANGELOG.md" | sed '/./,$!d'
