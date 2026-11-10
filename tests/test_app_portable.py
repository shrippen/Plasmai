"""The app builds on Windows too: POSIX headers and calls only behind a platform check.

Kante's benchmark probe (app/benchprobe.h) included <unistd.h> for every platform, and the
Windows build in CI stopped with C1083 "Cannot open include file: 'unistd.h'", and with the
include guarded, with C3861 "'sysconf': identifier not found" (cpuMs). Files only built
for one platform (their name ends in _posix, _android, _linux, ...) may include them freely."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POSIX = re.compile(r"#\s*include\s*<(unistd\.h|sys/[\w/]+\.h|termios\.h|pwd\.h|dlfcn\.h)>"
                   r"|\b(sysconf|clock_gettime|getpid|getuid|isatty|ioctl)\s*\(")
PLATFORM_FILE = re.compile(r"_(posix|unix|linux|android|mac|dbus)\.(h|cpp)$")
GUARD = re.compile(r"Q_OS_(LINUX|ANDROID|UNIX|MACOS|DARWIN)|__unix__|__linux__|__APPLE__")


def unguarded(path):
    found, stack = [], []
    for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        s = line.strip()
        if re.match(r"#\s*if", s):
            stack.append(bool(GUARD.search(s)) and "!" not in s.split("Q_OS", 1)[0][-3:])
        elif re.match(r"#\s*(else|elif)", s) and stack:
            stack[-1] = bool(GUARD.search(s)) if s.lstrip("# ").startswith("elif") else False
        elif re.match(r"#\s*endif", s) and stack:
            stack.pop()
        elif POSIX.search(s) and not any(stack):
            found.append(f"{path.relative_to(ROOT)}:{n}")
    return found


def test_posix_headers_only_behind_a_platform_check():
    found = []
    for path in sorted((ROOT / "app").rglob("*")):
        if path.suffix in (".h", ".cpp") and "build" not in path.parts[len(ROOT.parts) + 1:][:1] \
                and not PLATFORM_FILE.search(path.name) and "build-" not in str(path):
            found += unguarded(path)
    assert not found, "POSIX header or call without #if Q_OS_...: " + ", ".join(found)
