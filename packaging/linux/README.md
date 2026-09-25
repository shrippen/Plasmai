# Plasma Mobile / desktop Linux app packaging

This directory holds the shared assets for both ways the standalone Kirigami app (`app/`,
not the Plasmoid) is packaged for Linux:

| File | Used by |
|---|---|
| `com.github.shrippen.plasmai.desktop` | tarball install, Flatpak |
| `com.github.shrippen.plasmai.metainfo.xml` | tarball install, Flatpak (AppStream data) |
| `com.github.shrippen.plasmai.png` | tarball install, Flatpak (256×256 app icon, from the Android launcher icon) |

## Tarball (recommended default)

```bash
./scripts/package-linux-app.sh
```

Builds the app in Release mode and creates `dist/linux/plasmai-app-<version>-<arch>.tar.xz`.
Attach it to the GitHub Release alongside `scripts/install-app-linux.sh` (same pattern as the
Plasmoid's `.plasmoid` + `install-linux.sh`); the one-liner is:

```bash
curl -fsSL https://github.com/shrippen/Plasmai/releases/latest/download/install-app-linux.sh | bash
```

This links against the system Qt6/KF6 rather than bundling it, so it only runs on a system
that already has a compatible Qt6/KF6 Kirigami install — true by construction for any Plasma 6
desktop or Plasma Mobile device.

## Flatpak

`packaging/flatpak/com.github.shrippen.plasmai.yml` — see the comments at the top of that file
for what to check before building; it has not been built or run here (no `flatpak-builder` /
KDE runtime available in this environment). Once verified, publishing to Flathub means opening
a PR against [flathub/flathub](https://github.com/flathub/flathub) with this manifest; see
RELEASING.md.
