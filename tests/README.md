# Tests

Plasmai has two layers of automated tests:

1. **QML unit tests** (`tests/unit/tst_*.qml`) — `QtTest` cases against the
   `.js` libraries (`kimaiApi`, `profiles`, `colorDistinct`, …). No network,
   no Plasma shell.
2. **plasmoidviewer click sweeps** (`tests/viewer/`) — launch the applet in
   `plasmoidviewer`, click every safe control, and fail if **plasmoidviewer
   stderr** or the **plasmashell / plasmoidviewer journal** contains QML
   `TypeError` / `ReferenceError` / similar fatals.

## Dependencies

- `qmltestrunner` (Qt 6 Declarative tests; on Arch: `qt6-declarative`)
- `pytest`
- `plasmoidviewer` (`plasma-sdk`) and `xdotool` for click tests
- `python-gobject` + `at-spi2-core` (AT-SPI) so buttons can be discovered
- A graphical session (`DISPLAY` or `WAYLAND_DISPLAY`) for viewer tests
- On Wayland, the viewer is forced onto XWayland (`QT_QPA_PLATFORM=xcb`) so
  `xdotool` can find the window. Override with `PLASMAI_TEST_QPA=wayland` if needed.

## Run

```bash
./tests/run.sh          # QML units + pytest, skip live plasmashell panel test
./tests/run.sh unit     # QML units + log-classifier pytest only (no viewer)
QT_QPA_PLATFORM=xcb ./tests/run.sh   # if offscreen qmltestrunner misbehaves
```

Or separately:

```bash
qmltestrunner -input tests/unit
python -m pytest tests -m "not shell"
```

## Click safety

By default the viewer sweep **does not** click controls that would start, stop,
or switch live tracking on your Kimai/Clockify/Toggl/SolidTime account:

- Stop / Start / Continue / Switch
- Favorite and recent rows (`Accessible.role: ListItem`)
- plasmoidviewer SDK chrome (FormFactors, Location, refresh-which-removes)

Safe chrome **is** clicked: Add entry, Statistics, Back, Configure, stats
filters, config tabs, checkboxes, etc.

Display Apply is a dedicated viewer test (`tests/viewer/test_display_options.py`).
It launches plasmoidviewer with a temporary `XDG_CONFIG_HOME` so it cannot
rewrite your real `shared.json`. It opens Display, toggles each listed option,
and asserts **Apply / Anwenden** becomes enabled (then clicks Apply).

To include live tracking clicks (will hit your real API):

```bash
PLASMAI_TEST_LIVE=1 python -m pytest tests/viewer -m "not shell"
```

To click the **installed panel widget** inside plasmashell (not the viewer):

```bash
PLASMAI_TEST_SHELL=1 python -m pytest tests/viewer -m shell
```

Known Plasma desktop noise is ignored (Shortcuts/About `cfg_*` TypeErrors,
`digitalclock`, QML-debug banners). Applet errors under `contents/ui/` are not.
