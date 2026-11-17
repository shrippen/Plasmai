import QtQuick
import QtTest
import "../../app/qml/tui/tuiView.js" as View
import "../../contents/code/dayModel.js" as DayModel

/** tuiView.js: the terminal client's screens as text. */
TestCase {
    name: "TuiView"

    readonly property var size: ({ columns: 60, rows: 20 })
    readonly property var t: ({
        idle: "Nothing is running", today: "Today", week: "Week", recent: "Recent",
        noRecent: "No recent entries", noEntries: "No entries", noGaps: "No gaps",
        gaps: "Gaps:", total: "Total", mainKeys: "keys", subKeys: "sub"
    })

    function plain(text) {
        return text.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "")
    }

    function test_fitAndTimes() {
        compare(View.fit("abc", 5), "abc  ")
        compare(View.fit("abcdef", 4), "abc…")
        compare(View.clock(5425), "1:30:25")
        compare(View.hm(5425), "1:30")
        compare(View.hourLabel(13.25), "13:15")
    }

    function test_wrap() {
        compare(View.wrap("", 10, 3).length, 0)
        compare(View.wrap("aaa bbb ccc", 7, 3).join("|"), "aaa bbb|ccc")
        compare(View.wrap("aaa bbb ccc ddd", 3, 2).join("|"), "aaa|bb…")
    }

    function test_mainWrapsMessage() {
        const text = View.main({
            profileName: "Demo", statusText: "Online", tracking: false, selected: 0,
            message: "Could not start tracking: " + "word ".repeat(30), recent: []
        }, size, t)
        const lines = plain(text).split("\n")

        compare(lines.length, size.rows)
        verify(lines.every(function(l) { return l.length <= size.columns }))
        verify(lines[lines.length - 4].indexOf("Could not start tracking") === 0)
    }

    // A full list and a long message: exactly `rows` lines, the footer last.
    function test_mainFullListWithMessage() {
        const recent = []
        for (let i = 0; i < 30; i++) {
            recent.push({ title: "Entry " + i, sub: "Project" })
        }
        const small = { columns: 40, rows: 24 }
        const text = View.main({
            profileName: "Demo", statusText: "Online", tracking: false, selected: 0,
            message: "Could not start tracking: " + "word ".repeat(30), recent: recent
        }, small, t)
        const lines = plain(text).split("\n")

        compare(lines.length, small.rows)
        verify(lines.every(function(l) { return l.length <= small.columns }))
        verify(lines[lines.length - 1].indexOf(t.mainKeys.slice(0, 5)) === 0)
    }

    // Tiny terminals: a long message shrinks to the room left, the footer stays last.
    function test_mainTinyWithMessage_data() {
        return [{ rows: 9 }, { rows: 10 }, { rows: 11 }]
    }

    function test_mainTinyWithMessage(data) {
        const tiny = { columns: 40, rows: data.rows }
        const text = View.main({
            profileName: "Demo", statusText: "Online", tracking: false, selected: 0,
            message: "Could not start tracking: " + "word ".repeat(30), recent: []
        }, tiny, t)
        const lines = plain(text).split("\n")

        compare(lines.length, tiny.rows)
        verify(lines[lines.length - 1].indexOf(t.mainKeys.slice(0, 5)) === 0)
    }

    // Every line fits the terminal; the screen has exactly `rows` lines.
    function test_mainScreen() {
        const text = View.main({
            profileName: "Demo", statusText: "Online", tracking: true,
            activity: "Dreh", project: "Harbour Lights", elapsed: 3725,
            todaySeconds: 3600, weekSeconds: 7200, selected: 1, message: "",
            recent: [{ title: "Dreh", sub: "Harbour Lights" }, { title: "Fahrt", sub: "Harbour Lights" }]
        }, size, t)
        const lines = plain(text).split("\n")

        compare(lines.length, size.rows)
        verify(lines[2].indexOf("1:02:05") >= 0)
        verify(lines[3].indexOf("Today 1:00") >= 0)
        verify(lines.some(function(l) { return l.indexOf("2  Fahrt") === 0 }))
        verify(lines.every(function(l) { return l.length <= size.columns }))
        verify(text.indexOf(View.Style.INVERSE + "2  Fahrt") >= 0)
    }

    // A shoot from 8:15 to 12:30 and a gap until 13:15 in a 8–14 work day.
    function test_dayScreen() {
        const today = new Date(2026, 9, 14, 14, 0)
        const blocks = DayModel.blocks([
            { begin: new Date(2026, 9, 14, 8, 0).toISOString(), end: new Date(2026, 9, 14, 12, 30).toISOString() },
            { begin: new Date(2026, 9, 14, 13, 15).toISOString(), end: null }
        ], today, today.getTime()).map(function(b) { return Object.assign(b, { label: "X" }) })
        const lines = plain(View.day({ title: "Mi", blocks: blocks, workFrom: 8, workTo: 17, untilHour: 14 }, size, t)).split("\n")

        compare(lines.length, size.rows)
        verify(lines.some(function(l) { return l.indexOf("12 ██░░") === 0 }))
        verify(lines.some(function(l) { return l.indexOf("Gaps: 12:30–13:15 (45 min)") === 0 }))
    }

    function test_weekScreen() {
        const grid = {
            rows: [{ activity: "Dreh", project: "HL", days: [3600, 0, 0, 0, 0, 0, 0], total: 3600, running: true }],
            dayTotals: [3600, 0, 0, 0, 0, 0, 0], total: 3600
        }
        const lines = plain(View.week({ title: "KW 42", grid: grid, dayNames: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"],
                                        todayIndex: 0 }, size, t)).split("\n")
        verify(lines.some(function(l) { return l.indexOf("● Dreh · HL") === 0 && l.indexOf("1:00") > 0 }))
        verify(lines.some(function(l) { return l.indexOf("Total") === 0 }))
        compare(lines.length, size.rows)
    }

    readonly property var words: Object.assign({ unsyncedTitle: "Not synced", unsyncedKeys: "keys", allSynced: "Everything is synced." }, t)
    readonly property var failedOp: ({ kind: "op", id: "local:1", title: "Entry deleted", sub: "Not accepted: x" })
    readonly property var sendable: ({ kind: "group", id: 0, title: "2 changes wait for Ann on https://old.test", sub: "", canAdopt: true })
    readonly property var foreign: ({ kind: "group", id: 1, title: "1 change waits for Bob on https://new.test",
                                      sub: "Sign in as Bob to send them.", canAdopt: false })

    // The list of changes that wait: the ones that hang here, then the parked groups.
    function test_unsyncedScreen() {
        const text = View.unsynced({ profileName: "Demo", statusText: "Online", items: [failedOp, sendable, foreign],
                                     selected: 1, question: "", message: "" }, size, words)
        const lines = plain(text).split("\n")

        compare(lines.length, size.rows)
        verify(lines.some(function(l) { return l.indexOf("Not synced") === 0 }))
        verify(lines.some(function(l) { return l.indexOf("Entry deleted") >= 0 && l.indexOf("Not accepted: x") >= 0 }))
        verify(lines.some(function(l) { return l.indexOf("Sign in as Bob") >= 0 }))
        verify(lines.every(function(l) { return l.length <= size.columns }))
        verify(text.indexOf(View.Style.INVERSE) >= 0)
    }

    function test_unsyncedQuestionReplacesTheMessage() {
        const lines = plain(View.unsynced({ items: [failedOp], selected: 0, question: "Discard this change?", message: "old" },
                                          size, words)).split("\n")
        verify(lines.some(function(l) { return l.indexOf("Discard this change?") === 0 }))
        verify(!lines.some(function(l) { return l.indexOf("old") >= 0 }))
    }

    function test_unsyncedEmpty() {
        const lines = plain(View.unsynced({ items: [], selected: 0, question: "", message: "" }, size, words)).split("\n")
        verify(lines.some(function(l) { return l.indexOf("Everything is synced.") === 0 }))
    }

    // d discards, r retries what hangs, a sends a group that may be sent; nothing else does anything.
    function test_unsyncedKeys() {
        compare(View.unsyncedAction("d", failedOp), View.Action.DISCARD)
        compare(View.unsyncedAction("d", sendable), View.Action.DISCARD)
        compare(View.unsyncedAction("r", failedOp), View.Action.RETRY)
        compare(View.unsyncedAction("r", sendable), View.Action.NONE)
        compare(View.unsyncedAction("a", sendable), View.Action.ADOPT)
        compare(View.unsyncedAction("a", foreign), View.Action.NONE)
        compare(View.unsyncedAction("a", failedOp), View.Action.NONE)
        compare(View.unsyncedAction("x", failedOp), View.Action.NONE)
        compare(View.unsyncedAction("d", null), View.Action.NONE)
    }
}
