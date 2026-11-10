#!/bin/sh
# Shared settings for all Plasmai plasmoid instances.
#
# Subcommands:
#   init  -> create the folder (SharedConfigWatch needs it to exist).
#   load  -> print shared JSON on stdout (exit 0). Exit 1 if missing.
#   store -> write JSON from $KIMAI_SHARED_JSON env var.
#   append <job>  -> append $KIMAI_SHARED_JSON to the part file of <job>.
#   commit <job>  -> move the part file of <job> into place.
# One argv string is limited to 128 KiB, so large JSON (film-day extras)
# is sent in chunks with append + commit.

set -eu

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DIR="$CONFIG_HOME/io.github.shrippen.Plasmai"
FILE="$DIR/shared.json"
# Up to 2.6.3 the folder had the old id's name. It is copied once, not moved: a widget or app
# of the old id still running keeps using it. The copy gets its name at the end, so nobody reads
# it half-way; when another process was first, its copy counts.
OLD_DIR="$CONFIG_HOME/com.github.shrippen.plasmai"
if [ ! -e "$DIR" ] && [ -d "$OLD_DIR" ]; then
    COPY="$DIR.copy.$$"
    mkdir -p "${DIR%/*}"
    if cp -R "$OLD_DIR" "$COPY" 2>/dev/null && [ ! -e "$DIR" ]; then
        mv "$COPY" "$DIR" 2>/dev/null || true
    fi
    rm -rf "$COPY" "$DIR/${COPY##*/}" 2>/dev/null || true
fi

case "${1:-}" in
    init)
        mkdir -p "$DIR"
        ;;
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
            # Parts of interrupted writes (plasmashell quit, a failed append); a
            # running write of the other client is younger than an hour.
            find "$DIR" -maxdepth 1 -name '.shared.*.part' -mmin +60 -delete 2>/dev/null || true
        fi
        ;;
    *)
        echo "usage: $0 {init|load|store|append <job>|commit <job>}" >&2
        exit 64
        ;;
esac
