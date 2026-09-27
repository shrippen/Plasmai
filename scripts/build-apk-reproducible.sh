#!/usr/bin/env bash
# Reproducible release APK: the one build both the GitHub release (.github/workflows/release.yml)
# and F-Droid (packaging/fdroid/metadata/com.github.shrippen.plasmai.yml) run, so F-Droid can
# check its build against the signed GitHub APK byte for byte (Reproducible Builds) and ship ours.
#
# Usage: ANDROID_SDK_ROOT=<sdk> ./scripts/build-apk-reproducible.sh
# Output: app/build-android/android-build/build/outputs/apk/release/android-build-release-unsigned.apk
#   (or ...-release.apk, signed, when PLASMAI_KEYSTORE_PATH & co. are set as in build-android.sh)
#
# Needs, installed beforehand (the recipe's sudo: block, the release job's setup steps):
#   NDK 28.2.13676358, platforms;android-34, build-tools;34.0.0 in the SDK; Qt 6.7.3 android_arm64_v8a
#   and gcc_64 with qtshadertools under $PLASMAI_QT_DIR (default /opt/plasmai-qt/6.7.3); cmake,
#   ninja, perl, make, git.
#
# What keeps the two builds identical — change nothing here without checking both:
#   - fixed paths: dependencies build in /tmp/plasmai-build (their source paths end up in the
#     libraries, e.g. OpenMP source locations in Kirigami);
#   - SOURCE_DATE_EPOCH = the commit time (F-Droid sets the same), for the timestamps rcc
#     writes into Qt resources and OpenSSL's "built on";
#   - Kirigami built with -j1: its QML modules are AOT-compiled against each other's type
#     info, and a parallel build races on it, so which functions get compiled varies;
#   - OpenSSL from source (not the prebuilt libs in app/libs/openssl, which F-Droid removes);
#   - the SDK and checkout paths mapped away in the debug info (-ffile-prefix-map): it is
#     stripped from the APK, but the libraries' build IDs are hashed over it first.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT not set}"
NDK_PATH="$SDK_ROOT/ndk/28.2.13676358"
QT_DIR="${PLASMAI_QT_DIR:-/opt/plasmai-qt/6.7.3}"
QT_ANDROID="$QT_DIR/android_arm64_v8a"
QT_HOST="$QT_DIR/gcc_64"
KF6_VERSION="6.8.0"
OPENSSL_VERSION="3.5.8"   # LTS (until 2030-04); bump for security releases
WORK=/tmp/plasmai-build
KF6="$WORK/kf6"

[ -d "$NDK_PATH" ] || { echo "NDK not found: $NDK_PATH" >&2; exit 1; }
[ -d "$QT_ANDROID" ] && [ -d "$QT_HOST" ] || { echo "Qt not found under $QT_DIR" >&2; exit 1; }
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$REPO_DIR" log -1 --format=%ct)}"
echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"

# GitHub: /usr/local/lib/android/sdk and /home/runner/work/...; F-Droid: /opt/android-sdk and
# /home/vagrant/build/<appid>.
PREFIX_MAP="-ffile-prefix-map=$SDK_ROOT=/android-sdk -ffile-prefix-map=$REPO_DIR=/plasmai"

rm -rf "$WORK"
mkdir -p "$WORK" "$KF6"

# ── OpenSSL, as libssl_3.so/libcrypto_3.so (the names Qt 6 loads on Android) ──
git clone --quiet --depth 1 --branch "openssl-$OPENSSL_VERSION" \
    https://github.com/openssl/openssl.git "$WORK/openssl"
# A target named android-*-<arch> keeps OpenSSL's NDK setup; only the file suffix changes.
cat > "$WORK/openssl-qt.conf" <<'EOF'
my %targets = (
    "android-qt-arm64" => {
        inherit_from     => [ "android-arm64" ],
        shared_extension => "_3.so",
    },
);
EOF
(
    cd "$WORK/openssl"
    export ANDROID_NDK_ROOT="$NDK_PATH"
    export PATH="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
    ./Configure --config="$WORK/openssl-qt.conf" shared android-qt-arm64 -D__ANDROID_API__=28 > "$WORK/openssl.log"
    make -j"$(nproc)" build_generated >> "$WORK/openssl.log" 2>&1
    make -j"$(nproc)" libcrypto_3.so >> "$WORK/openssl.log" 2>&1
    # Without this libssl links libcrypto.a in statically instead of needing libcrypto_3.so.
    ln -sf libcrypto_3.so libcrypto.so
    make -j"$(nproc)" build_libs >> "$WORK/openssl.log" 2>&1
) || { tail -n 100 "$WORK/openssl.log"; exit 1; }
mkdir -p "$REPO_DIR/app/libs/openssl/arm64-v8a"
cp "$WORK/openssl/libssl_3.so" "$WORK/openssl/libcrypto_3.so" "$REPO_DIR/app/libs/openssl/arm64-v8a/"

# ── KF6: extra-cmake-modules, KCoreAddons, Kirigami ──
clone_kf6() {
    git clone --quiet --depth 1 --branch "v$KF6_VERSION" \
        "https://invent.kde.org/frameworks/$1.git" "$WORK/$1"
}
CROSS_ARGS=(
    -G Ninja
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="$QT_ANDROID;$KF6"
    -DCMAKE_INSTALL_PREFIX="$KF6"
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
    -DQT_HOST_PATH="$QT_HOST"
    -DECM_DIR="$KF6/share/ECM/cmake"
    -DCMAKE_C_FLAGS="$PREFIX_MAP" -DCMAKE_CXX_FLAGS="$PREFIX_MAP"
    -DBUILD_TESTING=OFF -DBUILD_QCH=OFF
)

clone_kf6 extra-cmake-modules
cmake -S "$WORK/extra-cmake-modules" -B "$WORK/extra-cmake-modules/build" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$KF6" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF
cmake --build "$WORK/extra-cmake-modules/build"
cmake --install "$WORK/extra-cmake-modules/build"

clone_kf6 kcoreaddons
cmake -S "$WORK/kcoreaddons" -B "$WORK/kcoreaddons/build" "${CROSS_ARGS[@]}"
cmake --build "$WORK/kcoreaddons/build" -j"$(nproc)"
cmake --install "$WORK/kcoreaddons/build"

clone_kf6 kirigami
cmake -S "$WORK/kirigami" -B "$WORK/kirigami/build" "${CROSS_ARGS[@]}" \
    -DBUILD_EXAMPLES=OFF -DDESKTOP_ENABLED=OFF
cmake --build "$WORK/kirigami/build" -j1
cmake --install "$WORK/kirigami/build"

# ── The app ──
cd "$REPO_DIR/app"
rm -rf build-android
cmake -B build-android \
    -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-34 \
    -DCMAKE_PREFIX_PATH="$QT_ANDROID;$KF6" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DQT_HOST_PATH="$QT_HOST" \
    -DANDROID_SDK_ROOT="$SDK_ROOT" \
    -DQT_ANDROID_TARGET_SDK_VERSION=34 \
    -DECM_DIR="$KF6/share/ECM/cmake" \
    -DQT_QML_IMPORT_PATH="$KF6/lib/qml" \
    -DCMAKE_C_FLAGS="$PREFIX_MAP" -DCMAKE_CXX_FLAGS="$PREFIX_MAP" \
    -DBUILD_TESTING=OFF
cmake --build build-android -j"$(nproc)"

# Kirigami's QML plugins need libomp at runtime.
mkdir -p build-android/android-build/libs/arm64-v8a
cp "$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/19/lib/linux/aarch64/libomp.so" \
    build-android/android-build/libs/arm64-v8a/

if [ -n "${PLASMAI_KEYSTORE_PATH:-}" ]; then
    {
        echo "RELEASE_STORE_FILE=$PLASMAI_KEYSTORE_PATH"
        echo "RELEASE_STORE_PASSWORD=${PLASMAI_KEYSTORE_PASSWORD:?PLASMAI_KEYSTORE_PASSWORD not set}"
        echo "RELEASE_KEY_ALIAS=${PLASMAI_KEY_ALIAS:?PLASMAI_KEY_ALIAS not set}"
        echo "RELEASE_KEY_PASSWORD=${PLASMAI_KEY_PASSWORD:?PLASMAI_KEY_PASSWORD not set}"
    } >> build-android/android-build/gradle.properties
fi
cd build-android/android-build
./gradlew assembleRelease

# Without its QML plugins the app builds fine but quits at startup ("module org.kde.kirigami
# plugin ... not found"), so check the APK has them and OpenSSL.
python3 - build/outputs/apk/release/*.apk <<'EOF'
import sys, zipfile
names = set(zipfile.ZipFile(sys.argv[1]).namelist())
need = ["lib/arm64-v8a/libqml_org_kde_kirigami_Kirigamiplugin_arm64-v8a.so",
        "lib/arm64-v8a/libomp.so", "lib/arm64-v8a/libssl_3.so", "lib/arm64-v8a/libcrypto_3.so"]
missing = [n for n in need if n not in names]
if missing:
    sys.exit("APK is missing: " + ", ".join(missing))
EOF
