# Changelog

## 1.0.0

First stable release of **Plasmai** (`com.github.shrippen.plasmai`).

### Tracking
- Start, stop, and switch activities from the panel popup or desktop widget
- Live elapsed timer with project/activity display
- Edit the active timesheet description (inline save)
- Continue last activity; recent list with durations
- Pinned favorites with customer color markers

### Work overview
- Today / week totals and remaining time vs Kimai work contract
- 24h day sparkline with usual work hours, overtime, hour ticks, and sunrise/sunset coloring
- Location search (OpenStreetMap Nominatim) or custom coordinates for daylight coloring
- Per-surface visibility for work summary and sparkline (panel flyout vs desktop)

### Configuration
- Multiple Kimai profiles; API tokens in KWallet
- Shared settings across widget instances
- Searchable project/activity pickers (customer grouping, keyboard navigation)
- Display, behavior, connection, and favorites settings with scrolling and clear page titles
- English and German translations

### Other
- Optional desktop blur background
- Notifications on start/stop/idle-stop
- Idle auto-stop (`xprintidle`, X11/XWayland)
- Migrate tokens and shared config from `org.arian.kimaitracker`
