"""Test and demo runs use their own keychain namespace (kwallet.sh PLASMAI_SECRET_SERVICE).

An isolated XDG_CONFIG_HOME does not isolate the Secret Service: a seed the widget
takes for pre-wizard settings (sharedConfig.js needsReset) cleared the user's real
"default" token on every viewer test run."""

import os
import subprocess
from pathlib import Path

from lib.viewer import TEST_SECRET_SERVICE, ViewerSession

ROOT = Path(__file__).resolve().parent.parent
REAL_SERVICE = "com.github.shrippen.plasmai"


def test_kwallet_script_honours_service_override(tmp_path):
    fake = tmp_path / "secret-tool"
    fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARGS_OUT"\n')
    fake.chmod(0o755)
    out = tmp_path / "args"
    env = {
        **os.environ,
        "PATH": f"{tmp_path}:{os.environ['PATH']}",
        "ARGS_OUT": str(out),
        "PLASMAI_SECRET_SERVICE": "x.test",
    }
    subprocess.run(["sh", str(ROOT / "contents/code/kwallet.sh"), "clear", "default"], env=env, check=True)
    assert out.read_text().split() == ["clear", "service", "x.test", "account", "api-token"]


def test_viewer_sessions_use_test_service(monkeypatch):
    seen = {}

    def fake_popen(cmd, **kwargs):
        seen.update(kwargs["env"])
        raise RuntimeError("stop")

    monkeypatch.setattr(subprocess, "Popen", fake_popen)
    session = ViewerSession(ROOT, extra_env={"PLASMAI_SECRET_SERVICE": REAL_SERVICE})
    try:
        session.start()
    except RuntimeError:
        pass
    assert seen["PLASMAI_SECRET_SERVICE"] == TEST_SECRET_SERVICE != REAL_SERVICE


def test_demo_uses_own_service():
    src = (ROOT / "demo" / "common.sh").read_text(encoding="utf-8")
    assert 'export PLASMAI_SECRET_SERVICE="com.github.shrippen.plasmai.demo"' in src
