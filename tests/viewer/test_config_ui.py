"""Display-option label tables used by the viewer Apply test."""

from lib.config_ui import DISPLAY_OPTIONS


def test_display_options_have_en_and_de():
    assert "elapsed" in DISPLAY_OPTIONS
    for key, labels in DISPLAY_OPTIONS.items():
        assert len(labels) >= 2, key
        lowered = [label.lower() for label in labels]
        assert len(set(lowered)) == len(lowered), key
