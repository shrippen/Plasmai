"""Deny-list for live Start/Stop/Continue/favorite clicks."""

from lib.atspi_clicks import should_skip


def test_skips_stop_and_start():
    assert should_skip("Stop", "push button", "", live=False)
    assert should_skip("Start", "push button", "", live=False)
    assert should_skip("Stoppen", "push button", "", live=False)


def test_skips_continue_prefix():
    assert should_skip("Continue · Acme · Coding", "push button", "", live=False)
    assert should_skip("Fortsetzen · x · y", "push button", "", live=False)


def test_skips_favorite_list_items():
    reason = should_skip("Coding", "list item", "Starts or switches this activity", live=False)
    assert reason


def test_allows_chrome_when_not_live():
    assert should_skip("Add entry", "push button", "", live=False) is None
    assert should_skip("Statistics", "push button", "", live=False) is None
    assert should_skip("Configure Plasmai", "push button", "", live=False) is None
    assert should_skip("Back", "push button", "", live=False) is None
    assert should_skip("All", "toggle button", "", live=False) is None


def test_live_flag_allows_start():
    assert should_skip("Start", "push button", "", live=True) is None
