#!/usr/bin/env bash
# Benchmark of the app with the demo profile (app/qml/BenchRunner.qml), on one target:
#   demo/bench-app.sh desktop --app BUILD/plasmai-app           [-n RUNS] [--save F] [--compare F]
#   demo/bench-app.sh flatpak --flatpak BUILD_DIR --manifest M  [-n RUNS] [--save F] [--compare F]
#   demo/bench-app.sh android --apk FILE                        [-n RUNS] [--save F] [--compare F]
# The build must have the demo (-DPLASMAI_DEMO=ON). Each run starts the app fresh with empty
# settings; the table is the median of all runs (demo/bench-report.py, as for the widget).
#   desktop  own XDG folders, so your settings stay untouched (QPA: BENCH_QPA, default xcb)
#   flatpak  flatpak-builder --run in the build folder: nothing is installed, own folders per run;
#            Wayland (the build sandbox has no X11)
#   android  installs the APK (a debug build is its own app, ".dev") and clears its data
#            before each run; back up that app's data first if it holds any
set -euo pipefail
TARGET=${1:?usage: $0 desktop|flatpak|android ...}
shift
RUNS=3
SAVE=""
COMPARE=""
APP=""
FLATPAK_DIR=""
MANIFEST=""
APK=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) RUNS=$2; shift 2 ;;
        --save) SAVE=$2; shift 2 ;;
        --compare) COMPARE=$2; shift 2 ;;
        --app) APP=$2; shift 2 ;;
        --flatpak) FLATPAK_DIR=$2; shift 2 ;;
        --manifest) MANIFEST=$2; shift 2 ;;
        --apk) APK=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 64 ;;
    esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/plasmai-bench-app-XXXXXX")"
cleanup() {
    # flatpak-builder stopped by the time limit leaves its rofiles mounts behind.
    local m
    for m in $(awk -v w="${WORK}" 'index($2, w) == 1 {print $2}' /proc/mounts); do
        fusermount3 -u "${m}" 2>/dev/null || fusermount -u "${m}" 2>/dev/null || true
    done
    # Deleting through a mount that is still there deletes the build folder behind it.
    if awk -v w="${WORK}" 'index($2, w) == 1 {found = 1} END {exit !found}' /proc/mounts; then
        echo "still mounted under ${WORK}: left in place" >&2
        return
    fi
    rm -rf "${WORK}"
}
trap cleanup EXIT
LINES="${WORK}/bench.jsonl"
: > "${LINES}"
# Generous: a run takes about three minutes on the desktop, more on a phone or in the Flatpak
# build sandbox (BENCH_LIMIT_S overrides it).
LIMIT_S=${BENCH_LIMIT_S:-600}
ANDROID_ACTIVITY="org.qtproject.qt.android.bindings.QtActivity"

run_desktop() {
    local log=$1 home="${WORK}/home"
    rm -rf "${home}"
    mkdir -p "${home}/config" "${home}/data" "${home}/cache"
    cp -p "${XDG_CONFIG_HOME:-${HOME}/.config}/kdeglobals" "${home}/config/" 2>/dev/null || true
    XDG_CONFIG_HOME="${home}/config" XDG_DATA_HOME="${home}/data" XDG_CACHE_HOME="${home}/cache" \
    PLASMAI_BENCH=1 LANGUAGE=en QT_QPA_PLATFORM="${BENCH_QPA:-xcb}" \
    QT_LOGGING_TO_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 \
        timeout "${LIMIT_S}" "${APP}" >"${log}" 2>&1 || true
}

run_flatpak() {
    local log=$1 run=$2
    # Fresh folders per run inside the sandbox, not the app's ~/.var/app/<id> (your settings).
    local home="/tmp/plasmai-bench-$$-${run}"
    timeout "${LIMIT_S}" flatpak-builder --state-dir="${WORK}/flatpak-state-${run}" --run "${FLATPAK_DIR}" "${MANIFEST}" \
        env WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" QT_QPA_PLATFORM="${BENCH_QPA:-wayland}" \
        XDG_CONFIG_HOME="${home}/config" XDG_DATA_HOME="${home}/data" XDG_CACHE_HOME="${home}/cache" \
        LANGUAGE=en plasmai-app --bench >"${log}" 2>&1 || true
}

run_android() {
    local log=$1 pkg=$2
    adb shell pm clear "${pkg}" >/dev/null
    # Cleared data asks for notifications again: the system dialog would hold the start up.
    adb shell pm grant "${pkg}" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
    adb logcat -c
    adb shell am start -W -n "${pkg}/${ANDROID_ACTIVITY}" -e applicationArguments --bench >/dev/null
    local waited=0
    until adb logcat -d | grep -q PLASMAI_BENCH_DONE; do
        sleep 5
        waited=$((waited + 5))
        [[ ${waited} -lt ${LIMIT_S} ]] || break
    done
    adb logcat -d > "${log}"
    adb shell am force-stop "${pkg}"
}

PKG=""
case "${TARGET}" in
    desktop) [[ -x "${APP}" ]] || { echo "--app: no executable ${APP}" >&2; exit 64; } ;;
    flatpak) [[ -d "${FLATPAK_DIR}" && -f "${MANIFEST}" ]] || { echo "--flatpak and --manifest needed" >&2; exit 64; } ;;
    android)
        [[ -f "${APK}" ]] || { echo "--apk: no file ${APK}" >&2; exit 64; }
        # The newest build-tools (several may be installed).
        AAPT2=$(ls -d "${ANDROID_SDK_ROOT:-${HOME}/android-sdk}"/build-tools/*/ | sort -V | tail -1)aapt2
        PKG=$("${AAPT2}" dump packagename "${APK}" 2>/dev/null | head -1 || true)
        [[ -n "${PKG}" ]] || { echo "cannot read the package name of ${APK}" >&2; exit 1; }
        adb install -r "${APK}" >/dev/null
        echo "installed ${PKG} on $(adb shell getprop ro.product.model)" >&2
        ;;
    *) echo "unknown target ${TARGET}" >&2; exit 64 ;;
esac

for ((run = 1; run <= RUNS; run++)); do
    LOG="${WORK}/run-${run}.log"
    case "${TARGET}" in
        desktop) run_desktop "${LOG}" ;;
        flatpak) run_flatpak "${LOG}" "${run}" ;;
        android) run_android "${LOG}" "${PKG}" ;;
    esac
    if ! grep -q "PLASMAI_BENCH_DONE" "${LOG}"; then
        echo "run ${run} did not finish. Log:" >&2
        grep -vE "^\s*$" "${LOG}" | tail -30 >&2
        exit 1
    fi
    if grep -E "TypeError|ReferenceError|is not defined|is not a type|failed to load" "${LOG}" >&2; then
        echo "run ${run}: QML errors (above)" >&2
    fi
    grep -o 'PLASMAI_BENCH {.*}' "${LOG}" | sed 's/^PLASMAI_BENCH //' >> "${LINES}"
    echo "run ${run}/${RUNS} done" >&2
done
python3 "${ROOT}/demo/bench-report.py" "${LINES}" "${SAVE}" "${COMPARE}"
