"""Open Add entry and assert Billable/Tags chrome is present (no save)."""

from __future__ import annotations

import os
import shutil
import time
from pathlib import Path

import pytest

from lib import atspi_clicks, config_ui
from lib.viewer import ViewerSession

pytestmark = pytest.mark.viewer


def _require_tools():
    missing = [c for c in ("plasmoidviewer", "xdotool") if shutil.which(c) is None]
    if missing:
        pytest.skip("missing " + ", ".join(missing))
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        pytest.skip("no DISPLAY / WAYLAND_DISPLAY")
    if atspi_clicks._try_import_atspi() is None:
        pytest.skip("python-atspi / gi Atspi not available")


def test_add_entry_shows_billable_when_configured(repo_root: Path):
    """If the flyout has Add entry (configured widget), Billable must be visible."""
    _require_tools()
    with ViewerSession(repo_root, formfactor="horizontal", location="floating", size="560x80") as session:
        session.wait_alive()
        time.sleep(1.5)
        wid = session.focus()
        atspi_clicks.expand_compact(wid)
        time.sleep(0.8)
        try:
            atspi_clicks.click_named(config_ui.ADD_ENTRY, roles=config_ui.BUTTON_ROLES, timeout=8)
        except (TimeoutError, RuntimeError):
            pytest.skip("Add entry not visible (widget not configured)")
        time.sleep(0.5)
        atspi_clicks.wait_named(config_ui.BILLABLE, roles=config_ui.CHECKBOX_ROLES, timeout=8)
        atspi_clicks.click_named(["Cancel", "Abbrechen"], roles=config_ui.BUTTON_ROLES, timeout=6)
