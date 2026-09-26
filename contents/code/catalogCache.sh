#!/bin/sh
# Disk cache for the Kimai catalog.
# Shared between plasmashell (widget) and the settings dialog process.
#
# Subcommands:
#   load  -> print JSON on stdout (exit 0). Exit 1 if missing.
#   store -> write JSON from $PLASMAI_CATALOG_JSON env var.
#   append <job>  -> append $PLASMAI_CATALOG_JSON to the part file of <job>.
#   commit <job>  -> move the part file of <job> into place.
# A shell command line is limited to 128 KiB (one argv string), so large
# catalogs are sent in chunks with append + commit.

set -eu

CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
DIR="$CACHE_HOME/com.github.shrippen.plasmai"
FILE="$DIR/catalog-cache.json"

case "${1:-}" in
    load)
        if [ ! -f "$FILE" ]; then
            exit 1
        fi
        exec cat "$FILE"
        ;;
    store)
        if [ -z "${PLASMAI_CATALOG_JSON:-}" ]; then
            echo "error: PLASMAI_CATALOG_JSON env var is empty" >&2
            exit 2
        fi
        mkdir -p "$DIR"
        TMP=$(mktemp "$DIR/.catalog-cache.json.XXXXXX")
        trap 'rm -f "$TMP"' EXIT
        printf %s "$PLASMAI_CATALOG_JSON" > "$TMP"
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
        PART="$DIR/.catalog-cache.$JOB.part"
        if [ "$1" = "append" ]; then
            printf %s "${PLASMAI_CATALOG_JSON:-}" >> "$PART"
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
