# Windows: the tray client

The app (`app/`) built for Windows is a tray client (ROADMAP pillar 7): a tray icon with the
app as its popup, like the Plasmoid in the Plasma panel. `PLASMAI_TRAY` is on by default for
Windows (`app/CMakeLists.txt`); on Linux it can be switched on to try it (`-DPLASMAI_TRAY=ON`,
needs a tray host).

| Part | Where |
|---|---|
| Tray icon, popup, single instance | `app/platform/traycontroller.*`, placement `trayplacement.h` |
| Autostart (HKCU `Run`, value `Plasmai`, `--hidden`) | `app/platform/autostart_win.cpp` |
| Idle time (`GetLastInputInfo`) | `app/platform/idlewatcher_win.cpp` |
| Notifications (the tray icon's message) | `app/platform/notifier_tray.cpp` |
| Token | Windows Credential Manager through QtKeychain (`tokenstore.cpp`) |
| Menu texts, tooltip, icon state | `app/qml/main.qml` (`trayMenu`, `trayAction`) |
| Icon and version resource | `app/windows/plasmai.ico`, `plasmai.rc.in` |

## Build and package

`release.yml` (job `windows`) builds everything on `windows-latest`:

1. Qt 6.10 (install-qt-action), MSVC, Ninja;
2. `scripts/build-deps.sh deps --kirigami` builds ECM, QtKeychain and Kirigami into `deps/`;
3. `DEPS=deps scripts/package-windows.sh` builds the app, deploys Qt with `windeployqt`, adds
   QtKeychain and Kirigami, and makes
   - `Plasmai-<version>-setup.exe` (Inno Setup, `plasmai.iss`): per user, no administrator
     rights, into `%LOCALAPPDATA%\Programs\Plasmai`, optional start at login;
   - `Plasmai-<version>-windows-x64.zip`: the same files to unpack anywhere.

`checks.yml` (job `app`, Windows) builds the same app with the test driver and runs it on the
demo offscreen; the screenshots are the `windows-screens` artifact.

## Not done yet

- **Signing.** The installer and the executable are unsigned, so SmartScreen warns on the
  first start. Signing needs a certificate (e.g. SignPath's free plan for open source, or an
  OV/EV certificate) as repository secrets; then `signtool sign` runs on `plasmai-app.exe`
  before `iscc` and on the setup after it (Inno Setup's `SignTool=` directive).
- **winget.** `winget/` holds a draft manifest. Per release: replace `VERSION`, put the
  setup's SHA256 (`sha256sum Plasmai-<version>-setup.exe`) into `InstallerSha256`, check it
  with `winget validate` and open a pull request against `microsoft/winget-pkgs`
  (`manifests/s/shrippen/Plasmai/<version>/`). Better after signing: unsigned installers
  are accepted, but the SmartScreen warning stays.
- **Tested on a Windows desktop.** CI builds and runs the app offscreen only; the tray icon,
  the popup next to it, autostart and notifications were tried on Linux (Xvfb, a tray host)
  with the same code, not on Windows itself.
