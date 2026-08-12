#!/bin/sh
# Extract translatable strings into translate/template.pot
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p translate

xgettext --from-code=UTF-8 -L JavaScript \
  --package-name="Plasmai" --package-version="1.3.1" \
  --msgid-bugs-address="https://github.com/shrippen/Plasmai/issues" \
  -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
  -o translate/template.pot \
  contents/ui/main.qml \
  contents/ui/ApiErrors.qml \
  contents/ui/ProjectActivityPickers.qml \
  contents/ui/SearchableCombo.qml \
  contents/ui/ActivityListRow.qml \
  contents/ui/ManualEntryView.qml \
  contents/ui/ActiveEditView.qml \
  contents/ui/StatsView.qml \
  contents/ui/BarChart.qml \
  contents/ui/StackedBarChart.qml \
  contents/ui/PieChart.qml \
  contents/ui/DateField.qml \
  contents/ui/TimeField.qml \
  contents/ui/DaySparkline.qml \
  contents/ui/config/ConfigConnection.qml \
  contents/ui/config/ConfigFavorites.qml \
  contents/ui/config/ConfigDisplay.qml \
  contents/ui/config/ConfigBehavior.qml \
  contents/ui/config/ConfigMaintenance.qml \
  contents/config/config.qml

echo "Wrote translate/template.pot"
