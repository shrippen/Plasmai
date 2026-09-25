#!/bin/sh
# Shared settings for all Plasmai plasmoid instances.
#
# Subcommands:
#   load  -> print shared JSON on stdout (exit 0). Exit 1 if missing.
#   store -> write JSON from $KIMAI_SHARED_JSON env var.
#   append <job>  -> append $KIMAI_SHARED_JSON to the part file of <job>.
#   commit <job>  -> move the part file of <job> into place.
# One argv string is limited to 128 KiB, so large JSON (film-day extras)
# is sent in chunks with append + commit.

set -eu

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DIR="$CONFIG_HOME/com.github.shrippen.plasmai"
FILE="$DIR/shared.json"

case "${1:-}" in
    load)
        if [ ! -f "$FILE" ]; then
            exit 1
        fi
        exec cat "$FILE"
        ;;
    store)
        if [ -z "${KIMAI_SHARED_JSON:-}" ]; then
            echo "error: KIMAI_SHARED_JSON env var is empty" >&2
            exit 2
        fi
        mkdir -p "$DIR"
        # Unique temp file: parallel stores (widget + settings) must not
        # write into the same $FILE.tmp.
        TMP=$(mktemp "$DIR/.shared.json.XXXXXX")
        trap 'rm -f "$TMP"' EXIT
        printf %s "$KIMAI_SHARED_JSON" > "$TMP"
        mv "$TMP" "$FILE"
        trap - EXIT
        ;;
    append|commit)
        JOB=${2:-}
        case "$JOB" in
            ''|*[!A-Za-z0-9_-]*)
                echo "error: invalid job id" >&2
                exit 64
                ;;
        esac
        mkdir -p "$DIR"
        PART="$DIR/.shared.$JOB.part"
        if [ "$1" = "append" ]; then
            printf %s "${KIMAI_SHARED_JSON:-}" >> "$PART"
        else
            if [ ! -s "$PART" ]; then
                echo "error: nothing to commit" >&2
                exit 2
            fi
            mv "$PART" "$FILE"
        fi
        ;;
    *)
        echo "usage: $0 {load|store|append <job>|commit <job>}" >&2
        exit 64
        ;;
esac
