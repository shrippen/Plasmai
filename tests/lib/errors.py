"""Classify QML / plasmashell log lines as fatal applet errors vs noise."""

from __future__ import annotations

import re

# Fail the click sweep when the applet (or viewer hosting it) logs these.
FATAL_PATTERNS = [
    re.compile(r"TypeError", re.I),
    re.compile(r"ReferenceError", re.I),
    re.compile(r"Cannot read property", re.I),
    re.compile(r"Cannot assign \[undefined\]", re.I),
    re.compile(r"QQmlComponent: Component is not ready", re.I),
    re.compile(r"QQmlApplicationEngine failed", re.I),
    re.compile(r"Segmentation fault", re.I),
    re.compile(r"Aborted \(core dumped\)", re.I),
    re.compile(r"ASSERT:", re.I),
    re.compile(r"QFatal", re.I),
]

# Plasma / other applets / known harmless viewer noise.
IGNORE_PATTERNS = [
    re.compile(r"QML debugging is enabled"),
    re.compile(r"digitalclock", re.I),
    re.compile(r"org/kde/plasma/digitalclock"),
    re.compile(r"org\.kde\.desktopcontainment"),
    re.compile(r"org/kde/desktopcontainment"),
    re.compile(r"isScreenUiReady"),
    re.compile(r"plasmoidviewershell", re.I),
    re.compile(r"org\.kde\.plasma\.folder"),
    re.compile(r"FolderViewLayer"),
    re.compile(r"ConfigurationShortcuts does not have a property called cfg_"),
    re.compile(r"AboutPlugin does not have a property called cfg_"),
    re.compile(r"Created graphical object was not placed in the graphics scene"),
    re.compile(r"kf\.(kirigami|plasma|kio|coreaddons|configwidgets)"),
    re.compile(r"qt\.qpa\."),
    re.compile(r"qt\.qml\.typeresolution"),
    re.compile(r"QFont::"),
    re.compile(r"connecting to deprecated signal"),
    re.compile(r"file:///usr/lib/qt6/qml/org/kde/kirigami/controls/PageRow"),
    re.compile(r"Aborting shell load:"),
    re.compile(r"Plasma Shell startup"),
]


def is_ignored(line: str) -> bool:
    return any(p.search(line) for p in IGNORE_PATTERNS)


def is_fatal(line: str) -> bool:
    if is_ignored(line):
        return False
    return any(p.search(line) for p in FATAL_PATTERNS)


APPLET_HINT = re.compile(
    r"plasmai|com\.github\.shrippen\.plasmai",
    re.I,
)


def is_fatal_journal(line: str) -> bool:
    """Journal is noisy; only fail lines that mention this applet or the viewer."""
    if not APPLET_HINT.search(line):
        return False
    return is_fatal(line)


def collect_fatals(lines: list[str], *, journal: bool = False) -> list[str]:
    check = is_fatal_journal if journal else is_fatal
    out = []
    for raw in lines:
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        if check(line):
            out.append(line)
    return out
