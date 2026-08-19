import QtQuick
import QtTest
import "../../contents/code/timesheetFields.js" as Fields

TestCase {
    name: "TimesheetFields"

    function test_normalizeTagsFromString() {
        var tags = Fields.normalizeTags("  alpha, Beta; alpha, ")
        compare(tags.length, 2)
        compare(tags[0], "alpha")
        compare(tags[1], "Beta")
    }

    function test_normalizeTagsFromObjects() {
        var tags = Fields.normalizeTags([{ name: "review" }, { name: "review" }, { title: "ops" }])
        compare(tags.length, 2)
        compare(tags[0], "review")
        compare(tags[1], "ops")
    }

    function test_normalizeTagsEmpty() {
        compare(Fields.normalizeTags("").length, 0)
        compare(Fields.normalizeTags(null).length, 0)
        compare(Fields.normalizeTags([]).length, 0)
    }

    function test_formatTagString() {
        compare(Fields.formatTagString(["a", "b"]), "a, b")
        compare(Fields.formatTagString("a, b"), "a, b")
    }

    function test_tagsFromTimesheet() {
        compare(Fields.tagsFromTimesheet({ tags: ["x", "y"] }).join(","), "x,y")
        compare(Fields.tagsFromTimesheet({ tags: [{ name: "z" }] })[0], "z")
        compare(Fields.tagsFromTimesheet({}).length, 0)
    }

    function test_defaultNewEntryIsBillable() {
        verify(Fields.defaultBillable())
        verify(Fields.resolveBillable({}))
        verify(Fields.resolveBillable(null))
    }

    function test_resolveBillablePrefersFieldsThenExisting() {
        compare(Fields.resolveBillable({ billable: false }), false)
        compare(Fields.resolveBillable({}, { billable: false }), false)
        compare(Fields.resolveBillable({ billable: true }, { billable: false }), true)
        compare(Fields.resolveBillable({}, { billable: 0 }), false)
    }

    function test_billableFromTimesheet() {
        verify(Fields.billableFromTimesheet({ billable: true }))
        verify(!Fields.billableFromTimesheet({ billable: false }))
        verify(Fields.billableFromTimesheet({}, true))
        verify(Fields.billableFromTimesheet(null))
    }

    function test_resolveTagsFromFieldsOrExisting() {
        compare(Fields.resolveTags({ tags: "a, b" }).join(","), "a,b")
        compare(Fields.resolveTags({}, { tags: ["kept"] })[0], "kept")
        compare(Fields.resolveTags({ tags: [] }, { tags: ["old"] }).length, 0)
    }

    function test_attachKimaiShape() {
        var row = { id: 1, begin: "2026-01-01T09:00:00" }
        Fields.attachKimaiShape(row, { tags: ["ops"], billable: true })
        compare(row.tags[0], "ops")
        verify(row.billable)
    }

    function test_parseInstantLocalAndIso() {
        var a = Fields.parseInstant("2026-03-10T09:00:00")
        verify(a !== null)
        var b = Fields.parseInstant("2026-03-10 10:30:00")
        verify(b !== null)
        compare(b.getTime() - a.getTime(), 90 * 60 * 1000)
        compare(Fields.parseInstant(""), null)
        compare(Fields.parseInstant(null), null)
        var fromDate = Fields.parseInstant(a)
        compare(fromDate.getTime(), a.getTime())
    }

    function test_midpointInstant() {
        var begin = Fields.parseInstant("2026-03-10T09:00:00")
        var end = Fields.parseInstant("2026-03-10T11:00:00")
        var mid = Fields.midpointInstant({
            begin: "2026-03-10T09:00:00",
            end: "2026-03-10T11:00:00"
        })
        verify(mid !== null)
        compare(mid.getTime(), Math.floor((begin.getTime() + end.getTime()) / 2))
    }

    function test_splitStoppedEntryOk() {
        var ts = {
            begin: "2026-03-10T09:00:00",
            end: "2026-03-10T11:00:00",
            description: "review",
            billable: false,
            tags: ["ops"]
        }
        var at = Fields.parseInstant("2026-03-10T10:00:00")
        var split = Fields.splitStoppedEntry(ts, "2026-03-10T10:00:00")
        verify(split.ok)
        compare(split.firstEnd.getTime(), at.getTime())
        compare(split.secondBegin.getTime(), at.getTime())
        compare(split.secondEnd.getTime(), Fields.parseInstant(ts.end).getTime())
        compare(split.description, "review")
        verify(!split.billable)
        compare(split.tags[0], "ops")
    }

    function test_splitStoppedEntryRejectsEdges() {
        var ts = { begin: "2026-03-10T09:00:00", end: "2026-03-10T11:00:00" }
        verify(!Fields.splitStoppedEntry(ts, "2026-03-10T09:00:00").ok)
        verify(!Fields.splitStoppedEntry(ts, "2026-03-10T11:00:00").ok)
        verify(!Fields.splitStoppedEntry(ts, "2026-03-10T08:00:00").ok)
        verify(!Fields.splitStoppedEntry({ begin: "2026-03-10T09:00:00" }, "2026-03-10T10:00:00").ok)
    }

    function test_previousStoppedTimesheetPicksLatestEnd() {
        var current = { id: 3, begin: "2026-03-10T12:00:00" }
        var recents = [
            current,
            { id: 1, begin: "2026-03-10T08:00:00", end: "2026-03-10T09:00:00" },
            { id: 2, begin: "2026-03-10T09:00:00", end: "2026-03-10T11:00:00" }
        ]
        var prev = Fields.previousStoppedTimesheet(recents, [], current)
        compare(prev.id, 2)
        compare(Fields.previousStoppedTimesheet([], [], current), null)
    }

    function test_previousStoppedTimesheetUsesTodayWhenRecentsDedupe() {
        var current = { id: 9, begin: "2026-03-10T14:00:00" }
        var recents = [current]
        var today = [
            { id: 8, begin: "2026-03-10T09:00:00", end: "2026-03-10T13:30:00" }
        ]
        compare(Fields.previousStoppedTimesheet(recents, today, current).id, 8)
    }

    function test_beginIsBeforePreviousEnd() {
        var prev = { end: "2026-03-10T11:00:00" }
        verify(Fields.beginIsBeforePreviousEnd("2026-03-10T10:59:00", prev))
        verify(!Fields.beginIsBeforePreviousEnd("2026-03-10T11:00:00", prev))
        verify(!Fields.beginIsBeforePreviousEnd("2026-03-10T11:01:00", prev))
        verify(!Fields.beginIsBeforePreviousEnd("2026-03-10T10:00:00", null))
    }
}
