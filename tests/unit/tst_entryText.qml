import QtQuick
import QtTest
import "../../contents/code/entryText.js" as EntryText

TestCase {
    name: "EntryText"

    readonly property var catalog: ({
        projects: [{ id: 1, name: "Alpha" }],
        activities: [{ id: 2, name: "Build" }],
        activitiesByProject: ({})
    })
    readonly property double now: new Date(2026, 7, 13, 12, 0, 0).getTime()

    function ago(minutes) {
        return EntryText.age(new Date(now - minutes * 60000).toISOString(), now)
    }

    function test_age_kinds() {
        compare(EntryText.age("", now).kind, EntryText.Age.None)
        compare(EntryText.age("garbage", now).kind, EntryText.Age.None)
        compare(ago(0).kind, EntryText.Age.Now)
        compare(ago(5).kind, EntryText.Age.Minutes)
        compare(ago(5).n, 5)
        compare(ago(59).n, 59)
        compare(ago(60).kind, EntryText.Age.Hours)
        compare(ago(3 * 60).n, 3)
        compare(ago(24 * 60).kind, EntryText.Age.Yesterday)
        compare(ago(3 * 24 * 60).kind, EntryText.Age.Days)
        compare(ago(3 * 24 * 60).n, 3)
        compare(ago(7 * 24 * 60).kind, EntryText.Age.Date)
    }

    function test_summary_joins_names_and_start() {
        const text = EntryText.summary({ project: { id: 1, name: "Alpha" }, activity: { id: 2, name: "Build" },
                                          begin: "2026-08-13T10:00:00+0200" }, catalog)
        verify(text.indexOf("Alpha · Build · ") === 0)
        verify(text.length > "Alpha · Build · ".length)
    }

    function test_summary_without_entry_or_begin() {
        compare(EntryText.summary(null, catalog), "")
        compare(EntryText.summary({ project: { id: 1, name: "Alpha" }, activity: { id: 2, name: "Build" } }, catalog), "Alpha · Build")
    }
}
