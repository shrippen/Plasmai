"""Deny-list for live Start/Stop/Continue/favorite clicks."""

from lib.atspi_clicks import should_skip


def test_skips_stop_and_start():
    assert should_skip("Stop", "push button", "", live=False)
    assert should_skip("Start", "push button", "", live=False)
    assert should_skip("Stoppen", "push button", "", live=False)


def test_skips_continue_prefix():
    assert should_skip("Continue · Acme · Coding", "push button", "", live=False)
    assert should_skip("Fortsetzen · x · y", "push button", "", live=False)
    assert should_skip("Start · Acme · Coding", "push button", "", live=False)


def test_skips_favorite_list_items():
    reason = should_skip("Coding", "list item", "Starts or switches this activity", live=False)
    assert reason


def test_allows_chrome_when_not_live():
    assert should_skip("Add entry", "push button", "", live=False) is None
    assert should_skip("Statistics", "push button", "", live=False) is None
    assert should_skip("Configure Plasmai", "push button", "", live=False) is None
    assert should_skip("Back", "push button", "", live=False) is None
    assert should_skip("All", "toggle button", "", live=False) is None
    assert should_skip("Billable", "check box", "", live=False) is None


def test_skips_recent_history_actions_even_when_live():
    assert should_skip("Entry actions", "push button", "", live=True)
    assert should_skip("Edit entry", "menu item", "", live=False)
    assert should_skip("Delete entry", "menu item", "", live=True)
    assert should_skip("Split entry", "menu item", "", live=False)
    assert should_skip("Eintrag löschen", "push button", "", live=True)
    assert should_skip("Eintrag bearbeiten", "push button", "", live=False)
    assert should_skip("Create project", "push button", "", live=True)
    assert should_skip("Keep time", "push button", "", live=True)
    assert should_skip("Discard idle", "push button", "", live=False)
    assert should_skip("Set anyway", "push button", "", live=True)


def test_live_flag_allows_start():
    assert should_skip("Start", "push button", "", live=True) is None
