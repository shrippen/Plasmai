#!/bin/sh
# Build a store.kde.org / kpackagetool6-ready .plasmoid archive.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json | head -n1)"
if [ -z "$VERSION" ]; then
    echo "error: could not read Version from metadata.json" >&2
    exit 1
fi

# Compile translations into contents/locale/
if [ -x "$ROOT/translate/build.sh" ]; then
    "$ROOT/translate/build.sh"
fi

mkdir -p "$ROOT/dist/plasmoid"
OUT="dist/plasmoid/Plasmai-${VERSION}.plasmoid"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/package"
cp metadata.json "$TMP/package/"
cp LICENSE README.md CHANGELOG.md "$TMP/package/" 2>/dev/null || true
cp -a contents "$TMP/package/"

# Ensure helper scripts are executable inside the archive.
chmod +x "$TMP/package"/contents/code/*.sh

# The demo (screenshots, testing) is internal: no demo code or data in published packages.
rm -f "$TMP/package/contents/code/demoKimai.js" "$TMP/package/contents/code/demoWorld.js" \
      "$TMP/package/contents/ui/DemoHook.qml" "$TMP/package/contents/ui/ScreenshotRunner.qml"
sed -i '/BEGIN internal demo/,/END internal demo/d' "$TMP/package/contents/ui/main.qml"
if grep -rlE 'demoKimai|demoWorld|DemoHook|ScreenshotRunner|demo\.invalid' "$TMP/package" >&2; then
    echo "error: the package still references the internal demo (files above)" >&2
    exit 1
fi

rm -f "$OUT"
(
    cd "$TMP/package"
    zip -r -q "$ROOT/$OUT" .
)

echo "Created $ROOT/$OUT"
echo "Install with: kpackagetool6 -i \"$ROOT/$OUT\" -t Plasma/Applet"
