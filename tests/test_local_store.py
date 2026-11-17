"""localStore.sh quarantine: a file set aside is never overwritten."""
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "contents/code/localStore.sh"
APP_DIR = "io.github.shrippen.Plasmai/plasmoid"


def run(data_home, *args, payload=None):
    env = dict(os.environ, XDG_DATA_HOME=str(data_home))
    if payload is not None:
        env["PLASMAI_LOCAL_JSON"] = payload
    return subprocess.run(["sh", str(SCRIPT), *args], env=env, capture_output=True, text=True)


def test_quarantine_twice_keeps_both(tmp_path):
    for text in ("{bad1", "{bad2"):
        assert run(tmp_path, "store", "box", payload=text).returncode == 0
        assert run(tmp_path, "quarantine", "box").returncode == 0
    kept = sorted(p.read_text() for p in (tmp_path / APP_DIR).glob("box.broken-*"))
    assert kept == ["{bad1", "{bad2"]
    assert not (tmp_path / APP_DIR / "box.json").exists()


def test_quarantine_of_missing_file_fails(tmp_path):
    assert run(tmp_path, "store", "other", payload="{}").returncode == 0
    assert run(tmp_path, "quarantine", "box").returncode != 0


def test_load_tells_missing_from_unreadable(tmp_path):
    assert run(tmp_path, "load", "box").returncode == 1
    (tmp_path / APP_DIR / "box.json").mkdir(parents=True)
    assert run(tmp_path, "load", "box").returncode == 2
