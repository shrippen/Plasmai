#!/bin/sh
# Returns system idle time in milliseconds on stdout.
# Uses xprintidle when available (X11 / XWayland sessions).

set -eu

if command -v xprintidle >/dev/null 2>&1; then
    xprintidle
    exit 0
fi

echo "error: xprintidle is not installed" >&2
exit 127
