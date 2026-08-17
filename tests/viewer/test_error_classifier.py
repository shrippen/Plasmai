"""Fail on QML TypeError / plasmashell fatals from captured log lines."""

from lib.errors import collect_fatals, is_fatal, is_ignored


def test_ignores_plasma_cfg_noise():
    line = (
        "file:///usr/share/plasma/shells/org.kde.plasma.desktop/contents/configuration/"
        "ConfigurationShortcuts.qml:99: TypeError: Cannot assign [undefined] to "
        "ConfigurationShortcuts does not have a property called cfg_refreshInterval"
    )
    assert is_ignored(line)
    assert not is_fatal(line)


def test_ignores_digitalclock():
    line = "file:///usr/share/plasma/plasmoids/org.kde.plasma.digitalclock/contents/ui/main.qml TypeError"
    assert not is_fatal(line)


def test_flags_plasmai_typeerror():
    line = (
        "file:///home/arian/Hacking/Plasmai/contents/ui/main.qml:210: TypeError: "
        "Cannot read property 'id' of undefined"
    )
    assert is_fatal(line)


def test_flags_reference_error():
    assert is_fatal("qrc:/qt/qml/plasmai/foo.qml:1: ReferenceError: bar is not defined")


def test_ignores_viewer_containment_noise():
    line = (
        "file:///usr/share/plasma/plasmoids/org.kde.desktopcontainment/"
        "contents/ui/main.qml:63: TypeError: Property 'isScreenUiReady'"
    )
    assert not is_fatal(line)


def test_journal_requires_applet_hint():
    from lib.errors import is_fatal_journal

    noise = (
        "2026-08-13T15:25:28+02:00 Geralt plasmoidviewer[1]: "
        "file:///usr/share/plasma/plasmoids/org.kde.desktopcontainment/"
        "contents/ui/main.qml:63: TypeError: Property 'isScreenUiReady'"
    )
    assert not is_fatal_journal(noise)
    real = (
        "2026-08-13T15:25:28+02:00 Geralt plasmoidviewer[1]: "
        "file:///home/arian/Hacking/Plasmai/contents/ui/main.qml:1: TypeError: boom"
    )
    assert is_fatal_journal(real)
    lines = [
        "QML debugging is enabled. Only use this in a safe environment.",
        "file:///home/x/Plasmai/contents/ui/StatsView.qml:12: TypeError: boom",
        "kf.kirigami: something",
    ]
    fatals = collect_fatals(lines)
    assert len(fatals) == 1
    assert "StatsView" in fatals[0]


def test_collect_fatals_filters():
    lines = [
        "QML debugging is enabled. Only use this in a safe environment.",
        "file:///home/x/Plasmai/contents/ui/StatsView.qml:12: TypeError: boom",
        "kf.kirigami: something",
    ]
    fatals = collect_fatals(lines)
    assert len(fatals) == 1
    assert "StatsView" in fatals[0]
