#!/bin/sh
# Bump build, install plasmoid for current user, restart plasmashell.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$("$ROOT/scripts/bump-build.sh")"
VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json | head -n1)"

kpackagetool6 -t Plasma/Applet -u "$ROOT"

# Plasma sessions usually run `plasmashell --replace` outside
# plasma-plasmashell.service. Restarting that unit starts a second
# `--no-respawn` process that exits immediately and leaves the old shell
# (and its in-memory QML) running.
if command -v kquitapp6 >/dev/null 2>&1; then
    kquitapp6 plasmashell >/dev/null 2>&1 || true
fi
i=0
while pgrep -x plasmashell >/dev/null 2>&1 && [ "$i" -lt 20 ]; do
    sleep 0.25
    i=$((i + 1))
done
if pgrep -x plasmashell >/dev/null 2>&1; then
    killall plasmashell >/dev/null 2>&1 || true
    sleep 0.4
fi
nohup plasmashell --replace >/dev/null 2>&1 &

echo ""
echo "Plasmai ${VERSION} build ${BUILD} installed."
echo "Check: main view header shows Plasmai #${BUILD}"
