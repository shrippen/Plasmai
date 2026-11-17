import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/session" as Parts
import "../../contents/code/timesheetFields.js" as Fields

/**
 * SessionEntries.write and SessionTimer.patchActive against a recording tracker: the
 * session checks begin and end and sends them as stamps with an offset, whichever
 * surface calls (widget or app). A refused input sends nothing and says failed(Save).
 */
TestCase {
    name: "SessionTimes"

    property var calls: []
    property var failures: []

    readonly property string stampPattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{4}$"

    Component {
        id: fixture
        QtObject {
            id: fake
            signal failed(int action, var result)
            signal entriesWritten()
            property bool busy: false
            property bool locked: false
            function refresh() {}
            function noteDropped() {}
            property var tracker: QtObject {
                function createTimesheet(url, token, fields, cb) { calls.push(["create", fields]); cb({ ok: true, data: {} }) }
                function patchTimesheet(url, token, id, fields, cb) { calls.push(["patch", id, fields]); cb({ ok: true, data: {} }) }
            }
            property var connection: QtObject {
                property bool configured: true
                property string url: "https://k"
                property string token: "t"
                property var tracker: fake.tracker
            }
            property var entries: Parts.SessionEntries { session: fake }
            property var timer: Parts.SessionTimer { session: fake; loaded: true; timesheetId: 5 }
        }
    }

    function init() {
        calls = []
        failures = []
    }

    function make() {
        const f = createTemporaryObject(fixture, this)
        f.failed.connect(function(action, result) { failures.push([action, result.invalid]) })
        return f
    }

    function hoursAgo(h) {
        return new Date(Date.now() - h * 3600 * 1000)
    }

    function typed(date) {
        const pad = function(n) { return (n < 10 ? "0" : "") + n }
        return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + " " + pad(date.getHours()) + ":" + pad(date.getMinutes())
    }

    function test_writeSendsStampsWithOffset() {
        const f = make()
        let answer = null
        f.entries.write(null, { begin: typed(hoursAgo(3)), end: typed(hoursAgo(2)), project: 1, activity: 2 }, function(r) { answer = r })
        verify(answer.ok)
        compare(calls.length, 1)
        verify(new RegExp(stampPattern).test(calls[0][1].begin), calls[0][1].begin)
        verify(new RegExp(stampPattern).test(calls[0][1].end), calls[0][1].end)
    }

    function test_writeRefusesEndBeforeBegin() {
        const f = make()
        let answer = null
        f.entries.write(null, { begin: typed(hoursAgo(2)), end: typed(hoursAgo(3)) }, function(r) { answer = r })
        verify(!answer.ok)
        compare(answer.invalid, Fields.TimeProblem.ORDER)
        compare(calls, [])
        compare(failures, [[Ui.Session.Action.Save, Fields.TimeProblem.ORDER]])
    }

    function test_writeRefusesUnreadableTimes() {
        const f = make()
        f.entries.write(7, { begin: "garbage", end: "" }, function() {})
        compare(calls, [])
        compare(failures, [[Ui.Session.Action.Save, Fields.TimeProblem.DATES]])
    }

    function test_patchActiveSendsStampWithOffset() {
        const f = make()
        let done = false
        f.timer.patchActive({ begin: typed(hoursAgo(3)), project: 1 }, function() { done = true })
        verify(done)
        verify(new RegExp(stampPattern).test(calls[0][2].begin), calls[0][2].begin)
        compare(calls[0][2].project, 1)
    }

    function test_patchActiveRefusesFutureBegin() {
        const f = make()
        let done = false
        f.timer.patchActive({ begin: typed(hoursAgo(-3)) }, function() { done = true })
        verify(!done)
        compare(calls, [])
        compare(failures, [[Ui.Session.Action.Save, Fields.TimeProblem.FUTURE]])
    }

    function test_patchActiveRefusesUnreadableBegin() {
        const f = make()
        f.timer.patchActive({ begin: "garbage" })
        compare(calls, [])
        compare(failures, [[Ui.Session.Action.Save, Fields.TimeProblem.BEGIN]])
    }

    function test_patchActiveWithoutBeginPassesThrough() {
        const f = make()
        f.timer.patchActive({ description: "x" })
        compare(calls[0][2], { description: "x" })
        compare(failures, [])
    }
}
