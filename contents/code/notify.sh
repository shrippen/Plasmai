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

# "--" ends option parsing: a summary/body starting with "-" (e.g. a
# description like "-fix") must not be read as a notify-send option.
if [ -n "$body" ]; then
    exec notify-send -i "$icon" -- "$summary" "$body"
fi

exec notify-send -i "$icon" -- "$summary"
