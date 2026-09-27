"""The app loads contents/code/*.js from its Qt resources: every script it imports,
directly or through another script's .import, must be listed in app/plasmai-app.qrc.
A missing one still builds but the app fails at startup ("Script … unavailable")."""

import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QRC = ROOT / "app" / "plasmai-app.qrc"
DEMO_QRC = ROOT / "app" / "demo.qrc"  # internal builds only (-DPLASMAI_DEMO)
CODE = ROOT / "contents" / "code"

QML_IMPORT = re.compile(r'^import\s+"(?:\.\./)+contents/code/([\w.]+\.js)"', re.M)
JS_IMPORT = re.compile(r'^\.import\s+"\./([\w.]+\.js)"', re.M)


def qrc_aliases(qrc=QRC):
    return {f.get("alias") or f.text for f in ET.parse(qrc).getroot().iter("file")}


def scripts_the_app_loads():
    todo = set()
    for qml in (ROOT / "app" / "qml").rglob("*.qml"):
        todo.update(QML_IMPORT.findall(qml.read_text(encoding="utf-8")))
    seen = set()
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        todo.update(JS_IMPORT.findall((CODE / name).read_text(encoding="utf-8")))
    return seen


def test_every_loaded_script_is_in_the_qrc():
    aliases = qrc_aliases() | qrc_aliases(DEMO_QRC)
    missing = sorted(n for n in scripts_the_app_loads() if f"contents/code/{n}" not in aliases)
    assert not missing, f"add to app/plasmai-app.qrc (or app/demo.qrc for demo files): {missing}"


def test_published_resources_have_no_demo():
    """The demo is internal: the resources of every build must not contain it."""
    leaked = sorted(a for a in qrc_aliases() if "demo" in a.lower())
    assert not leaked, f"move to app/demo.qrc: {leaked}"


if __name__ == "__main__":  # CI runs it without pytest
    test_every_loaded_script_is_in_the_qrc()
    test_published_resources_have_no_demo()
    print("app resources: ok")
