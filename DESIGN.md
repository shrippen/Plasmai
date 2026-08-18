# Plasmai design decisions and principles

This file is the source of truth for how Plasmai should look, behave, and be
extended. Follow it for new features, refactors, and UI tweaks. Code comments
explain local mechanics; this document explains *why*.

Plugin ID: `com.github.shrippen.plasmai`  
Stack: KDE Plasma 6, QML, JavaScript (`.pragma library`). No compiled binaries
(KDE Store QML applet requirement).

---

## Product intent

- Native Plasma panel widget, not a standalone app. It should feel like a
  first-class applet: compact representation in the panel, Kirigami-styled
  popup, standard Configure / context menu, KWallet for secrets.
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
  `colorDistinction`, `billableFilter`, `billableEdit`, `tags`,
  `workContract`, `holidayBundle`, `deleteEntry`, `editStopped`, `createEntities`).
  Entry tags and billable use one `TimesheetMetaFields` block on Add
  entry and Edit running; hide a field when the capability is false
  (Clockify has no name-based tags yet). Kimai tags use a searchable
  `TagPicker`: inline color pills (Kimai `color` / `color-safe`) inside
  the Add-tags field, searchable popup sized to the result count, and
  “Create tag …” when the search has no match.
  New entries default **billable** to true because Kimai’s API treats
  omitted booleans as false. Kimai writes (`POST`/`PATCH`) send tags as
  a comma-separated **string**; a JSON array is rejected as Validation
  Failed. Other providers keep tag arrays. Stopped Recents use the same
  use the same Add-entry form for edit; delete
  and split are overflow-menu actions gated by `deleteEntry` /
  `editStopped`. Creating a customer, project, or activity is an
  overflow on the pickers (`Create project` / `Create activity`), not a
  settings tab.
- Color distinction, customer colors, and Maintenance clash groups are
  **Kimai-only**. Other providers must not grow a parallel color UI.

### Persistence

- **API tokens:** KWallet / libsecret via `contents/code/kwallet.sh` and
  `secret.js`. Never write tokens to `main.xml`, `shared.json`, or logs.
- **Settings:** shared across every Plasmai instance through
  `~/.config/com.github.shrippen.plasmai/shared.json` (`sharedConfig.js` /
  `sharedConfig.sh`). Instance config is a cache; edits persist a patch into
  the shared file.
- **Catalog cache:** `~/.cache/com.github.shrippen.plasmai/catalog-cache.json`.
  Favorites settings and Maintenance should read this cache, not hit the live
  API on every open. “Reload from server” must **not** reshuffle assigned
  colors: fingerprint entities (normalized hex, order-independent); keep the
  widget-theme half of `settingsKey`; rebuild distinction only when the
  distinction inputs actually change.
- Shell helpers are small executable scripts next to the JS that invokes them
  (`kwallet.sh`, `idle.sh`, `notify.sh`, `sharedConfig.sh`, `catalogCache.sh`).
  Keep them POSIX `sh`, quote arguments with `secret.js` `shQuote`. Idle
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
  and Maintenance persist on enter; Shortcuts and About do not — that is
  why only the first group used to reset Connection to Default. Other
  tabs persist **only their own keys**. `sanitizeProfilesForPersistence`
  must restore `profilesJson` / `activeProfileId` when the shared base
  has those keys missing **or** empty and the live configuration still
  has profiles.
- Favorites project rows need an accessible name so AT-SPI can select
  them. Activity `CheckDelegate`s must handle `Accessible.onToggleAction`
  (AT-SPI Toggle does not fire `onToggled`).
- Tabs: Connection, Favorites, Display, Maintenance, Behavior — keep that
  split. Do not dump tracking actions into Display. Last-used
  project/activity ids are shared.json keys, not Display checkboxes.
  Forgot-to-start lives on Behavior. Favorites and Maintenance load
  `shared.json` first, then the catalog cache, only when their tab is
  visible — do not hit the API on every settings dialog open.
  Favorites must show a running `BusyIndicator` **before** catalog I/O.
  Parse `catalog-cache.json` off the UI thread (`WorkerScript`); never
  `JSON.parse` a large catalog on the same frame as becoming visible.
  Favorites color pills use the same `ColorDistinct` maps as Maintenance.
  Hydrate them from the catalog-cache clash groups Maintenance already
  stored — do not recompute hues on Favorites open. Rebuild only when
  those groups are missing. Apply the maps after the project list paints
  so the KCM stays switchable.

---

## Visual language

### Theme, not a custom skin

- Use Kirigami / Plasma tokens: `Kirigami.Theme.textColor`, `highlightColor`,
  `positiveTextColor`, `negativeTextColor`, `neutralTextColor`,
  `backgroundColor`, `Kirigami.Units.*`, `Kirigami.Theme.smallFont`.
- No hardcoded brand palette for chrome. Customer/project colors come from
  Kimai (or the distinction map). Default placeholder color is
  `KimaiApi.DEFAULT_CUSTOMER_COLOR` (`#d2d6de`).
- Symbolic Breeze icons (`chronometer`, `media-playback-start/stop`,
  `list-add`, `view-statistics`, `document-edit`, `configure`, …). Tint with
  `Kirigami.Icon.color` / `icon.color` when status must read at a glance
  (tracking = positive; error = disconnect icon).
- Desktop-widget blur is handled by the Plasma containment via
  `StandardBackground` (the default). Do not set `TranslucentBackground` —
  it bypasses the containment’s blur pipeline.

### Hierarchy and color bars

- Customer is the colored identity; project is secondary; activity is the
  bold title. `ColorLabelRow` keeps a **fixed left slot** so thick customer
  bars and thin project bars share one vertical axis. Do not let bars jump
  horizontally between rows.
- Color distinction shifts **within a category only** (customers vs
  customers, not customer vs project). Same hex may still appear across
  categories. Replacement hues bias toward the current Plasma theme palette,
  skipping greys. Do not randomize on every refresh.

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

### Charts and sparkline

- Sparkline is a 24h work-day bar (business hours from Kimai calendar when
  available, else 08:00–18:00), overtime in `neutralTextColor`, tracked time
  in `positiveTextColor`. Sun/moon/work arcs are optional (`showSparklineArcs`)
  and punch soft holes under header labels so text stays readable.
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
  activity via Recent shows the switch dialog (current vs target cards), not
  a silent stop+start.
- **Continue** is “last recent”, not a generic Start. Favorites and Recent
  are one-tap presets. If Recents are empty, **Start · last used** uses the
  last started project/activity pair from shared.json. Recent **row click**
  still starts or switches; it does not open an editor. A stopped Recent row
  shows a permanent overflow icon when edit/delete/split is available; edit,
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
- **Forgot-to-start** is one notification per local day during configured
  work hours, opt-in on Behavior. The notification daemon handles Do Not
  Disturb.
- **Edit** (running entry) is in-place (`ActiveEditView`), not a settings
  page. It can also set billable and tags when the provider allows.
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
  with `PLASMAI_TEST_LIVE`.

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
  save button).
- Kimai **week remaining** (`remainingWeekSeconds`) subtracts tracked time
  from an effective week target: contracted hours minus approved vacation /
  sickness / other absences and public holidays for the current Mon–Sun
  (`kimai-holiday-bundle`, capability `holidayBundle`). Fall back to the
  plain contract total when the bundle is unavailable.
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
  `tests/viewer/test_favorites_loading.py`.
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
