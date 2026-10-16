#!/usr/bin/env bash
# Run the date and time tests under many locales: 24- and 12-hour clocks,
# Latin and native digits, right-to-left scripts. Qt reads the locale from
# LC_ALL, no generated system locales needed.
# Usage: tests/locales.sh [locale ...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QMLTEST="${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
LOCALES=("$@")
if [[ ${#LOCALES[@]} -eq 0 ]]; then
    LOCALES=(de_DE en_US en_GB en_AU en_CA fr_FR fr_CA es_ES es_MX it_IT nl_NL pt_BR pl_PL
             sv_SE tr_TR el_GR uk_UA ru_RU ja_JP ko_KR zh_CN zh_TW ar_EG fa_IR he_IL
             hi_IN bn_BD th_TH)
fi
FILES=(tests/unit/tst_timeLocale.qml tests/unit/tst_appTimePicker.qml
       tests/unit/tst_dateTimeFormat.qml tests/unit/tst_kanteInputs.qml)

failed=()
for loc in "${LOCALES[@]}"; do
    for file in "${FILES[@]}"; do
        if ! LANG="$loc.UTF-8" LC_ALL="$loc.UTF-8" QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}" \
            "$QMLTEST" -input "$file" -silent >"${TMPDIR:-/tmp}/plasmai-locale.log" 2>&1; then
            grep -E "^(FAIL|   Actual|   Expected)" "${TMPDIR:-/tmp}/plasmai-locale.log" | sed "s/^/$loc: /"
            failed+=("$loc $(basename "$file")")
        fi
    done
done

if [[ ${#failed[@]} -gt 0 ]]; then
    printf 'failed: %s\n' "${failed[@]}" >&2
    exit 1
fi
echo "all ${#LOCALES[@]} locales pass"
