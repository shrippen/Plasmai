#!/usr/bin/env python3
"""Convert translate/*.po into app/i18n/<lang>.json for the Android build.

Android has no KF6 I18n / gettext runtime, so the app looks messages up in these
JSON catalogs ({msgid: msgstr}) that are bundled into the QRC (see main.cpp, I18nFallback).
Plural forms are skipped: the app QML only uses plain i18n().
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "app" / "i18n"


def unesc(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def parse(text):
    catalog = {}
    for block in re.split(r"\n\n+", text):
        if "msgid_plural" in block or "Project-Id-Version" in block:
            continue
        msgid = []
        msgstr = []
        target = None
        for line in block.splitlines():
            if line.startswith("msgid "):
                target = msgid
                line = line[len("msgid "):]
            elif line.startswith("msgstr "):
                target = msgstr
                line = line[len("msgstr "):]
            elif not line.startswith('"'):
                target = None
                continue
            if target is not None:
                m = re.match(r'"(.*)"$', line)
                if m:
                    target.append(unesc(m.group(1)))
        key, val = "".join(msgid), "".join(msgstr)
        if key and val and key != val:
            catalog[key] = val
    return catalog


def main():
    OUT.mkdir(exist_ok=True)
    for po in sorted(ROOT.glob("*.po")):
        lang = po.stem
        if lang == "en":
            continue
        catalog = parse(po.read_text(encoding="utf-8"))
        (OUT / f"{lang}.json").write_text(
            json.dumps(catalog, ensure_ascii=False, indent=0, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Wrote app/i18n/{lang}.json ({len(catalog)} strings)")


if __name__ == "__main__":
    sys.exit(main())
