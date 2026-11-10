"""One id everywhere: io.github.shrippen.Plasmai (Flathub takes no new com.github.* ids).

Up to 2.6.3 the widget, the keychain service, the shared folders and the Android package were
com.github.shrippen.plasmai, only the Flatpak and the desktop file io.github.shrippen.Plasmai.
The old id is left only where something of it moves: the folders (sharedConfig.sh,
catalogCache.sh, localStore.sh, the app's AppIdMigration), the keychain entries (kwallet.sh,
TokenStore) and the placed widgets (install-linux.sh)."""

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
NEW = "io.github.shrippen.Plasmai"
OLD = "com.github.shrippen.plasmai"

# Where the old id may stay: the code that moves things from it, the notes that explain it,
# and this test.
MIGRATION = {
    "app/appid.h",
    "contents/code/sharedConfig.sh",
    "contents/code/catalogCache.sh",
    "contents/code/localStore.sh",
    "contents/code/kwallet.sh",
    "scripts/install-linux.sh",
    "tests/test_app_id.py",
    "CHANGELOG.md",
    "DESIGN.md",
    "RELEASING.md",
    "RELEASE-TODO.md",
}


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [p for p in out.decode().split("\0") if p]


def test_old_id_only_where_it_migrates():
    found = []
    for rel in tracked():
        if OLD.replace(".", "/") in rel.lower() or OLD in rel.lower():
            found.append(f"{rel} (path)")
            continue
        if rel in MIGRATION:
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if re.search(r"com[./]github[./]shrippen[./]plasmai", line, re.IGNORECASE):
                found.append(f"{rel}:{n}")
    assert not found, "old id outside the migration code: " + ", ".join(found)


def test_every_identity_uses_the_new_id():
    meta = json.loads((ROOT / "metadata.json").read_text(encoding="utf-8"))
    assert meta["KPlugin"]["Id"] == NEW
    assert f'package="{NEW}"' in (ROOT / "app/android/AndroidManifest.xml").read_text(encoding="utf-8")
    assert f'QT_ANDROID_PACKAGE_NAME "{NEW}"' in (ROOT / "app/CMakeLists.txt").read_text(encoding="utf-8")
    assert f'APP_ID = QStringLiteral("{NEW}")' in (ROOT / "app/appid.h").read_text(encoding="utf-8")
    java = ROOT / "app/android/src" / NEW.replace(".", "/") / "TrackingNotice.java"
    assert java.read_text(encoding="utf-8").startswith(f"package {NEW};")
    assert f"app-id: {NEW}" in (ROOT / f"packaging/flatpak/{NEW}.yml").read_text(encoding="utf-8")
    catalogs = sorted((ROOT / "contents/locale").glob("*/LC_MESSAGES/*.mo"))
    assert catalogs and all(p.name == f"plasma_applet_{NEW}.mo" for p in catalogs)


# -- the widget's folders --------------------------------------------------------

SCRIPTS = [
    # script, args, env var with the data, XDG variable, folder under it, file in it
    ("sharedConfig.sh", ["load"], "XDG_CONFIG_HOME", "", "shared.json"),
    ("catalogCache.sh", ["load"], "XDG_CACHE_HOME", "", "catalog-cache.json"),
    ("localStore.sh", ["load", "outbox"], "XDG_DATA_HOME", "plasmoid", "outbox.json"),
]


def run_script(name, args, env):
    return subprocess.run(["sh", str(ROOT / "contents/code" / name), *args], env=env,
                          capture_output=True, text=True)


@pytest.mark.parametrize("name,args,xdg,sub,file", SCRIPTS)
def test_widget_folder_of_the_old_id_moves(tmp_path, name, args, xdg, sub, file):
    base = tmp_path / xdg
    old = base / OLD / sub
    old.mkdir(parents=True)
    (old / file).write_text('{"from":"old"}')
    (base / OLD / "other.json").write_text("kept")
    env = {**os.environ, xdg: str(base)}

    result = run_script(name, args, env)
    assert result.returncode == 0, result.stderr
    assert result.stdout == '{"from":"old"}'
    assert not (base / OLD).exists()
    assert (base / NEW / "other.json").read_text() == "kept"


@pytest.mark.parametrize("name,args,xdg,sub,file", SCRIPTS)
def test_widget_folder_of_the_new_id_wins(tmp_path, name, args, xdg, sub, file):
    base = tmp_path / xdg
    for folder, text in ((OLD, "old"), (NEW, "new")):
        (base / folder / sub).mkdir(parents=True)
        (base / folder / sub / file).write_text(text)
    env = {**os.environ, xdg: str(base)}

    assert run_script(name, args, env).stdout == "new"
    assert (base / OLD / sub / file).read_text() == "old"


# -- the widget's keychain entries ---------------------------------------------

FAKE_SECRET_TOOL = r"""#!/bin/sh
# A keychain in a folder: one file per service and account.
cmd=$1; shift
service=""; account=""
while [ $# -gt 0 ]; do
    case "$1" in
        --label=*) ;;
        service) service=$2; shift ;;
        account) account=$2; shift ;;
    esac
    shift
done
f="$STORE/$service@$account"
case "$cmd" in
    lookup) [ -f "$f" ] && cat "$f" ;;
    store) cat > "$f" ;;
    clear) rm -f "$f" ;;
esac
"""


@pytest.fixture
def keychain(tmp_path):
    store = tmp_path / "store"
    store.mkdir()
    tool = tmp_path / "bin" / "secret-tool"
    tool.parent.mkdir()
    tool.write_text(FAKE_SECRET_TOOL)
    tool.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if k != "PLASMAI_SECRET_SERVICE"}
    env.update(PATH=f"{tool.parent}:{os.environ['PATH']}", STORE=str(store))
    return store, env


def kwallet(env, *args):
    return subprocess.run(["sh", str(ROOT / "contents/code/kwallet.sh"), *args], env=env,
                          capture_output=True, text=True)


def test_token_of_the_old_service_moves(keychain):
    store, env = keychain
    (store / f"{OLD}@api-token:work").write_text("tok-1")

    result = kwallet(env, "load", "work")
    assert (result.returncode, result.stdout) == (0, "tok-1")
    assert (store / f"{NEW}@api-token:work").read_text() == "tok-1"
    assert not (store / f"{OLD}@api-token:work").exists()


def test_clear_clears_a_token_not_yet_moved(keychain):
    store, env = keychain
    (store / f"{OLD}@api-token").write_text("tok-2")

    assert kwallet(env, "clear").returncode == 0
    assert kwallet(env, "load").returncode == 1
    assert not list(store.iterdir())


def test_test_service_does_not_take_the_old_token(keychain):
    store, env = keychain
    (store / f"{OLD}@api-token").write_text("real")

    assert kwallet({**env, "PLASMAI_SECRET_SERVICE": "x.test"}, "load").returncode == 1
    kwallet({**env, "PLASMAI_SECRET_SERVICE": "x.test"}, "clear")
    assert (store / f"{OLD}@api-token").read_text() == "real"


# -- placed widgets (install-linux.sh) -------------------------------------------

FAKE_PLASMA = r"""
const log = [];
let nextId = 100;
function widget(type, index, config, refuse) {
    return {
        id: nextId++, type, index, geometry: { x: 10, y: 20, width: 30, height: 40 },
        globalShortcut: type === OLD_TYPE ? "Meta+K" : "", config, path: [], removed: false,
        get configKeys() { return Object.keys(this.group()).filter(k => typeof this.group()[k] !== "object"); },
        get configGroups() { return Object.keys(this.group()).filter(k => typeof this.group()[k] === "object"); },
        set currentConfigGroup(p) { this.path = p; },
        get currentConfigGroup() { return this.path; },
        group() {
            let g = this.config;
            for (const p of this.path) { g[p] = g[p] || {}; g = g[p]; }
            return g;
        },
        readConfig(k) { return this.group()[k]; },
        writeConfig(k, v) { this.group()[k] = v; },
        reloadConfig() {},
        remove() { this.removed = true; },
    };
}
const OLD_TYPE = "com.github.shrippen.plasmai";
function containment(name, ws, locked) {
    return {
        name, ws,
        widgets(type) { return this.ws.filter(w => w.type === type && !w.removed); },
        addWidget(type, x, y, w, h) {
            if (locked) return null;
            const n = widget(type, this.ws.length, {});
            n.geometry = { x, y, width: w, height: h };
            this.ws.push(n);
            log.push(name + " add " + type + " " + [x, y, w, h].join(","));
            return n;
        },
    };
}
const panel = containment("panel", [widget("org.kde.plasma.clock", 0, {}),
    widget(OLD_TYPE, 1, { PreloadWeight: "42", General: { kimaiUrl: "https://k", Sub: { a: "1" } } }),
    widget("org.kde.plasma.tray", 2, {})]);
const desk = containment("desk", [widget(OLD_TYPE, 0, { General: { touchMode: "2" } })]);
const lockedPanel = containment("locked", [widget(OLD_TYPE, 0, {})], LOCKED);
function panels() { return LOCKED ? [panel, lockedPanel] : [panel]; }
function desktops() { return [desk]; }
let printed = "";
function print(s) { printed += s; }
"""


def run_move_script(locked):
    if not shutil.which("node"):
        pytest.skip("node not installed")
    src = (ROOT / "scripts/install-linux.sh").read_text(encoding="utf-8")
    js = re.search(r"# BEGIN widget-move.*?<<'JS'\n(.*?)\nJS\n", src, re.S).group(1)
    report = """
console.log(JSON.stringify({ printed, panel: panel.ws, desk: desk.ws }));
"""
    program = f"const LOCKED = {'true' if locked else 'false'};\n" + FAKE_PLASMA + js + report
    out = subprocess.run(["node", "-e", program], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def test_placed_widgets_move_with_settings_and_place():
    state = run_move_script(locked=False)
    assert state["printed"] == "moved 2 left 0"

    panel = [w for w in state["panel"] if not w["removed"]]
    assert [w["type"] for w in sorted(panel, key=lambda w: w["index"])][1] == NEW
    new = next(w for w in panel if w["type"] == NEW)
    assert new["index"] == 1
    assert new["config"] == {"PreloadWeight": "42", "General": {"kimaiUrl": "https://k", "Sub": {"a": "1"}}}
    assert new["globalShortcut"] == "Meta+K"

    desk = [w for w in state["desk"] if not w["removed"]]
    assert [w["type"] for w in desk] == [NEW]
    assert desk[0]["geometry"] == {"x": 10, "y": 20, "width": 30, "height": 40}
    assert desk[0]["config"] == {"General": {"touchMode": "2"}}


def test_widget_that_cannot_move_stays():
    state = run_move_script(locked=True)
    assert state["printed"] == "moved 2 left 1"


def test_old_package_goes_only_when_every_widget_moved():
    src = (ROOT / "scripts/install-linux.sh").read_text(encoding="utf-8")
    after = src.split("# END widget-move", 1)[1]
    assert re.search(r'"\$RESULT" == \*" left 0" \]\].*?kpackagetool6 -t Plasma/Applet -r "\$OLD_APPLET"',
                     after, re.S)


# -- unsent offline changes (review of PR #52) -------------------------------------

def unsent(tmp_path, files):
    src = (ROOT / "scripts/install-linux.sh").read_text(encoding="utf-8")
    fn = re.search(r"# BEGIN unsent-outbox[^\n]*\n(.*?)# END unsent-outbox", src, re.S).group(1)
    data = tmp_path / "data"
    for rel, text in files.items():
        (data / rel).parent.mkdir(parents=True, exist_ok=True)
        (data / rel).write_text(text)
    out = subprocess.run(["bash", "-c", fn + "\nunsent_outboxes"], env={**os.environ, "XDG_DATA_HOME": str(data)},
                         capture_output=True, text=True, check=True).stdout
    return sorted(Path(p).name for p in out.split())


def test_unsent_offline_changes_are_found(tmp_path):
    found = unsent(tmp_path, {
        f"{OLD}/plasmoid/offline-outbox-plasmoid-94-default.json": '{"v":2,"counter":3,"ops":[{"kind":"stop"}]}',
        f"{NEW}/plasmoid/offline-outbox-plasmoid-5-work.json": '{"v": 2, "counter": 1, "ops": [ {"kind": "start"} ]}',
        f"{OLD}/plasmoid/offline-outbox-plasmoid-2-demo.json": '{"v":2,"counter":0,"ops":[]}',
        f"{OLD}/plasmoid/offline-state-plasmoid-94-default.json": '{"ops":[1]}',
    })
    assert found == ["offline-outbox-plasmoid-5-work.json", "offline-outbox-plasmoid-94-default.json"]


def test_no_outbox_nothing_found(tmp_path):
    assert unsent(tmp_path, {}) == []


def test_widget_move_waits_for_unsent_offline_changes():
    """The new widget has a new applet id, and the outbox file is named after the old one: moved
    with changes still waiting, they would never be sent."""
    src = (ROOT / "scripts/install-linux.sh").read_text(encoding="utf-8")
    after = src.split("# END unsent-outbox", 1)[1]
    check = after.index("unsent_outboxes")
    assert check < after.index('plasma_script "$MOVE_SCRIPT"'), "check before the move"


def test_folder_move_is_posix():
    for name in ("sharedConfig.sh", "catalogCache.sh", "localStore.sh"):
        text = (ROOT / "contents/code" / name).read_text(encoding="utf-8")
        assert "mv -T" not in text, f"{name}: mv -T is GNU only"
