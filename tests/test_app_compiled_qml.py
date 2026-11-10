"""The app's QML and JavaScript are compiled at build time (qmlcachegen, app/CMakeLists.txt).

Loaded from the plain qrc, every file was compiled on the device at the first start after an
install or update (Pixel 6: data shown after 2.74 s; compiled at build time 1.94 s) and typed
bindings ran in the interpreter (warm start 1.35 s, compiled 1.16 s). CMake takes the files from
the qrc's "/" entries of the form <file alias="X.qml">source</file>, one per line: an entry in
another form would still be shipped, but no longer compiled."""

import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CMAKE = (ROOT / "app" / "CMakeLists.txt").read_text(encoding="utf-8")
# The pattern plasmai_split_qrc() in app/CMakeLists.txt matches.
ENTRY = re.compile(r'<file alias="([^"]+\.(qml|js))">([^<]+)</file>')


def test_the_app_compiles_its_qml_at_build_time():
    assert re.search(r"qt_add_qml_module\(plasmai-app\b(?:(?!\n\)).)*?QML_FILES \$\{PLASMAI_QML_FILES\}", CMAKE, re.S), \
        "app/CMakeLists.txt: qt_add_qml_module(plasmai-app … QML_FILES ${PLASMAI_QML_FILES})"
    assert "plasmai_split_qrc(plasmai-app.qrc" in CMAKE
    assert "plasmai_split_qrc(demo.qrc" in CMAKE
    assert "plasmai-app.qrc\n" not in CMAKE.split("qt_add_executable(plasmai-app", 1)[1].split(")", 1)[0], \
        "the qrc itself is not a source of the executable: its QML would be shipped twice"


def test_every_qml_and_script_entry_is_one_cmake_reads():
    for name in ("plasmai-app.qrc", "demo.qrc"):
        qrc = ROOT / "app" / name
        text = qrc.read_text(encoding="utf-8")
        lines = [line for line in text.split("\n") if "<file" in line]
        for res in ET.parse(qrc).getroot().iter("qresource"):
            if res.get("prefix") != "/":
                continue
            for f in res.iter("file"):
                path = f.get("alias") or f.text
                if not path.endswith((".qml", ".js")):
                    continue
                found = [line for line in lines if f'"{path}"' in line or f">{path}<" in line]
                assert found and ENTRY.search(found[0]), \
                    f"app/{name}: write {path} as <file alias=\"{path}\">source</file> on one line"
