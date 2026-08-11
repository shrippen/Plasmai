# Plasmai

A KDE Plasma 6 panel widget for time tracking — Kimai, Clockify, Toggl Track, or SolidTime.

**Plugin ID:** `com.github.shrippen.plasmai`  
**Repository:** https://github.com/shrippen/Plasmai
**KDE Store:** https://store.kde.org/p/2368175/

**Note:** This is completely vibe coded from start to finish. This is simply something I wanted for myself but might as well share here.

## Features

- Live timer in the panel (project/activity + elapsed time)
- Start, stop, and switch tracking from the popup or desktop widget
- Click Recent while tracking to confirm switching to that activity
- Edit the running entry’s start time, project, and activity
- Manual time entries (+) and a secondary statistics view with charts
- Recent activities and pinned favorites (customer colors)
- Multiple profiles per service; API tokens stored in KWallet
- Backends: **Kimai**, **Clockify**, **Toggl Track**, **SolidTime**
- Searchable project/activity pickers
- Today/week work summary (Kimai work contract when available)
- Day sparkline: zoomed work-hours bar, sun/moon/work arcs, overtime segments, hour ticks
- Optional color distinction when customer/project colors clash
- Shared settings across all widget instances
- Desktop notifications; optional idle auto-stop
- Translations: EN, DE, FR, ES, IT, NL, PT (BR), PL, UK, RU, JA, ZH (CN)

## Requirements

- KDE Plasma 6
- `secret-tool` (libsecret / libsecret-tools)
- `notify-send` (libnotify) for desktop notifications
- `xprintidle` for idle auto-stop (X11/XWayland; optional)
- A supported time tracker with API access

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
kpackagetool6 -i Plasmai-1.3.0.plasmoid -t Plasma/Applet
```

## Setup

1. Right-click the panel → **Add Widgets** → search for **Plasmai**
2. Right-click the widget → **Configure Plasmai**
3. **Connection** tab: choose service (Kimai / Clockify / Toggl / SolidTime), set URL if needed, save API token, test connection
4. **Favorites** tab: pin frequently used project/activity pairs
5. **Display** / **Behavior** tabs: recent count, panel labels, sparkline arcs, idle stop, notifications
6. **Maintenance** tab (optional): review color-clash groups when distinction is enabled

Use **+** on the widget for manual entries and the chart icon for statistics.

## Shared settings

Profiles, favorites, display, and behavior settings are shared across all Plasmai instances via:

`~/.config/com.github.shrippen.plasmai/shared.json`

## Packaging

Build a store-ready `.plasmoid` archive:

```bash
./scripts/package.sh
```

See [STORE.md](STORE.md) for publishing to [store.kde.org](https://store.kde.org/).

## Translations

UI strings use Plasma `i18n`. Bundled languages: `en`, `de`, `fr`, `es`, `it`, `nl`, `pt_BR`, `pl`, `uk`, `ru`, `ja`, `zh_CN`.

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
`provider` id (`kimai`, `clockify`, `toggl`, `solidtime`). Shared UI helpers remain
in `contents/code/kimaiApi.js`; each provider normalizes responses to that shape.

**Only the Kimai backend is tested.** Clockify, Toggl Track, and SolidTime are
implemented against their public APIs but have not been verified with live accounts
yet — treat them as experimental.

| Service | Notes |
|---|---|
| **Kimai** | Reference implementation (Bearer token + server URL) — **tested** |
| **Clockify** | API key; optional regional API URL — untested |
| **Toggl Track** | API token (Basic auth) — untested |
| **SolidTime** | Bearer JWT + instance URL — untested |

See `contents/code/providers/NOTES.txt` for implementation details.

## Uninstall

```bash
kpackagetool6 -r com.github.shrippen.plasmai -t Plasma/Applet
```

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).
