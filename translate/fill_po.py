#!/usr/bin/env python3
"""Fill PO msgstr values from translation dictionaries."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

HEADERS = {
    "en": ('English', "en", 'nplurals=2; plural=(n != 1);'),
    "de": ('German', "de", 'nplurals=2; plural=(n != 1);'),
    "fr": ('French', "fr", 'nplurals=2; plural=(n > 1);'),
    "es": ('Spanish', "es", 'nplurals=2; plural=(n != 1);'),
    "it": ('Italian', "it", 'nplurals=2; plural=(n != 1);'),
    "nl": ('Dutch', "nl", 'nplurals=2; plural=(n != 1);'),
    "pt_BR": ('Brazilian Portuguese', "pt_BR", 'nplurals=2; plural=(n > 1);'),
    "pl": ('Polish', "pl", 'nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);'),
    "uk": ('Ukrainian', "uk", 'nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);'),
    "ru": ('Russian', "ru", 'nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);'),
    "ja": ('Japanese', "ja", 'nplurals=1; plural=0;'),
    "zh_CN": ('Simplified Chinese', "zh_CN", 'nplurals=1; plural=0;'),
}


def unesc(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def read_entries(text):
    entries = []
    i = 0
    lines = text.splitlines()
    while i < len(lines):
        if lines[i].startswith("#:"):
            refs = []
            while i < len(lines) and lines[i].startswith("#:"):
                refs.append(lines[i])
                i += 1
            continue
        if lines[i].startswith("msgid "):
            block = []
            if lines[i] == 'msgid ""':
                parts = []
                i += 1
                while i < len(lines) and lines[i].startswith('"'):
                    parts.append(unesc(re.findall(r'"(.*)"', lines[i])[0]))
                    i += 1
                msgid = "".join(parts)
                block.append('msgid ""')
                for p in msgid.split("\n"):
                    block.append(f'"{esc(p)}\\n"')
            else:
                msgid = unesc(re.findall(r'"(.*)"', lines[i])[0])
                block.append(lines[i])
                i += 1
            plural = None
            plural_id = None
            if i < len(lines) and lines[i].startswith("msgid_plural "):
                plural_id = unesc(re.findall(r'"(.*)"', lines[i])[0])
                block.append(lines[i])
                plural = lines[i]
                i += 1
            msgstr_lines = []
            while i < len(lines) and (lines[i].startswith("msgstr") or lines[i].startswith('"')):
                msgstr_lines.append(lines[i])
                i += 1
            entries.append({
                "refs": refs if 'refs' in dir() else [],
                "msgid": msgid,
                "plural_id": plural_id,
                "block_prefix": block,
                "msgstr_lines": msgstr_lines,
            })
            refs = []
            continue
        if lines[i].startswith('msgid ""') and i < 3:
            # header
            i += 1
            while i < len(lines) and (lines[i].startswith("msgstr") or lines[i].startswith('"')):
                i += 1
            continue
        i += 1
    return entries


def _read_msgid(block):
    head = re.split(r"\nmsgid_plural|\nmsgstr", block, maxsplit=1)[0]
    if re.search(r'^msgid ""\s*$', head, re.M):
        chunks = []
        for ln in head.splitlines():
            if ln.startswith('"'):
                chunks.append(unesc(re.findall(r'"(.*)"', ln)[0]))
        return "".join(chunks)
    m = re.search(r'^msgid "(.*)"$', head, re.M)
    return unesc(m.group(1)) if m else None


def parse_po(text):
    """Return list of (refs, msgid, plural_id)."""
    items = []
    for block in re.split(r"\n\n+", text):
        if "msgid " not in block or "Project-Id-Version" in block:
            continue
        refs = [ln for ln in block.splitlines() if ln.startswith("#:")]
        msgid = _read_msgid(block)
        if msgid is None:
            continue
        mp = re.search(r'^msgid_plural "(.*)"$', block, re.M)
        plural_id = unesc(mp.group(1)) if mp else None
        items.append((refs, msgid, plural_id))
    return items


def po_header(lang):
    team, code, plural = HEADERS[lang]
    pot = (ROOT / "template.pot").read_text(encoding="utf-8")
    pot_date = re.search(r"POT-Creation-Date: ([^\n\"\\]+)", pot).group(1).strip()
    return (
        f"# {team} translation for Plasmai.\n"
        f"# Copyright (C) 2026 Plasmai authors\n"
        f"# This file is distributed under the same license as the Plasmai package.\n"
        f"#\n"
        f'msgid ""\n'
        f'msgstr ""\n'
        f'"Project-Id-Version: Plasmai 0.5.0\\n"\n'
        f'"Report-Msgid-Bugs-To: https://github.com/shrippen/Plasmai/issues\\n"\n'
        f'"POT-Creation-Date: {pot_date}\\n"\n'
        f'"PO-Revision-Date: 2026-08-09 19:45+0200\\n"\n'
        f'"Last-Translator: Cursor Agent\\n"\n'
        f'"Language-Team: {team}\\n"\n'
        f'"Language: {code}\\n"\n'
        f'"MIME-Version: 1.0\\n"\n'
        f'"Content-Type: text/plain; charset=UTF-8\\n"\n'
        f'"Content-Transfer-Encoding: 8bit\\n"\n'
        f'"Plural-Forms: {plural}\\n"\n'
    )


def fmt_msgstr(s):
    if "\n" in s:
        out = ['msgstr ""']
        for part in s.split("\n"):
            out.append(f'"{esc(part)}\\n"')
        return out
    return [f'msgstr "{esc(s)}"']


def fmt_plural(lang, vals):
    n = 1 if lang in ("ja", "zh_CN") else (3 if lang in ("pl", "uk", "ru") else 2)
    while len(vals) < n:
        vals.append(vals[-1] if vals else "")
    out = []
    for i in range(n):
        out.append(f'msgstr[{i}] "{esc(vals[i])}"')
    return out


def write_po(lang, items, trans):
    lines = [po_header(lang)]
    for refs, msgid, plural_id in items:
        lines.extend(refs)
        t = trans.get(msgid, {})
        if plural_id:
            lines.append(f'msgid "{esc(msgid)}"')
            lines.append(f'msgid_plural "{esc(plural_id)}"')
            lines.extend(fmt_plural(lang, t.get("p", ["", ""])))
        else:
            if "\n" in msgid:
                lines.append('msgid ""')
                for part in msgid.split("\n"):
                    lines.append(f'"{esc(part)}\\n"')
            else:
                lines.append(f'msgid "{esc(msgid)}"')
            val = t.get("s", msgid if lang == "en" else "")
            lines.extend(fmt_msgstr(val))
        lines.append("")
    (ROOT / f"{lang}.po").write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def main():
    sys.path.insert(0, str(ROOT / "langs"))
    pot = (ROOT / "template.pot").read_text(encoding="utf-8")
    items = parse_po(pot)
    langs = sys.argv[1:] if len(sys.argv) > 1 else [
        "en", "de", "fr", "es", "it", "nl", "pt_BR", "pl", "uk", "ru", "ja", "zh_CN"
    ]
    for lang in langs:
        mod = __import__(lang)
        trans = {}
        for msgid, val in mod.T.items():
            trans[msgid] = {"s": val}
        for msgid, vals in mod.PLURALS.items():
            trans[msgid] = {"p": vals}
        write_po(lang, items, trans)
        print(f"Wrote {lang}.po ({len(items)} strings)")


if __name__ == "__main__":
    main()
