#!/usr/bin/env bash
# Benchmark of the widget in plasmoidviewer with the demo profile (contents/ui/BenchRunner.qml).
#   demo/bench.sh [-n RUNS] [--save FILE] [--compare FILE]
# Each run starts a fresh viewer; the table shows the median of all runs and rounds.
# --save writes the medians as JSON, --compare prints them next to a saved file.
# Needs a display (the popup must really draw; QPA defaults to xcb, BENCH_QPA overrides).
set -euo pipefail
RUNS=3
SAVE=""
COMPARE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) RUNS=$2; shift 2 ;;
        --save) SAVE=$2; shift 2 ;;
        --compare) COMPARE=$2; shift 2 ;;
        *) echo "usage: $0 [-n RUNS] [--save FILE] [--compare FILE]" >&2; exit 64 ;;
    esac
done
source "$(dirname "$0")/common.sh"
echo '{ "rounds": 3 }' > "${CONFIG}/io.github.shrippen.Plasmai/bench.json"
LINES="${WORK}/bench.jsonl"
: > "${LINES}"
for ((run = 1; run <= RUNS; run++)); do
    LOG="${WORK}/viewer-${run}.log"
    # A fresh offline snapshot each run: the first run must not warm the next.
    rm -rf "${WORK}/data-home"
    rc=0
    XDG_CONFIG_HOME="${CONFIG}" XDG_DATA_HOME="${WORK}/data-home" LANGUAGE=en LANG=C.UTF-8 \
    QT_QPA_PLATFORM="${BENCH_QPA:-xcb}" QT_LOGGING_TO_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout --signal=TERM --kill-after=3 240s \
        plasmoidviewer -a "${ROOT}" -f horizontal -l bottomedge -s 900x60 >"${LOG}" 2>&1 || rc=$?
    if ! grep -q "PLASMAI_BENCH_DONE" "${LOG}"; then
        echo "run ${run} did not finish (exit ${rc}). Log:" >&2
        tail -30 "${LOG}" >&2
        exit 1
    fi
    grep -o 'PLASMAI_BENCH {.*}' "${LOG}" | sed 's/^PLASMAI_BENCH //' >> "${LINES}"
    echo "run ${run}/${RUNS} done" >&2
done
python3 "${ROOT}/demo/bench-report.py" "${LINES}" "${SAVE}" "${COMPARE}"
