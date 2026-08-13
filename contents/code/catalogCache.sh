#!/bin/sh
# Disk cache for Kimai catalog + maintenance clash groups.
# Shared between plasmashell (widget) and the settings dialog process.
#
# Subcommands:
#   load  -> print JSON on stdout (exit 0). Exit 1 if missing.
#   store -> write JSON from $PLASMAI_CATALOG_JSON env var.

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
        printf %s "$PLASMAI_CATALOG_JSON" > "$FILE.tmp"
        mv "$FILE.tmp" "$FILE"
        ;;
    *)
        echo "usage: $0 {load|store}" >&2
        exit 64
        ;;
esac
