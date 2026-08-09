#!/bin/sh
# Shared settings for all Plasmai plasmoid instances.
#
# Subcommands:
#   load  -> print shared JSON on stdout (exit 0). Exit 1 if missing.
#   store -> write JSON from $KIMAI_SHARED_JSON env var.

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
        printf %s "$KIMAI_SHARED_JSON" > "$FILE.tmp"
        mv "$FILE.tmp" "$FILE"
        ;;
    *)
        echo "usage: $0 {load|store}" >&2
        exit 64
        ;;
esac
