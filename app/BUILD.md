# Plasmai App – Build-Anleitung

## Desktop (Linux)

```bash
cd app
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
./build/plasmai-app
```

Abhängigkeiten (Arch Linux):
```bash
sudo pacman -S extra-cmake-modules qt6-base qt6-declarative kirigami2 \
  qt6-svg qtkeychain-qt6 kf6-i18n kf6-coreaddons
```

## Android (Craft-Container)

Docker muss laufen (`sudo systemctl start docker`).

### 1. Container starten

```bash
# Image nur einmalig pullen (~3–5 GB)
docker pull invent-registry.kde.org/sysadmin/ci-images/android-qt611

# Plasmai-Repo mounten, Container öffnen
docker run -it --rm \
  -v "$(cd .. && pwd)":/workspace \
  -w /workspace \
  invent-registry.kde.org/sysadmin/ci-images/android-qt611 \
  bash
```

### 2. Inside Container: Craft-Blueprint anlegen

Craft ist im Image bereits konfiguriert (Nutzer `kde`).

```bash
# Blueprint-Verzeichnis
BP="$HOME/.local/share/ crafts-blueprints-kde/kde/applications"
mkdir -p "$BP/plasmai"

cat > "$BP/plasmai/plasmai.py" << 'BLUEPRINT'
from Package.CraftPackageObject import CraftPackageObject
from CraftSetupMacro import setup

def init():
    CraftPackageObject("plasmai").setDescription("Plasmai time tracking app")

class Package(CMakePackageBase):
    def __init__(self):
        CMakePackageBase.__init__(self)
        self.defaultOptions["CMAKE_INSTALL_PREFIX"] = craftStandardDirs.prefix
BLUEPRINT
```

### 3. Dependency installieren + Build

```bash
# Craft baut Qt-for-Android, Kirigami, qtkeychain (erstmalig ~30 Min)
craft -i plasmai
```

### 4. APK signieren

```bash
cd ~/craft-root/tmp   # oder $CRAFT_ROOT/tmp

# Debug-Keystore (einmalig)
keytool -genkey -noprompt \
  -keystore key.keystore -keypass plasmai \
  -dname "CN=Debug" -alias debug -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass plasmai

# zipalign + signieren
$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_REVISION/zipalign \
  -p -f 4 plasmai.apk plasmai-aligned.apk

$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_REVISION/apksigner sign \
  --ks key.keystore --ks-pass pass:plasmai \
  plasmai-aligned.apk
```

### 5. Auf Gerät installieren

```bash
adb install plasmai-aligned.apk
```

**Alternative ohne Docker (Qt Creator):**
Installiere Qt 6.8+ mit Android Kit via [Qt Online Installer](https://www.qt.io/download-qt-installer),
öffne `app/CMakeLists.txt` in Qt Creator, wähle Android-Kit, Build → Run.

## Plattformspezifische Hinweise

### shared.json Interop
- **Desktop**: `~/.config/com.github.shrippen.plasmai/shared.json`
- **Android**: App-Internal Storage (nicht teilbar)
- Profile, Favoriten und Einstellungen werden auf Desktop zwischen Plasmoid
  und App geteilt. Auf Android ist die App eigenständig.

### Token-Speicherung
- **Desktop**: qtkeychain → KWallet / freedesktop Secret Service
- **Android**: qtkeychain → Android Keystore (automatisch)
- Auf beiden Plattformen: API-Tokens verschlüsselt gespeichert.

### Fehlende Features (Desktop vs. App)
- Idle-Detection (xprintidle/loginctl): App-seitig nicht implementiert
- Desktop-Benachrichtigungen: Optional, via Android-Notification-System
- Sparkline (DaySparkline): Benötigt Qt5Compat.GraphicalEffects (nicht auf Android)
- Farb-Distinction Settings: Noch nicht in App-Settings implementiert
