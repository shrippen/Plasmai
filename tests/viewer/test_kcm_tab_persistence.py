"""KCM tab persistence regression test (Apply + tab switching).

This reproduces the reported Plasmai KCM bug where applying settings and then
switching between tabs may reset previous changes (notably the Connection
profile selection). The bug regressed further and is expected to affect all
tabs, so this test covers every KCM category we ship in `contents/config/config.qml`.
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


_KCM_TABS = ["Connection", "Favorites", "Display", "Maintenance", "Behavior"]

# Stable test data (also used for AT-SPI lookups).
_PROFILE_2_NAME = "Profile 2"

_TEST_CUSTOMER = {"id": 1, "name": "Test Customer", "color": "#ff0000"}
_TEST_PROJECT = {
    "id": 10,
    "name": "Test Project",
    "customer": _TEST_CUSTOMER,
    "color": "#00ff00",
}
_TEST_ACTIVITY = {
    "id": 100,
    "name": "Test Activity 1",
    # KimaiApi.activityProjectId treats object.project.id as project-id.
    "project": {"id": _TEST_PROJECT["id"]},
    "color": "",
}


_FALSE_DISPLAY = {
    # Panel
    "showElapsedInPanel": False,
    "showProjectInPanel": False,
    "showActivityInPanel": False,
    "showCustomerColorInPanel": False,
    "showProjectColorInPanel": False,
    # Panel flyout
    "popupShowWorkSummary": False,
    "popupShowFavorites": False,
    "popupShowRecent": False,
    "popupShowContinue": False,
    "popupShowNewActivity": False,
    # Desktop widget
    "desktopShowWorkSummary": False,
    "desktopShowFavorites": False,
    "desktopShowRecent": False,
    "desktopShowNewActivity": False,
    # Sparklines
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
        p.mkdir(parents=True, exist_ok=True)

    # Seed shared.json with two profiles + pinnedActivities so KCM UI can show
    # a stable activity checklist without hitting the network.
    shared_dir = cfg / "com.github.shrippen.plasmai"
    shared_dir.mkdir(parents=True)
    (shared_dir / "shared.json").write_text(
        json.dumps(
            {
                **_FALSE_DISPLAY,
                # Leave profilesJson empty so Connection initially shows only
                # the built-in "Default" profile. The test will create
                # "Profile 2" via the Connection UI ("Add profile").
                "pinnedActivities": "",
                "profilesJson": "",
                "activeProfileId": "default",
                # Behaves like "default" while still allowing toggles.
                "confirmBeforeStop": False,
                "idleStopEnabled": False,
                "idleStopMinutes": 15,
                "notifyOnStart": True,
                "notifyOnStop": True,
                "notifyOnIdleStop": True,
                "notifyForgotToStart": False,
            }
        ),
        encoding="utf-8",
    )

    # Seed catalog cache on disk so Favorites tab can render project + activities
    # without requiring an API token.
    cache_dir = cache / "com.github.shrippen.plasmai"
    cache_dir.mkdir(parents=True)
    (cache_dir / "catalog-cache.json").write_text(
        json.dumps(
            {
                # Favorites/maintenance only need a non-empty catalog; the UI
                # will still load it even if the active profile-id is
                # different (it is treated as a preloaded payload).
                "profileId": "default",
                "customers": [_TEST_CUSTOMER],
                "projects": [_TEST_PROJECT],
                "activities": [_TEST_ACTIVITY],
                # Stored group data is optional (ColorDistinct can rebuild).
                "customerGroups": [],
                "projectGroups": [],
                "activityGroups": [],
                "shiftedCount": 0,
                "groupCount": 0,
                "settingsKey": "",
                "statusText": "",
                "effectiveSimilarity": {"customer": 22, "project": 22, "activity": 22},
                # Let defaults / in-memory TTL logic decide freshness.
            }
        ),
        encoding="utf-8",
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


def _click_tab(tab_name: str) -> None:
    atspi_clicks.click_named([tab_name], roles=config_ui.TAB_ROLES, timeout=15)
    # Give Qt time to swap pages; AT-SPI polling is still event-driven so keep this small.
    time.sleep(0.4)


def _read_shared_json(env: dict[str, str]) -> dict:
    shared = (
        Path(env["XDG_CONFIG_HOME"])
        / "com.github.shrippen.plasmai"
        / "shared.json"
    )
    return json.loads(shared.read_text(encoding="utf-8"))


def _select_connection_profile(profile_name: str) -> None:
    # Deprecated: Connection profile selection is now done via "Add profile"
    # to avoid relying on seeded profilesJson accessibility.
    raise NotImplementedError


def _add_profile_2_and_apply(shared_path: Path) -> None:
    """In Connection tab: add "Profile 2", apply, and assert persistence."""
    atspi_clicks.click_named(["Add profile"], roles=config_ui.BUTTON_ROLES, timeout=10)
    time.sleep(0.6)

    # "Add profile" selects it in the combobox, but it does not mark it as
    # the active profile. "Use this profile" updates `activeProfileField`
    # and is what we actually need to preserve across tab switches.
    atspi_clicks.click_named(
        ["Use this profile"], roles=config_ui.BUTTON_ROLES, timeout=10
    )
    time.sleep(0.4)

    # Ensure the UI updated.
    atspi_clicks.wait_named(
        ["Active profile: " + _PROFILE_2_NAME],
        roles=None,
        timeout=12,
        require_showing=True,
    )

    apply_enabled = atspi_clicks.named_enabled(
        config_ui.APPLY, roles=config_ui.BUTTON_ROLES
    )
    assert apply_enabled is True, "Adding Profile 2 did not enable Apply"

    atspi_clicks.click_named(
        config_ui.APPLY, roles=config_ui.BUTTON_ROLES, timeout=8
    )
    time.sleep(0.8)
    assert (
        atspi_clicks.named_enabled(config_ui.APPLY, roles=config_ui.BUTTON_ROLES) is False
    ), "Apply stayed enabled after clicking Apply (Connection)"

    data = json.loads(shared_path.read_text(encoding="utf-8"))
    assert data.get("profilesJson"), "profilesJson missing after applying Connection"
    profiles = json.loads(data["profilesJson"])
    profile2 = next((p for p in profiles if p.get("name") == _PROFILE_2_NAME), None)
    assert profile2 and profile2.get("id"), profiles
    assert data.get("activeProfileId") == profile2["id"], data


def test_kcm_tab_option_persistence(repo_root: Path, tmp_path: Path):
    """Edit+Apply persistence across KCM tabs (including Connection profile)."""
    _require_tools()
    env = _isolated_env(tmp_path)

    shared_path = (
        Path(env["XDG_CONFIG_HOME"])
        / "com.github.shrippen.plasmai"
        / "shared.json"
    )

    with ViewerSession(
        repo_root,
        formfactor="horizontal",
        location="floating",
        size="560x80",
        extra_env=env,
    ) as session:
        session.wait_alive()
        time.sleep(1.5)
        wid = session.focus()
        atspi_clicks.expand_compact(wid)
        time.sleep(0.8)

        _open_configure(session)

        # Wait for Apply to exist and confirm initial "no dirty changes".
        apply_enabled = atspi_clicks.named_enabled(
            config_ui.APPLY, roles=config_ui.BUTTON_ROLES
        )
        if apply_enabled is None:
            pytest.fail(
                "Apply/Anwenden not found after opening KCM\n"
                + "\n".join(
                    atspi_clicks.list_showing(
                        atspi_clicks._try_import_atspi(),
                        roles=config_ui.BUTTON_ROLES | config_ui.CHECKBOX_ROLES,
                    )
                )
            )

        assert apply_enabled is False, f"Apply should be disabled on open, got {apply_enabled}"

        # "No change" path: switch tabs away/back without edits.
        _click_tab("Display")
        atspi_clicks.wait_named(
            config_ui.DISPLAY_OPTIONS["elapsed"],
            roles=config_ui.CHECKBOX_ROLES,
            timeout=12,
        )
        _click_tab("Connection")
        apply_enabled_after = atspi_clicks.named_enabled(
            config_ui.APPLY, roles=config_ui.BUTTON_ROLES
        )
        assert apply_enabled_after is False, (
            f"Apply unexpectedly enabled after no-op tab switch: {apply_enabled_after}"
        )

        # —— Connection ——
        _click_tab("Connection")
        atspi_clicks.wait_named(["Add profile"], roles=config_ui.BUTTON_ROLES, timeout=12)
        _add_profile_2_and_apply(shared_path)

        _click_tab("Display")
        _click_tab("Connection")
        atspi_clicks.wait_named(
            ["Active profile: " + _PROFILE_2_NAME],
            roles=None,
            timeout=12,
            require_showing=False,
        )

        # —— Favorites ——
        _click_tab("Favorites")
        atspi_clicks.wait_named([_TEST_PROJECT["name"]], roles=None, timeout=12, require_showing=False)
        # Select the project; activity checkboxes depend on it.
        atspi_clicks.click_named(
            [_TEST_PROJECT["name"]],
            roles={"list item", "push button", "button"},
            timeout=10,
        )
        time.sleep(0.6)
        atspi_clicks.wait_named(
            [_TEST_ACTIVITY["name"]],
            roles=config_ui.CHECKBOX_ROLES,
            timeout=12,
        )

        before = atspi_clicks.named_checked(
            [_TEST_ACTIVITY["name"]],
            roles=config_ui.CHECKBOX_ROLES,
        )
        # With seeded pinnedActivities="", the first toggle should check it.
        if before is not False and before is not None:
            # If it was unexpectedly already checked, toggle off then on again.
            atspi_clicks.click_named(
                [_TEST_ACTIVITY["name"]],
                roles=config_ui.CHECKBOX_ROLES,
                timeout=8,
            )
            time.sleep(0.3)
        atspi_clicks.click_named(
            [_TEST_ACTIVITY["name"]],
            roles=config_ui.CHECKBOX_ROLES,
            timeout=10,
        )
        time.sleep(0.5)
        assert (
            atspi_clicks.named_enabled(config_ui.APPLY, roles=config_ui.BUTTON_ROLES) is True
        ), "Favorites edits did not enable Apply"
        atspi_clicks.click_named(config_ui.APPLY, roles=config_ui.BUTTON_ROLES, timeout=8)
        time.sleep(0.8)

        _click_tab("Behavior")
        _click_tab("Favorites")
        atspi_clicks.wait_named(
            [_TEST_PROJECT["name"]], roles=None, timeout=12, require_showing=False
        )
        atspi_clicks.click_named(
            [_TEST_PROJECT["name"]],
            roles={"list item", "push button", "button"},
            timeout=10,
        )
        time.sleep(0.6)
        atspi_clicks.wait_named(
            [_TEST_ACTIVITY["name"]],
            roles=config_ui.CHECKBOX_ROLES,
            timeout=12,
        )
        assert (
            atspi_clicks.named_checked([_TEST_ACTIVITY["name"]], roles=config_ui.CHECKBOX_ROLES)
            is True
        ), "Favorites checkbox did not persist after tab switch"
        data = json.loads(shared_path.read_text(encoding="utf-8"))
        assert "10:100" in data.get("pinnedActivities", ""), data

        # —— Display ——
        _click_tab("Display")
        elapsed = config_ui.DISPLAY_OPTIONS["elapsed"]
        before = atspi_clicks.named_checked(elapsed, roles=config_ui.CHECKBOX_ROLES)
        atspi_clicks.click_named(elapsed, roles=config_ui.CHECKBOX_ROLES, timeout=10)
        time.sleep(0.5)
        assert (
            atspi_clicks.named_enabled(config_ui.APPLY, roles=config_ui.BUTTON_ROLES) is True
        ), "Display edits did not enable Apply"
        atspi_clicks.click_named(config_ui.APPLY, roles=config_ui.BUTTON_ROLES, timeout=8)
        time.sleep(0.8)

        _click_tab("Behavior")
        _click_tab("Display")
        assert (
            atspi_clicks.named_checked(elapsed, roles=config_ui.CHECKBOX_ROLES) is True
        ), f"Display checkbox did not persist (before={before})"
        data = json.loads(shared_path.read_text(encoding="utf-8"))
        assert data.get("showElapsedInPanel") is True, data

        # —— Behavior ——
        _click_tab("Behavior")
        behavior_checkbox = "Stop timer when idle"
        atspi_clicks.wait_named([behavior_checkbox], roles=config_ui.CHECKBOX_ROLES, timeout=12)

        # Toggle it on.
        atspi_clicks.click_named([behavior_checkbox], roles=config_ui.CHECKBOX_ROLES, timeout=10)
        time.sleep(0.5)
        assert (
            atspi_clicks.named_enabled(config_ui.APPLY, roles=config_ui.BUTTON_ROLES) is True
        ), "Behavior edits did not enable Apply"
        atspi_clicks.click_named(config_ui.APPLY, roles=config_ui.BUTTON_ROLES, timeout=8)
        time.sleep(0.8)

        # Maintenance is mostly read-only, but switching tabs away/back still
        # reproduces the “merge patch clobbered earlier keys” regression.
        _click_tab("Maintenance")
        _click_tab("Behavior")
        deadline = time.time() + 12
        while time.time() < deadline:
            if atspi_clicks.named_checked(
                [behavior_checkbox], roles=config_ui.CHECKBOX_ROLES
            ) is True:
                break
            time.sleep(0.2)
        else:
            raise AssertionError("Behavior checkbox did not persist after tab switch")
        data = json.loads(shared_path.read_text(encoding="utf-8"))
        assert data.get("idleStopEnabled") is True, data

        # Safety: Apply must be disabled again after applying.
        assert (
            atspi_clicks.named_enabled(config_ui.APPLY, roles=config_ui.BUTTON_ROLES) is False
        ), "Apply unexpectedly enabled at end of test"

