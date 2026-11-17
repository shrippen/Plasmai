"""The app's pages (app/qml) load with their qrc layout, so QML tests of them run on a copy
of it: one symlink per entry of app/plasmai-app.qrc, plus the tests of tests/app_pages/."""

import os
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
QMLTEST_FALLBACKS = ("/usr/lib/qt6/bin/qmltestrunner", "qmltestrunner-qt6", "qmltestrunner")


def find_qmltestrunner():
    env = os.environ.get("QMLTESTRUNNER")
    if env:
        return env
    for name in QMLTEST_FALLBACKS:
        found = shutil.which(name)
        if found:
            return found
    return None


def stage_qrc(stage):
    """Links every entry of the root prefix at its alias, as the app's resources have it."""
    for res in ET.parse(APP / "plasmai-app.qrc").getroot().iter("qresource"):
        if res.get("prefix") != "/":
            continue
        for entry in res.iter("file"):
            alias = entry.get("alias") or entry.text
            link = stage / alias
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to((APP / entry.text).resolve())


def test_app_page_tests(tmp_path):
    runner = find_qmltestrunner()
    assert runner, "qmltestrunner not found (install qt6-declarative)"
    stage_qrc(tmp_path)
    shutil.copytree(ROOT / "tests" / "app_pages", tmp_path / "app_pages")

    result = subprocess.run(
        [runner, "-input", str(tmp_path / "app_pages")],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
        capture_output=True, text=True, timeout=300,
    )
    assert result.returncode == 0, result.stdout + result.stderr
