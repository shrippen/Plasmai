# Changelog

## 1.6.3

### Desktop
- New shatter-clock icon (themed via `currentColor` for Breeze and other icon themes)
- Billable defaults to auto: Kimai resolves billable from activity/project/customer settings instead of forcing true

### Settings
- Display location search waits briefly after typing instead of querying Nominatim on every keystroke
- Behavior option (on by default) asks before saving a running-entry start that falls inside the previous timesheet; the editor shows that previous end time

### Landing page
- Rebuilt with DesignDefault Gruvbox-warm palette, Rajdhani headings, install card with copy button

## 1.6.2

### Desktop
- Favorite clicks while tracking use the same switch dialog and already-running hint as Recents (same activity is not stopped)

## 1.6.1

### Desktop
- Removed the logind shutdown/reboot inhibitor. Kickoff restart tears down plasmashell first, so the lock never delayed reboot the way Kate’s unsaved-file dialog does.

## 1.6.0

### Timesheet
- Week remaining detects kimai-holiday-bundle or the official WorkContractBundle (re-probed hourly) and subtracts approved absences/public holidays for either plugin (WorkContract auto-bookings are not counted twice)

### Desktop
- While tracking, shutdown and reboot wait like an unsaved file (lid close and sleep are not blocked)
- Opening the widget when a timer is already running sends one “Tracking in progress” notification

### i18n
- All 12 bundled languages cover the current UI strings (tags, Recents overflow, create entities, idle, Display options); unused leftover keys were dropped
- KDE Store description is localized for every bundled language

## 1.5.0

### Timesheet
- Tags on Add entry and Edit running (Kimai searchable picker with color pills and create-new; Toggl when the API allows names)
- Billable on Add entry and Edit running (default on for new entries)
- Edit, delete, and split stopped Recents from a permanent overflow menu
- Create customer, project, or activity from the picker overflow
- Week remaining subtracts approved absences and public holidays (`kimai-holiday-bundle`)
- Editing a stopped Recent pre-fills project and activity

### Profiles and settings
- Connection Apply saves profile add/edit; duplicate names are rejected; profile numbers reuse after delete
- Clear token is disabled when none is stored
- Switching KCM tabs no longer resets Connection to the Default profile
- Favorites shows a loading indicator and stays responsive; color pills match Maintenance via the catalog cache
- Profile switcher stays on the main and statistics views, not on Add/Edit screens
- Desktop widget uses the theme `StandardBackground` so KWin blur matches other widgets

### Idle and reminders
- Idle dialog: keep time, discard idle, or discard and continue
- Wayland idle prefers session IdleHint / ScreenSaver over `xprintidle`
- Optional forgot-to-start reminder during work hours (one per day)

### Development
- KCM tab-persistence and Favorites-loading viewer tests
- Unit tests for timesheet fields, holiday week targets, and shared-config merge

## 1.4.2

### Settings
- Checking Display options (panel labels, flyout, desktop widget) enables Apply/OK again
- Optional customer and project color pills on the panel chip (off by default)

### Panel
- Stronger, longer description-save checkmark
- Accessible name on the compact panel chip

### Development
- QML unit tests and plasmoidviewer click tests, including Display Apply with isolated config
- `install-dev.sh` restarts a `plasmashell --replace` session instead of the unused systemd unit

## 1.4.1

### Performance
- Day sparkline no longer repaints the canvas for sun rotation; the now-marker updates every 30s instead of every second
- Loading-row pulse runs only while the row is visible

### Settings
- Display, Connection, Behavior, and Maintenance layouts regrouped so forms wrap instead of clipping
- Maintenance and Favorites read the shared catalog cache so clash groups and project lists appear immediately
- Reloading the catalog from the server no longer reshuffles distinction colors
- Favorites “Reload” sits on the right of the project header; the list uses the full column height
- Config pages declare all `cfg_*` keys and use `Kirigami.Page` so Plasma stops flooding the journal on our tabs

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
- Notifications on start/stop/idle-stop
- Idle auto-stop (`xprintidle`, X11/XWayland)
