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

OUT="Plasmai-${VERSION}.plasmoid"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/package"
cp metadata.json "$TMP/package/"
cp LICENSE README.md CHANGELOG.md "$TMP/package/" 2>/dev/null || true
cp -a contents "$TMP/package/"

# Ensure helper scripts are executable inside the archive.
chmod +x "$TMP/package"/contents/code/*.sh

rm -f "$OUT"
(
    cd "$TMP/package"
    zip -r -q "$ROOT/$OUT" .
)

echo "Created $ROOT/$OUT"
echo "Install with: kpackagetool6 -i \"$OUT\" -t Plasma/Applet"
