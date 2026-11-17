"""Requests to a Kimai plugin (Drehzettel, trips, holidays) go through the active tracker.

ARCHITECTURE.md: what is particular to one service stays in its provider file, behind timeTracker
and its capability flags. The film-day summary, the extras' resend and the holiday load once went
straight to kimaiApi.js; a test could not swap them and the offline layer could not see them."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN_REQUESTS = (
    "detectDrehzettel", "detectMileage", "detectPlugin", "fetchContractAdjustments", "fetchFilmDay",
    "fetchDrehzettelEngagements", "fetchEngagementStatus", "fetchDaySummary", "putFilmDay",
    "fetchTrips", "fetchTripSuggestions", "fetchMileageMeta", "fetchVehicles", "createTrip",
    "patchTrip", "deleteTrip", "acceptTripSuggestion", "dismissTripSuggestion",
)
DIRECT = re.compile(r"\bKimaiApi\.(" + "|".join(PLUGIN_REQUESTS) + r")\b")
COMMENT = ("*", "/*", "//")
ALLOWED = {
    "contents/code/kimaiApi.js", "contents/code/timeTracker.js",
    # demo and screenshot code drives the Kimai module itself
    "contents/ui/DemoHook.qml", "contents/ui/ScreenshotRunner.qml", "app/qml/DemoHook.qml",
    "app/qml/tui/TuiDemo.qml",
}


def test_plugin_requests_go_through_the_tracker():
    found = []
    for folder in ("contents", "app"):
        for path in (ROOT / folder).rglob("*"):
            rel = path.relative_to(ROOT).as_posix()
            if path.suffix not in (".js", ".qml") or rel in ALLOWED or "/Kante" in rel or "/providers/" in rel:
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if not line.lstrip().startswith(COMMENT) and DIRECT.search(line.split("//")[0]):
                    found.append(f"{rel}:{number}")
    assert not found, "ask the tracker (ctx.tracker / connection.tracker), not KimaiApi: " + ", ".join(found)
