"""A busy indicator is a KanteBusyIndicator, never QQC2.BusyIndicator { running: x; visible: x }.

Material (Android) fades a stopped BusyIndicator out with an OpacityAnimator, and an Animator
advances only while its item is drawn: an indicator hidden as it stopped never ended the fade, and
the app drew ~90 frames a second with half a core busy while idle (Pixel 6, the timer page's
indicator). KanteBusyIndicator builds the indicator while it runs only. Plasma widget settings
(contents/ui/config, PlasmaComponents3) never run in the app and keep the platform's."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAIN = re.compile(r"\bQQC2\.BusyIndicator\b|^\s*BusyIndicator\s*\{", re.M)


def views():
    for folder in (ROOT / "app" / "qml", ROOT / "contents" / "ui"):
        for qml in folder.rglob("*.qml"):
            rel = qml.relative_to(ROOT)
            if rel.parts[:3] in (("contents", "ui", "Kante"), ("contents", "ui", "KantePlasma"), ("contents", "ui", "config")):
                continue
            yield rel, qml.read_text(encoding="utf-8")


def test_no_plain_busy_indicator():
    found = [f"{rel}:{text[:m.start()].count(chr(10)) + 1}"
             for rel, text in views() for m in PLAIN.finditer(text)]
    assert not found, "use KanteBusyIndicator { running: … } instead: " + ", ".join(found)


def test_app_pages_find_every_kante_type_they_use():
    """app/qml imports "Kante" through app/qml/kante-redirect.qmldir; a type missing there builds,
    but the page that uses it fails to load ("KanteBusyIndicator is not a type")."""
    redirect = (ROOT / "app" / "qml" / "kante-redirect.qmldir").read_text(encoding="utf-8")
    listed = set(re.findall(r"^(?:singleton\s+)?(Kante\w+)\s", redirect, re.M))
    qrc = (ROOT / "app" / "plasmai-app.qrc").read_text(encoding="utf-8")
    used = set()
    for qml in (ROOT / "app" / "qml").rglob("*.qml"):
        used.update(re.findall(r"\b(Kante\w+)\s*\{", qml.read_text(encoding="utf-8")))
    used = {t for t in used if (ROOT / "contents" / "ui" / "Kante" / f"{t}.qml").exists()}
    assert not used - listed, f"missing in kante-redirect.qmldir: {sorted(used - listed)}"
    unshipped = [t for t in used if f"contents/ui/Kante/{t}.qml" not in qrc]
    assert not unshipped, f"missing in plasmai-app.qrc: {sorted(unshipped)}"
