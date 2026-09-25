#!/bin/sh
# Extract translatable strings into translate/template.pot
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p translate

# All QML sources (Plasmoid, Plasma Mobile / Android app, vendored kirigami-addons)
# so new files with i18n() are not missed. Kirigami style overrides carry no strings.
find contents app/qml -name '*.qml' -not -path '*/kirigami-styles/*' -print0 | sort -z | xargs -0 \
xgettext --from-code=UTF-8 -L JavaScript \
  --package-name="Plasmai" --package-version="2.0.0" \
  --msgid-bugs-address="https://github.com/shrippen/Plasmai/issues" \
  -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 -ki18nd:2 -ki18ndc:3 \
  -o translate/template.pot

echo "Wrote translate/template.pot"
