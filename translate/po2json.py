#!/usr/bin/env python3
"""Convert translate/*.po into app/i18n/<lang>.json for the Android build.

Android has no KF6 I18n / gettext runtime, so the app looks messages up in these
JSON catalogs ({msgid: msgstr}) that are bundled into the QRC (see main.cpp, I18nFallback).
Plural forms (msgid/msgid_plural) are stored under both the singular and plural
msgid, each mapped to its own msgstr — matching I18nFallback::i18np(), which only
picks between the two English-rule forms, not full gettext plural rules.
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
        if "Project-Id-Version" in block:
            continue
        fields = {}
        target = None
        for line in block.splitlines():
            for prefix, name in (
                ("msgid_plural ", "msgid_plural"), ("msgid ", "msgid"),
                ("msgstr[0] ", "msgstr0"), ("msgstr[1] ", "msgstr1"), ("msgstr ", "msgstr"),
            ):
                if line.startswith(prefix):
                    target = fields.setdefault(name, [])
                    line = line[len(prefix):]
                    break
            else:
                if not line.startswith('"'):
                    target = None
                    continue
            if target is not None:
                m = re.match(r'"(.*)"$', line)
                if m:
                    target.append(unesc(m.group(1)))
        joined = {k: "".join(v) for k, v in fields.items()}
        if "msgid_plural" in joined:
            singular, plural = joined.get("msgid", ""), joined["msgid_plural"]
            msgstr0, msgstr1 = joined.get("msgstr0", ""), joined.get("msgstr1", "")
            if singular and msgstr0 and singular != msgstr0:
                catalog[singular] = msgstr0
            if plural and msgstr1 and plural != msgstr1:
                catalog[plural] = msgstr1
            continue
        key, val = joined.get("msgid", ""), joined.get("msgstr", "")
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
