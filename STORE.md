# Publishing Plasmai to store.kde.org

## 1. Build the package

```bash
./scripts/package.sh
```

This creates `Plasmai-<version>.plasmoid` (a ZIP with `metadata.json` and `contents/` at the root).

## 2. Test the package locally

```bash
kpackagetool6 -r com.github.shrippen.plasmai -t Plasma/Applet 2>/dev/null || true
kpackagetool6 -i ./Plasmai-*.plasmoid -t Plasma/Applet
```

Add the widget to a panel and verify start/stop, pickers, and configuration.

## 3. Prepare store.kde.org listing

1. Create / sign in at [https://store.kde.org](https://store.kde.org/) (KDE identity).
2. Upload a new product in category **Plasma Addons → Plasma 6 Applets** (or the current Plasma widgets section).
3. Fill in:
   - **Name:** Plasmai
   - **Description:** short + long (see README features)
   - **License:** GPL-3.0-or-later
   - **Homepage / Source:** https://github.com/shrippen/Plasmai
   - **Bug tracker:** https://github.com/shrippen/Plasmai/issues
   - **Version:** match `metadata.json` (`1.0.0`)
4. Upload screenshots (panel compact view + open popup). Put source images in `screenshots/` for reuse.
5. Upload the `.plasmoid` file as the downloadable content.

## 4. Metadata checklist

- [x] `KPackageStructure`: `Plasma/Applet`
- [x] `X-Plasma-API-Minimum-Version`: `6.0`
- [x] Unique `Id`: `com.github.shrippen.plasmai`
- [x] `Website` / `BugReportUrl` set
- [x] Pure QML/JS (no compiled binaries — required for Store QML applets)
- [x] Scripts are executable (`contents/code/*.sh`)

## 5. After publishing

Tag the release on GitHub to match the store version:

```bash
git tag -a v1.0.0 -m "Plasmai 1.0.0"
git push origin main --tags
```

Attach the same `.plasmoid` file to the GitHub Release.
