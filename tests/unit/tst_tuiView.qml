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
}
