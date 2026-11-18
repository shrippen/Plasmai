import QtQuick
import QtTest
import "../../contents/code/notices.js" as Notices

TestCase {
    name: "Notices"

    readonly property var on: ({ notifyOnStart: true, notifyOnStop: true, notifyOnIdleStop: true })
    readonly property var off: ({ notifyOnStart: false, notifyOnStop: false, notifyOnIdleStop: false })

    function test_start_kinds() {
        compare(Notices.forStart(Notices.Begin.Start, on), Notices.Kind.Started)
        compare(Notices.forStart(Notices.Begin.Switch, on), Notices.Kind.Switched)
        compare(Notices.forStart(Notices.Begin.Start, off), null)
        compare(Notices.forStart(Notices.Begin.Switch, off), null)
    }

    function test_stop_kinds() {
        compare(Notices.forStop(Notices.Cause.Manual, on), Notices.Kind.Stopped)
        compare(Notices.forStop(Notices.Cause.Idle, on), Notices.Kind.IdleStopped)
        compare(Notices.forStop(Notices.Cause.Manual, off), null)
        compare(Notices.forStop(Notices.Cause.Idle, off), null)
        compare(Notices.forStop(Notices.Cause.Manual, { notifyOnStop: false, notifyOnIdleStop: true }), null)
        compare(Notices.forStop(Notices.Cause.Idle, { notifyOnStop: true, notifyOnIdleStop: false }), null)
    }

    // A start found by a refresh is news; one of this client was told at its start.
    function test_found_timer() {
        compare(Notices.forFound(Notices.Found.Elsewhere, on), Notices.Kind.InProgress)
        compare(Notices.forFound(Notices.Found.Own, on), null)
        compare(Notices.forFound(Notices.Found.Elsewhere, off), null)
    }

    function test_idle_discarded() {
        compare(Notices.forIdleDiscard(on), Notices.Kind.IdleDiscarded)
        compare(Notices.forIdleDiscard(off), null)
    }
}
