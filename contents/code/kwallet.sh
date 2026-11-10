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
#
# PLASMAI_SECRET_SERVICE replaces the service name. Test and demo runs set it: an
# isolated XDG_CONFIG_HOME does not isolate the keychain, and a reset there
# (sharedConfig.js needsReset) would clear the real tokens.
#
# Up to 2.6.3 the service was OLD_SERVICE: a load that finds nothing takes the token from
# there, stores it under SERVICE and clears the old entry (a clear clears both, so a token not
# yet moved does not come back).

set -eu

SERVICE="${PLASMAI_SECRET_SERVICE:-io.github.shrippen.Plasmai}"
OLD_SERVICE="com.github.shrippen.plasmai"
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
        if [ -z "${PLASMAI_SECRET_SERVICE:-}" ] \
            && TOKEN=$(secret-tool lookup service "$OLD_SERVICE" account "$ACCOUNT" 2>/dev/null); then
            if printf %s "$TOKEN" | secret-tool store --label="$LABEL" \
                service "$SERVICE" account "$ACCOUNT" 2>/dev/null; then
                secret-tool clear service "$OLD_SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
            fi
            printf %s "$TOKEN"
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
        if [ -z "${PLASMAI_SECRET_SERVICE:-}" ]; then
            secret-tool clear service "$OLD_SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
        fi
        secret-tool clear service "$SERVICE" account "$ACCOUNT" >/dev/null 2>&1 || true
        exit 0
        ;;
    *)
        echo "usage: $0 {load|store|clear} [profileId]" >&2
        exit 64
        ;;
esac
