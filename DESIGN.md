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
  `colorDistinction`, `billableFilter`, `workContract`).
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
  Keep them POSIX `sh`, quote arguments with `secret.js` `shQuote`.

### Configuration UI

- Every settings page **must** be a `Kirigami.Page` (`ConfigPageBase`). Plasma’s
  PageRow injects every `main.xml` key as `cfg_*` / `cfg_*Default` plus
  `title`; a plain `Item` logs TypeErrors. Shortcuts/About `cfg_*` spam is
  Plasma desktop (bug 494417), not fixable in this applet.
- Config chrome: `Kirigami.FormLayout`, `pageMargin` from `gridUnit`, stack
  labels above fields when the window is narrow (`formWide` pattern in
  Display).
- Display binds each control with `property alias cfg_*` (Plasma’s documented
  Apply path). Dummy `property var cfg_*` does not show up in
  `hasOwnProperty`, so toggling never enables Apply. Use `onToggled` (not
  `onCheckedChanged`) for user edits. Do **not** call
  `applyToConfiguration(plasmoid.configuration, shared)` while the dialog is
  open — that writes the live applet before Apply. Persist `shared.json` only
  in `saveConfig()` (Apply/OK). Other tabs keep dummy `cfg_*` on `ConfigPage`
  so Plasma’s key injection does not TypeError.
- Tabs: Connection, Favorites, Display, Maintenance, Behavior — keep that
  split. Do not dump tracking actions into Display.

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
- Optional translucent background (`useBlurBackground`) uses Plasma’s
  `TranslucentBackground` so KWin blur applies. Do not fake blur in QML.

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
  checkmark, held fully opaque, then faded out. A theme-tinted symbolic icon
  at default contrast is not enough — boost saturation and contrast against
  the field. Transient hints (already-running row) stay short (~1.4s).
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
  avoid live API clicks).
- Icon-only buttons keep a `text` and `ToolTip`.

---

## Interaction principles

- **Panel click** expands/collapses. It must not start or stop tracking
  (too easy to misclick). Explicit Start / Stop / Continue / row click do
  that.
- **Stop** may confirm (`confirmBeforeStop`). Switching away from a running
  activity via Recent shows the switch dialog (current vs target cards), not
  a silent stop+start.
- **Continue** is “last recent”, not a generic Start. Favorites and Recent
  are one-tap presets.
- **Edit** (running entry) is in-place (`ActiveEditView`), not a settings
  page. Manual **Add entry** is a separate `mainViewMode`.
- **Configure** is the only path to tokens, profiles, and display flags.
  Placeholder “Connect a time tracker” when unconfigured; don’t hide the
  widget.
- Right-click anywhere on the full UI opens the standard applet menu
  (a capturing `MouseArea` is required because labels steal RMB).
- Do not click-test live Start/Stop/Continue/favorite/recent in default CI
  (`tests/README.md`). Those mutate the user’s tracker.

---

## Performance and robustness

- Avoid canvas/scenegraph work when the popup is closed. Gate expensive
  loaders (`LoadingRow`, sparkline animators, stats) on visibility and
  `mainViewMode`.
- `plasmoid.configuration` Connections must not refresh from the API while
  `plasmoid.userConfiguring` (config dialog open) — that fights the editor
  and rewrites shared.json.
- Polling: `refreshInterval` (seconds), idle check once a minute when
  enabled. No busy-loops, no per-keystroke API calls (description save is
  explicit: Enter or the save button).
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
  `shared.json`).
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
