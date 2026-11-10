"""The app's start builds what it shows, not what it may show later.

The timer page held six dialogs nobody had asked for yet (each with Material's shadows), the
edit form of the running entry and the "start something else" pickers; main.qml built the eight
entries of the closed drawer. On a Pixel 6 (warm start) the data showed after 1.69 s with them,
1.35 s with them built when needed: dialogs in a LazyDialog, the forms in a Loader that is active
while they are open, the drawer's entries a moment after the start."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPEN = re.compile(r"([A-Za-z_][\w.]*)\s*(?::\s*)?\{")


def blocks(text):
    """(type, line, ancestor types) for every `Type {` in a QML file, nesting by braces."""
    stack, found = [], []
    for lineno, line in enumerate(text.split("\n"), 1):
        code = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line.split("//")[0])
        pos = 0
        while pos < len(code):
            if code[pos] == "{":
                m = None
                for cand in OPEN.finditer(code[:pos + 1]):
                    if cand.end() == pos + 1:
                        m = cand
                name = m.group(1) if m else ""
                found.append((name, lineno, list(stack)))
                stack.append(name)
            elif code[pos] == "}" and stack:
                stack.pop()
            pos += 1
    return found


def eager(path, types):
    text = (ROOT / path).read_text(encoding="utf-8")
    return [f"{path}:{line} {name}" for name, line, above in blocks(text)
            if name in types and "Component" not in above]


def test_timer_page_builds_no_dialog_before_it_is_opened():
    found = eager("app/qml/TimerPage.qml", {"Kirigami.PromptDialog", "Kirigami.Dialog", "CreateEntityDialog"})
    assert not found, "put it in a LazyDialog { sourceComponent: Component { … } }: " + ", ".join(found)


def test_timer_page_builds_its_forms_when_they_open():
    found = eager("app/qml/TimerPage.qml", {"ActiveEditView", "ProjectActivityPickers"})
    assert not found, "build it in a Loader active while the form is open: " + ", ".join(found)


def test_drawer_rows_come_after_the_start():
    text = (ROOT / "app/qml/main.qml").read_text(encoding="utf-8")
    inline = [line for name, line, above in blocks(text)
              if name == "Kirigami.Action" and "Kirigami.GlobalDrawer" in above]
    assert not inline, f"app/qml/main.qml: drawer entries built with the window (lines {inline})"
    assert re.search(r"actions:\s*root\.drawerReady\s*\?", text), "the drawer's actions wait for drawerReady"
