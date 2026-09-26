#!/usr/bin/env bash
# Copies the Kante QML module from the design system repo into the widget.
#
#   contents/ui/Kante        KanteStyle, wrappers, skins, fonts (also the app's, via qrc)
#   contents/ui/KantePlasma  the PlasmaComponents3 wrappers of the widget
#
# Source: KANTE_DS, default ../shrippen.github.io (https://github.com/shrippen/shrippen.github.io).
# The copies are not edited here; change the design system and sync again.
set -euo pipefail
cd "$(dirname "$0")/.."

DS="${KANTE_DS:-../shrippen.github.io}"
if [ ! -f "$DS/qml/Kante/qmldir" ]; then
    echo "sync-kante: no Kante module in $DS/qml (set KANTE_DS)" >&2
    exit 1
fi

for module in Kante KantePlasma; do
    rm -rf "contents/ui/$module"
    cp -r "$DS/qml/$module" "contents/ui/$module"
done

echo "sync-kante: $(git -C "$DS" describe --always --dirty 2>/dev/null || echo unknown) -> contents/ui/Kante, contents/ui/KantePlasma"
