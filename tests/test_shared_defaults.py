"""sharedConfig.js DEFAULTS (written in full when pre-wizard settings are reset) must equal
the defaults in contents/config/main.xml, or a reset Plasmoid and the app disagree.
profilesJson is the default profile there instead of main.xml's "" (see sharedConfig.js)."""

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NS = "{http://www.kde.org/standards/kcfg/1.0}"
EXEMPT = {"profilesJson", "settingsVersion"}


def kcfg_defaults():
    out = {}
    for entry in ET.parse(ROOT / "contents" / "config" / "main.xml").getroot().iter(NS + "entry"):
        node = entry.find(NS + "default")
        text = node.text if node is not None and node.text is not None else ""
        kind = entry.get("type")
        if kind == "Bool":
            value = text == "true"
        elif kind == "Int":
            value = int(text or 0)
        elif kind == "Double":
            value = float(text or 0)
        else:
            value = text
        out[entry.get("name")] = value
    return out


def js_defaults():
    src = (ROOT / "contents" / "code" / "sharedConfig.js").read_text(encoding="utf-8")
    body = re.search(r"var DEFAULTS = \{(.*?)\n\}", src, re.S).group(1)
    out = {}
    for key, raw in re.findall(r"^\s+(\w+): (.+?),?$", body, re.M):
        out[key] = None if raw == "DEFAULT_PROFILES_JSON" else json.loads(raw)
    return out


def shared_keys():
    src = (ROOT / "contents" / "code" / "sharedConfig.js").read_text(encoding="utf-8")
    block = re.search(r"var SHARED_KEYS = \[(.*?)\]", src, re.S).group(1)
    return re.findall(r'"(\w+)"', block)


def test_defaults_match_main_xml():
    kcfg = kcfg_defaults()
    js = js_defaults()
    keys = [k for k in shared_keys() if k not in EXEMPT]
    missing = [k for k in keys if k not in js]
    assert not missing, f"add to DEFAULTS in sharedConfig.js: {missing}"
    differ = {k: (js[k], kcfg[k]) for k in keys if js[k] != kcfg[k]}
    assert not differ, f"DEFAULTS differ from main.xml (js, xml): {differ}"


if __name__ == "__main__":
    test_defaults_match_main_xml()
    print("shared defaults: ok")
