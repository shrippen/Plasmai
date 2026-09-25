# Releasing Plasmai 2.0.0 (Plasmoid + Android + Plasma Mobile / desktop Linux)

Reference doc for cutting a release across all three targets. `RELEASE-TODO.md` is the
short checklist for a human to work through; this file has the actual commands and the
reasoning behind them.

Everything in this document was prepared but **not executed** past building local, unsigned
artifacts: no git tag, no push, no GitHub release, no store/Flathub/F-Droid submission. That is
intentional — see `RELEASE-TODO.md`.

## 1. Version numbers (done)

2.0.0 is set in: `metadata.json` (Plasmoid), `app/CMakeLists.txt` (project version + the
`QT_ANDROID_VERSION_NAME`/`_CODE` and `KAboutData`/`app.setApplicationVersion` in
`app/main.cpp`), `app/android/AndroidManifest.xml` (`versionCode="200"`,
`versionName="2.0.0"`), `STORE.md`, `docs/index.html`. `contents/code/buildInfo.js` was
regenerated via `./scripts/bump-build.sh` (reads the version from `metadata.json`, bumps
`build.number`). Translation catalogs (`translate/*.po`, `contents/locale/*/*.mo`,
`app/i18n/*.json`) were regenerated (`translate/extract.sh`, `python3 translate/fill_po.py`,
`translate/build.sh`) so `Project-Id-Version` matches.

versionCode 200 follows the existing `major*100 + minor*10 + patch` scheme (163 → 1.6.3). If
you'd rather keep more headroom, e.g. for point releases without a version bump, switch to
`major*10000 + minor*100 + patch` before publishing — versionCode can only increase over time
on the Play Store / F-Droid, so decide before the first 2.x release goes out anywhere.

## 2. Changelog (done)

`CHANGELOG.md` has a `## 2.0.0` section (Android/Plasma Mobile app as the headline addition)
above `## 1.6.3`, with a fresh empty `## Unreleased` above that.

## 3. Plasmoid (store.kde.org)

Unchanged from before — see `STORE.md`. `./scripts/package.sh` builds
`dist/plasmoid/Plasmai-2.0.0.plasmoid`; test it locally with `kpackagetool6 -i`; update the
store.kde.org listing's version/changelog fields to match.

## 4. Android

### 4.1 Debug build (works, CI builds it too now)

`./scripts/build-android.sh debug` → `dist/android/plasmai-app-debug.apk`. This is what CI
(`.github/workflows/android.yml`) also produces, on every push to `main` that touches `app/`.

**Previous CI gap, now closed**: the workflow used to skip KF6 entirely and build a
non-Kirigami fallback UI — not what's in this repo. `scripts/build-android.sh` only worked
locally because `~/kf6-android` already existed on the development machine, built previously
outside this repo with no reproducing script.

Fixed by adding `scripts/build-kf6-android.sh`, which cross-compiles the only KF6 pieces the
app actually needs — extra-cmake-modules, KCoreAddons (a Kirigami dependency), and Kirigami
itself (`app/CMakeLists.txt` only requires `KF6::Kirigami` when cross-compiling) — for
`android_arm64_v8a`, from the `frameworks/{extra-cmake-modules,kcoreaddons,kirigami}` KDE
repos at tag `v6.8.0`. This is verified working, end to end, not just written and hoped for:
built from a clean clone, linked against by a fresh build of the app, and the resulting APK's
native libraries checked with `readelf` for the `libomp.so` dependency (see below). It runs in
well under a minute (ECM installs cmake modules only; KCoreAddons and Kirigami compile in
~10s and ~30s respectively on a 24-core machine — CI will be slower but still fast), so it
isn't cached between runs; add that if CI runtime becomes a concern.

Both `scripts/build-android.sh` and the CI workflow now call this script automatically when
`~/kf6-android` doesn't already have `KF6Kirigami` installed.

**One real gotcha this surfaced and that both now handle**: `androiddeployqt`'s dependency
scanner does not detect that `libKirigami.so` needs `libomp.so` (Kirigami's `ImageColors` uses
OpenMP for palette generation) — confirmed with `readelf -d libKirigami.so | grep NEEDED`. Without
it, the app is missing a native library and would crash on startup on-device. Both scripts copy
it into `libs/arm64-v8a` and rebuild the APK with Gradle as a second pass.

### 4.2 Release build (works, unsigned — produced a local artifact)

```bash
./scripts/build-android.sh release
```

→ `dist/android/plasmai-app-release.apk`, currently **unsigned** (Android will refuse to
install it, or install it as debuggable, depending on the device). `app/android/build.gradle`
(an override `androiddeployqt` picks up from `QT_ANDROID_PACKAGE_SOURCE_DIR`) has a
`signingConfigs.release` block that activates automatically once these four Gradle properties
are set — `scripts/build-android.sh` writes them from environment variables when present:

```bash
export PLASMAI_KEYSTORE_PATH=/path/to/plasmai-release.jks
export PLASMAI_KEYSTORE_PASSWORD='...'
export PLASMAI_KEY_ALIAS=plasmai
export PLASMAI_KEY_PASSWORD='...'
./scripts/build-android.sh release
```

### 4.3 Creating the release keystore (not done — needs a human-chosen password)

I did not generate this: the password needs to be chosen and stored by whoever holds it, not
invented by me. One-time, on any machine with a JDK:

```bash
keytool -genkeypair -v -keystore plasmai-release.jks -alias plasmai \
    -keyalg RSA -keysize 4096 -validity 10950 \
    -storetype PKCS12
```

**This keystore signs every future Play Store update — losing it means you can never update
that listing again, only publish under a new package name.** Back it up somewhere durable and
separate from this repo (a password manager's file storage, an encrypted volume) — never
commit it. If distributing only via GitHub/F-Droid (not the Play Store), a lost keystore is
recoverable by just cutting a new one and telling users to reinstall, so it's lower-stakes
there, but still worth treating as a secret.

Store the four values (path handled separately — upload the `.jks` itself, not a path) as
GitHub Actions repository secrets (`Settings → Secrets and variables → Actions`) if you want CI
to sign release builds: `PLASMAI_KEYSTORE_B64` (`base64 -w0 plasmai-release.jks`),
`PLASMAI_KEYSTORE_PASSWORD`, `PLASMAI_KEY_ALIAS`, `PLASMAI_KEY_PASSWORD`. No workflow currently
decodes/uses these — add a release job once the KF6-Android CI gap (4.1) is solved, since
signing a broken build doesn't help.

### 4.4 GitHub Release

Once signed: attach `dist/android/plasmai-app-release.apk` (rename to something like
`Plasmai-2.0.0.apk`) to the GitHub Release alongside the `.plasmoid` and the Linux app tarball.

### 4.5 F-Droid

F-Droid builds from source on their own infrastructure — you cannot upload a binary APK there
(except in narrow, discouraged exceptions). Preparing this means submitting a recipe
(`metadata/com.github.shrippen.plasmai.yml`) as a PR to
[F-Droid/fdroiddata](https://gitlab.com/fdroid/fdroiddata), not producing an artifact here.

4.1's gap is closed (`scripts/build-kf6-android.sh` cross-compiles ECM + KCoreAddons + Kirigami
in well under a minute, verified end to end), which removes the biggest uncertainty. **One
real difference remains, not just paperwork**: that script does a plain `git clone` of
`invent.kde.org/frameworks/{...}` at build time — fine for CI, but F-Droid's sandboxed
builders don't allow live network access during the build (that's how they guarantee
reproducible builds). The KDE sources need to become an F-Droid `srclibs:` entry instead (their
mechanism for pinning an external source ahead of the sandboxed build) rather than a raw clone
inside the recipe's build steps. Sequence:

1. Read F-Droid's [Build Metadata Reference](https://f-droid.org/docs/Build_Metadata_Reference/)
   and [Inclusion Policy](https://f-droid.org/docs/Inclusion_Policy/) (all dependencies must be
   FOSS — Qt6/KF6/QtKeychain all qualify; the Kimai/Clockify/etc. backends are just HTTP APIs,
   fine).
2. Translate `scripts/build-kf6-android.sh`'s three `cmake -B/--build/--install` passes (ECM,
   KCoreAddons, Kirigami) into `srclibs:` entries + `build:`/`init:` steps in the recipe —
   the actual CMake invocations can likely be reused close to verbatim, only the source
   acquisition changes.
3. Open the PR — expect review rounds; F-Droid maintainers test the build themselves before
   merging, so treat this as a starting point, not a finished submission.

## 5. Plasma Mobile / desktop Linux app

### 5.1 Tarball (recommended default — works, produced a local artifact)

```bash
./scripts/package-linux-app.sh
```

→ `dist/linux/plasmai-app-2.0.0-x86_64.tar.xz` (built and smoke-tested — extracted, binary
launches under `QT_QPA_PLATFORM=offscreen`). Links against the *system* Qt6/KF6, so it only
runs where a compatible one is already installed — true by construction for Plasma 6 desktops
and Plasma Mobile devices. Attach it plus `scripts/install-app-linux.sh` to the GitHub Release;
see `packaging/linux/README.md`.

The `x86_64` in the filename is this machine's architecture. Plasma Mobile devices are
typically `aarch64` — you need to either cross-compile or build on/for that architecture
separately and attach a second tarball (`plasmai-app-2.0.0-aarch64.tar.xz`); the install script
already picks the right one via `uname -m`. I did not set up an aarch64 cross-build here.

### 5.2 Flatpak (prepared, unverified)

`packaging/flatpak/com.github.shrippen.plasmai.yml` — see its header comment for exactly what
to check (KDE runtime version, whether QtKeychain is already in the runtime, the pinned
qtkeychain tag). **I could not build or run this** — no `flatpak-builder` and no
`org.kde.Platform` runtime available in this environment, only the `flatpak` CLI itself. Before
trusting it:

```bash
flatpak install flathub org.kde.Platform//6.9 org.kde.Sdk//6.9   # match the manifest
flatpak-builder --user --install --force-clean build-dir packaging/flatpak/com.github.shrippen.plasmai.yml
flatpak run com.github.shrippen.plasmai
```

Publishing to Flathub means a PR to
[flathub/flathub](https://github.com/flathub/flathub) with this manifest (their bot builds and
tests it, then a human reviewer approves). The app ID `com.github.shrippen.plasmai` mirrors the
Plasmoid's KPackage ID and the Android package name for internal consistency; Flathub's own
convention for GitHub-hosted projects is usually `io.github.<user>.<Name>`
(`io.github.shrippen.Plasmai`) — decide which you want *before* the first Flathub submission,
since the app ID can't be renamed afterwards without losing install history.

## 6. Tagging and publishing (not done — your call)

Everything above stops at local, built-but-unsigned artifacts. When ready:

```bash
git add -A
git commit -m "Release 2.0.0"
git tag -a v2.0.0 -m "2.0.0"
git push origin feature/android-plasmamobile   # or wherever this lands after review/merge
git push origin v2.0.0
```

Pushing the tag does **not** currently trigger anything (no release workflow reacts to tags —
`.github/workflows/android.yml` only reacts to pushes on `main`). Add a tag-triggered workflow
once 4.1/4.3 are sorted if you want CI to build+sign+attach release artifacts automatically;
until then, build everything above locally and attach it to a manually-created GitHub Release.
