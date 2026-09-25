# Changelog

## Unreleased

### Trips (kimai-anfahrten plugin, Desktop and app)
- With the Anfahrten plugin (MileageBundle) on the Kimai server: log a trip from the header, from the running entry or from a Recent entry's menu (linked to that entry); edit and delete trips
- Trips detected from Dawarich show above Recent (Desktop) and on the new Trips page (app): accept, edit and accept, or dismiss
- App: Trips page with the month's logbook, "Log trip" and "Commute today"; after saving a travel day the film day page offers "Log trip"
- Statistics show the trip km of this week and month
- New setting "Trips" (on by default) to hide all of it

## 2.0.0

### Android / Plasma Mobile
- New: Plasmai is now also a standalone Kirigami app for Android and Plasma Mobile (KF6), built from `app/`, sharing the Kimai/Clockify/Toggl Track/SolidTime backend and QML components with the Plasmoid
- Full timer flow: start/stop/switch activity, continue last entry, edit the running entry, add a manual entry, favorites (pin/unpin/start), recent entries with edit/split/delete, statistics, color maintenance, and settings — matching the Plasmoid's behavior
- Kirigami pages, dialogs (`PromptDialog`/`Dialog`) and date/time pickers (vendored `kirigami-addons` `DatePopup`/`TimePopup`) replace bespoke controls
- Breeze-Dark icon subset bundled for Android, which has no system icon theme
- Translations: the 11 languages already shipped for the Plasmoid now also cover the app (Plasma Mobile via compiled `.mo` catalogs through KLocalizedString; Android, which has no gettext runtime, via bundled JSON catalogs)
- Add entry now loads promptly — the date/time popups are built on first use instead of upfront
- Timer card layout matches the Plasmoid's hero card (summary, continue button, and description all inside one bordered card)
- Split works (the second half was never created); save errors on the Film day page are shown
- Token loads for two profiles in flight no longer lose one; settings and cache files are written atomically

### Desktop
- Redesigned icon: half-dial clock with a gold shard trail; the panel icon uses the mono variant (tinted by the theme) while idle, the store and Android icons use the colored version
- Film day view (Kimai only): a shooting-day entry screen modeled on the Android TimeSheet app — begin/end/break, catering, day category/type, production shooting day, extra pay, note. Begin/end save to a normal Kimai entry; the film-specific extras go to kimai-drehzettel-bundle when it is installed (see below), else they stay on this device
- Film day saves only update a finished entry of the picked project; other projects' entries and the running timer are left alone, and picking a project reloads that day

### Film day and the Drehzettel plugin (Desktop and app)
- With kimai-drehzettel-bundle on the server, break, catering, day category/type, shooting day, extra pay and note are stored in the plugin instead of on the device; without it nothing changes (local mode, with a hint)
- The plugin is detected per profile and the answer is remembered, so an offline start does not fall back to local storage; the app now probes it too
- Only changed fields are sent; if sending fails (offline), the change is queued and sent later unless the day was changed on the server meanwhile (the server wins)
- Projects without an engagement for the day, or users without the Drehzettel permission, save begin and end only; the extras are hidden with a hint
- Break up to 12 h with a "Default" option from the engagement's ruleset; new "Surcharge day (1–7, empty = automatic)" field for the 6th/7th-day surcharge; the old production-day counter is now "Production shooting day"; note limited to 500 characters; ruleset name in the header; extra pay in the customer's currency; earnings from the plugin's day summary
- One-time offer to copy film days stored on this device to the plugin; days with other values on the server keep the server values, local copies are never deleted
- German translation for the film day view

### Kimai
- Works for regular users (ROLE_USER) again: `exported` is no longer sent, and `billable` only when you change it; without the edit_billable permission the entry is saved without it and a hint is shown
- Manual entries and running-entry edits no longer save as non-billable when the checkbox was left alone
- Start lets Kimai set the begin time (Kimai timezone instead of the device clock)
- Continue keeps the description and tags (`copy=all`)
- Statistics/week totals no longer fail for ranges with exactly 100, 200 … entries
- Customers, projects and activities load in one request (no duplicates above 500)
- Hidden customers, projects and activities are no longer offered in the pickers
- Requests are aborted after 30 s so the widget and app do not stay busy
- Discarding idle time stops the entry where idle began, not where you clicked
- Short absence durations in seconds are no longer read as hours; day sparkline is correct on DST days

### Security and robustness (Desktop)
- The API token no longer stays on the `sh -c` command line while it is stored
- Large catalog caches and `shared.json` (>128 KiB, e.g. many film days) are saved in chunks; config/cache files are written via `mktemp`
- Idle detection asks the ScreenSaver D-Bus when logind does not report idle
- Notifications whose text starts with "-" are shown; widget paths with spaces work for the shell helpers

## 1.x fixes on main (before the 2.0 merge, all included in 2.0.0)

These landed on `main` for the 1.x line after 1.6.3 (not tagged separately) and are part of 2.0.0 above, there also for the app.

### Kimai
- Works for regular users (ROLE_USER) again: `exported` is no longer sent, and `billable` only when you change it; without the edit_billable permission the entry is saved without it and a hint is shown
- Manual entries no longer save as non-billable when the checkbox was left alone
- Start lets Kimai set the begin time (Kimai timezone instead of the desktop clock)
- Continue keeps the description and tags (`copy=all`)
- Statistics/week totals no longer fail for ranges with exactly 100, 200 … entries
- Customers, projects and activities load in one request (no duplicates above 500)
- Hidden customers, projects and activities are no longer offered in the pickers
- Requests are aborted after 30 s so the widget does not stay busy

### Desktop
- Discarding idle time stops the entry where idle began, not where you clicked
- Idle detection asks the ScreenSaver D-Bus when logind does not report idle
- Notifications whose text starts with "-" are shown
- Short absence durations in seconds are no longer read as hours; day sparkline is correct on DST days

### Security and robustness
- The API token no longer stays on the `sh -c` command line while it is stored
- Large catalog caches (>128 KiB) are saved in chunks; config/cache files are written via `mktemp`
- Widget paths with spaces work for the shell helpers

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
