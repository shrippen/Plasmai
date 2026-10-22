# Review guide

Every PR is reviewed before it is merged (rule in `agent.md`): by PR-Agent
(owner, 22.10.2026); a new Claude agent checks the **Wichtig** of earlier
rounds, and reviews when PR-Agent fails. The
reviewer knows nothing of the session that wrote the change: it gets the
PR's intent, its diff and the repository, and this file. The owner does not read code; this review is the second reader.

## What failure looks like here

Plasmai tracks working time (widget, app, TUI; Kimai, Clockify, Toggl,
SolidTime). A bug that matters costs the user hours or trust:

- **Wrong time:** a timer that does not start, stop or switch, a begin off
  by hours (UTC-8, UTC+14), an entry on the wrong project or day, week
  totals that count absences, holidays or WorkContract bookings twice.
- **Lost or doubled entries:** an offline change dropped silently, an
  outbox replay out of order, a create sent twice after a lost answer, an
  entry changed elsewhere overwritten without asking (`offline.js`).
- **Leaks secrets:** an API token in a config file, a log or a command
  line; a plain-text fallback when no keychain is there.
- **Breaks a client:** the widget does not load, Linux-only code in the
  app, film day or trips shown without their Kimai plugin, settings that
  stop syncing through `shared.json`, an Android app that does not build
  or start.
- **Lies:** CHANGELOG, DESIGN, README or comments that the code contradicts.

## What to check in particular

- Bug fixes: a test that failed before the fix (`agent.md`); does the fix
  remove the cause, not one case of it?
- Tests: new behaviour in `tests/unit` (runs in three time zones),
  `tests/locales.sh` (12/24 h, RTL, native digits), `app/tests`. Say what
  is only verified in a Plasma session or on a device. CI builds Android
  only on `main` (`android.yml`): changes to `app/android/` or
  `scripts/build-android*.sh` count as unverified.
- New or changed texts: an entry in `translate/langs/*` and the rebuilt
  `.po`, `contents/locale/`, `app/i18n/` (check only that they came along).
- `var` to `let`/`const` (`agent.md`, QML lint): each one checked for a
  read after its block or in a closure.
- GUI rule: no own colours, sizes or component copies; `contents/ui/Kante*`
  is a copy from Kante (`scripts/sync-kante.sh`) and is not edited here.
- Layers: pages call the session/tracker, never a provider or shell helper
  directly; shell helpers stay POSIX `sh`, arguments quoted (`shQuote`).
- `agent.md` code rules: braces on every `if`, no new public members
  without the owner's consent, no unrelated changes.

## Skip

- `contents/ui/Kante/`, `contents/ui/KantePlasma/` (synced from Kante).
- Generated: `translate/*.po`, `*.pot`, `contents/locale/`, `app/i18n/*.json`,
  `contents/code/buildInfo.js`, `build.number`.
- `app/libs/openssl/`, `screenshots/`, `docs/shots/`, `fastlane/` images.

## How to report

- Every finding names file and line and the concrete input or state that
  goes wrong. No guess without evidence; if unsure, say so.
- Each finding gets one label: **Wichtig** (a bug from the list above,
  must be fixed or answered before the merge), **Kleinigkeit** (optional,
  at most five) or **Bestand** (the bug was there before this PR; not
  blocking).
- The report starts with the count, e.g. "2 Wichtig, 1 Kleinigkeit" (the
  session puts the heading above it). The count of **Wichtig** holds every
  one still open, also from an earlier round, e.g. "1 Wichtig (offen aus
  Runde 1)". Only when none is open it says plainly: "Nichts zu beheben."
- In a later round: say for each open **Wichtig** of the last round whether
  it is fixed, or whether its answer is accepted, with the reason. PR-Agent
  sees no earlier round: it reports only its own findings with their labels,
  and a new Claude agent closes the open ones (`agent.md`).
- Findings in German, code names as they are.
