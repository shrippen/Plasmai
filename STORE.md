# Publishing Plasmai to store.kde.org

## 1. Build the package

```bash
./scripts/package.sh
```

This creates `Plasmai-<version>.plasmoid` (a ZIP with `metadata.json` and `contents/` at the root).

Current release artifact: **`Plasmai-1.6.2.plasmoid`**

## 2. Test the package locally

```bash
kpackagetool6 -r com.github.shrippen.plasmai -t Plasma/Applet 2>/dev/null || true
kpackagetool6 -i ./Plasmai-1.6.2.plasmoid -t Plasma/Applet
```

Add the widget to a panel and verify start/stop, pickers, sparkline, stats, and configuration.

## 3. Prepare store.kde.org listing

1. Create / sign in at [https://store.kde.org](https://store.kde.org/) (KDE identity).
2. Upload a new product (or update the existing listing) in category **Plasma Addons → Plasma 6 Applets**.
3. Fill in:

| Field | Value |
|---|---|
| **Name** | Plasmai |
| **Version** | 1.6.2 |
| **License** | GPL-3.0-or-later |
| **Homepage / Source** | https://github.com/shrippen/Plasmai |
| **Bug tracker** | https://github.com/shrippen/Plasmai/issues |

**Short description:**
> Track time with Kimai, Clockify, Toggl Track, or SolidTime from the Plasma panel.

**Long description (suggested):**
> Plasmai is a KDE Plasma 6 widget for time tracking. Start and stop timers from the panel, edit the running entry, switch from Recent while tracking, add manual entries, browse statistics, pin favorites, and see today/week totals against your work contract. A zoomed day sparkline shows work hours, overtime, and sun arcs for your location. Supports Kimai, Clockify, Toggl Track, and SolidTime. API tokens stay in KWallet; settings are shared across widget instances. Translations: EN, DE, FR, ES, IT, NL, PT (BR), PL, UK, RU, JA, ZH (CN).

4. Upload screenshots from `screenshots/` (`01-panel.jpg`, `02-popup.jpg`).
5. Upload **`Plasmai-1.6.2.plasmoid`** as the downloadable content.

## 4. Metadata checklist

- [x] `KPackageStructure`: `Plasma/Applet`
- [x] `X-Plasma-API-Minimum-Version`: `6.0`
- [x] Unique `Id`: `com.github.shrippen.plasmai`
- [x] `Website` / `BugReportUrl` set
- [x] Author: shrippen
- [x] Pure QML/JS (no compiled binaries — required for Store QML applets)
- [x] Scripts are executable (`contents/code/*.sh`)
- [x] Translations compiled under `contents/locale/`

## 5. After publishing

Tag the release on GitHub to match the store version:

```bash
git tag -a v1.6.2 -m "Plasmai 1.6.2"
git push origin main --tags
```

Attach the same `.plasmoid` file to the GitHub Release.
