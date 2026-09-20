#!/usr/bin/env bash
# Plasmai: install or update the widget from the latest GitHub Release into the user's home.
#
#   curl -fsSL https://github.com/shrippen/Plasmai/releases/latest/download/install-linux.sh | bash
#
# Needs kpackagetool6 (part of KDE Plasma 6). Runs as your user, no sudo.
set -Eeuo pipefail

REPO="${PLASMAI_REPO:-shrippen/Plasmai}"
APPLET="com.github.shrippen.plasmai"

command -v kpackagetool6 >/dev/null || { echo "error: kpackagetool6 not found (KDE Plasma 6 required)" >&2; exit 1; }

# The /releases/latest URL redirects to the newest tag, so no API call or rate limit is involved.
TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
TAG="${TAG##*/}"
VERSION="${TAG#v}"
[ -n "$VERSION" ] || { echo "error: could not determine the latest release" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FILE="$TMP/Plasmai-${VERSION}.plasmoid"

echo "Downloading Plasmai ${VERSION} ..."
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/Plasmai-${VERSION}.plasmoid" -o "$FILE"

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$APPLET"; then
    kpackagetool6 -t Plasma/Applet -u "$FILE"
else
    kpackagetool6 -t Plasma/Applet -i "$FILE"
fi

echo "Plasmai ${VERSION} installed. Add it via right-click on the panel > Add Widgets."
echo "After an update, reload Plasma if needed: plasmashell --replace &"
