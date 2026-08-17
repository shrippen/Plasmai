"""Toggle Display settings in plasmoidviewer and assert Apply enables.

Uses an isolated XDG_CONFIG_HOME so the run cannot rewrite the user's
~/.config/com.github.shrippen.plasmai/shared.json.
"""

from __future__ import annotations

import json
import os
import shutil
import time
from pathlib import Path

import pytest

from lib import atspi_clicks, config_ui
from lib.viewer import ViewerSession

pytestmark = pytest.mark.viewer

# Seed matches the "everything unchecked" bug: shared.json all-false overlay.
_FALSE_DISPLAY = {
    "showElapsedInPanel": False,
    "showProjectInPanel": False,
    "showActivityInPanel": False,
    "showCustomerColorInPanel": False,
    "showProjectColorInPanel": False,
    "popupShowWorkSummary": False,
    "popupShowFavorites": False,
    "popupShowRecent": False,
    "popupShowContinue": False,
    "popupShowNewActivity": False,
    "desktopShowWorkSummary": False,
    "desktopShowFavorites": False,
    "desktopShowRecent": False,
    "desktopShowNewActivity": False,
    "popupShowSparkline": False,
    "desktopShowSparkline": False,
}


def _require_tools():
    missing = [c for c in ("plasmoidviewer", "xdotool") if shutil.which(c) is None]
    if missing:
        pytest.skip("missing " + ", ".join(missing))
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        pytest.skip("no DISPLAY / WAYLAND_DISPLAY")
    if atspi_clicks._try_import_atspi() is None:
        pytest.skip("python-atspi / gi Atspi not available")


def _isolated_env(tmp_path: Path) -> dict[str, str]:
    cfg = tmp_path / "config"
    cache = tmp_path / "cache"
    data = tmp_path / "data"
    state = tmp_path / "state"
    for p in (cfg, cache, data, state):
        p.mkdir()
    shared_dir = cfg / "com.github.shrippen.plasmai"
    shared_dir.mkdir(parents=True)
    (shared_dir / "shared.json").write_text(
        json.dumps(_FALSE_DISPLAY), encoding="utf-8"
    )
    return {
        "XDG_CONFIG_HOME": str(cfg),
        "XDG_CACHE_HOME": str(cache),
        "XDG_DATA_HOME": str(data),
        "XDG_STATE_HOME": str(state),
    }


def _open_configure(session: ViewerSession) -> None:
    wid = session.focus()
    atspi_clicks.expand_compact(wid)
    time.sleep(0.8)
    try:
        atspi_clicks.click_named(
            config_ui.CONFIGURE, roles=config_ui.BUTTON_ROLES, timeout=8
        )
        return
    except TimeoutError:
        pass
    # Fallback: applet context menu (unconfigured placeholder may be missing).
    if wid:
        import subprocess

        subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
        subprocess.run(["xdotool", "click", "3"], check=False)
        time.sleep(0.5)
    atspi_clicks.click_named(
        config_ui.CONFIGURE
        + ["Configure Plasmai…", "Plasmai konfigurieren", "Configure Applet…"],
        roles=config_ui.BUTTON_ROLES | {"menu item"},
        timeout=12,
    )


def _open_display(session: ViewerSession) -> None:
    session.wait_alive()
    time.sleep(1.5)
    _open_configure(session)
    time.sleep(0.8)
    atspi_clicks.click_named(config_ui.DISPLAY_TAB, roles=config_ui.TAB_ROLES, timeout=15)
    time.sleep(0.6)
    atspi_clicks.wait_named(
        config_ui.DISPLAY_OPTIONS["elapsed"],
        roles=config_ui.CHECKBOX_ROLES,
        timeout=12,
    )


def test_display_option_toggles_enable_apply(repo_root: Path, tmp_path: Path):
    """Each Display checkbox must enable Apply; Apply click must succeed."""
    _require_tools()
    env = _isolated_env(tmp_path)
    shared = Path(env["XDG_CONFIG_HOME"]) / "com.github.shrippen.plasmai" / "shared.json"

    with ViewerSession(
        repo_root,
        formfactor="horizontal",
        location="floating",
        size="560x80",
        extra_env=env,
    ) as session:
        _open_display(session)

        apply_enabled = atspi_clicks.named_enabled(
            config_ui.APPLY, roles=config_ui.BUTTON_ROLES
        )
        if apply_enabled is None:
            pytest.fail(
                "Apply/Anwenden not found after opening Display\n"
                + "\n".join(
                    atspi_clicks.list_showing(
                        atspi_clicks._try_import_atspi(),
                        roles=config_ui.BUTTON_ROLES | config_ui.CHECKBOX_ROLES,
                    )
                )
            )

        tried = []
        for key, labels in config_ui.DISPLAY_OPTIONS.items():
            before = atspi_clicks.named_checked(labels, roles=config_ui.CHECKBOX_ROLES)
            atspi_clicks.click_named(labels, roles=config_ui.CHECKBOX_ROLES, timeout=10)
            time.sleep(0.5)
            after = atspi_clicks.named_checked(labels, roles=config_ui.CHECKBOX_ROLES)
            enabled = atspi_clicks.named_enabled(
                config_ui.APPLY, roles=config_ui.BUTTON_ROLES
            )
            tried.append(f"{key}: checked {before} -> {after}, apply_enabled={enabled}")
            assert after is not None and after != before, (
                f"{key}: checkbox did not toggle ({labels})\n" + "\n".join(tried)
            )
            assert enabled is True, (
                f"{key}: Apply stayed disabled after toggle\n" + "\n".join(tried)
            )
            atspi_clicks.click_named(
                config_ui.APPLY, roles=config_ui.BUTTON_ROLES, timeout=8
            )
            time.sleep(0.8)
            # After Apply, Plasma greys the button until the next edit.
            enabled_after = atspi_clicks.named_enabled(
                config_ui.APPLY, roles=config_ui.BUTTON_ROLES
            )
            assert enabled_after is False, (
                f"{key}: Apply stayed enabled after clicking Apply "
                f"(still {enabled_after})\n" + "\n".join(tried)
            )

        data = json.loads(shared.read_text(encoding="utf-8"))
        assert data.get("showElapsedInPanel") is True, data
        assert data.get("showProjectInPanel") is True, data
