#!/usr/bin/env bash
# Build the Windows tray client (app/, ROADMAP pillar 7) and package it: an installer
# (Inno Setup, packaging/windows/plasmai.iss) and a zip of the same files.
#
# Runs in Git Bash on Windows with MSVC in the environment (vcvars), Qt 6 on PATH
# (windeployqt) and ECM, QtKeychain and Kirigami installed under $DEPS
# (release.yml, job "windows", builds them as checks.yml does).
#
# Usage: DEPS=<prefix> ./scripts/package-windows.sh
# Output: dist/windows/Plasmai-<version>-setup.exe, dist/windows/Plasmai-<version>-windows-x64.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${DEPS:?set DEPS to the prefix with ECM, QtKeychain and Kirigami}"

VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json | head -n1)"
[ -n "$VERSION" ] || { echo "error: could not read Version from metadata.json" >&2; exit 1; }

BUILD=build-windows
OUT=dist/windows
STAGE="$OUT/Plasmai"
rm -rf "$OUT"
mkdir -p "$STAGE"

cmake -S app -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$DEPS"
cmake --build "$BUILD"

cp "$BUILD/plasmai-app.exe" "$STAGE/"
# Qt, its QML modules and plugins. Kirigami's QML module comes from $DEPS (--qmlimport);
# windeployqt follows the imports of the app's QML and of the shared components.
windeployqt --release --no-translations --compiler-runtime \
    --qmldir app/qml --qmldir contents/ui --qmlimport "$DEPS/lib/qml" \
    "$STAGE/plasmai-app.exe"
# QtKeychain and Kirigami's libraries; Kirigami's QML module whole (its styles are loaded
# at run time, not imported, so windeployqt misses some of them).
cp "$DEPS"/bin/*.dll "$STAGE/"
mkdir -p "$STAGE/qml/org/kde"
cp -r "$DEPS/lib/qml/org/kde/kirigami" "$STAGE/qml/org/kde/"
cp LICENSE "$STAGE/LICENSE.txt"

# Zip: the same files, unpack anywhere and start plasmai-app.exe (settings and the token
# still live in the user's profile, not next to it).
(cd "$OUT" && 7z a -tzip -bso0 "Plasmai-${VERSION}-windows-x64.zip" Plasmai)

ISCC="${ISCC:-iscc}"
command -v "$ISCC" > /dev/null || ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
"$ISCC" //Q "//DAppVersion=$VERSION" "//DSourceDir=$(cygpath -w "$ROOT/$STAGE")" \
    "//DOutputDir=$(cygpath -w "$ROOT/$OUT")" packaging/windows/plasmai.iss

ls -l "$OUT"
