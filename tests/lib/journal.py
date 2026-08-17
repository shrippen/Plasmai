"""Snapshot journalctl for plasmashell / plasmoidviewer during a test."""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass


@dataclass
class JournalCursor:
    cursor: str
    started: float


def _run(args: list[str]) -> str:
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    return proc.stdout or ""


def mark() -> JournalCursor:
    out = _run(["journalctl", "--user", "-n", "0", "--show-cursor", "-q"])
    cursor = ""
    for line in out.splitlines():
        if line.startswith("-- cursor:"):
            cursor = line.split(":", 1)[1].strip()
    return JournalCursor(cursor=cursor, started=time.time())


def since(marker: JournalCursor) -> list[str]:
    args = ["journalctl", "--user", "--no-pager", "-o", "short-iso"]
    if marker.cursor:
        args.extend(["--after-cursor", marker.cursor])
    else:
        args.extend(["--since", f"@{int(marker.started)}"])
    text = _run(args)
    keep = []
    for line in text.splitlines():
        low = line.lower()
        if "plasmashell" in low or "plasmoidviewer" in low or "plasmai" in low:
            keep.append(line)
    return keep
