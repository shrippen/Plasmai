"""Every Python test at the top of tests/ runs in the CI and in `tests/run.sh unit`.

The CI's pytest step named its files one by one, and new tests (test_app_id.py,
test_app_portable.py, test_startup_lazy.py, test_app_compiled_qml.py) ran only on the machine
that wrote them: a POSIX call in app/ was then caught by the Windows build, not by its test."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_ci_pytest_step_takes_every_top_level_test():
    workflow = (ROOT / ".github/workflows/checks.yml").read_text(encoding="utf-8")
    step = re.search(r"- name: pytest[^\n]*\n\s*run: ([^\n]+)", workflow).group(1)
    assert "tests/test_*.py" in step, f"checks.yml pytest step lists files by name: {step}"


def test_run_sh_unit_takes_every_top_level_test():
    script = (ROOT / "tests/run.sh").read_text(encoding="utf-8")
    unit = re.search(r'if \[\[ "\$\{1:-\}" == "unit" \]\]; then\n\s*PYTEST=\(([^\n]+)\)', script).group(1)
    assert "tests/test_*.py" in unit, f"tests/run.sh unit lists files by name: {unit}"


def test_ci_has_node_for_the_widget_move_test():
    """test_app_id.py runs install-linux.sh's widget move in node; without it, it skips."""
    workflow = (ROOT / ".github/workflows/checks.yml").read_text(encoding="utf-8")
    assert re.search(r"pacman -Syu[^\n]*\bnodejs\b", workflow)


def test_ci_trusts_the_checkout_for_git():
    """Review of PR #55: in the archlinux container the checkout belongs to another user, git
    refused it ("dubious ownership", exit 128) and test_app_id.py's `git ls-files` failed."""
    workflow = (ROOT / ".github/workflows/checks.yml").read_text(encoding="utf-8")
    unit = workflow.split("- uses: actions/checkout@v7", 2)[1]
    assert 'git config --global --add safe.directory "$GITHUB_WORKSPACE"' in unit.split("- name: pytest")[0]
