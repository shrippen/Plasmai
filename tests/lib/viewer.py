"""Launch plasmoidviewer and capture stderr."""

from __future__ import annotations

import os
import signal
import subprocess
import threading
import time
from pathlib import Path


class ViewerSession:
    def __init__(
        self,
        applet_path: Path,
        *,
        formfactor: str = "horizontal",
        location: str = "floating",
        size: str = "560x80",
        extra_args: list[str] | None = None,
        extra_env: dict[str, str] | None = None,
    ):
        self.applet_path = applet_path
        self.formfactor = formfactor
        self.location = location
        self.size = size
        self.extra_args = extra_args or []
        self.extra_env = extra_env or {}
        self.proc: subprocess.Popen | None = None
        self._lines: list[str] = []
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        env = os.environ.copy()
        env.setdefault("QT_LOGGING_RULES", "qt.qml.connections.warning=true")
        env["QT_LINUX_ACCESSIBILITY_ALWAYS_ON"] = "1"
        env["QT_ACCESSIBILITY"] = "1"
        env.setdefault("NO_AT_BRIDGE", "0")
        # Prefer XWayland so xdotool can find the window on a Wayland session.
        env["QT_QPA_PLATFORM"] = env.get("PLASMAI_TEST_QPA", "xcb")
        env.update(self.extra_env)
        cmd = [
            "plasmoidviewer",
            "-a",
            str(self.applet_path),
            "-f",
            self.formfactor,
            "-l",
            self.location,
            "-s",
            self.size,
        ] + self.extra_args
        self.proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            cwd=str(self.applet_path),
        )
        self._thread = threading.Thread(target=self._pump, daemon=True)
        self._thread.start()

    def _pump(self) -> None:
        assert self.proc and self.proc.stdout
        for line in self.proc.stdout:
            with self._lock:
                self._lines.append(line.rstrip("\n"))

    def lines(self) -> list[str]:
        with self._lock:
            return list(self._lines)

    def wait_alive(self, timeout: float = 25.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.proc and self.proc.poll() is not None:
                raise RuntimeError(
                    "plasmoidviewer exited early:\n" + "\n".join(self.lines()[-40:])
                )
            if self.window_ids():
                return
            time.sleep(0.2)
        raise TimeoutError(
            "plasmoidviewer window did not appear\n"
            + "\n".join(self.lines()[-50:])
        )

    def _descendant_pids(self) -> list[int]:
        if not self.proc:
            return []
        pids = [self.proc.pid]
        try:
            out = subprocess.run(
                ["pgrep", "-P", str(self.proc.pid)],
                capture_output=True,
                text=True,
            )
            pids.extend(int(x) for x in (out.stdout or "").split() if x.strip().isdigit())
        except (ValueError, FileNotFoundError):
            pass
        return pids

    def window_ids(self) -> list[str]:
        ids: list[str] = []
        for pid in self._descendant_pids():
            out = subprocess.run(
                ["xdotool", "search", "--pid", str(pid)],
                capture_output=True,
                text=True,
            )
            ids.extend(w.strip() for w in (out.stdout or "").splitlines() if w.strip())
        if ids:
            return ids
        out = subprocess.run(
            ["xdotool", "search", "--onlyvisible", "--class", "plasmoidviewer"],
            capture_output=True,
            text=True,
        )
        return [w.strip() for w in (out.stdout or "").splitlines() if w.strip()]

    def focus(self) -> str | None:
        ids = self.window_ids()
        if not ids:
            return None
        wid = ids[-1]
        subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)
        time.sleep(0.15)
        return wid

    def stop(self) -> None:
        if not self.proc:
            return
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=3)

    def __enter__(self) -> "ViewerSession":
        self.start()
        return self

    def __exit__(self, *exc) -> None:
        self.stop()
