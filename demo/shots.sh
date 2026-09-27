#!/usr/bin/env bash
# Landing-page screenshots of the widget with the demo profile, for
# shrippen.github.io/tools/screenshots.py (demo/shots.json). Renders offscreen; the plan in
# screenshots.json is picked up by contents/ui/ScreenshotRunner.qml. Output: $SHOT_DIR/<name>.png
set -euo pipefail
source "$(dirname "$0")/common.sh"
OUT="${SHOT_DIR:-${ROOT}/build/demo-shots}"
mkdir -p "${OUT}"
python3 - "${OUT}" "${ROOT}/demo/shots.json" > "${CONFIG}/com.github.shrippen.plasmai/screenshots.json" <<'PY'
import json, sys
shots = json.load(open(sys.argv[2]))["shots"]
print(json.dumps({"dir": sys.argv[1], "shots": [{"name": s["name"], "view": s.get("view", "main")} for s in shots]}))
PY
cat > "${WORK}/screens.json" <<'JSON'
{ "screens": [ { "name": "shot", "x": 0, "y": 0, "width": 1920, "height": 1200,
                 "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1 } ] }
JSON
LOG="${WORK}/viewer.log"
rc=0
XDG_CONFIG_HOME="${CONFIG}" LANGUAGE="${LANG_}" LANG="${LOCALE}" LC_MESSAGES="${LOCALE}" \
QT_QPA_PLATFORM="offscreen:configfile=${WORK}/screens.json" QT_QPA_PLATFORMTHEME=kde QT_SCALE_FACTOR=2 \
QT_LOGGING_TO_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 \
timeout --signal=TERM --kill-after=3 180s \
    plasmoidviewer -a "${ROOT}" -f horizontal -l bottomedge -s 900x60 >"${LOG}" 2>&1 || rc=$?
grep -o "PLASMAI_SCREENSHOT.*" "${LOG}" || true
if ! grep -q "PLASMAI_SCREENSHOT_DONE" "${LOG}"; then
    echo "Screenshot run did not finish (exit ${rc}). Log:"
    tail -40 "${LOG}"
    exit 1
fi
