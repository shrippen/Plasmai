# Architecture

How this repository is meant to be built. Where the code differs today is listed under
"Known deviations". Change this file in the PR that changes the structure. How the
session layer works in detail, and how Plasmai looks and behaves, is in `DESIGN.md`.

## What it does

Plasmai is a time tracker for Kimai (and, experimental, Clockify, Toggl, SolidTime): a
Plasma widget, and the same thing as an app for Android, Plasma Mobile and the Windows
tray, with a terminal client. Start, switch and stop a timer, book and edit entries,
favourites, statistics, offline work; for Kimai also film days and trips.

## Building blocks

| Path | Its one task |
|---|---|
| `contents/ui/main.qml` and the files only it uses | The widget: panel chip and popup. It keeps view state and words the session's signals. |
| `contents/ui/` (other files) | Components the widget and the app share: views and editors, pickers, fields, charts, rows, the setup wizard, `ApiErrors` (error kinds to texts), `EntryTexts` (the texts about entries and the day both show), `PlasmaiColors`. |
| `contents/ui/config/`, `contents/config/` | The widget's settings pages; the description of its settings with their defaults (`main.xml`). |
| `contents/ui/Session.qml`, `contents/ui/session/` | The session layer: everything a view needs of the tracker, without a view and without texts. One file per part (connection, settings, catalog, timer, entries, totals, sync, film day, trips, statistics, reminders, setup). |
| `contents/code/timeTracker.js`, `kimaiApi.js`, `providers/`, `providerUtil.js` | The providers: the registry with each provider's capabilities, one file per service, and what they share (request, answer, error kinds). |
| `contents/code/offline.js` | The offline layer's session: wraps the tracker so reads and writes work without network. |
| `contents/code/offlineState.js` | The stored state of that layer: the snapshot of server answers on disk and the overlay of waiting changes on it. |
| `contents/code/offlineOutbox.js` | The outbox of that layer: queued changes, sending them again in order, conflicts, retry and discard. |
| `contents/code/filmDaySync.js`, `catalogCache.js`, `geocode.js` | What the session uses beside a provider: the film day's sync, the catalog on disk, the place search. |
| `contents/code/platform.js`, `desktopBackend.js`, `secret.js`, `*.sh`, `contents/ui/ExecSource.qml`, `app/qml/platform/appBackend.js` | The platform: one facade for settings file (`shared.json`), tokens, files, idle time and notifications, with a backend for the widget (shell scripts, KWallet) and one for the app. |
| `contents/code/sharedConfig.js` | The shared settings: their names and defaults. |
| `contents/code/` (other files) | Pure logic with tests: dates and durations, day model and totals, statistics, favourites, film days, mileage, layouts, profiles. |
| `contents/ui/Kante/`, `KantePlasma/` | Synced copies of the design system. Never edited here. |
| `contents/ui/Controls/`, `app/qml/controls/` | The same controls under one name for each platform: Plasma's in the widget, Kirigami's in the app. |
| `app/qml/` | The app's pages and its start; `tui/` the terminal client's screens. They reuse `contents/ui/` and `contents/code/`. |
| `app/main.cpp`, `app/platform/`, `app/tui/`, `app/android/` | The app's C++ start; one file per platform for tray, idle, notifications, token store, autostart; the terminal; the Android package. |
| `app/addons/`, `app/qml/kirigami-*`, `app/libs/` | Foreign code the app ships. Not edited here. |
| `tests/`, `app/tests/` | Unit tests in QML (`unit/`; `app_pages/` for app pages, run on a copy of the app's qrc layout), tests of packaging and structure in Python, tests in the running widget (`viewer/`); C++ tests of the app. |
| `scripts/`, `packaging/`, `translate/`, `demo/`, `docs/`, `fastlane/`, `tools/` | Build, install and package per platform; store packages; translations; the demo start, screenshots and benchmarks; landing page; store texts; the structure check (synced copy). |

## Layers

```
 widget (contents/ui/main.qml)          app pages (app/qml/)   terminal (app/qml/tui/)
        │                                       │                    │
        ├────────────► shared components ◄──────┤                    │
        │              (contents/ui/)           │                    │
        │                     │                 │                    │
        ▼                     ▼                 ▼                    ▼
 Session (contents/ui/Session.qml + session/): state, actions, signals, no texts
        │                               │                    │
        ▼                               ▼                    ▼
 timeTracker ─► provider         offline, filmDaySync,   platform.js ─► backend
 (kimaiApi, providers/*)         catalogCache, geocode   (widget: scripts; app: C++)
        │                                                    │
        ▼                                                    ▼
 the service's server                         shared.json, tokens, files, idle, notify

 pure logic (contents/code/): used by every layer
```

- A view never calls a provider and never sends a request. It binds to the session's
  state, calls its actions and puts its signals into words.
- Only the session uses the platform (`platform.js`, its backends, the app's C++
  services). The exceptions: each host sets the backend at
  start; the widget's `main.qml` carries its Plasma configuration to `shared.json`
  and back; the app's host drives its own glue to the system (tray, permanent
  notification, network status, autostart); demo, screenshot and benchmark code.
- The session holds no text and no view state. What needs a view comes back as a
  value or a signal.
- A flow (load, check, save) that widget and app both need stands once, in the
  session; a text both show stands once, in a shared file. The two only display.
- What is particular to one service stays in its provider file, behind
  `timeTracker` and its capability flags. What providers share (request, reading an
  answer, error kinds) stands once, in `providerUtil.js`.
- A helper lives in the file named after its topic; a provider file holds requests,
  no display helpers.
- A value stands once: a shared setting's key and default in `sharedConfig.js`
  (`main.xml` repeats the default, because Plasma reads it there; a test holds the
  two equal), the version in `metadata.json`, an error kind in the one list.
- Pure logic lives in `contents/code/` and has a unit test; the program holds no
  code only tests call.
- A service that differs by platform sits behind one name with a file per platform
  (`app/platform/*_<platform>.cpp`, the two `Controls` folders, the backends). The
  app's start and small differences branch in place (`#ifdef`, `Qt.platform.os`).
- The widget stays without compiled code; C++ exists only in `app/`.
- Demo, screenshot and benchmark code is cut out of every package.

## Where new things go

| Change | Touch |
|---|---|
| A new action or state of the tracker | A part in `contents/ui/session/` (a new part also in its `qmldir`, as a property in `Session.qml` and in `app/plasmai-app.qrc`), a test in `tests/unit/`; then the views of widget and app |
| A new call to a service | The provider file; for all services also `timeTracker.js` with a capability flag |
| A new service | `contents/code/providers/<name>.js`, its entry in `timeTracker.js` |
| A new shared setting | `contents/code/sharedConfig.js`, `contents/config/main.xml`, a property in `contents/ui/session/SessionSettings.qml` and its key in `SESSION_KEYS` if the session reads it, a range in `LIMITS` for a number; a settings page in `contents/ui/config/` and `app/qml/SettingsPage.qml` |
| Something both widget and app show | A component in `contents/ui/` (listed in `app/qml/contents-ui.qmldir` and `app/plasmai-app.qrc`) |
| A calculation or a format | The file for its topic in `contents/code/`, with a test |
| Something the system does (file, token, notification) | `platform.js` and both backends |
| Something only one platform of the app does | `app/platform/`, one file per platform |
| A text | In place with `i18n`; then `translate/` |
| A design element that is missing | Kante, then `scripts/sync-kante.sh`; never the copies here |
| A release | The steps in `RELEASE.md` |

## Known deviations

- `kimaiApi.js` holds, beside Kimai's requests, the display helpers and the day's
  calculation every service needs (`AUDIT.md`, finding 5).
- `contents/ui/main.qml` is one file of 2795 lines, still over the size limit; film day,
  trips, statistics and the shared texts have left it (`AUDIT.md`, finding 10).
