# Plasmai design decisions and principles

This file is the source of truth for how Plasmai should look, behave, and be
extended. Follow it for new features, refactors, and UI tweaks. Code comments
explain local mechanics; this document explains *why*.

Plugin ID: `com.github.shrippen.plasmai`  
Stack: KDE Plasma 6, QML, JavaScript (`.pragma library`). No compiled binaries
(KDE Store QML applet requirement).

Visual foundation:
[shrippen/shrippen.github.io](https://github.com/shrippen/shrippen.github.io) — shared
Gruvbox-warm palette, Rajdhani headings, icon language, and landing-page
template. The widget itself uses `Kirigami.Theme.*` for all interactive chrome;
only brand elements (icon mark fill `#E8DCC4` with gold `#FABD2F` shards, version badges, landing page)
use the shared palette directly. See DesignDefault for the full token table,
typography stack, badge format, and social-preview spec.

---

## Product intent

- Native Plasma panel widget, not a standalone app. It should feel like a
  first-class applet: compact representation in the panel, Kirigami-styled
  popup, standard Configure / context menu, KWallet for secrets.
- Phone companion: a Kirigami app (`app/`) for Android and Plasma Mobile. It
  reuses the provider layer (`contents/code/*`) and copies of the Plasmoid
  components (`app/qml/shared/`), and should match the Plasmoid in features
  and look. On the desktop the Plasmoid stays the product; the app is not a
  desktop window or tray replacement.
- App pages support pull to refresh (`KantePullToRefresh` from the Kante module,
  attached to each page's scroll view, since the pages use Kirigami.Page +
  QQC2.ScrollView instead of Kirigami.ScrollablePage).
- Capability target: Kemai-like time tracking from the panel, with one-click
  recents/favorites and deeper Plasma integration (notifications, idle stop,
  blur, translations).
- Kimai is the reference backend and the only one treated as production-tested.
  Clockify, Toggl Track, and SolidTime are real implementations against public
  APIs but experimental until verified with live accounts.

---

## Architecture

### Representations

- **Panel (horizontal/vertical form factor):** `compactRepresentation` is the
  panel chip; click toggles `expanded` (the flyout). `compactPopupLayout` is
  true in this mode.
- **Desktop / planar:** `fullRepresentation` is the widget itself. Feature
  flags use the `desktopShow*` configuration keys, not the popup ones.
- IDs inside `fullRepresentation` / `compactRepresentation` are **not always
  in document scope** at the `PlasmoidItem` root (Plasma instantiates them as
  separate trees). Any root function that touches `activeEditView`,
  `manualEntryView`, `switchPickers`, `descriptionEdit`, etc. must guard with
  `typeof x !== "undefined" && x` (including inside `Qt.callLater`).

### Data model

- All providers normalize to a **Kimai-shaped** timesheet/project/activity
  object. Shared UI helpers (duration, pickers, sparkline, names) live in
  `contents/code/kimaiApi.js`. Network routing is `timeTracker.js` →
  `contents/code/providers/*.js`.
- Do not fork the UI per provider. Gate features with
  `TimeTracker.providerCapabilities(providerId)` (`statistics`,
  `billableFilter`, `billableEdit`, `tags`,
  `workContract`, `holidayBundle`, `deleteEntry`, `editStopped`, `createEntities`,
  `filmDays`, `drehzettelApi`, `mileage`). The last two only say a Kimai
  plugin *may* be there; the UI still probes it (see "Kimai plugin
  detection").
  Entry tags and billable use one `TimesheetMetaFields` block on Add
  entry and Edit running; hide a field when the capability is false
  (Clockify has no name-based tags yet). Kimai tags use a searchable
  `TagPicker`: inline color pills (Kimai `color` / `color-safe`) inside
  the Add-tags field, searchable popup sized to the result count, and
  “Create tag …” when the search has no match.
  New entries omit **billable** so Kimai auto-resolves it from the
  activity/project/customer settings; the checkbox only sends a value
  when the user actively toggles it (edits: only when it differs from the
  loaded value). `billable` needs Kimai's edit_billable permission; without
  it Kimai answers "This form should not contain extra fields", so
  `kimaiApi.js` retries once without it, remembers that per server/token,
  and the UI says the billable change was not saved. `exported` is never
  sent. Start omits `begin` so Kimai stamps "now" in the user's Kimai
  timezone. Kimai writes (`POST`/`PATCH`) send tags as
  a comma-separated **string**; a JSON array is rejected as Validation
  Failed. Other providers keep tag arrays. Stopped Recents use the same
  use the same Add-entry form for edit; delete
  and split are overflow-menu actions gated by `deleteEntry` /
  `editStopped`. Creating a customer, project, or activity is an
  overflow on the pickers (`Create project` / `Create activity`), not a
  settings tab.
- Customer colors are **Kimai-only**. Other providers must not grow a
  parallel color UI. Shown colors are the raw Kimai colors; fixing colors
  that look too similar is the job of a separate Kimai plugin, not Plasmai.

### Persistence

- **API tokens:** KWallet / libsecret via `contents/code/kwallet.sh` and
  `secret.js`. Never write tokens to `main.xml`, `shared.json`, or logs.
- **Settings:** shared across every Plasmai instance through
  `~/.config/com.github.shrippen.plasmai/shared.json` (`sharedConfig.js` /
  `sharedConfig.sh`). Instance config is a cache; edits persist a patch into
  the shared file.
- **Catalog cache:** `~/.cache/com.github.shrippen.plasmai/catalog-cache.json`.
  Favorites settings should read this cache, not hit the live API on every
  open. The widget writes it only after a real catalog fetch, so the
  `FRESH_MS` age check keeps working.
- Shell helpers are small executable scripts next to the JS that invokes them
  (`kwallet.sh`, `idle.sh`, `notify.sh`, `sharedConfig.sh`, `catalogCache.sh`).
  Keep them POSIX `sh`, quote arguments with `secret.js` `shQuote`.
  The executable engine runs `sh -c <command>`: that argv is world-readable
  and capped at 128 KiB. Pass secrets as `NAME=… exec sh script` (the
  `exec` drops the command line at once) and send large payloads (catalog
  cache, shared.json) in chunks (`catalogCache.sh` / `sharedConfig.sh`
  `append/commit`, `secret.js` `storeJson`).
  Stores write through `mktemp` + `mv` (app: `QSaveFile`). Idle
  prefers the session idle hint on Wayland (`loginctl` /
  `org.freedesktop.ScreenSaver`) and `xprintidle` on X11.

### Configuration UI

- Every settings page **must** be a `Kirigami.Page` (`ConfigPageBase`). Plasma’s
  PageRow injects every `main.xml` key as `cfg_*` / `cfg_*Default` plus
  `title`; a plain `Item` logs TypeErrors. Shortcuts/About `cfg_*` spam is
  Plasma desktop (bug 494417), not fixable in this applet.
- Config chrome: `Kirigami.FormLayout`, `pageMargin` from `gridUnit`, stack
  labels above fields when the window is narrow (`formWide` pattern in
  Display).
- Display binds each control with `property alias cfg_*` (Plasma’s documented
  Apply path). Connection, Favorites, and Behavior sync `cfg_*` in
  `saveConfig()` (Apply/OK) and persist the same patch to `shared.json`.
  Dummy `property var cfg_*` on `ConfigPage` stops Plasma key injection
  TypeErrors on tabs that do not alias every key. Use `onToggled` (not
  `onCheckedChanged`) for Display checkboxes so Apply detects edits. Do **not**
  call `applyToConfiguration(plasmoid.configuration, shared)` from Display
  while the dialog is open — that writes the live applet before Apply. Load
  `shared.json` on tab enter, then overlay onto controls; use
  `SharedConfig.coerceInt()` for SpinBox values because KConfig may inject
  strings. Block `notifyEdited` / `persistShared` while controls are being
  populated (`suppressNotify`).
- Plasma **replaces** the current settings page on each tab switch and
  re-injects `cfg_*` from `main.xml` defaults. Apply can already have
  written the real profiles to `shared.json` while Connection still
  receives `cfg_activeProfileId: "default"` and an empty or
  **default-only** `cfg_profilesJson`. Those placeholders are non-empty
  strings, so a “prefer cfg if present” merge will hide `shared.json`.
  `pageEntered` fires once; Connection must reload whenever the tab
  becomes `visible`, run `resolveConnectionState` (shared over
  placeholders) **before** `ensureSelection` / `syncProfiles`, and never
  persist an empty `profilesJson` patch. Favorites, Display, Behavior,
  persist on enter; Shortcuts and About do not — that is
  why only the first group used to reset Connection to Default. Other
  tabs persist **only their own keys**. `sanitizeProfilesForPersistence`
  must restore `profilesJson` / `activeProfileId` when the shared base
  has those keys missing **or** empty and the live configuration still
  has profiles.
- Favorites project rows need an accessible name so AT-SPI can select
  them. Activity `CheckDelegate`s must handle `Accessible.onToggleAction`
  (AT-SPI Toggle does not fire `onToggled`).
- Tabs: Connection, Favorites, Display, Behavior — keep that
  split. Do not dump tracking actions into Display. Last-used
  project/activity ids are shared.json keys, not Display checkboxes.
  Forgot-to-start lives on Behavior, as does overlapping-start confirmation
  for the running entry. Favorites loads
  `shared.json` first, then the catalog cache, only when its tab is
  visible — do not hit the API on every settings dialog open.
  Favorites must show a running `BusyIndicator` **before** catalog I/O.
  Parse `catalog-cache.json` off the UI thread (`WorkerScript`); never
  `JSON.parse` a large catalog on the same frame as becoming visible.

---

## Visual language

### Theme, not a custom skin

- Use Kirigami / Plasma tokens: `Kirigami.Theme.textColor`, `highlightColor`,
  `positiveTextColor`, `negativeTextColor`, `neutralTextColor`,
  `backgroundColor`, `Kirigami.Units.*`, `Kirigami.Theme.smallFont`.
- **Visual style:** popup views (`contents/ui/*.qml`) and the app
  (`app/qml`) read colors, fonts and shapes from the `Style` singleton, not
  from `Kirigami.Theme` directly. Settings pages (`contents/ui/config`)
  keep `Kirigami.Theme`. Units and spacing stay `Kirigami.Units` / `TouchUi`.
  The setting `visualStyle` (shared.json, Display page / app settings)
  picks one of two styles; the System style is the default and must stay
  pixel-identical to the plain Plasma look (see "Kante" below).
- The main view is `TimerCard.qml` / `TimerCardKante.qml` (timer card,
  loaded by style) plus `EntryLists.qml` (favorites, detected trips, recent,
  start/switch form). They only lay out state and call actions of the widget
  root (`widget`); logic stays in `main.qml`.
- No hardcoded brand palette for chrome in the System style (Kante below is
  the opt-in exception). Customer/project colors come from
  Kimai (or the distinction map). Default placeholder color is
  `KimaiApi.DEFAULT_CUSTOMER_COLOR` (`#d2d6de`).
- Brand accent (`#E8DCC4` warm cream from DesignDefault) is used only for
  the icon mark fill and version badges, never for interactive controls.
  The icon's shards use the gold accent `#FABD2F`; the monochrome variant
  (`docs/icon-mono.svg`, `contents/images/icon.svg` with `currentColor`) is
  used wherever the icon must follow the theme.
  Landing pages and README badges use the full DesignDefault palette.
- Symbolic Breeze icons (`chronometer`, `media-playback-start/stop`,
  `list-add`, `view-statistics`, `document-edit`, `configure`, …). Tint with
  `Kirigami.Icon.color` / `icon.color` when status must read at a glance
  (tracking = positive; error = disconnect icon).
- Desktop-widget blur is handled by the Plasma containment via
  `StandardBackground` (the default). Do not set `TranslucentBackground` —
  it bypasses the containment’s blur pipeline.

### Kante (opt-in style that breaks with Breeze)

The one deliberate exception to "theme, not a custom skin": an opt-in style
built from the [Kante design system](https://github.com/shrippen/shrippen.github.io)
for people who want Plasmai to look like Plasmai rather than like Breeze.

- **Module, not a copy.** Style, wrappers, skins and fonts come from the
  design system's QML module, vendored by `scripts/sync-kante.sh` into
  `contents/ui/Kante` (`KanteStyle`, QQC2 wrappers, skins, fonts) and
  `contents/ui/KantePlasma` (PlasmaComponents3 wrappers of the widget). The
  app takes `contents/ui/Kante` through its qrc (`qml/Kante`). Do not edit
  the copies; change the design system and sync. Plasmai's own colors
  (entity fallback, chart bars) live in `PlasmaiColors`. Import the module
  by directory only (`import "Kante"`), so `KanteStyle` exists once.

- **Opt-in, never default.** `visualStyle` 0 = System, 1 = Kante. Switching
  back restores every Plasma value (`Binding` with `when: KanteStyle.active`, no
  one-way assignments).
- **Palette:** Gruvbox dark; with a light Plasma theme the "Leinen" light
  values (`KantePalette.dark` / `.light`). The app forces dark on Android
  (`KanteStyle.preferDark`).
- **Type:** uppercase Rajdhani for titles and buttons, JetBrains Mono for
  figures (timer, times, durations) and small section labels; body text
  stays the system font. Fonts ship in `contents/ui/Kante/fonts` (SIL OFL) and are
  only loaded, never installed.
- **Shape:** square controls; cards and dialogs cut the top-right corner
  (`KanteCard`, `KanteStyle.chamfer`) and carry an accent bar on top.
- **Translucency:** Kante never paints the popup ground. Plasma's blur and
  transparency stay; surfaces are tints with alpha (card 60 %, sunken 50 %,
  dialog 97 %). Color only in small opaque areas (project bars, chart
  segments, the gold timer, primary buttons). Muted text is one step
  lighter on glass (`#bdae93`).
- **Main view:** timer card with the accent-colored timer, activity as the
  heading, a day strip when idle; favorites as tiles (two per row); Recent as
  a time line (time · color bar · activity · project · duration).
- **Controls:** views use the wrappers `KanteButton` (with `emphasis` Primary /
  Destructive), `KanteToolButton`, `KanteTextField`, `KanteHeading`,
  `KanteDialog`; the widget uses `KantePlasmaButton`, `KantePlasmaToolButton`
  and `KantePlasmaHeading` instead of the first three. In the
  System style they are the plain Plasma / QQC2 controls. In Kante they hide
  the style's frame and content and draw their own, so disabled states fade
  instead of taking the platform's disabled colors. `KanteScope` hands the
  Kante colors to `Kirigami.Theme` for everything else (labels, check boxes,
  spin boxes); popups need their own (`KanteDialog`, app `KanteDialogSkin`).
  Controls that keep their base type get a skin as a child instead:
  `KanteCheckSkin` (check boxes, switches), `KanteFieldSkin` (spin boxes,
  combo boxes, text areas), `KanteSliderSkin`, `KantePopupSkin` (menus),
  `KanteMessageSkin` (inline messages), app `KantePageTitle` (page header).
  Each hides the style's part and draws its own only while Kante is on.
- **Panel chip:** keeps the Plasmai mark while tracking, tinted with the
  accent, square frame.

### Kante Light (opt-in, Kante shapes on the platform look)

`visualStyle` 2. For people who want Plasmai to sit with Breeze and still
read as Kante. It is the design system's `KanteStyle.Kind.KanteLight`:

- **Every color is the theme's.** `KanteStyle` roles forward
  `Kirigami.Theme` live (Plasma theme in the widget, color scheme in the
  app), so any scheme, light or dark, switched at runtime, just works. Never
  hardcode or cache a color for this style.
- **Controls stay the platform's.** Buttons, fields, check boxes, menus and
  dialogs are the plain Plasma / Kirigami ones: the wrappers and skins only
  draw in `KanteStyle.themed` (full Kante). The panel chip stays System.
- **From Kante:** the Kante layouts (timer card, favorite tiles, Recent as
  a time line, Kante statistics), cut corners and accent bars in the
  highlight color, titles (level 1–2 headings, page titles) in uppercase
  Rajdhani, figures and section labels in JetBrains Mono with a rule.
  Card headings stay the system font.
- Views branch on `KanteStyle.active` (Kante or Kante Light) for layout and
  shape, on `KanteStyle.themed` only for palette-dependent spots.

### Hierarchy and color bars

- Customer is the colored identity; project is secondary; activity is the
  bold title. `ColorLabelRow` keeps a **fixed left slot** so thick customer
  bars and thin project bars share one vertical axis. Do not let bars jump
  horizontally between rows.
- Bars show the Kimai colors unchanged. Do not re-add color shifting in
  Plasmai; similar colors are fixed on the server by a separate Kimai plugin.

### Density and touch

- Default desktop density is compact (panel flyout). All hit targets, row
  padding, picker height, and flyout size go through the `TouchUi` singleton
  (`preference`: auto / on / off from `touchMode`). Do not sprinkle raw
  `gridUnit * 2.5` button heights; use `TouchUi.buttonMinHeight` and friends.
- Icon-only toolbuttons in the header when not in touch mode; text beside
  icon when `TouchUi.active`. Always set `text:` anyway (accessibility +
  tooltips).

### Motion and feedback

- Short opacity fades (~160ms, `Easing.OutCubic`) for section show/hide.
  Do not add decorative animation that runs while the flyout is collapsed
  (sparkline sun spin and canvas repaints are gated on flyout open; sparkline
  `nowTick` is ~30s, not per-frame).
- Success on the running-entry description: a **high-chroma** positive
  checkmark at the same `iconSizes.small` as the save glyph (not a larger
  overlay), held fully opaque, then faded out. Paint the glyph (do not use
  a themed `dialog-ok` icon — those ignore tint). The circle outline uses a
  desaturated sibling of the same hue, not `positiveTextColor` (already loud).
  Transient hints (already-running row) stay short (~1.4s).
- Busy state: small `BusyIndicator` in the header, disable mutating actions
  (`isBusy`, connection error). `LoadingRow` placeholders only while a list
  is empty and loading — do not flash them over existing data.

### Film day view (Kimai only)

- `mainViewMode: "filmday"` (`FilmDayView.qml`; app: `FilmDayPage.qml` with the
  shared copy), gated by `providerCapabilities.filmDays` (Kimai only — no parallel
  UI on other providers).
- One shooting day = one Kimai timesheet entry for that calendar day (begin/end,
  created or patched like Add entry; only a stopped entry of the picked project is
  reused). If the project has more stopped entries that day, the view says so
  (their total time) and offers "Merge into one entry": begin/end stretch over
  all of them, and after a successful save the other entries are deleted
  (`FilmDaySync.deleteEntries`; failures are reported, never retried silently). The film-specific extras — break, catering, day category, day type,
  production shooting day, surcharge day, extra pay, note — belong to
  [kimai-drehzettel-bundle](https://github.com/shrippen/kimai-drehzettel-bundle).
- **Online only** (`filmDaySync.js`, shared by Plasmoid and app so the
  orchestration exists once): the extras live only in the plugin; Plasmai keeps
  no copy on the device, queues nothing and never compares device and server
  values.
  - Plugin answers `ping` with `v1` → **server mode**: the view loads
    `GET /v1/film-days/{date}?project=` and shows the extras.
  - `ping` 404 (or no `v1`) → no plugin: extras hidden, "only begin and end are
    saved".
  - Film-day GET 404 (`no_engagement`) → extras hidden, same hint. Missing
    `drehzettel` permission (`ping.permissions.view` false or 403) → same, with
    a permission hint.
  - Network/5xx → extras hidden, "only begin and end can be saved right now".
  - Project or day change reloads the day, which is also the engagement check.
    The `user` parameter is never sent (own data only).
- **Save is two-step**: timesheet first, then `PUT` with **only the keys that differ
  from the loaded server JSON** (`FilmDays.toApiPatch`; keys the server JSON does
  not have — an older plugin — are never sent, so extra pay is hidden there). A
  failed PUT is reported ("begin and end were saved, the extras were not"); the
  user saves again.
- Field mapping (decision D7): Plasmai's old "production day" counter is the
  production's running shooting day → `shootingDayNumber` ("Production shooting
  day"). The server's `productionDay` is a separate override for the day of the
  TV FFS calendar week that drives the 6th/7th-day surcharge ("Surcharge day
  (1–7, empty = automatic)"). Unknown response keys (e.g.
  `streakMode`) are ignored. Break 0–720 with a
  "Default (n min)" option (`null`, the ruleset's `defaultBreakMinutes`). `catering` yes/no ↔ bool,
  category `""` ↔ `null`, note trimmed, max 500.
- Earnings show the plugin's day summary (`payCents`, customer currency); Plasmai
  never computes pay itself. Extra pay is entered in the customer's currency.
- **Shared data maps** (`pluginProbesJson`, `SharedConfig.DATA_MAP_KEYS`) are
  written by the Plasmoid and the app. Never write them as a whole from memory:
  `Platform.patchShared(…, patch, bases)` three-way merges each top-level key
  onto the file as loaded just now (`SharedConfig.mergeMapJson`), writes are
  queued one at a time per process, and the Plasmoid's settings-wide write
  (`fromConfiguration(…, { withoutDataMaps: true })`) leaves them out.
- Same-day begin/end only (no overnight span across midnight), matching the
  reference Android app's day screen.

### Trips (kimai-anfahrten, Kimai only)

- Gated by `providerCapabilities.mileage`, the `showTrips` setting (shared,
  default on) and `GET /api/mileage/ping`: 200 with `v1` and
  `permissions.view` → available; 404 → absent. The probe is cached 24 h per
  profile in `pluginProbesJson` (key `profileId|url|mileage`) like the
  Drehzettel probe. Writing needs `permissions.editOwn`, deleting `deleteOwn`.
- Requests in `kimaiApi.js` (`fetchTrips`, `createTrip`, `patchTrip`,
  `deleteTrip`, `fetchVehicles`, `fetchTripSuggestions`,
  `acceptTripSuggestion`, `dismissTripSuggestion`, `fetchMileageMeta`); form,
  bodies and totals in `mileage.js`, shared by both UIs. The `user` parameter
  is never sent. A new trip sends every set field; an edit sends only the keys
  that differ from the loaded trip. `timesheet` is only sent when the ping lists
  `tripTimesheet`; accepting with project/distance/comment/timesheet needs
  `acceptFields`; `from`/`to` queries need `dateRange` (else year/month).
- Times: the plugin writes `departure`/`arrival` in the user's Kimai timezone
  and reads "HH:MM" in it, so the form takes the literal "HH:MM" of the string
  (no device-timezone conversion).
- `TripSheet.qml` (Plasmoid `mainViewMode: "trip"`, app `TripEditPage`) is the
  one form: date, purpose, means of travel (+ assigned vehicle when the user
  has vehicles), one-way distance, round trip, from/to, optional times,
  comment, linked time entry (can be unlinked). Plugin field errors
  (`400 {"errors": {field: message}}`) show under the form. A detected trip
  opens the same sheet read-only for date/route/times ("Edit and accept").
- Entry points: header "Log trip", the running entry's trip button and the
  Recent row menu (linked to that entry) on the Plasmoid; drawer "Trips"
  (`TripsPage`: month logbook, detected trips, "Log trip", "Commute today"),
  the running entry and the Recent menu in the app; after saving a travel film
  day the app offers "Log trip" in the notification.
- Detected trips (`TripSuggestionList.qml`) only when the profile has Dawarich
  configured (`ping.profile.dawarichConfigured`); the Plasmoid loads them when
  the popup opens, at most every 10 minutes, last 14 days, 2–3 rows.
- Statistics show trip km this week/month (`StatsData.tripKmSummary`, the
  plugin's `totalKm`, i.e. round trips count twice).

### Charts and sparkline

- Sparkline is a 24h work-day bar (business hours from Kimai calendar when
  available, else 08:00–18:00), overtime in `neutralTextColor`, tracked time
  in `positiveTextColor`. Sun/moon/work arcs are optional (`showSparklineArcs`)
  and punch soft holes under header labels so text stays readable.
  Display location search is Nominatim; debounce typing, keep the field
  usable while a request is in flight, ignore late replies for older queries.
- Stats view is a secondary pane (`mainViewMode`), not a separate window.
  Billable filters and day/week navigation stay in-widget. Empty charts use
  a single quiet empty string, not a second placeholder stack.

### Copy and i18n

- Every user-visible string goes through `i18n` / `i18nc`. Bundled languages
  live under `contents/locale/` (see README). Do not concatenate untranslated
  fragments.
- Errors: `ApiErrors.text()` — user-facing, no stack traces, no raw JSON.
  Distinguish network / auth / forbidden / not found / server.
- Panel tooltip and compact labels must stay short; elide, don’t wrap the
  panel chip.

### Accessibility

- Compact chip: `Accessible.role: Button`, name “Plasmai”, press toggles the
  flyout. Optional customer/project color pills (`CustomerColorDot`) are
  independent panel flags, off by default. They appear only while tracking.
- Favorite/recent rows: `Accessible.role: ListItem`, description makes clear
  that activating **starts or switches** tracking (tests also use this to
  avoid live API clicks). Stopped Recent rows show a permanent **Entry
  actions** overflow icon (`view-more`); edit, delete, and split live in
  that menu when the provider allows. Those exact names let tests skip
  history mutations without blocking Add entry. Create overflow and idle
  dialog actions (`Create project`, `Keep time`, `Discard idle`, …) are
  also skipped — they mutate the tracker.
- Icon-only buttons keep a `text` and `ToolTip`.
- Panel click expands/collapses the flyout only (see Interaction principles).

---

## Interaction principles

- **Panel click** expands/collapses. It must not start or stop tracking
  (too easy to misclick). Explicit Start / Stop / Continue / row click do
  that.
- **Stop** may confirm (`confirmBeforeStop`). Switching away from a running
  activity via Recent or Favorites shows the switch dialog (current vs target
  cards), not a silent stop+start. Clicking the same project/activity that is
  already running shows the already-running hint; it must not stop the timer.
- **Continue** is “last recent”, not a generic Start. Favorites and Recent
  are one-tap presets. If Recents are empty, **Start · last used** uses the
  last started project/activity pair from shared.json. Favorite and Recent
  **row click** start or switch with the same dialog and hint; they do not
  open an editor. A stopped Recent row shows a permanent overflow icon
  when edit/delete/split is available; edit,
  delete, and split are menu items (never on Favorites). Delete always confirms.
  Split asks for a time strictly between begin and end, then patches the
  original `end` and creates the second half with the same project, activity,
  tags, and billable. The running timesheet is edited in-place
  (`ActiveEditView`), not from Recent. Create-project picks the customer with
  the same customer color pills as project pickers (`ColorLabelRow`).
- **Idle:** when idle stop is enabled and the session is idle past the
  threshold, ask Keep / Discard idle / Discard and continue. Do not silently
  stop if the dialog can open. Expand the flyout so the dialog is visible.
  Idle checks must not run while `plasmoid.userConfiguring`.
- **Logout/reboot:** a plasmoid cannot join ksmserver like Kate’s unsaved-file
  dialog. logind `systemd-inhibit` from inside plasmashell does not delay
  Kickoff reboot (the session dies first and drops the lock). Do not restore
  that hold.
- **Already running:** the first `applyActiveTimesheet` after load that was
  not a local Start/Switch/Continue sends one “Tracking in progress”
  notification. Poll refreshes must not repeat it.
- **Forgot-to-start** is one notification per local day during configured
  work hours, opt-in on Behavior. The notification daemon handles Do Not
  Disturb.
- **Edit** (running entry) is in-place (`ActiveEditView`), not a settings
  page. It can also set billable and tags when the provider allows.
  When `confirmStartBeforePreviousEnd` is on (Behavior, default on), the
  editor shows the previous stopped entry’s end and asks before saving a
  start that is earlier; the user can confirm and set it anyway.
  Manual **Add entry** is a separate `mainViewMode` and uses the same
  `TimesheetMetaFields` extras. Editing a stopped Recent reuses that
  form (`editingStoppedTimesheet`); Save patches instead of creating.
- **Configure** is the only path to tokens, profiles, and display flags.
  Placeholder “Connect a time tracker” when unconfigured; don’t hide the
  widget.
- Right-click anywhere on the full UI opens the standard applet menu
  (a capturing `MouseArea` is required because labels steal RMB).
- Do not click-test live Start/Stop/Continue/favorite/recent in default CI
  (`tests/README.md`). Those mutate the user’s tracker. Also skip Recent
  overflow, Create project/activity/customer, and idle Keep/Discard even
  with `PLASMAI_TEST_LIVE`. Also skip overlap **Set anyway**.

---

## Performance and robustness

- Avoid canvas/scenegraph work when the popup is closed. Gate expensive
  loaders (`LoadingRow`, sparkline animators, stats) on visibility and
  `mainViewMode`.
- `plasmoid.configuration` Connections must not refresh from the API while
  `plasmoid.userConfiguring` (config dialog open) — that fights the editor
  and rewrites shared.json.
- Polling: `refreshInterval` (seconds), idle check once a minute when
  enabled, forgot-to-start every five minutes when enabled. No busy-loops,
  no per-keystroke API calls (description save is explicit: Enter or the
  save button; Display location search waits ~400ms after typing and
  drops stale Nominatim replies).
- Kimai **week remaining** (`remainingWeekSeconds`) subtracts tracked time
  from an effective week target: contracted hours minus approved vacation /
  sickness / other absences and public holidays for the current Mon–Sun.
  Detect **one** Kimai plugin per server (they are not installed together):
  `GET /api/holiday/absences/types` → kimai-holiday-bundle;
  else `GET /api/absences/types` → official WorkContractBundle
  (`controlling.html`). Re-probe at most once per hour per server URL so a
  later plugin swap is picked up without hammering 404s every poll.
  Normalize both JSON shapes into the same absence/
  holiday records. WorkContractBundle may auto-book those hours as
  timesheets; remaining adds an **absence credit** so target reduce and
  bookings do not double-count. Fall back to the plain contract total when
  neither plugin answers.
- **Kimai plugin detection** (`KimaiApi.detectPlugin`): one GET probe per plugin
  and profile. 200 (plus a plugin check such as "`apiVersions` has `v1`") →
  present, 404 → absent, 403 → forbidden. The answer is cached **persistently**
  in `shared.json` `pluginProbesJson` (key `profileId|url|plugin`, 24 h) so an
  offline start keeps the last known state; network errors, 401 and 5xx never
  overwrite it and are not cached. The Plasmoid probes when the film day view
  opens, the app once after login. Holiday/WorkContract detection still uses its
  own in-memory hourly probe.
- Failures set `connectionState` / `errorMessage` and offer Retry +
  Configure. Do not toast every poll failure.

---

## Testing and packaging

- QML unit tests (`tests/unit`) cover `.js` libraries with `qmltestrunner`.
  Viewer tests launch `plasmoidviewer` against the **source tree**, click
  chrome, and fail on applet `TypeError` / `ReferenceError` in viewer stderr
  or journal lines that mention Plasmai. Ignore Plasma desktop / containment
  / digitalclock / Shortcuts `cfg_*` noise. Display Apply is covered by
  `tests/viewer/test_display_options.py` (isolated `XDG_*`, no user
  `shared.json`). Connection tab re-entry (profiles survive
  Favorites/Display/Behavior) is covered by
  `tests/viewer/test_kcm_tab_persistence.py`. Favorites loading indicator
  and KCM responsiveness are covered by
  `tests/viewer/test_favorites_loading.py`. WorkContractBundle remaining-
  hours math is fixture-tested from the public Absence/PublicHoliday JSON
  shape; there is no live paid-plugin call.
- Dev install: `./scripts/install-dev.sh` (build number bump, `kpackagetool6
  -u`, plasmashell restart). Store packages keep `Build: 0`.
- Release: `./scripts/package.sh`, version in `metadata.json` + changelog
  style `Release Plasmai x.y.z with …`. See `STORE.md`.

---

## When adding something

1. Prefer Kirigami/Plasma controls and `TouchUi` metrics over custom chrome.
2. Keep provider-specific code behind `timeTracker` + capabilities flags.
3. Persist user data in shared.json or the catalog cache, never only in the
   instance config.
4. Guard representation IDs; add `Accessible.name` on new clickable chrome.
5. If it can fire a QML error in plasmoidviewer, add or extend a test.
