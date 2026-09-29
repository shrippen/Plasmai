#!/bin/sh
# The Plasmoid's own files (offline snapshot and outbox), not shared with the app.
# Data, not cache: an outbox holds changes not yet on the server.
#
# Subcommands (NAME: letters, digits, "_", "-", "."):
#   load NAME          -> print JSON on stdout (exit 0). Exit 1 if missing.
#   store NAME         -> write JSON from $PLASMAI_LOCAL_JSON.
#   append NAME <job>  -> append $PLASMAI_LOCAL_JSON to the part file of <job>.
#   commit NAME <job>  -> move the part file of <job> into place.
# A shell command line is limited to 128 KiB (one argv string), so large
# files are sent in chunks with append + commit (as in catalogCache.sh).

set -eu
umask 077

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DIR="$DATA_HOME/com.github.shrippen.plasmai/plasmoid"

valid() {
    case "$1" in
        ''|*[!A-Za-z0-9_.-]*|.*)
            echo "error: invalid name" >&2
            exit 64
            ;;
    esac
}

CMD=${1:-}
NAME=${2:-}
valid "$NAME"
FILE="$DIR/$NAME.json"

case "$CMD" in
    load)
        if [ ! -f "$FILE" ]; then
            exit 1
        fi
        exec cat "$FILE"
        ;;
    store)
        if [ -z "${PLASMAI_LOCAL_JSON:-}" ]; then
            echo "error: PLASMAI_LOCAL_JSON env var is empty" >&2
            exit 2
        fi
        mkdir -p "$DIR"
        TMP=$(mktemp "$DIR/.$NAME.json.XXXXXX")
        trap 'rm -f "$TMP"' EXIT
        printf %s "$PLASMAI_LOCAL_JSON" > "$TMP"
        mv "$TMP" "$FILE"
        trap - EXIT
        ;;
    append|commit)
        JOB=${3:-}
        valid "$JOB"
        mkdir -p "$DIR"
        PART="$DIR/.$NAME.$JOB.part"
        if [ "$CMD" = "append" ]; then
            printf %s "${PLASMAI_LOCAL_JSON:-}" >> "$PART"
        else
            if [ ! -s "$PART" ]; then
                echo "error: nothing to commit" >&2
                exit 2
            fi
            mv "$PART" "$FILE"
        fi
        ;;
    *)
        echo "usage: $0 {load NAME|store NAME|append NAME <job>|commit NAME <job>}" >&2
        exit 64
        ;;
esac
