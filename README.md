# Plasmai

A KDE Plasma 6 panel widget for tracking time on your self-hosted [Kimai](https://www.kimai.org/) instance.

**Plugin ID:** `com.github.shrippen.plasmai`  
**Repository:** https://github.com/shrippen/Plasmai

## Features

- Live timer in the panel (project/activity + elapsed time)
- Start, stop, and switch tracking from the popup or desktop widget
- Recent activities and pinned favorites (customer colors)
- Multiple profiles; API tokens stored in KWallet
- Pluggable time-tracking backends (Kimai fully supported; more planned)
- Searchable project/activity pickers
- Today/week work summary vs work-contract targets
- 24h sparkline with work hours, overtime, and sunrise/sunset coloring
- Shared settings across all widget instances
- Desktop notifications; optional idle auto-stop
- English and German translations

## Requirements

- KDE Plasma 6
- `secret-tool` (libsecret / libsecret-tools)
- `notify-send` (libnotify) for desktop notifications
- `xprintidle` for idle auto-stop (X11/XWayland; optional)
- A Kimai instance with API access

## Installation (from source)

```bash
git clone https://github.com/shrippen/Plasmai.git
cd Plasmai
chmod +x contents/code/*.sh
kpackagetool6 -i . -t Plasma/Applet
```

Update after changes:

```bash
kpackagetool6 -u . -t Plasma/Applet
# reload Plasma if needed:
# plasmashell --replace &
```

Install a release package (`.plasmoid`):

```bash
kpackagetool6 -i Plasmai-1.0.0.plasmoid -t Plasma/Applet
```

## Setup

1. Right-click the panel → **Add Widgets** → search for **Plasmai**
2. Right-click the widget → **Configure Plasmai**
3. **Connection** tab: set URL, save API token, optionally manage multiple profiles
4. **Favorites** tab: pin frequently used project/activity pairs
5. **Display** / **Behavior** tabs: recent count, panel labels, idle stop, notifications

Generate an API token in Kimai: user menu → **API Access** → **Create**.

## Shared settings

Profiles, favorites, display, and behavior settings are shared across all Plasmai instances via:

`~/.config/com.github.shrippen.plasmai/shared.json`

Settings from the previous plugin id (`org.arian.kimaitracker`) are migrated automatically.

## Packaging

Build a store-ready `.plasmoid` archive:

```bash
./scripts/package.sh
```

See [STORE.md](STORE.md) for publishing to [store.kde.org](https://store.kde.org/).

## Translations

UI strings use Plasma `i18n`. English is the source language; German (`de`) is included.

```bash
./translate/extract.sh   # refresh translate/template.pot from QML
# edit translate/de.po (and other languages), then:
./translate/build.sh     # compile .mo into contents/locale/
```

Compiled catalogs ship in `contents/locale/<lang>/LC_MESSAGES/plasma_applet_com.github.shrippen.plasmai.mo`.

## Development

```bash
plasmoidviewer -a com.github.shrippen.plasmai -l topedge -f horizontal
plasmoidviewer -a com.github.shrippen.plasmai
```

## Time-tracking backends

Plasmai routes API calls through `contents/code/timeTracker.js`. Profiles store a
`provider` id (default `kimai`). Kimai is the reference implementation in
`contents/code/kimaiApi.js`.

**Easy next additions** (see `contents/code/providers/NOTES.txt`):

| Service | Why it’s a good fit |
|---|---|
| **Clockify** | API key auth, clear start/stop time-entry endpoints |
| **Toggl Track** | Popular SaaS, well-documented running-timer API |
| **SolidTime** | FOSS self-hosted, domain model close to Kimai |
| **Local JSON** | Offline/demo backend for UI work without a server |

Harder fits: WakaTime (automatic heartbeats), Jira Tempo / YouTrack (issue-centric).

## Uninstall

```bash
kpackagetool6 -r com.github.shrippen.plasmai -t Plasma/Applet
```

If you still have the old package installed:

```bash
kpackagetool6 -r org.arian.kimaitracker -t Plasma/Applet
```

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).
