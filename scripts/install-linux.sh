#!/usr/bin/env bash
# Plasmai: install or update the widget from the latest GitHub Release into the user's home.
#
#   curl -fsSL https://github.com/shrippen/Plasmai/releases/latest/download/install-linux.sh | bash
#
# Needs kpackagetool6 (part of KDE Plasma 6). Runs as your user, no sudo.
set -Eeuo pipefail

REPO="${PLASMAI_REPO:-shrippen/Plasmai}"
APPLET="io.github.shrippen.Plasmai"

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

if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$APPLET"; then
    kpackagetool6 -t Plasma/Applet -u "$FILE"
else
    kpackagetool6 -t Plasma/Applet -i "$FILE"
fi

# Up to 2.6.3 the widget had the id OLD_APPLET. Plasma knows no renaming: each placed widget of
# the old id is replaced by one of the new id in the same place, with its settings, and the old
# package goes once no widget uses it. Without a running Plasma it stays (its widgets would
# break), and the next run of this script moves them.
OLD_APPLET="com.github.shrippen.plasmai"
plasma_script() {
    local q
    for q in qdbus6 qdbus-qt6 qdbus; do
        if command -v "$q" >/dev/null; then
            "$q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
            return
        fi
    done
    return 1
}
if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -qx "$OLD_APPLET"; then
    # BEGIN widget-move (tests/test_app_id.py runs this part)
    MOVE_SCRIPT=$(cat <<'JS'
const OLD = "com.github.shrippen.plasmai";
const NEW = "io.github.shrippen.Plasmai";
let moved = 0;
let left = 0;
function copyConfig(from, to, path) {
    from.currentConfigGroup = path;
    to.currentConfigGroup = path;
    const keys = from.configKeys;
    const groups = from.configGroups;
    for (let i = 0; i < keys.length; ++i) {
        to.writeConfig(keys[i], from.readConfig(keys[i]));
    }
    for (let i = 0; i < groups.length; ++i) {
        copyConfig(from, to, path.concat([groups[i]]));
        from.currentConfigGroup = path;
        to.currentConfigGroup = path;
    }
}
const inPanels = panels();
const containments = inPanels.concat(desktops());
for (let c = 0; c < containments.length; ++c) {
    const box = containments[c];
    const old = box.widgets(OLD);
    for (let i = 0; i < old.length; ++i) {
        const g = old[i].geometry;
        const index = old[i].index;
        const added = box.addWidget(NEW, g.x, g.y, g.width, g.height);
        if (!added || added.type !== NEW) {
            ++left;
            continue;
        }
        copyConfig(old[i], added, []);
        added.globalShortcut = old[i].globalShortcut;
        if (c < inPanels.length) {
            added.index = index;
        }
        added.reloadConfig();
        old[i].remove();
        ++moved;
    }
}
print("moved " + moved + " left " + left);
JS
)
    # END widget-move
    if RESULT=$(plasma_script "$MOVE_SCRIPT" 2>/dev/null) && [[ "$RESULT" == *" left 0" ]]; then
        [[ "$RESULT" == "moved 0 left 0" ]] || echo "Widgets moved to the new id (${RESULT% left 0})."
        kpackagetool6 -t Plasma/Applet -r "$OLD_APPLET" >/dev/null
    else
        echo "note: the widget of the old id stays until Plasma runs; run this script again then." >&2
    fi
fi

echo "Plasmai ${VERSION} installed. Add it via right-click on the panel > Add Widgets."
echo "After an update, reload Plasma if needed: plasmashell --replace &"
