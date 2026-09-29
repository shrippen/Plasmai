#!/usr/bin/env bash
# Build the app's KDE and keychain dependencies into a prefix, for platforms without
# packages of them (Windows, macOS). CI: checks.yml (job "app"), release.yml (job "windows").
#
# Usage: ./scripts/build-deps.sh <prefix> [--kirigami]
#   ECM and QtKeychain always (app/CMakeLists.txt requires them); Kirigami with --kirigami
#   (the whole app; without it only the C++ side builds). Versions: KF_VERSION, QTKEYCHAIN_VERSION.
set -euo pipefail

PREFIX="$1"
KIRIGAMI="${2:-}"
KF_VERSION="${KF_VERSION:-6.30.0}"
QTKEYCHAIN_VERSION="${QTKEYCHAIN_VERSION:-0.15.0}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "v$KF_VERSION" https://invent.kde.org/frameworks/extra-cmake-modules.git "$WORK/ecm"
cmake -S "$WORK/ecm" -B "$WORK/ecm/build" -G Ninja -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_TESTING=OFF \
    -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF
cmake --install "$WORK/ecm/build"

git clone -q --depth 1 --branch "$QTKEYCHAIN_VERSION" https://github.com/frankosterfeld/qtkeychain.git "$WORK/qtkeychain"
cmake -S "$WORK/qtkeychain" -B "$WORK/qtkeychain/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_WITH_QT6=ON -DBUILD_TRANSLATIONS=OFF \
    -DBUILD_TEST_APPLICATION=OFF
cmake --build "$WORK/qtkeychain/build"
cmake --install "$WORK/qtkeychain/build"

if [ "$KIRIGAMI" = "--kirigami" ]; then
    git clone -q --depth 1 --branch "v$KF_VERSION" https://invent.kde.org/frameworks/kirigami.git "$WORK/kirigami"
    # Its KDevelop project templates are packed with tar, which on Windows (Git's GNU tar)
    # reads "C:" as a remote host; the app does not need them.
    : > "$WORK/kirigami/templates/CMakeLists.txt"
    cmake -S "$WORK/kirigami" -B "$WORK/kirigami/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF
    cmake --build "$WORK/kirigami/build"
    cmake --install "$WORK/kirigami/build"
fi
