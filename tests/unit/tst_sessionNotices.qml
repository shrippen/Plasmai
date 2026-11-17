import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/session" as Parts
import "../../contents/code/notices.js" as Notices

/**
 * When SessionReminders says a notice, against a session that only emits the signals:
 * the settings decide, a start of this client is told once, a stop for idle says so.
 */
TestCase {
    name: "SessionNotices"

    property var told: []

    Component {
        id: fixture
        QtObject {
            id: fake
            signal started(var timesheet, int origin, var names)
            signal stopped(var timesheet, var names, int cause)
            signal trackingBegan(var timesheet)
            property var settings: QtObject {
                property bool notifyOnStart: true
                property bool notifyOnStop: true
                property bool notifyOnIdleStop: true
            }
            property var timer: QtObject {
                property string project: "Found P"
                property string activity: "Found A"
                property int elapsedSeconds: 90
                property bool answers: true
                function stop(cause) {
                    if (answers) {
                        fake.stopped(null, { project: "P", activity: "A" }, cause)
                    }
                }
            }
            property var reminders: Parts.SessionReminders { session: fake }
        }
    }

    function init() {
        told = []
    }

    function make() {
        const f = createTemporaryObject(fixture, this)
        f.reminders.notice.connect(function(kind, names) { told.push([kind, names]) })
        return f
    }

    function test_startAndSwitch() {
        const f = make()
        f.started(null, Ui.Session.Origin.Start, { project: "P", activity: "A" })
        f.started(null, Ui.Session.Origin.Switch, { project: "P", activity: "B" })
        f.started(null, Ui.Session.Origin.Continue, { project: "P", activity: "C" })
        compare(told.map(function(t) { return t[0] }), [Notices.Kind.Started, Notices.Kind.Switched, Notices.Kind.Started])
        compare(told[1][1].activity, "B")
    }

    // The refresh that follows a start of this client is no news.
    function test_startThenBeganOnce() {
        const f = make()
        f.started(null, Ui.Session.Origin.Start, { project: "P", activity: "A" })
        f.trackingBegan(null)
        compare(told.length, 1)
        compare(told[0][0], Notices.Kind.Started)
    }

    function test_foundTimerInProgress() {
        const f = make()
        f.trackingBegan(null)
        compare(told.length, 1)
        compare(told[0][0], Notices.Kind.InProgress)
        compare(told[0][1].elapsedSeconds, 90)
    }

    function test_foundAfterLocalStartIsNews() {
        const f = make()
        f.started(null, Ui.Session.Origin.Start, { project: "P", activity: "A" })
        wait(50)
        f.trackingBegan(null)
        compare(told.length, 2)
        compare(told[1][0], Notices.Kind.InProgress)
    }

    function test_stopPlainThenIdle() {
        const f = make()
        f.stopped(null, { project: "P", activity: "A" }, Ui.Session.StopCause.Manual)
        f.reminders.stopForIdle()
        f.stopped(null, { project: "P", activity: "A" }, Ui.Session.StopCause.Manual)
        compare(told.map(function(t) { return t[0] }),
                [Notices.Kind.Stopped, Notices.Kind.IdleStopped, Notices.Kind.Stopped])
    }

    // A stop for idle that failed must not turn the next stop by hand into an idle one.
    function test_failedIdleStopDoesNotLeak() {
        const f = make()
        f.timer.answers = false
        f.reminders.stopForIdle()
        compare(told.length, 0)
        f.stopped(null, { project: "P", activity: "A" }, Ui.Session.StopCause.Manual)
        compare(told.length, 1)
        compare(told[0][0], Notices.Kind.Stopped)
    }

    function test_settingsSilenceNotices() {
        const f = make()
        f.settings.notifyOnStart = false
        f.settings.notifyOnStop = false
        f.settings.notifyOnIdleStop = false
        f.started(null, Ui.Session.Origin.Start, { project: "P", activity: "A" })
        f.started(null, Ui.Session.Origin.Switch, { project: "P", activity: "A" })
        f.trackingBegan(null)
        f.stopped(null, { project: "P", activity: "A" }, Ui.Session.StopCause.Manual)
        f.reminders.stopForIdle()
        compare(told.length, 0)
    }
}
