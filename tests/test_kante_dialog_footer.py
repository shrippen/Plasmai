"""A KanteDialog must not set its own `footer`: under the Kante style, KanteDialog swaps the
footer for a button box that shows only `standardButtons`, so buttons in a custom footer
vanish (the widget's "Switch activity" and "You were idle" dialogs had none left)."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def kante_dialog_footers(path):
    """Line numbers of `footer:` set directly on a KanteDialog in the file."""
    lines = path.read_text(encoding="utf-8").splitlines()
    found = []
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*)KanteDialog \{", line)
        if not m:
            continue
        indent = len(m.group(1))
        child = None
        for j in range(i + 1, len(lines)):
            text = lines[j]
            if not text.strip():
                continue
            depth = len(text) - len(text.lstrip())
            if depth <= indent:
                break
            if child is None:
                child = depth
            if depth == child and text.lstrip().startswith("footer:"):
                found.append(j + 1)
    return found


def test_no_kante_dialog_sets_footer():
    hits = []
    for path in sorted([*(ROOT / "contents" / "ui").rglob("*.qml"), *(ROOT / "app" / "qml").rglob("*.qml")]):
        hits += [f"{path.relative_to(ROOT)}:{n}" for n in kante_dialog_footers(path)]
    assert hits == [], "buttons belong in contentItem: " + ", ".join(hits)
