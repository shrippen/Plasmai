# Demo (internal)

For screenshots and testing only: published builds contain none of this (see
`scripts/package.sh` for the widget and the `PLASMAI_DEMO` build option of the app).

The profile "Demo" (address `https://demo.invalid`) answers from an in-memory Kimai with the
Drehzettel and Anfahrten plugins (`contents/code/demoKimai.js`), no server and no keychain. Its data
is Studio Weber, the demo world shared by all shrippen projects, seen by camera assistant Jonas
Brandt (`contents/code/demoWorld.js`, generated from `shrippen.github.io/demo`; do not edit it here).
`demo/start.sh [de|en]` opens the widget in plasmoidviewer with that profile; `demo/shots.sh` renders
the landing-page screenshots offscreen (plan in `demo/shots.json`, run by
`shrippen.github.io/demo/tools/screenshots.py`).

