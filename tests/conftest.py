from __future__ import annotations

import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return ROOT


@pytest.fixture(scope="session", autouse=True)
def _test_keychain():
    """Viewer runs store tokens under their own service (lib.viewer); drop them afterwards."""
    yield
    from lib.viewer import clear_test_secrets

    clear_test_secrets()
