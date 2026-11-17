import QtQuick
import QtTest
import "../../contents/code/notices.js" as Notices

TestCase {
    name: "Notices"

    readonly property var on: ({ notifyOnStart: true, notifyOnStop: true, notifyOnIdleStop: true })
    readonly property var off: ({ notifyOnStart: false, notifyOnStop: false, notifyOnIdleStop: false })

    function test_start_kinds() {
        compare(Notices.forStart(Notices.Origin.Start, on), Notices.Kind.Started)
        compare(Notices.forStart(Notices.Origin.Continue, on), Notices.Kind.Started)
        compare(Notices.forStart(Notices.Origin.Switch, on), Notices.Kind.Switched)
        compare(Notices.forStart(Notices.Origin.Start, off), null)
        compare(Notices.forStart(Notices.Origin.Switch, off), null)
    }

    function test_stop_kinds() {
        compare(Notices.forStop(false, on), Notices.Kind.Stopped)
        compare(Notices.forStop(true, on), Notices.Kind.IdleStopped)
        compare(Notices.forStop(false, off), null)
        compare(Notices.forStop(true, off), null)
        compare(Notices.forStop(false, { notifyOnStop: false, notifyOnIdleStop: true }), null)
        compare(Notices.forStop(true, { notifyOnStop: true, notifyOnIdleStop: false }), null)
    }

    // A start found by a refresh is news; one of this client was told at its start.
    function test_found_timer() {
        compare(Notices.forFound(false, on), Notices.Kind.InProgress)
        compare(Notices.forFound(true, on), null)
        compare(Notices.forFound(false, off), null)
    }

    function test_idle_discarded() {
        compare(Notices.forIdleDiscard(on), Notices.Kind.IdleDiscarded)
        compare(Notices.forIdleDiscard(off), null)
    }
}
