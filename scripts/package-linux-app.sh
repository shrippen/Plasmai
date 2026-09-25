#!/usr/bin/env bash
# Build the Plasma Mobile / desktop-Linux Plasmai app (app/, KF6 Kirigami) and package it as a
# tarball for distribution outside a distro package or Flatpak (packaging/flatpak/ has that).
#
# This links against the *system* Qt6/KF6 — it is not a self-contained bundle like an AppImage.
# It only runs on a system with a compatible Qt6/KF6 already installed (true by construction for
# any Plasma 6 desktop or Plasma Mobile device — that is what the Plasmoid targets too).
#
# Usage: ./scripts/package-linux-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json | head -n1)"
[ -n "$VERSION" ] || { echo "error: could not read Version from metadata.json" >&2; exit 1; }

./scripts/build-desktop.sh --rebuild

ARCH="$(uname -m)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

install -Dm755 app/build/plasmai-app "$STAGE/plasmai-app-${VERSION}/bin/plasmai-app"
install -Dm644 packaging/linux/com.github.shrippen.plasmai.desktop \
    "$STAGE/plasmai-app-${VERSION}/share/applications/com.github.shrippen.plasmai.desktop"
install -Dm644 packaging/linux/com.github.shrippen.plasmai.metainfo.xml \
    "$STAGE/plasmai-app-${VERSION}/share/metainfo/com.github.shrippen.plasmai.metainfo.xml"
install -Dm644 packaging/linux/com.github.shrippen.plasmai.png \
    "$STAGE/plasmai-app-${VERSION}/share/icons/hicolor/256x256/apps/com.github.shrippen.plasmai.png"
cp -a app/build/locale "$STAGE/plasmai-app-${VERSION}/share/locale" 2>/dev/null || true
install -Dm644 LICENSE "$STAGE/plasmai-app-${VERSION}/LICENSE" 2>/dev/null || true

mkdir -p dist/linux
OUT="dist/linux/plasmai-app-${VERSION}-${ARCH}.tar.xz"
rm -f "$OUT"
tar -C "$STAGE" -cJf "$OUT" "plasmai-app-${VERSION}"

echo "Created $ROOT/$OUT"
echo "Install with: ./scripts/install-app-linux.sh (from a checkout) or the one-liner in packaging/linux/README.md"
