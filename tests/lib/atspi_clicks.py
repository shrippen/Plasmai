"""Walk AT-SPI and click applet controls, skipping live tracking actions."""

from __future__ import annotations

import os
import re
import subprocess
import time
from dataclasses import dataclass, field

CLICK_ROLES = {
    "push button",
    "toggle button",
    "check box",
    "radio button",
    "page tab",
    "menu item",
    "link",
    "combo box",
    "button",
}

LIVE_ROLES = {
    "list item",
}

# Names that start/stop/switch tracking (skipped unless PLASMAI_TEST_LIVE=1).
TRACKING_EXACT = {
    "stop",
    "stoppen",
    "start",
    "starten",
    "switch",
    "wechseln",
    "toggle plasmai tracking",
    "stop plasmai tracking",
    "start last plasmai activity",
    "continue last plasmai activity",
}

# Viewer SDK / destructive settings — never click.
SDK_EXACT = {
    "formfactors",
    "location",
    "configure containment",
    "planar",
    "vertical",
    "horizontal",
    "mediacenter",
    "application",
    "floating",
    "desktop",
    "fullscreen",
    "top edge",
    "bottom edge",
    "left edge",
    "right edge",
    "defaults",
    "restore defaults",
    "reset",
    "remove",
    "delete",
    "löschen",
    "entfernen",
}

# History mutations from Recent overflow — never click (even PLASMAI_TEST_LIVE).
HISTORY_PREFIX = (
    "delete entry",
    "edit entry",
    "split entry",
    "entry actions",
    "eintrag löschen",
    "eintrag bearbeiten",
    "eintrag teilen",
    "eintragsaktionen",
    "create project",
    "create activity",
    "create customer",
    "projekt anlegen",
    "tätigkeit anlegen",
    "kunde anlegen",
    "keep time",
    "discard idle",
    "discard and continue",
    "zeit behalten",
    "leerlauf verwerfen",
    "verwerfen und fortsetzen",
    "stop timer",
    "shut down anyway",
    "timer stoppen",
    "trotzdem herunterfahren",
)

DENY_PREFIX = (
    "continue ·",
    "continue · ",
    "fortsetzen ·",
    "continue last",
    "switch to ",
    "switch to another",
    "start ·",
    "start last",
)

DENY_CONTAINS = (
    "starts or switches this activity",
)

# plasmoidviewer SDK toolbar: refresh removes the applet; hide drops the bar.
DENY_EMPTY_TOOLBAR = True

NAME_STRIP = re.compile(r"\s+")


def _norm(name: str) -> str:
    return NAME_STRIP.sub(" ", (name or "").strip().lower())


def live_clicks_enabled() -> bool:
    return os.environ.get("PLASMAI_TEST_LIVE", "").strip() in ("1", "true", "yes")


def should_skip(name: str, role: str, description: str, *, live: bool | None = None) -> str | None:
    if live is None:
        live = live_clicks_enabled()
    role_l = (role or "").strip().lower()
    desc = _norm(description)
    n = _norm(name)

    if not live and role_l in LIVE_ROLES:
        return "list-item (would start/switch tracking)"
    if not live and any(token in desc for token in DENY_CONTAINS):
        return "activity row"
    if n in SDK_EXACT:
        return f"deny-list name {name!r}"
    if any(n.startswith(p) for p in HISTORY_PREFIX):
        return "history mutation"
    if not live and n in TRACKING_EXACT:
        return f"deny-list name {name!r}"
    if not live and any(n.startswith(p) for p in DENY_PREFIX):
        return "live tracking control"
    if not live and (n.startswith("continue") or n.startswith("fortsetzen")):
        return "continue tracking"
    if n in {"ok", "apply"} and "containment" in desc:
        return "containment settings"
    return None


@dataclass
class ClickRecord:
    name: str
    role: str
    skipped: str | None = None


@dataclass
class SweepResult:
    clicked: list[ClickRecord] = field(default_factory=list)
    skipped: list[ClickRecord] = field(default_factory=list)
    atspi_available: bool = False
    applications: list[str] = field(default_factory=list)


def _try_import_atspi():
    try:
        import gi

        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi  # type: ignore

        return Atspi
    except Exception:
        return None


def _role_name(Atspi, acc) -> str:
    try:
        name = acc.get_role_name()
        if name:
            return str(name)
    except Exception:
        pass
    try:
        role = acc.get_role()
        return str(role)
    except Exception:
        return ""


def _is_showing_enabled(Atspi, acc) -> bool:
    try:
        st = acc.get_state_set()
        showing = st.contains(Atspi.StateType.SHOWING)
        enabled = not st.contains(Atspi.StateType.DEFUNCT)
        sensitive = st.contains(Atspi.StateType.SENSITIVE) or st.contains(Atspi.StateType.ENABLED)
        return showing and enabled and sensitive
    except Exception:
        return True


def _iter_tree(acc, path: str = "", depth: int = 0, max_depth: int = 36):
    if depth > max_depth or acc is None:
        return
    yield path, acc
    try:
        n = acc.get_child_count()
    except Exception:
        return
    for i in range(max(0, n)):
        try:
            child = acc.get_child_at_index(i)
        except Exception:
            continue
        if child is None:
            continue
        yield from _iter_tree(child, f"{path}/{i}", depth + 1, max_depth)


def _apps(Atspi, *, include_shell: bool = False, include_all: bool = False):
    desktop = Atspi.get_desktop(0)
    found = []
    try:
        n = desktop.get_child_count()
    except Exception:
        return found
    for i in range(n):
        try:
            app = desktop.get_child_at_index(i)
        except Exception:
            continue
        if app is None:
            continue
        try:
            name = app.get_name() or ""
        except Exception:
            name = ""
        low = name.lower()
        if include_all:
            found.append((name, app))
            continue
        if "plasmoidviewer" in low or "plasmawindowed" in low:
            found.append((name, app))
        elif "plasmai" in low:
            found.append((name, app))
        elif include_shell and "plasmashell" in low:
            found.append((name, app))
    return found


def _do_action(acc) -> bool:
    try:
        n = acc.get_n_actions()
    except Exception:
        n = 0
    if n:
        try:
            for i in range(n):
                an = (acc.get_action_name(i) or "").lower()
                if an in ("click", "press", "activate", "toggle", "jump"):
                    return bool(acc.do_action(i))
            return bool(acc.do_action(0))
        except Exception:
            pass
    try:
        ext = acc.get_extents(1)  # SCREEN
        x = int(ext.x + ext.width / 2)
        y = int(ext.y + ext.height / 2)
        if ext.width <= 0 or ext.height <= 0:
            return False
        subprocess.run(
            ["xdotool", "mousemove", "--sync", str(x), str(y), "click", "1"],
            check=False,
            capture_output=True,
        )
        return True
    except Exception:
        return False


def _in_bottom_toolbar(acc, window_geom: tuple[int, int, int, int] | None) -> bool:
    """Skip plasmoidviewer SDK buttons along the bottom of the window."""
    if not window_geom:
        return False
    try:
        ext = acc.get_extents(1)
    except Exception:
        return False
    _wx, wy, _ww, wh = window_geom
    if wh <= 0:
        return False
    cy = ext.y + ext.height / 2
    return cy >= wy + wh - 90


def window_geometry(wid: str | None) -> tuple[int, int, int, int] | None:
    if not wid:
        return None
    out = subprocess.run(
        ["xdotool", "getwindowgeometry", "--shell", wid],
        capture_output=True,
        text=True,
    )
    vals = {}
    for line in (out.stdout or "").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    try:
        return (
            int(vals["X"]),
            int(vals["Y"]),
            int(vals["WIDTH"]),
            int(vals["HEIGHT"]),
        )
    except (KeyError, ValueError):
        return None


def expand_compact(wid: str | None) -> None:
    """Click the upper-middle of the viewer (compact representation / applet)."""
    if not wid:
        return
    geom = window_geometry(wid)
    if not geom:
        subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
        subprocess.run(["xdotool", "click", "1"], check=False)
        return
    x, y, w, h = geom
    # Compact bar sits in the top half; SDK toolbar is at the bottom.
    cx = x + w // 2
    cy = y + max(20, min(40, h // 5))
    subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
    subprocess.run(
        ["xdotool", "mousemove", "--sync", str(cx), str(cy), "click", "1"],
        check=False,
    )
    time.sleep(0.6)


def press_escape(wid: str | None) -> None:
    if wid:
        subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
    subprocess.run(["xdotool", "key", "Escape"], check=False)
    time.sleep(0.15)


def collect_clickables(Atspi, apps, geom, *, live: bool) -> list[tuple]:
    """Return (key, acc, name, role, skip_reason) for unique showing controls."""
    seen: set[str] = set()
    out = []
    for _app_name, app in apps:
        for path, acc in _iter_tree(app):
            role = _role_name(Atspi, acc).lower()
            if role not in CLICK_ROLES and role not in LIVE_ROLES:
                continue
            if not _is_showing_enabled(Atspi, acc):
                continue
            try:
                name = acc.get_name() or ""
            except Exception:
                name = ""
            try:
                desc = acc.get_description() or ""
            except Exception:
                desc = ""
            key = f"{role}|{_norm(name)}|{path}"
            if key in seen:
                continue
            seen.add(key)
            skip = should_skip(name, role, desc, live=live)
            if not name.strip() and DENY_EMPTY_TOOLBAR and _in_bottom_toolbar(acc, geom):
                skip = skip or "viewer sdk toolbar"
            if _in_bottom_toolbar(acc, geom) and _norm(name) in {
                "formfactors",
                "location",
                "configure containment",
            }:
                skip = skip or "viewer sdk toolbar"
            out.append((key, acc, name, role, skip))
    return out


def sweep(wid: str | None, *, live: bool | None = None, max_clicks: int = 70) -> SweepResult:
    result = SweepResult()
    if live is None:
        live = live_clicks_enabled()
    Atspi = _try_import_atspi()
    if Atspi is None:
        return result
    result.atspi_available = True
    apps = _apps(
        Atspi,
        include_shell=os.environ.get("PLASMAI_TEST_SHELL", "").strip() in ("1", "true", "yes"),
    )
    result.applications = [n for n, _ in apps]
    if not apps:
        return result

    geom = window_geometry(wid)
    clicked_keys: set[str] = set()
    deadline = time.time() + 45
    for _pass in range(4):
        if time.time() > deadline:
            break
        targets = collect_clickables(Atspi, apps, geom, live=live)
        progress = False
        for key, acc, name, role, skip in targets:
            rec = ClickRecord(name=name or "(unnamed)", role=role)
            if skip:
                if all(s.name != rec.name or s.skipped != skip for s in result.skipped):
                    rec.skipped = skip
                    result.skipped.append(rec)
                continue
            if key in clicked_keys:
                continue
            if len(result.clicked) >= max_clicks:
                return result
            if _do_action(acc):
                clicked_keys.add(key)
                result.clicked.append(rec)
                progress = True
                time.sleep(0.25)
                press_escape(wid)
        if not progress:
            break
    return result


def state_checked(Atspi, acc) -> bool | None:
    try:
        st = acc.get_state_set()
        return bool(st.contains(Atspi.StateType.CHECKED))
    except Exception:
        return None


def state_enabled(Atspi, acc) -> bool:
    try:
        st = acc.get_state_set()
        if st.contains(Atspi.StateType.DEFUNCT):
            return False
        return bool(
            st.contains(Atspi.StateType.SENSITIVE)
            or st.contains(Atspi.StateType.ENABLED)
        )
    except Exception:
        return False


def showing_nodes(Atspi, *, include_all: bool = False, require_showing: bool = True):
    apps = _apps(
        Atspi,
        include_all=include_all,
        include_shell=os.environ.get("PLASMAI_TEST_SHELL", "").strip() in ("1", "true", "yes"),
    )
    for _app_name, app in apps:
        for _path, acc in _iter_tree(app):
            if require_showing:
                try:
                    st = acc.get_state_set()
                    if st.contains(Atspi.StateType.DEFUNCT):
                        continue
                    if not (
                        st.contains(Atspi.StateType.SHOWING)
                        or st.contains(Atspi.StateType.VISIBLE)
                    ):
                        continue
                except Exception:
                    pass
            try:
                name = acc.get_name() or ""
            except Exception:
                name = ""
            yield name, _role_name(Atspi, acc), acc


def list_showing(Atspi, *, roles: set[str] | None = None, limit: int = 100) -> list[str]:
    out: list[str] = []
    for name, role, _acc in showing_nodes(Atspi):
        if not (name or "").strip():
            continue
        if roles and role.lower() not in roles:
            continue
        out.append(f"{role}: {name}")
        if len(out) >= limit:
            break
    return out


def find_named(
    Atspi,
    names: list[str],
    *,
    roles: set[str] | None = None,
    enabled_only: bool = False,
    require_showing: bool = True,
):
    want = {_norm(n) for n in names}
    for name, role, acc in showing_nodes(Atspi, require_showing=require_showing):
        if _norm(name) not in want:
            continue
        if roles and role.lower() not in roles:
            continue
        if enabled_only and not state_enabled(Atspi, acc):
            continue
        return name, role, acc
    return None


def wait_named(
    names: list[str],
    *,
    roles: set[str] | None = None,
    timeout: float = 15.0,
    enabled_only: bool = False,
    require_showing: bool = True,
):
    Atspi = _try_import_atspi()
    if Atspi is None:
        raise RuntimeError("AT-SPI (python-gobject / atspi) is not available")
    deadline = time.time() + timeout
    dump: list[str] = []
    while time.time() < deadline:
        hit = find_named(
            Atspi,
            names,
            roles=roles,
            enabled_only=enabled_only,
            require_showing=require_showing,
        )
        if not hit and require_showing:
            hit = find_named(
                Atspi,
                names,
                roles=roles,
                enabled_only=enabled_only,
                require_showing=False,
            )
        if hit:
            return hit
        dump = list_showing(Atspi, limit=80)
        if not dump:
            dump = [f"application: {n}" for n, _ in _apps(Atspi, include_all=False)]
            dump.append("(no showing controls under plasmoidviewer)")
        time.sleep(0.2)
    raise TimeoutError(f"no control named {names!r}\n" + "\n".join(dump))


def _scroll_into_view(Atspi, acc) -> None:
    try:
        acc.scroll_to(Atspi.ScrollType.ANYWHERE)
        return
    except Exception:
        pass
    try:
        Atspi.Component.scroll_to(acc, Atspi.ScrollType.ANYWHERE)
    except Exception:
        pass


def click_named(
    names: list[str],
    *,
    roles: set[str] | None = None,
    timeout: float = 15.0,
) -> str:
    name, _role, acc = wait_named(names, roles=roles, timeout=timeout)
    Atspi = _try_import_atspi()
    if Atspi is not None:
        _scroll_into_view(Atspi, acc)
        time.sleep(0.15)
    if not _do_action(acc):
        raise RuntimeError(f"could not click {name!r}")
    time.sleep(0.4)
    return name


def named_enabled(names: list[str], *, roles: set[str] | None = None) -> bool | None:
    Atspi = _try_import_atspi()
    if Atspi is None:
        return None
    hit = find_named(Atspi, names, roles=roles) or find_named(
        Atspi, names, roles=roles, require_showing=False
    )
    if not hit:
        return None
    return state_enabled(Atspi, hit[2])


def named_checked(names: list[str], *, roles: set[str] | None = None) -> bool | None:
    Atspi = _try_import_atspi()
    if Atspi is None:
        return None
    hit = find_named(Atspi, names, roles=roles) or find_named(
        Atspi, names, roles=roles, require_showing=False
    )
    if not hit:
        return None
    return state_checked(Atspi, hit[2])

