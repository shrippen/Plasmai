"""Launch plasmoidviewer, click applet controls, fail on QML / plasmashell errors."""

from __future__ import annotations

import os
import shutil
import time
from pathlib import Path

import pytest

from lib import atspi_clicks
from lib.errors import collect_fatals
from lib.journal import mark as journal_mark
from lib.journal import since as journal_since
from lib.viewer import ViewerSession

pytestmark = pytest.mark.viewer


def _require_tools():
    missing = [c for c in ("plasmoidviewer", "xdotool") if shutil.which(c) is None]
    if missing:
        pytest.skip("missing " + ", ".join(missing))
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        pytest.skip("no DISPLAY / WAYLAND_DISPLAY")


def _assert_no_fatals(viewer_lines: list[str], journal_lines: list[str], label: str) -> None:
    fatals = collect_fatals(viewer_lines) + collect_fatals(journal_lines, journal=True)
    assert not fatals, (
        f"{label}: QML / plasmashell errors after clicks:\n" + "\n".join(fatals[:40])
    )


def _run_sweep(session: ViewerSession, *, wait: float = 2.5):
    session.wait_alive()
    time.sleep(wait)
    wid = session.focus()
    atspi_clicks.expand_compact(wid)
    time.sleep(0.8)
    result = atspi_clicks.sweep(wid)
    time.sleep(0.6)
    return session.lines(), result


def test_horizontal_popup_clicks_have_no_qml_errors(repo_root: Path):
    _require_tools()
    cursor = journal_mark()
    with ViewerSession(repo_root, formfactor="horizontal", location="floating", size="560x80") as session:
        viewer_lines, result = _run_sweep(session)
        # Always click-expand even if AT-SPI is empty so load errors still surface.
        if not result.atspi_available:
            pytest.skip("python-atspi / gi Atspi not available")
        if not result.applications:
            # Accessibility bus may be off; compact click already happened.
            pass
        journal_lines = journal_since(cursor)
        _assert_no_fatals(viewer_lines, journal_lines, "horizontal popup")
        if session.proc and session.proc.poll() not in (None, 0):
            pytest.fail(f"plasmoidviewer crashed with code {session.proc.returncode}")


def test_desktop_widget_clicks_have_no_qml_errors(repo_root: Path):
    _require_tools()
    cursor = journal_mark()
    with ViewerSession(repo_root, formfactor="planar", location="desktop", size="420x640") as session:
        viewer_lines, result = _run_sweep(session, wait=3.0)
        journal_lines = journal_since(cursor)
        _assert_no_fatals(viewer_lines, journal_lines, "desktop widget")
        if session.proc and session.proc.poll() not in (None, 0):
            pytest.fail(f"plasmoidviewer crashed with code {session.proc.returncode}")


def test_configure_dialog_tabs_have_no_qml_errors(repo_root: Path):
    """Open Plasmai settings from the placeholder / sweep and click config tabs."""
    _require_tools()
    cursor = journal_mark()
    with ViewerSession(repo_root, formfactor="horizontal", location="floating", size="560x80") as session:
        session.wait_alive()
        time.sleep(2.0)
        wid = session.focus()
        atspi_clicks.expand_compact(wid)
        time.sleep(0.8)
        atspi_clicks.sweep(wid, max_clicks=50)
        time.sleep(0.8)
        journal_lines = journal_since(cursor)
        _assert_no_fatals(session.lines(), journal_lines, "configure dialog")


def test_viewer_load_logs_no_plasmai_errors(repo_root: Path):
    """Load-only: applet must instantiate without TypeError even before clicks."""
    _require_tools()
    cursor = journal_mark()
    with ViewerSession(repo_root, formfactor="horizontal", location="floating", size="480x72") as session:
        session.wait_alive()
        time.sleep(2.5)
        journal_lines = journal_since(cursor)
        _assert_no_fatals(session.lines(), journal_lines, "load")


@pytest.mark.shell
def test_plasmashell_panel_clicks_have_no_qml_errors():
    """Optional: click the installed panel widget. Set PLASMAI_TEST_SHELL=1."""
    if os.environ.get("PLASMAI_TEST_SHELL", "").strip() not in ("1", "true", "yes"):
        pytest.skip("set PLASMAI_TEST_SHELL=1 to click the live plasmashell applet")
    _require_tools()
    import subprocess

    cursor = journal_mark()
    search = subprocess.run(
        ["xdotool", "search", "--onlyvisible", "--name", "Plasmai"],
        capture_output=True,
        text=True,
    )
    ids = [w.strip() for w in (search.stdout or "").splitlines() if w.strip()]
    if not ids:
        pytest.skip("no visible window named Plasmai (add the widget to a panel first)")
    wid = ids[-1]
    subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
    atspi_clicks.expand_compact(wid)
    time.sleep(0.8)
    atspi_clicks.sweep(wid)
    time.sleep(0.6)
    journal_lines = journal_since(cursor)
    fatals = collect_fatals(journal_lines, journal=True)
    assert not fatals, "plasmashell errors after panel clicks:\n" + "\n".join(fatals[:40])
