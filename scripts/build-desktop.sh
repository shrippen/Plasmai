#!/usr/bin/env bash
# Configure and build the desktop-Linux Kirigami app.
# Usage: ./scripts/build-desktop.sh [--rebuild]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/app/build"

if [ "${1:-}" = "--rebuild" ]; then
    rm -rf "$BUILD_DIR"
fi

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    cmake -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release "$ROOT/app"
fi

cmake --build "$BUILD_DIR" -j"$(nproc)"

echo ""
echo "Built: $BUILD_DIR/plasmai-app"
