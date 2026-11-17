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

    // ── timeFields: check and convert begin / end before a save ──

    readonly property double now: new Date(2026, 5, 10, 12, 0, 0).getTime()
    readonly property string stampPattern: "^2026-06-10T09:00:00[+-]\\d{4}$"

    function test_timeFieldsEntryConvertsToStampWithOffset() {
        var r = Fields.timeFields({ begin: "2026-06-10T09:00", end: "2026-06-10 10:00", project: 1 }, Fields.TimeCheck.ENTRY, now)
        compare(r.problem, Fields.TimeProblem.NONE)
        verify(new RegExp(stampPattern).test(r.fields.begin), r.fields.begin)
        verify(/^2026-06-10T10:00:00[+-]\d{4}$/.test(r.fields.end), r.fields.end)
        compare(r.fields.project, 1)
    }

    function test_timeFieldsEntryRefusesBadDates() {
        compare(Fields.timeFields({ begin: "nope", end: "2026-06-10T10:00" }, Fields.TimeCheck.ENTRY, now).problem, Fields.TimeProblem.DATES)
        compare(Fields.timeFields({ begin: "2026-06-10T09:00" }, Fields.TimeCheck.ENTRY, now).problem, Fields.TimeProblem.DATES)
    }

    function test_timeFieldsEntryRefusesEndNotAfterBegin() {
        compare(Fields.timeFields({ begin: "2026-06-10T10:00", end: "2026-06-10T10:00" }, Fields.TimeCheck.ENTRY, now).problem, Fields.TimeProblem.ORDER)
        compare(Fields.timeFields({ begin: "2026-06-10T10:00", end: "2026-06-10T09:00" }, Fields.TimeCheck.ENTRY, now).problem, Fields.TimeProblem.ORDER)
    }

    function test_timeFieldsEntryWithoutTimesPassesThrough() {
        var r = Fields.timeFields({ description: "x" }, Fields.TimeCheck.ENTRY, now)
        compare(r.problem, Fields.TimeProblem.NONE)
        compare(r.fields.description, "x")
        verify(r.fields.begin === undefined)
    }

    function test_timeFieldsRunningChecksBegin() {
        compare(Fields.timeFields({ begin: "x" }, Fields.TimeCheck.RUNNING, now).problem, Fields.TimeProblem.BEGIN)
        compare(Fields.timeFields({ begin: "2026-06-10T12:02" }, Fields.TimeCheck.RUNNING, now).problem, Fields.TimeProblem.FUTURE)
        compare(Fields.timeFields({ begin: "2026-06-10T12:00:30" }, Fields.TimeCheck.RUNNING, now).problem, Fields.TimeProblem.NONE)
        var r = Fields.timeFields({ begin: "2026-06-10T09:00", tags: [] }, Fields.TimeCheck.RUNNING, now)
        verify(new RegExp(stampPattern).test(r.fields.begin), r.fields.begin)
    }

    function test_timeFieldsKeepsAStampWithOffset() {
        var r = Fields.timeFields({ begin: "2026-06-10T09:00:00+0200" }, Fields.TimeCheck.RUNNING, now)
        compare(new Date(r.fields.begin.replace(/([+-]\d{2})(\d{2})$/, "$1:$2")).getTime(), new Date("2026-06-10T09:00:00+02:00").getTime())
    }
}
