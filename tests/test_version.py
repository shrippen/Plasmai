"""The version stands in metadata.json (KPlugin.Version); the builds read it from there
(app/CMakeLists.txt, translate/extract.sh, scripts/bump-build.sh). The files no build reads
must say the same, or a release ships with a forgotten place (AUDIT.md, finding 2)."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION = json.loads((ROOT / "metadata.json").read_text(encoding="utf-8"))["KPlugin"]["Version"]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def version_code():
    major, minor, patch = (int(part) for part in VERSION.split("."))
    return major * 10000 + minor * 100 + patch


def test_android_manifest():
    """F-Droid's UpdateCheckData reads both attributes from the file, so it cannot be generated."""
    manifest = text("app/android/AndroidManifest.xml")
    assert f'android:versionName="{VERSION}"' in manifest
    assert f'android:versionCode="{version_code()}"' in manifest


def test_store_text():
    assert f"| **Version** | {VERSION} |" in text("STORE.md")


def test_newest_metainfo_release():
    metainfo = text("packaging/linux/io.github.shrippen.Plasmai.metainfo.xml")
    assert re.search(r"<releases>\s*<release version=\"([^\"]+)\"", metainfo).group(1) == VERSION


def test_landing_page_footer():
    assert f'<a href="#changes">v{VERSION}</a>' in text("docs/index.html")


def test_changelogs_for_android_stores():
    for lang in ("en-US", "de-DE"):
        assert (ROOT / f"fastlane/metadata/android/{lang}/changelogs/{version_code()}.txt").exists()


def test_generated_build_info():
    assert f'var VERSION = "{VERSION}"' in text("contents/code/buildInfo.js")
