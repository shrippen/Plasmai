"""Display-option and timesheet-meta label tables."""

from lib.config_ui import BILLABLE, DISPLAY_OPTIONS, TAGS


def test_display_options_have_en_and_de():
    assert "elapsed" in DISPLAY_OPTIONS
    for key, labels in DISPLAY_OPTIONS.items():
        assert len(labels) >= 2, key
        lowered = [label.lower() for label in labels]
        assert len(set(lowered)) == len(lowered), key


def test_timesheet_meta_labels_cover_de():
    assert "Billable" in BILLABLE
    assert "Abrechenbar" in BILLABLE
    assert any("tag" in label.lower() for label in TAGS)
