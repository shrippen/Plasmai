#!/usr/bin/env bash
# Build Plasmai APK — Host build with aqtinstall + Android NDK.
# Usage: ./scripts/build-android.sh [debug|release]
set -euo pipefail
MODE="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_DIR/app"
SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
NDK_DIR="$SDK_ROOT/ndk"
QT_VER="6.7.3"
QT_ANDROID="$HOME/Qt/$QT_VER/android_arm64_v8a"
QT_HOST="$HOME/Qt/$QT_VER/gcc_64"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. NDK ──
NDK_PATH=$(ls -d "$NDK_DIR"/28.* 2>/dev/null | head -1)
if [ ! -d "$NDK_PATH" ]; then
    info "Installing Android NDK r28..."
    mkdir -p "$SDK_ROOT/cmdline-tools"
    if [ ! -f "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
        TMP=$(mktemp /tmp/cmdtools.zip)
        curl -sL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$TMP"
        unzip -qo "$TMP" -d "$SDK_ROOT/cmdline-tools/"
        mv "$SDK_ROOT/cmdline-tools/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest" 2>/dev/null || true
        rm -f "$TMP"
    fi
    yes | "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK_ROOT" "ndk;28.2.13676358" 2>&1 | tail -3
fi
NDK_PATH=$(ls -d "$NDK_DIR"/28.* 2>/dev/null | head -1)
[ -d "$NDK_PATH" ] || error "NDK not found"
info "NDK: $NDK_PATH"

# ── 2. Qt6 Host + Android ──
[ -d "$QT_ANDROID" ] || {
    info "Installing aqtinstall..."
    pip install --user --break-system-packages aqtinstall 2>/dev/null || true
    export PATH="$HOME/.local/bin:$PATH"
    info "Downloading Qt $QT_VER for Android..."
    aqt install-qt linux android "$QT_VER" android_arm64_v8a -O "$HOME/Qt" 2>&1 | tail -3
    info "Downloading Qt $QT_VER host tools..."
    aqt install-qt linux desktop "$QT_VER" linux_gcc_64 -O "$HOME/Qt" 2>&1 | tail -3
}
[ -d "$QT_ANDROID" ] && [ -d "$QT_HOST" ] || error "Qt not found"
info "Qt: host=$QT_HOST android=$QT_ANDROID"

# ── 3. Build ──
info "Building Plasmai ($MODE)..."
cd "$APP_DIR"
rm -rf build-android

ANDROID_SDK_ROOT="$SDK_ROOT" \
cmake -B build-android \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE="$MODE" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-34 \
    -DCMAKE_PREFIX_PATH="$QT_ANDROID;$HOME/kf6-android" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DQT_HOST_PATH="$QT_HOST" \
    -DANDROID_SDK_ROOT="$SDK_ROOT" \
    -DQT_ANDROID_TARGET_SDK_VERSION=34 \
    -DECM_DIR="$HOME/kf6-android/share/ECM/cmake" \
    -DQT_QML_IMPORT_PATH="$HOME/kf6-android/lib/qml" \
    -DBUILD_TESTING=OFF \
    2>&1 | tail -5

cmake --build build-android -j$(nproc) 2>&1 | tail -10

# ── 4. Patch KF6 QML plugin dependencies (libomp.so) ──
GRADLE_TASK="assembleDebug"
[ "$MODE" = "release" ] && GRADLE_TASK="assembleRelease"

# Release signing (optional): scripts/build-android.sh release with these set produces a
# signed APK; see RELEASING.md for how to create the keystore. Without them, "release"
# still builds (unoptimized signing config falls back to unsigned/debuggable output).
if [ "$MODE" = "release" ] && [ -n "${PLASMAI_KEYSTORE_PATH:-}" ]; then
    info "Configuring release signing from PLASMAI_KEYSTORE_* environment variables..."
    PROPS="$APP_DIR/build-android/android-build/gradle.properties"
    {
        echo "RELEASE_STORE_FILE=$PLASMAI_KEYSTORE_PATH"
        echo "RELEASE_STORE_PASSWORD=${PLASMAI_KEYSTORE_PASSWORD:?PLASMAI_KEYSTORE_PASSWORD not set}"
        echo "RELEASE_KEY_ALIAS=${PLASMAI_KEY_ALIAS:?PLASMAI_KEY_ALIAS not set}"
        echo "RELEASE_KEY_PASSWORD=${PLASMAI_KEY_PASSWORD:?PLASMAI_KEY_PASSWORD not set}"
    } >> "$PROPS"
elif [ "$MODE" = "release" ]; then
    info "No PLASMAI_KEYSTORE_PATH set — release build will be unsigned. See RELEASING.md."
fi

LIBS_DIR="$APP_DIR/build-android/android-build/libs/arm64-v8a"
LIBOMP="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/19/lib/linux/aarch64/libomp.so"
if [ -d "$LIBS_DIR" ] && [ -f "$LIBOMP" ] && [ ! -f "$LIBS_DIR/libomp.so" ]; then
    info "Adding libomp.so for KF6 Kirigami QML plugins..."
    cp "$LIBOMP" "$LIBS_DIR/"
fi
cd "$APP_DIR/build-android/android-build"
./gradlew "$GRADLE_TASK" 2>&1 | tail -10
cd "$APP_DIR"

# ── 5. Copy APK ──
APK=$(find "$APP_DIR/build-android/android-build/build/outputs/apk/$MODE" -name "*.apk" 2>/dev/null | head -1)
[ -z "$APK" ] && APK=$(find "$APP_DIR/build-android/android-build/build/outputs/apk" -name "*.apk" 2>/dev/null | head -1)
if [ -n "$APK" ]; then
    mkdir -p "$REPO_DIR/dist/android"
    OUT="$REPO_DIR/dist/android/plasmai-app-$MODE.apk"
    cp "$APK" "$OUT"
    info "APK ready: $OUT"
    info "Install: adb install -r $OUT"
    case "$APK" in
        *unsigned*) info "Note: unsigned APK — sign it (apksigner) before distributing, see RELEASING.md." ;;
    esac
else
    error "APK not found in build output"
fi
