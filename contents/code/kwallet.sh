#!/bin/sh
# Manages Kimai API tokens in the Secret Service (KWallet on KDE).
#
# Subcommands:
#   load  [profileId] -> prints token (exit 0). Exit 1 if not present.
#   store [profileId] -> stores token from $KIMAI_TOKEN env var.
#   clear [profileId] -> removes stored token.
#
# Profile IDs map to secret-tool account names:
#   default / omitted -> api-token
#   other             -> api-token:<profileId>

set -eu

SERVICE="com.github.shrippen.plasmai"
LEGACY_SERVICE="org.arian.kimaitracker"
PROFILE_ID=${2:-default}

if [ "$PROFILE_ID" = "default" ]; then
    ACCOUNT="api-token"
    LABEL="Plasmai API token"
else
    ACCOUNT="api-token:${PROFILE_ID}"
    LABEL="Plasmai API token (${PROFILE_ID})"
fi

if ! command -v secret-tool >/dev/null 2>&1; then
    echo "error: secret-tool (libsecret) is not installed" >&2
    exit 127
fi

case "${1:-}" in
    load)
        if TOKEN=$(secret-tool lookup service "$SERVICE" account "$ACCOUNT" 2>/dev/null); then
            printf %s "$TOKEN"
            exit 0
        fi
        # Fall back to tokens stored by the previous plugin id.
        if TOKEN=$(secret-tool lookup service "$LEGACY_SERVICE" account "$ACCOUNT" 2>/dev/null); then
            printf %s "$TOKEN"
            # Best-effort migrate into the new service name.
            printf %s "$TOKEN" | secret-tool store \
                --label="$LABEL" \
                service "$SERVICE" \
                account "$ACCOUNT" >/dev/null 2>&1 || true
            exit 0
        fi
        exit 1
        ;;
    store)
        if [ -z "${KIMAI_TOKEN:-}" ]; then
            echo "error: KIMAI_TOKEN env var is empty" >&2
            exit 2
        fi
        printf %s "$KIMAI_TOKEN" | secret-tool store \
            --label="$LABEL" \
            service "$SERVICE" \
            account "$ACCOUNT"
        ;;
    clear)
        secret-tool clear service "$SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
        secret-tool clear service "$LEGACY_SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
        exit 0
        ;;
    *)
        echo "usage: $0 {load|store|clear} [profileId]" >&2
        exit 64
        ;;
esac
