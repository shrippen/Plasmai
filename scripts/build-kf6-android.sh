#!/usr/bin/env bash
# Build the KF6 prefix the Android app needs (app/CMakeLists.txt: `find_package(KF6 COMPONENTS
# Kirigami QUIET)` when cross-compiling) — extra-cmake-modules, KCoreAddons (a Kirigami
# dependency), and Kirigami itself, cross-compiled for android_arm64_v8a. Nothing else in KF6 is
# needed: the app links only against KF6::Kirigami.
#
# Usage: ./scripts/build-kf6-android.sh [prefix]
#   prefix defaults to $HOME/kf6-android (what scripts/build-android.sh and
#   .github/workflows/android.yml both expect). Safe to re-run — skips already-installed
#   modules unless -f/--force is passed.
#
# Needs: the Android NDK and Qt6-for-Android + Qt6 host tools already installed (see
# scripts/build-android.sh for how it installs both), and network access to invent.kde.org.
set -euo pipefail

FORCE=0
PREFIX="${1:-$HOME/kf6-android}"
if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--force" ]; then FORCE=1; PREFIX="${2:-$HOME/kf6-android}"; fi

KF6_VERSION="6.8.0"
SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
QT_VER="6.7.3"
QT_ANDROID="$HOME/Qt/$QT_VER/android_arm64_v8a"
QT_HOST="$HOME/Qt/$QT_VER/gcc_64"
ANDROID_PLATFORM_LEVEL="android-28"   # matches QT_ANDROID_MIN_SDK_VERSION in app/CMakeLists.txt

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NDK_PATH=$(ls -d "$SDK_ROOT"/ndk/28.* 2>/dev/null | head -1)
[ -d "$NDK_PATH" ] || error "Android NDK not found under $SDK_ROOT/ndk — run scripts/build-android.sh once first (it installs the NDK), or set ANDROID_SDK_ROOT"
[ -d "$QT_ANDROID" ] && [ -d "$QT_HOST" ] || error "Qt $QT_VER (android_arm64_v8a + gcc_64) not found under \$HOME/Qt — run scripts/build-android.sh once first (it installs Qt via aqtinstall)"

if [ -d "$PREFIX/lib/cmake/KF6Kirigami" ] && [ "$FORCE" -ne 1 ]; then
    info "$PREFIX already has KF6Kirigami — skipping (pass -f to rebuild)"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$PREFIX"

CROSS_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM="$ANDROID_PLATFORM_LEVEL"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="$QT_ANDROID;$PREFIX"
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
    -DQT_HOST_PATH="$QT_HOST"
    -DECM_DIR="$PREFIX/share/ECM/cmake"
    -DBUILD_TESTING=OFF -DBUILD_QCH=OFF
)

clone() {
    # frameworks/<repo> at tag v$KF6_VERSION, shallow.
    git clone --quiet --depth 1 --branch "v$KF6_VERSION" \
        "https://invent.kde.org/frameworks/$1.git" "$WORK/$1"
}

info "Cloning extra-cmake-modules, kcoreaddons, kirigami @ v$KF6_VERSION..."
clone extra-cmake-modules &
clone kcoreaddons &
clone kirigami &
wait

info "Building extra-cmake-modules (cmake modules only, no compilation)..."
cmake -B "$WORK/extra-cmake-modules/build" -S "$WORK/extra-cmake-modules" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF
cmake --build "$WORK/extra-cmake-modules/build" -j"$(nproc)"
cmake --install "$WORK/extra-cmake-modules/build"

info "Building KCoreAddons for android_arm64_v8a..."
cmake -B "$WORK/kcoreaddons/build" -S "$WORK/kcoreaddons" "${CROSS_ARGS[@]}"
cmake --build "$WORK/kcoreaddons/build" -j"$(nproc)"
cmake --install "$WORK/kcoreaddons/build"

info "Building Kirigami for android_arm64_v8a..."
cmake -B "$WORK/kirigami/build" -S "$WORK/kirigami" "${CROSS_ARGS[@]}" \
    -DBUILD_EXAMPLES=OFF -DDESKTOP_ENABLED=OFF
cmake --build "$WORK/kirigami/build" -j"$(nproc)"
cmake --install "$WORK/kirigami/build"

info "KF6 for Android ready at $PREFIX"
