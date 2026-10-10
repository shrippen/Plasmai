#!/usr/bin/env bash
# qmllint over the widget's QML (contents/ui), as the CI runs it. Exit 1 on any finding.
# Every finding as JSON: scripts/qmllint.sh --json -
#
# Off, on purpose:
#   unqualified                  the plasmoid object, i18n and the parent scope are context
#                                properties by design
#   missing-property             properties typed var / Item hide the real type
#   block-scope-var-declaration  Qt 6.12 reports every `var` in a block (about 200). Working code;
#                                switch file by file with a check (agent.md, "QML lint").
# Singletons (`pragma Singleton`) run in a second pass without the import check: Qt 6.12 reports
# each as "not declared as singleton in qmldir", even in a minimal correct module.
# The app's pages resolve only through its qrc and are not linted here.
set -uo pipefail
cd "$(dirname "$0")/.."
QMLLINT=/usr/lib/qt6/bin/qmllint
[ -x "$QMLLINT" ] || QMLLINT=$(command -v qmllint6 || command -v qmllint)
Q=("$QMLLINT" --unqualified disable --missing-property disable --block-scope-var-declaration disable
   --max-warnings 0 -I contents/ui "$@")
mapfile -t files < <(find contents/ui -name '*.qml' | sort)
mapfile -t singletons < <(grep -l '^pragma Singleton' "${files[@]}")
mapfile -t others < <(grep -L '^pragma Singleton' "${files[@]}")
rc=0
"${Q[@]}" "${others[@]}" || rc=1
"${Q[@]}" --import disable "${singletons[@]}" || rc=1
[ $rc = 0 ] && echo "qmllint: no findings"
exit $rc
