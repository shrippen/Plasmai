#!/bin/sh
# Print system idle time in milliseconds on stdout.
#
# Wayland (Plasma 6 default): loginctl IdleSinceHint, then ScreenSaver D-Bus.
# X11: xprintidle. Do not prefer xprintidle when WAYLAND_DISPLAY is set —
# it only sees XWayland and is often stuck "idle".

set -eu

emit_ms() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) echo "$1"; return 0 ;;
    esac
}

idle_from_loginctl() {
    if ! command -v loginctl >/dev/null 2>&1; then
        return 1
    fi
    sid=${XDG_SESSION_ID:-}
    if [ -z "$sid" ]; then
        return 1
    fi
    hint=$(loginctl show-session "$sid" -p IdleHint --value 2>/dev/null || true)
    since=$(loginctl show-session "$sid" -p IdleSinceHint --value 2>/dev/null || true)
    if [ "$hint" != "yes" ] || [ -z "$since" ] || [ "$since" = "0" ]; then
        echo 0
        return 0
    fi
    now_s=$(date +%s)
    since_s=$((since / 1000000))
    idle_s=$((now_s - since_s))
    if [ "$idle_s" -lt 0 ]; then
        idle_s=0
    fi
    echo $((idle_s * 1000))
    return 0
}

idle_from_screensaver() {
    raw=""
    if command -v gdbus >/dev/null 2>&1; then
        raw=$(gdbus call --session \
            --dest org.freedesktop.ScreenSaver \
            --object-path /org/freedesktop/ScreenSaver \
            --method org.freedesktop.ScreenSaver.GetSessionIdleTime 2>/dev/null || true)
    elif command -v dbus-send >/dev/null 2>&1; then
        raw=$(dbus-send --session --print-reply \
            --dest=org.freedesktop.ScreenSaver \
            /org/freedesktop/ScreenSaver \
            org.freedesktop.ScreenSaver.GetSessionIdleTime 2>/dev/null || true)
    else
        return 1
    fi
    ms=$(printf '%s\n' "$raw" | awk '/uint32/ { gsub(/[^0-9]/, "", $NF); print $NF; exit }')
    emit_ms "$ms"
}

idle_from_xprintidle() {
    if ! command -v xprintidle >/dev/null 2>&1; then
        return 1
    fi
    out=$(xprintidle 2>/dev/null || true)
    emit_ms "$out"
}

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if idle_from_loginctl; then
        exit 0
    fi
    if idle_from_screensaver; then
        exit 0
    fi
    if idle_from_xprintidle; then
        exit 0
    fi
else
    if idle_from_xprintidle; then
        exit 0
    fi
    if idle_from_loginctl; then
        exit 0
    fi
    if idle_from_screensaver; then
        exit 0
    fi
fi

echo "error: no idle source (loginctl, ScreenSaver, or xprintidle)" >&2
exit 127
