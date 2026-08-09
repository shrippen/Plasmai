#!/bin/sh
# Send a desktop notification without exposing secrets on the command line.
#
# Usage: notify.sh "Summary" "Body text"
# Env:   KIMAI_NOTIFY_ICON (optional, defaults to chronometer)

set -eu

if ! command -v notify-send >/dev/null 2>&1; then
    exit 127
fi

summary=${1:-}
body=${2:-}
icon=${KIMAI_NOTIFY_ICON:-chronometer}

if [ -z "$summary" ]; then
    echo "usage: $0 summary [body]" >&2
    exit 64
fi

if [ -n "$body" ]; then
    exec notify-send "$summary" "$body" -i "$icon"
fi

exec notify-send "$summary" -i "$icon"
