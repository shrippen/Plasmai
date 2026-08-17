#!/usr/bin/env bash
# Run Plasmai unit tests (qmltestrunner) and plasmoidviewer click sweeps (pytest).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QMLTEST="${QMLTESTRUNNER:-}"
if [[ -z "$QMLTEST" ]]; then
    if [[ -x /usr/lib/qt6/bin/qmltestrunner ]]; then
        QMLTEST=/usr/lib/qt6/bin/qmltestrunner
    elif command -v qmltestrunner-qt6 >/dev/null 2>&1; then
        QMLTEST="$(command -v qmltestrunner-qt6)"
    elif command -v qmltestrunner >/dev/null 2>&1; then
        QMLTEST="$(command -v qmltestrunner)"
    else
        echo "qmltestrunner not found (install qt6-declarative)" >&2
        exit 1
    fi
fi

echo "==> QML unit tests ($QMLTEST)"
# Offscreen is enough for .js TestCase files; do not leak this into pytest/viewer.
QML_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
QT_QPA_PLATFORM="$QML_PLATFORM" "$QMLTEST" -input "$ROOT/tests/unit"

echo "==> pytest (log classifier + plasmoidviewer clicks)"
# Viewer tests need a real display.
unset QT_QPA_PLATFORM || true
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "warning: no DISPLAY/WAYLAND_DISPLAY — viewer tests will skip" >&2
fi
PYTEST=(python -m pytest "$ROOT/tests" -q)
if [[ "${1:-}" == "unit" ]]; then
    PYTEST=(python -m pytest "$ROOT/tests/viewer/test_error_classifier.py" "$ROOT/tests/viewer/test_deny_list.py" -q)
elif [[ "${1:-}" != "all" && "${1:-}" != "shell" ]]; then
    PYTEST+=(-m "not shell")
fi
"${PYTEST[@]}"
