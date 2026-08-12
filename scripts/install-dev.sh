#!/bin/sh
# Bump build, install plasmoid for current user, restart plasmashell.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$("$ROOT/scripts/bump-build.sh")"
VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json | head -n1)"

kpackagetool6 -t Plasma/Applet -u "$ROOT"
systemctl --user restart plasma-plasmashell

echo ""
echo "Plasmai ${VERSION} build ${BUILD} installed."
echo "Check: main view header shows Plasmai #${BUILD}"
