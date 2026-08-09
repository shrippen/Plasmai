# Plasmai

A KDE Plasma 6 panel widget for tracking time on your self-hosted [Kimai](https://www.kimai.org/) instance.

**Plugin ID:** `com.github.shrippen.plasmai`  
**Repository:** https://github.com/shrippen/Plasmai

## Features

- Live timer in the panel (project name + elapsed time)
- Start and stop tracking from the popup
- Recent activities as one-click presets (restart)
- Pinned favorites for frequent project/activity pairs
- Multiple Kimai profiles (different instances or accounts)
- Searchable project/activity pickers with customer colors
- API tokens stored securely in KWallet (via `secret-tool`)
- Shared settings across all widget instances
- Global shortcuts (toggle / stop tracking)
- Desktop notifications on start, stop, and idle-stop
- Idle auto-stop when away from the desk

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

Default shortcuts (change in **System Settings → Keyboard → Shortcuts → Plasma**):

| Action | Default |
|---|---|
| Toggle Plasmai tracking | Meta+Shift+K |
| Stop Plasmai tracking | Meta+Shift+S |

## Packaging

Build a store-ready `.plasmoid` archive:

```bash
./scripts/package.sh
```

See [STORE.md](STORE.md) for publishing to [store.kde.org](https://store.kde.org/).

## Development

```bash
plasmoidviewer -a com.github.shrippen.plasmai -l topedge -f horizontal
plasmoidviewer -a com.github.shrippen.plasmai
```

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
