"""Every error kind stands in ErrorType (providerUtil.js); no loose words.

An error object is { type, status, detail }. A kind spelled as a word in some file
("config" meant two things: no access, and a missing field) is missed by ApiErrors."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UTIL = ROOT / "contents/code/providerUtil.js"
API_ERRORS = ROOT / "contents/ui/ApiErrors.qml"
SOURCE_DIRS = ("contents", "app")
SKIPPED_DIRS = {"Kante", "KantePlasma"}
# Kinds that fall through to the generic "Request failed" text on purpose.
GENERIC = {"Unknown", "Conflict", "CacheMiss"}


def error_kinds():
    block = re.search(r"var ErrorType = \{(.*?)\}", UTIL.read_text(encoding="utf-8"), re.S).group(1)
    return re.findall(r"^\s*(\w+):", block, re.M)


def sources():
    for top in SOURCE_DIRS:
        for path in (ROOT / top).rglob("*"):
            if path.suffix not in (".js", ".qml") or SKIPPED_DIRS & set(path.parts):
                continue
            yield path, path.read_text(encoding="utf-8")


def test_no_kind_as_a_loose_word():
    loose = re.compile(r"""\btype:\s*["']\w+["']\s*,\s*status\b|\b(?:err|error)\.type\s*[!=]==?\s*["']""")
    found = [f"{path.relative_to(ROOT)}: {m.group(0)}" for path, text in sources() for m in loose.finditer(text)]
    assert not found, "error kinds as words, use ErrorType:\n" + "\n".join(found)


def test_api_errors_has_a_text_per_kind():
    text = API_ERRORS.read_text(encoding="utf-8")
    missing = [k for k in error_kinds() if k not in GENERIC and f"ErrorType.{k}" not in text]
    assert not missing, f"ApiErrors.qml has no text for: {missing}"


def test_missing_input_is_not_reported_as_missing_access():
    text = API_ERRORS.read_text(encoding="utf-8")
    branch = re.search(r"ErrorType\.InvalidInput\).*?\n        \}", text, re.S)
    assert branch, "ApiErrors.qml has no branch for ErrorType.InvalidInput"
    assert "API token" not in branch.group(0)
    assert "error.detail" in branch.group(0)
