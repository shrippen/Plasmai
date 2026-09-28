#!/usr/bin/env python3
"""Convert translate/*.po into app/i18n/<lang>.json for the Android build.

The app has no gettext runtime (Android, Windows, macOS; on Linux too, one path
everywhere), so it looks messages up in these JSON catalogs, bundled into the QRC
(see app/i18nfallback.cpp):

  {msgid: msgstr}                     plain messages
  {"\u0004" + msgid: [form0, ...]}    all plural forms of a msgid/msgid_plural pair
  {"\u0004Plural-Forms": "<rule>"}    the language's gettext plural rule

Only the rules I18nFallback knows (PLURAL_RULES) are accepted: a new language with
another rule fails here instead of showing wrong plurals in the app.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "app" / "i18n"

# \u0004 (gettext's context separator) never occurs in a msgid: no clash with messages.
PLURAL_PREFIX = "\u0004"
PLURAL_FORMS_KEY = PLURAL_PREFIX + "Plural-Forms"

# Rules implemented in app/i18nfallback.cpp (pluralIndex), whitespace removed.
PLURAL_RULES = {
    "0",
    "(n!=1)",
    "(n>1)",
    "(n%10==1&&n%100!=11?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)",
    "(n==1?0:n%10>=2&&n%10<=4&&(n%100<10||n%100>=20)?1:2)",
}


def unesc(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def plural_rule(text):
    """The plural= expression of the header, whitespace removed ("(n!=1)")."""
    m = re.search(r"Plural-Forms:[^\\]*?plural=([^;\\]+);", text)
    return re.sub(r"\s+", "", m.group(1)) if m else "(n!=1)"


def parse(text):
    catalog = {}
    for block in re.split(r"\n\n+", text):
        if "Project-Id-Version" in block:
            continue
        fields = {}
        target = None
        for line in block.splitlines():
            m = re.match(r"(msgid_plural|msgid|msgstr\[(\d+)\]|msgstr) ", line)
            if m:
                name = "msgstr%s" % m.group(2) if m.group(2) else m.group(1)
                target = fields.setdefault(name, [])
                line = line[m.end():]
            elif not line.startswith('"'):
                target = None
                continue
            if target is not None:
                m = re.match(r'"(.*)"$', line)
                if m:
                    target.append(unesc(m.group(1)))
        joined = {k: "".join(v) for k, v in fields.items()}
        if "msgid_plural" in joined:
            singular, plural = joined.get("msgid", ""), joined["msgid_plural"]
            forms = []
            while "msgstr%d" % len(forms) in joined:
                forms.append(joined["msgstr%d" % len(forms)])
            if singular and forms and all(forms):
                catalog[PLURAL_PREFIX + singular] = forms
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
        text = po.read_text(encoding="utf-8")
        rule = plural_rule(text)
        if rule not in PLURAL_RULES:
            sys.exit(f"{po.name}: plural rule {rule} is not in I18nFallback (app/i18nfallback.cpp)")
        catalog = parse(text)
        catalog[PLURAL_FORMS_KEY] = rule
        (OUT / f"{lang}.json").write_text(
            json.dumps(catalog, ensure_ascii=False, indent=0, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Wrote app/i18n/{lang}.json ({len(catalog)} strings)")


if __name__ == "__main__":
    sys.exit(main())
