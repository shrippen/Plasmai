# Releasing Plasmai 2.0.0 (Plasmoid + Android + Plasma Mobile / desktop Linux)

Reference doc for cutting a release across all three targets. `RELEASE-TODO.md` is the
short checklist for a human to work through; this file has the actual commands and the
reasoning behind them.

Everything in this document was prepared but **not executed** past building local, unsigned
artifacts: no git tag, no push, no GitHub release, no store/Flathub/F-Droid submission. That is
intentional — see `RELEASE-TODO.md`.

## 1. Version numbers (done)

2.0.0 is set in: `metadata.json` (Plasmoid), `app/CMakeLists.txt` (project version + the
`QT_ANDROID_VERSION_NAME`/`_CODE` and `app.setApplicationVersion` in
`app/main.cpp`), `app/android/AndroidManifest.xml` (`versionCode="20000"`,
`versionName="2.0.0"`), `STORE.md`, `docs/index.html`. `contents/code/buildInfo.js` was
regenerated via `./scripts/bump-build.sh` (reads the version from `metadata.json`, bumps
`build.number`). Translation catalogs (`translate/*.po`, `contents/locale/*/*.mo`,
`app/i18n/*.json`) were regenerated (`translate/extract.sh`, `python3 translate/fill_po.py`,
`translate/build.sh`) so `Project-Id-Version` matches.

versionCode is `major*10000 + minor*100 + patch` (2.0.0 → 20000), set in
`app/CMakeLists.txt` (`QT_ANDROID_VERSION_CODE`) and `app/android/AndroidManifest.xml`. It
replaced the 1.x scheme `major*100 + minor*10 + patch` before any APK was published; it can
only increase from here (F-Droid, Play Store).

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
repos at the tag in the script (`KF6_VERSION`, now 6.30.0, with Qt 6.11.3). This is verified working, end to end, not just written and hoped for:
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
`PLASMAI_KEYSTORE_PASSWORD`, `PLASMAI_KEY_ALIAS`, `PLASMAI_KEY_PASSWORD`.
`.github/workflows/release.yml` decodes and uses them (section 6). Set them with `gh`, e.g.
`base64 -w0 plasmai-release.jks | gh secret set PLASMAI_KEYSTORE_B64 -R shrippen/Plasmai`.

### 4.4 GitHub Release

Once signed: attach `dist/android/plasmai-app-release.apk` (rename to something like
`Plasmai-2.0.0.apk`) to the GitHub Release alongside the `.plasmoid` and the Linux app tarball.

### 4.5 IzzyOnDroid — ruled out (AI policy)

[IzzyOnDroid](https://apt.izzysoft.de/fdroid/) would have taken the signed APK straight from the
GitHub release, no source build needed. **Not usable**: their
[App Inclusion Policy](https://izzyondroid.org/docs/general/AppInclusionPolicy/#ai-policy)
states plainly "Vibe-coded apps will be rejected" and that they are "strongly opposed to apps
which are fully or in part created by generative AI tools." Plasmai was built with AI
assistance throughout, so this route is closed regardless of app quality — do not submit here.

### 4.6 Main F-Droid repository (chosen route — recipe build-verified)

F-Droid builds from source on their own infrastructure — you cannot upload a binary APK there
(except in narrow, discouraged exceptions), which also sidesteps IzzyOnDroid's per-APK AI
objection: F-Droid's own
[Inclusion Policy](https://f-droid.org/docs/Inclusion_Policy/) has no blanket AI-authorship ban
at the time of writing, only the usual FOSS/reproducibility requirements (Qt6/KF6/QtKeychain all
qualify; the Kimai/Clockify/etc. backends are just HTTP APIs, fine) — recheck this before
submitting, since policies change. Submitting means a PR to
[F-Droid/fdroiddata](https://gitlab.com/fdroid/fdroiddata) with a recipe, not an artifact
produced here.

A recipe is prepared under `packaging/fdroid/metadata/com.github.shrippen.plasmai.yml` (mirrors
how `packaging/flatpak/` holds the Flathub draft). `sudo:` installs Qt6, the NDK, the android-36
platform and a handful of runtime libs (root, network available); `build:` runs
`scripts/build-apk-reproducible.sh`, which builds OpenSSL from source, cross-compiles ECM →
KCoreAddons → Kirigami, then the app (unprivileged, but **also** with network — real recipes
already in fdroiddata do live `git clone`/`wget` in `build:` too).

**Reproducible Builds**: the GitHub release job (4.3) runs the same script, so both builds are
byte-identical and F-Droid can ship the APK with our signature (the recipe's `signatures/`
directory, made with `fdroid signatures <signed release APK>`). Verified after 2.0.0 (commit
8f9ba61, Qt 6.11.3 + KF6 6.30.0 + OpenSSL 3.5.8; 9246974 (Qt 6.7) was also installed on a Pixel 6: starts,
HTTPS with the self-built OpenSSL works): a build in F-Droid's own buildserver image (`registry.gitlab.com/fdroid/fdroidserver:
buildserver-trixie`, run locally with Docker the way fdroiddata's CI job does) plus the signature
block of the GitHub test build's signed APK gave exactly the signed APK (`apksigcopier compare
--unsigned`). What keeps them identical is listed in the script's header — change nothing there,
in the Qt/NDK/SDK versions or in the release job's setup without re-checking. To check a change
before a release: run release.yml by hand (test build, its artifact `plasmai-test-apk` is the
signed APK), then `packaging/fdroid/check-reproducible.sh <commit> <that APK>` (Docker,
apksigcopier and apksigner needed; ~15 min). **One-way door**: once F-Droid publishes a release with our key, every
later release must reproduce too (or F-Droid stops updating it); once F-Droid signs with its own
key, switching to ours later means users reinstall.

**Build-verified** on F-Droid's CI (before the reproducible script, v2.0.0): a throwaway MR from
the fork's own branch against its own `master` (only to trigger a `merge_request_event`
pipeline, not a submission), closed once green — `fdroid build`, `check apk`, `fdroid
rewritemeta`, `fdroid lint`, schema validation and `checkupdates` all passed. The recipe file's
git history and header comment have the problems met on the way.

Submission is prepared as far as it can be without opening the PR yourself:

1. A fork `shrippen/fdroiddata` exists (`glab repo fork fdroid/fdroiddata`), cloned to
   `/home/arian/Hacking/eigene/fdroiddata`.
2. Branch `new/com.github.shrippen.plasmai` there has the verified recipe committed and pushed
   to the fork.
3. Before opening the MR: release a version built by the reproducible release job (2.0.1 or
   later; v2.0.0's APK can't be reproduced), point `Builds[0].commit`/`versionName`/`versionCode`
   at its tag, run `fdroid signatures <its signed APK from the GitHub release>` in the fdroiddata
   clone and commit `metadata/com.github.shrippen.plasmai/signatures/`. Then run the throwaway
   MR once more: `fdroid build` must pass including the signature check. Still open from the
   template: KF6 sources as git submodules instead of a plain clone (not a blocker).
4. Open the MR yourself at `https://gitlab.com/shrippen/fdroiddata/-/merge_requests/new` (branch
   `new/com.github.shrippen.plasmai` against `fdroid/fdroiddata:master`), with an AI-disclosure
   note (same reasoning as Flathub, 5.2) — expect review rounds; F-Droid maintainers test the
   build themselves before merging, so treat this as a strong starting point, not a guaranteed
   merge.
5. TODO once accepted: add the F-Droid "Get it on" badge and a shields.io version badge
   (`https://img.shields.io/f-droid/v/com.github.shrippen.plasmai.svg?logo=F-Droid`, per
   CONTRIBUTING.md) to the project's README.md on Gitea/GitHub — not the landing page
   (`docs/index.html`), where it wouldn't fit stylistically.

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

`packaging/flatpak/io.github.shrippen.Plasmai.yml` — see its header comment for exactly what
to check (KDE runtime version, whether QtKeychain is already in the runtime, the pinned
qtkeychain tag). **I could not build or run this** — no `flatpak-builder` and no
`org.kde.Platform` runtime available in this environment, only the `flatpak` CLI itself. Before
trusting it:

```bash
flatpak install flathub org.kde.Platform//6.9 org.kde.Sdk//6.9   # match the manifest
flatpak-builder --user --install --force-clean build-dir packaging/flatpak/io.github.shrippen.Plasmai.yml
flatpak run io.github.shrippen.Plasmai
```

Publishing to Flathub means a PR to
[flathub/flathub](https://github.com/flathub/flathub) with this manifest (their bot builds and
tests it, then a human reviewer approves). The Linux app ID is `io.github.shrippen.Plasmai`
(Flathub does not take new `com.github.*` IDs): file names under `packaging/`, the desktop file
name (`KAboutData::setDesktopFileName`) and the Flatpak `app-id`. Internally the app keeps
`com.github.shrippen.plasmai` as the keychain service and the config folder it shares with the
widget, and Android keeps it as the package name. The manifest builds from the local checkout;
for Flathub switch the `plasmai` source to `type: git` with the release tag and commit.

## 6. Tagging and publishing

**Rule: every release carries assets for all platforms**, each installable from the release
page: the Android APK (`Plasmai-X.Y.Z.apk`), a Flatpak bundle (`.flatpak`, besides any Flathub
listing), an AppImage, and the Plasma widget (`Plasmai-X.Y.Z.plasmoid`). If one of them cannot
be built, say so before tagging instead of releasing without it. The APK may live only on the
GitHub release, for people who install it directly; the release itself also exists on Gitea.
`.github/workflows/release.yml` builds all four on a tag and attaches them to the GitHub
release (APK signed; AppImage via `scripts/build-appimage.sh` on Ubuntu 22.04; Flatpak bundle
from `packaging/flatpak/`; widget via `scripts/package.sh`). For an existing release run it by
hand with `tag` set: `gh workflow run release.yml -R shrippen/Plasmai -f tag=vX.Y.Z`.

Git work goes to Gitea (git.arianw.de); its push mirror carries commits and tags to GitHub,
but not releases. So a release is made in two places, the second one automatically:

1. `CHANGELOG.md` has a section `## X.Y.Z` (the release notes: `scripts/release-notes.sh X.Y.Z`).
2. Tag and push to Gitea: `git tag -a vX.Y.Z -m "X.Y.Z" && git push origin vX.Y.Z`.
3. Gitea release with `tea`, notes only, no files (GitHub is the public channel and the only one
   with release files; Gitea runs the checks):
   `tea releases create --login git.arianw.de --repo shrippen/plasmai --tag vX.Y.Z --title "Plasmai X.Y.Z" --note "$(scripts/release-notes.sh X.Y.Z)"`
4. The mirror pushes the tag to GitHub; `.github/workflows/release.yml` builds the release APK,
   signs it with the secrets from 4.3, checks the signature and creates the GitHub release
   with the same notes and the APK (`Plasmai-X.Y.Z.apk`), attached for direct install.
   Run by hand (`gh workflow run release.yml -R shrippen/Plasmai`) it only builds an unsigned
   test APK.
