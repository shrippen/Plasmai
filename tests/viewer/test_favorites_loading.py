"""Favorites KCM must show a loading indicator and stay responsive."""

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


def _require_tools():
    missing = [c for c in ("plasmoidviewer", "xdotool") if shutil.which(c) is None]
    if missing:
        pytest.skip("missing " + ", ".join(missing))
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        pytest.skip("no DISPLAY / WAYLAND_DISPLAY")
    if atspi_clicks._try_import_atspi() is None:
        pytest.skip("python-atspi / gi Atspi not available")


def _large_catalog() -> dict:
    customers = []
    projects = []
    activities = []
    for c in range(40):
        customers.append({"id": c + 1, "name": f"Customer {c + 1}", "color": "#aabbcc"})
        for p in range(8):
            pid = c * 8 + p + 1
            projects.append(
                {
                    "id": pid,
                    "name": f"Project {pid}",
                    "customer": customers[-1],
                    "color": "#112233",
                }
            )
            for a in range(4):
                aid = pid * 10 + a
                activities.append(
                    {
                        "id": aid,
                        "name": f"Activity {aid}",
                        "project": {"id": pid},
                        "color": "",
                    }
                )
    return {
        "profileId": "default",
        "customers": customers,
        "projects": projects,
        "activities": activities,
        "customerGroups": [],
        "projectGroups": [],
        "activityGroups": [],
        "shiftedCount": 0,
        "groupCount": 0,
        "settingsKey": "",
        "statusText": "",
        "effectiveSimilarity": {"customer": 22, "project": 22, "activity": 22},
    }


def _isolated_env(tmp_path: Path) -> dict[str, str]:
    cfg = tmp_path / "config"
    cache = tmp_path / "cache"
    data = tmp_path / "data"
    state = tmp_path / "state"
    for p in (cfg, cache, data, state):
        p.mkdir(parents=True)

    shared_dir = cfg / "com.github.shrippen.plasmai"
    shared_dir.mkdir(parents=True)
    (shared_dir / "shared.json").write_text(
        json.dumps(
            {
                "profilesJson": json.dumps(
                    [
                        {
                            "id": "default",
                            "name": "Default",
                            "url": "https://kimai.example.com",
                            "provider": "kimai",
                        }
                    ]
                ),
                "activeProfileId": "default",
                "pinnedActivities": "",
            }
        ),
        encoding="utf-8",
    )

    cache_dir = cache / "com.github.shrippen.plasmai"
    cache_dir.mkdir(parents=True)
    (cache_dir / "catalog-cache.json").write_text(
        json.dumps(_large_catalog()), encoding="utf-8"
    )

    return {
        "XDG_CONFIG_HOME": str(cfg),
        "XDG_CACHE_HOME": str(cache),
        "XDG_DATA_HOME": str(data),
        "XDG_STATE_HOME": str(state),
    }


def _discard_unsaved_dialog() -> None:
    try:
        atspi_clicks.click_named(
            ["Discard", "Verwerfen"],
            roles=config_ui.BUTTON_ROLES,
            timeout=1.2,
        )
        time.sleep(0.3)
    except TimeoutError:
        pass


def test_favorites_shows_loading_and_kcm_stays_responsive(
    repo_root: Path, tmp_path: Path
) -> None:
    _require_tools()
    env = _isolated_env(tmp_path)

    with ViewerSession(
        repo_root,
        formfactor="horizontal",
        location="floating",
        size="560x80",
        extra_env=env,
    ) as session:
        session.wait_alive()
        time.sleep(1.2)
        wid = session.focus()
        atspi_clicks.expand_compact(wid)
        time.sleep(0.8)
        atspi_clicks.click_named(
            config_ui.CONFIGURE, roles=config_ui.BUTTON_ROLES, timeout=12
        )
        time.sleep(0.8)

        atspi_clicks.click_named(
            config_ui.FAVORITES_TAB, roles=config_ui.TAB_ROLES, timeout=12
        )
        _discard_unsaved_dialog()
        atspi_clicks.wait_named(
            ["Profile:", "Profil:", "Connection", "Verbindung"],
            timeout=8,
            require_showing=True,
        )
        atspi_clicks.click_named(
            config_ui.FAVORITES_TAB, roles=config_ui.TAB_ROLES, timeout=12
        )

        try:
            atspi_clicks.wait_named(
                config_ui.LOADING_PROJECTS, timeout=3.0, require_showing=True
            )
        except TimeoutError as exc:
            raise AssertionError(
                "Favorites opened without a loading indicator "
                "(BusyIndicator / 'Loading projects')"
            ) from exc

        started = time.time()
        atspi_clicks.click_named(
            config_ui.CONNECTION_TAB, roles=config_ui.TAB_ROLES, timeout=4
        )
        _discard_unsaved_dialog()
        elapsed = time.time() - started
        assert elapsed < 4.0, (
            f"KCM froze switching away from Favorites ({elapsed:.2f}s)"
        )

        atspi_clicks.wait_named(
            ["Profile:", "Profil:", "Connection", "Verbindung"],
            timeout=8,
            require_showing=True,
        )
