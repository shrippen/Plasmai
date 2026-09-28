import QtQuick
import QtTest
import "../../contents/code/timerSession.js" as TimerSession

/**
 * timerSession.js: idle prompts, the idle snapshot, discard end and the
 * "nothing is tracking" reminder, shared by the Plasmoid and the app.
 */
TestCase {
    name: "TimerSession"

    readonly property int minute: 60 * 1000

    function test_thresholdMs() {
        compare(TimerSession.thresholdMs(5), 5 * minute)
        compare(TimerSession.thresholdMs("10"), 10 * minute)
        compare(TimerSession.thresholdMs(0), minute)
        compare(TimerSession.thresholdMs("x"), minute)
        compare(TimerSession.thresholdMs(undefined), minute)
    }

    function test_verdict() {
        // No reading (no idle detection): nothing changes.
        compare(TimerSession.verdict(-1, true, 5), { prompt: false, ignoring: true })
        compare(TimerSession.verdict(-1, false, 5), { prompt: false, ignoring: false })
        // Below / at the threshold.
        compare(TimerSession.verdict(5 * minute - 1, false, 5), { prompt: false, ignoring: false })
        compare(TimerSession.verdict(5 * minute, false, 5), { prompt: true, ignoring: false })
        // Kept idle time: ignored while still idle, until active again.
        compare(TimerSession.verdict(20 * minute, true, 5), { prompt: false, ignoring: true })
        compare(TimerSession.verdict(TimerSession.ACTIVE_AGAIN_MS - 1, true, 5), { prompt: false, ignoring: false })
    }

    function test_snapshot() {
        var begin = new Date(2026, 8, 28, 9, 0)
        var ts = { begin: begin.toISOString(), project: 3, activity: { id: 7 } }
        var snap = TimerSession.snapshot(ts, 42, { project: "P", activity: "A", description: "d" })
        compare(snap, { beginMs: begin.getTime(), timesheetId: 42, projectId: 3, activityId: 7,
                        projectName: "P", activityName: "A", description: "d" })
        var none = TimerSession.snapshot(null, 0, { project: "", activity: "", description: "" })
        compare(none.beginMs, 0)
        compare(none.projectId, null)
    }

    function test_discardEnd() {
        var now = new Date(2026, 8, 28, 12, 0).getTime()
        var since = TimerSession.idleSince(now, 30 * minute)
        compare(since, now - 30 * minute)
        compare(TimerSession.idleSince(now, -5), now)
        compare(TimerSession.discardEnd({ beginMs: now - 60 * minute }, since).getTime(), since)
        // Idle longer than the entry: it ends where it began, not before.
        compare(TimerSession.discardEnd({ beginMs: now - 10 * minute }, since).getTime(), now - 10 * minute)
        compare(TimerSession.discardEnd(null, since).getTime(), since)
    }

    function test_canContinue() {
        verify(TimerSession.canContinue({ projectId: 1, activityId: 2 }))
        verify(!TimerSession.canContinue({ projectId: 1, activityId: null }))
        verify(!TimerSession.canContinue(null))
    }

    function test_forgotToStartDay() {
        var nine = new Date(2026, 8, 28, 9, 0)
        var state = { enabled: true, configured: true, tracking: false,
                      workDayBegin: "08:00", workDayEnd: "18:00", lastDay: "" }
        compare(TimerSession.forgotToStartDay(state, nine), "2026-09-28")
        compare(TimerSession.forgotToStartDay(Object.assign({}, state, { lastDay: "2026-09-28" }), nine), "")
        compare(TimerSession.forgotToStartDay(Object.assign({}, state, { lastDay: "2026-09-27" }), nine), "2026-09-28")
        compare(TimerSession.forgotToStartDay(Object.assign({}, state, { tracking: true }), nine), "")
        compare(TimerSession.forgotToStartDay(Object.assign({}, state, { enabled: false }), nine), "")
        compare(TimerSession.forgotToStartDay(Object.assign({}, state, { configured: false }), nine), "")
        compare(TimerSession.forgotToStartDay(state, new Date(2026, 8, 28, 7, 59)), "")
    }

    function test_switchHintKey() {
        compare(TimerSession.switchHintKey({ project: 3, activity: 7, id: 11 }), "3|7|11")
        compare(TimerSession.switchHintKey({ project: 3, activity: 7 }), "3|7|")
    }
}
