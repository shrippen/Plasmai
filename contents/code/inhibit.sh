#!/bin/sh
# Shutdown inhibitor for Plasmai.
#
# hold [why]   Foreground: block poweroff/reboot/halt only (not sleep or lid).
# preparing    Print 1 if logind is preparing shutdown, else 0.
#
# --what=shutdown does not include sleep or handle-lid-switch.

set -eu

cmd=${1:-}

emit_preparing_from_raw() {
    case "$1" in
        *true*) echo 1; return 0 ;;
        *false*) echo 0; return 0 ;;
    esac
    return 1
}

preparing_from_busctl() {
    if ! command -v busctl >/dev/null 2>&1; then
        return 1
    fi
    raw=$(busctl --system get-property org.freedesktop.login1 \
        /org/freedesktop/login1 org.freedesktop.login1.Manager PreparingForShutdown 2>/dev/null || true)
    emit_preparing_from_raw "$raw"
}

preparing_from_gdbus() {
    if ! command -v gdbus >/dev/null 2>&1; then
        return 1
    fi
    raw=$(gdbus call --system --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1 \
        --method org.freedesktop.DBus.Properties.Get \
        org.freedesktop.login1.Manager PreparingForShutdown 2>/dev/null || true)
    emit_preparing_from_raw "$raw"
}

if [ "$cmd" = "preparing" ]; then
    if preparing_from_busctl; then
        exit 0
    fi
    if preparing_from_gdbus; then
        exit 0
    fi
    echo 0
    exit 0
fi

if [ "$cmd" = "hold" ]; then
    why=${2:-A timer is still running}
    if command -v systemd-inhibit >/dev/null 2>&1; then
        exec systemd-inhibit --what=shutdown --mode=block --who=Plasmai --why="$why" sleep infinity
    fi
    # No inhibitor available; stay attached so QML does not reconnect-loop.
    exec sleep infinity
fi

echo "usage: $0 hold [why] | preparing" >&2
exit 64
