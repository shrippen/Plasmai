# Changelog

## 1.4.0

### Touch optimization
- Display setting: Automatic (Plasma tablet mode) / On / Off
- Larger tap targets for buttons, list rows, favorites, pickers, and date/time controls when touch mode is active
- Bigger panel icon and flyout size in touch mode; chart segments show tooltips on tap

### Layout & pickers
- Compact header: title and connection status in one block; action icons vertically centered
- Flyout uses full width when no main scrollbar is needed
- Project/activity popup shows a scrollbar when the list exceeds the available height
- Statistics billable filter stretches to full width

## 1.3.1

### Pickers & layout
- Shared project/activity pickers across main view, manual entry, and active-entry editor
- Popup open direction uses the visible flyout viewport (opens above only when space below is tight)
- Pickers close when the main view is scrolled

### Recent list
- Tapping an already-running activity shows a short “already running” hint with the panel-style elapsed counter (green, monospace)

### Stats
- Week navigation for statistics charts

### Development
- Optional build number in the main header for local `install-dev` builds (`BUILD=0` in store releases)

## 1.3.0

### Switch from Recent while tracking
- Clicking a **Recent** entry while a timer is running opens a confirmation dialog
- Stop the current activity and start the selected one in one step
- Dialog shows current → target with customer/project/activity styling (color bars) and translations

### Day Sparkline (from 1.2.2)
- Sun icon aligned on the arc; moon icon removed; smooth 3-minute rotation

## 1.2.2

### Day Sparkline
- Sun icon now sits exactly on the arc curve (uses quadratic Bézier point matching)
- Removed moon icon to avoid overlap clutter — only the sun icon is shown
- Sun icon rotates smoothly (full revolution every 3 minutes)
- Fixed animation to run at 25 fps for fluid motion instead of per-second ticks

## 1.2.1

### Display settings
- Compact usual work-hours fields (no longer stretch across the page)
- Form layouts adapt on narrow config windows so labels and checkbox text stay visible
- Day-sparkline location search and related controls wrap cleanly when the window is small

## 1.2.0

### Edit running entry
- Edit icon beside **Stop** opens an inline editor for the active timesheet
- Change **start time**, **project**, and **activity** (same pickers as new activity)
- Fields prefill from the current entry; Save patches via the provider API
- On narrow layouts, Edit/Stop move under the today/week work summary instead of overflowing

### i18n
- Strings for the active-entry editor in all bundled languages

## 1.1.0

### Multi-provider backends
- Pluggable tracker API via `timeTracker.js`
- **Clockify**, **Toggl Track**, and **SolidTime** alongside Kimai
- Connection settings: choose service per profile; workspace/org ids stored after a successful test

### Manual entries & statistics
- **+** in the main view opens a compact editor (project/activity pickers + begin/end)
- Secondary **Statistics** screen (today/week totals, project breakdown, charts) — switchable without replacing the timer

### Day sparkline (concept H)
- Zoomed business-hours view (±1h, expanded for segments and “now”)
- Sun and moon arcs above the bar; work arc with briefcase icon below
- Layered bar: moon base → sun fill with soft rise/set bleed → business hours → activity segments
- Soft holes under the timer/customer header so arcs don’t cross the text
- Capsule ends stay rounded at any zoom; arc glow stays continuous on wide windows
- Optional “Show sun, moon, and work arcs” display setting

### Colors & maintenance
- Optional within-category color distinction (vivid replacements for clashes)
- Maintenance settings page listing clash groups (kept vs shifted)

### i18n
- Added FR, ES, IT, NL, PT (BR), PL, UK, RU, JA, ZH (CN) alongside EN and DE
- Strings for statistics, manual entry, multi-provider connection, color distinction, and Maintenance

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
