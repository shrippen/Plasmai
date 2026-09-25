#!/usr/bin/env bash
# Plasmai app (Plasma Mobile / desktop Linux): install or update from the latest GitHub
# Release into the user's home. Not the Plasma Widget — see scripts/install-linux.sh for that.
#
#   curl -fsSL https://github.com/shrippen/Plasmai/releases/latest/download/install-app-linux.sh | bash
#
# Needs a system with a Qt6/KF6 Kirigami install already (true for any Plasma 6 desktop or
# Plasma Mobile device). Installs under ~/.local, no sudo.
set -Eeuo pipefail

REPO="${PLASMAI_REPO:-shrippen/Plasmai}"
PREFIX="${PLASMAI_INSTALL_PREFIX:-$HOME/.local}"
ARCH="$(uname -m)"

TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
TAG="${TAG##*/}"
VERSION="${TAG#v}"
[ -n "$VERSION" ] || { echo "error: could not determine the latest release" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FILE="$TMP/plasmai-app-${VERSION}-${ARCH}.tar.xz"

echo "Downloading Plasmai app ${VERSION} (${ARCH}) ..."
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/plasmai-app-${VERSION}-${ARCH}.tar.xz" -o "$FILE" \
    || { echo "error: no prebuilt tarball for ${ARCH} in release ${TAG} — build from source (see README.md)" >&2; exit 1; }

tar -C "$TMP" -xJf "$FILE"
SRC="$TMP/plasmai-app-${VERSION}"

mkdir -p "$PREFIX/bin" "$PREFIX/share/applications" "$PREFIX/share/metainfo" \
    "$PREFIX/share/icons/hicolor/256x256/apps" "$PREFIX/share/locale"
install -m755 "$SRC/bin/plasmai-app" "$PREFIX/bin/plasmai-app"
install -m644 "$SRC/share/icons/hicolor/256x256/apps/com.github.shrippen.plasmai.png" \
    "$PREFIX/share/icons/hicolor/256x256/apps/com.github.shrippen.plasmai.png"
install -m644 "$SRC/share/metainfo/com.github.shrippen.plasmai.metainfo.xml" \
    "$PREFIX/share/metainfo/com.github.shrippen.plasmai.metainfo.xml"
[ -d "$SRC/share/locale" ] && cp -a "$SRC/share/locale/." "$PREFIX/share/locale/"

# Point the launcher at the installed binary directly so it works even if $PREFIX/bin is not on PATH.
sed "s#^Exec=plasmai-app#Exec=$PREFIX/bin/plasmai-app#" \
    "$SRC/share/applications/com.github.shrippen.plasmai.desktop" \
    > "$PREFIX/share/applications/com.github.shrippen.plasmai.desktop"

command -v update-desktop-database >/dev/null && update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache "$PREFIX/share/icons/hicolor" 2>/dev/null || true

echo "Plasmai app ${VERSION} installed to $PREFIX."
echo "Launch from your app grid/launcher, or run: $PREFIX/bin/plasmai-app"
