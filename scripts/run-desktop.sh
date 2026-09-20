#!/usr/bin/env bash
# Build (if needed) and launch the desktop-Linux Kirigami app.
# Usage: ./scripts/run-desktop.sh [--rebuild]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build-desktop.sh" "${1:-}"

exec "$ROOT/app/build/plasmai-app"
