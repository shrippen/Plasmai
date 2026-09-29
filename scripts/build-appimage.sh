#!/usr/bin/env bash
# Build the Plasmai app (app/) as an AppImage that runs without Qt/KF6 installed:
# Qt 6.11.3 via aqtinstall, KF6 6.30 (ECM, Kirigami) and QtKeychain from
# source, bundled with linuxdeploy and its Qt plugin. The same versions as the Android build.
# Build on an old distro (CI: ubuntu-22.04) so the AppImage runs on as many systems as possible.
#
# Usage: ./scripts/build-appimage.sh   → dist/appimage/Plasmai-<version>-x86_64.AppImage
# Needs: cmake, ninja, a C++20 compiler, git, python3 + pip, gettext, libsecret-1-dev, the GL/EGL
# and xkbcommon development files, curl, and network access.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/metadata.json" | head -n1)"
[ -n "$VERSION" ] || { echo "error: could not read Version from metadata.json" >&2; exit 1; }

QT_VER="6.11.3"
KF6_VERSION="6.30.0"
QTKEYCHAIN_TAG="0.17.0"
QT="$HOME/Qt/$QT_VER/gcc_64"
PREFIX="${KF6_LINUX:-$HOME/kf6-linux}"
ARCH="$(uname -m)"

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
# Build output is trimmed to its last lines; PLASMAI_VERBOSE=1 (CI) shows all of it.
show() { if [ -n "${PLASMAI_VERBOSE:-}" ]; then cat; else tail -"$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── 1. Qt (host build with ShaderTools, which Kirigami needs) ──
if [ ! -d "$QT/lib/cmake/Qt6ShaderTools" ]; then
    info "Installing Qt $QT_VER (aqtinstall)..."
    pip install --user --break-system-packages aqtinstall 2>/dev/null || pip install --user aqtinstall
    export PATH="$HOME/.local/bin:$PATH"
    aqt install-qt linux desktop "$QT_VER" linux_gcc_64 -m qtshadertools -O "$HOME/Qt" 2>&1 | show 3
fi

# ── 2. KF6 + QtKeychain into $PREFIX ──
build() { # name source-dir [cmake args...]
    local name="$1" src="$2"; shift 2
    info "Building $name..."
    cmake -S "$src" -B "$src/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="$QT;$PREFIX" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_PYTHON_BINDINGS=OFF "$@" 2>&1 | show 3
    cmake --build "$src/build" 2>&1 | show 3
    cmake --install "$src/build" > /dev/null
}
# Always lib/ (Debian/Ubuntu would pick lib/x86_64-linux-gnu, where linuxdeploy does not look).
if ! grep -qs "\"$KF6_VERSION\"" "$PREFIX"/lib*/cmake/KF6Kirigami/KF6KirigamiConfigVersion.cmake; then
    rm -rf "${PREFIX:?}"   # another KF6 version (built against another Qt) must not mix with this one
    mkdir -p "$PREFIX"
    for repo in extra-cmake-modules kirigami; do
        git clone --quiet --depth 1 --branch "v$KF6_VERSION" "https://invent.kde.org/frameworks/$repo.git" "$WORK/$repo" &
    done
    git clone --quiet --depth 1 --branch "$QTKEYCHAIN_TAG" https://github.com/frankosterfeld/qtkeychain.git "$WORK/qtkeychain" &
    wait
    build extra-cmake-modules "$WORK/extra-cmake-modules" -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF
    build Kirigami "$WORK/kirigami" -DBUILD_EXAMPLES=OFF
    build QtKeychain "$WORK/qtkeychain" -DBUILD_WITH_QT6=ON -DBUILD_TRANSLATIONS=OFF
fi
LIBDIR="$PREFIX/lib"; [ -d "$PREFIX/lib64/cmake" ] && LIBDIR="$PREFIX/lib64"

# ── 3. The app, installed into an AppDir ──
info "Building Plasmai $VERSION..."
APPDIR="$WORK/AppDir"
cmake -S "$ROOT/app" -B "$WORK/app" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT;$PREFIX" -DCMAKE_INSTALL_PREFIX=/usr 2>&1 | show 5
cmake --build "$WORK/app" 2>&1 | show 10
DESTDIR="$APPDIR" cmake --install "$WORK/app" > /dev/null
install -Dm644 "$ROOT/packaging/linux/io.github.shrippen.Plasmai.desktop" "$APPDIR/usr/share/applications/io.github.shrippen.Plasmai.desktop"
install -Dm644 "$ROOT/packaging/linux/io.github.shrippen.Plasmai.metainfo.xml" "$APPDIR/usr/share/metainfo/io.github.shrippen.Plasmai.metainfo.xml"
install -Dm644 "$ROOT/packaging/linux/io.github.shrippen.Plasmai.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/io.github.shrippen.Plasmai.png"
# KLocalizedString finds the catalogs through XDG_DATA_DIRS.
mkdir -p "$APPDIR/apprun-hooks"
cat > "$APPDIR/apprun-hooks/plasmai-data-dirs.sh" <<'EOF'
export XDG_DATA_DIRS="$APPDIR/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
EOF

# ── 4. Bundle with linuxdeploy ──
TOOLS="$WORK/tools"; mkdir -p "$TOOLS"
for tool in linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
            linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage; do
    curl -sSfL "https://github.com/$tool" -o "$TOOLS/$(basename "$tool")"
done
chmod +x "$TOOLS"/*.AppImage
info "Bundling the AppImage..."
# linuxdeploy-plugin-qt deploys Wayland's EGL client integration only for the pre-6.10 plugin
# name; without it Qt Quick can't create an OpenGL context on Wayland and shows nothing. Its
# RUNPATH ($ORIGIN/../../lib) and Qt dependencies fit the AppDir; EGL/wayland-egl are system libs.
mkdir -p "$APPDIR/usr/plugins/wayland-graphics-integration-client"
cp "$QT/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so" \
    "$APPDIR/usr/plugins/wayland-graphics-integration-client/"
(
    cd "$WORK"
    export APPIMAGE_EXTRACT_AND_RUN=1   # no FUSE needed (CI containers)
    export PATH="$TOOLS:$QT/bin:$PATH"
    export QMAKE="$QT/bin/qmake"
    export LD_LIBRARY_PATH="$LIBDIR:$QT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export QML_SOURCES_PATHS="$ROOT/app/qml"   # the app's QML; contents/ui is the widget
    export NO_STRIP=1   # linuxdeploy's strip is too old for current distros' libraries (.relr.dyn)
    export QML_MODULES_PATHS="$LIBDIR/qml"
    export EXTRA_PLATFORM_PLUGINS="libqwayland.so"   # Qt 6.10+: one Wayland plugin (was -egl and -generic)
    export EXTRA_QT_MODULES="svg;dbus"
    export LINUXDEPLOY_OUTPUT_VERSION="$VERSION"
    "$TOOLS/linuxdeploy-x86_64.AppImage" --appdir "$APPDIR" --plugin qt \
        -d "$APPDIR/usr/share/applications/io.github.shrippen.Plasmai.desktop" \
        -i "$APPDIR/usr/share/icons/hicolor/256x256/apps/io.github.shrippen.Plasmai.png" 2>&1 | show 15
    # What the Qt plugin deploys but the app never loads (~20 MB unpacked): Qt's own
    # translations (the app has its JSON catalogs and installs no QTranslator) and the
    # Controls styles it does not use (it imports Material; Fusion/Basic are the fallbacks).
    rm -rf "$APPDIR/usr/translations"
    for style in FluentWinUI3 Imagine Universal; do
        rm -rf "$APPDIR/usr/qml/QtQuick/Controls/$style"
        rm -f "$APPDIR"/usr/lib/libQt6QuickControls2"$style"*.so*
    done
    "$TOOLS/linuxdeploy-x86_64.AppImage" --appdir "$APPDIR" --output appimage 2>&1 | show 15
)
mkdir -p "$ROOT/dist/appimage"
OUT="$ROOT/dist/appimage/Plasmai-$VERSION-$ARCH.AppImage"
mv "$WORK"/Plasmai-*.AppImage "$OUT"
info "AppImage ready: $OUT"
