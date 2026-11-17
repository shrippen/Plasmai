import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/session" as Parts
import "../../contents/code/providerUtil.js" as ProviderUtil

/**
 * SessionTimer.continueEntry against a recording tracker: a server that refuses the
 * restart still lets the user carry on (a new entry, same project, activity and
 * description); a failure without an answer (network, offline) must not start anything,
 * the restart may have arrived.
 */
TestCase {
    name: "SessionContinue"

    property var calls: []
    property var restartAnswer: null
    property var failures: []
    property var starts: []

    readonly property var stopped: ({ id: 7, project: { id: 3, name: "P" }, activity: { id: 4, name: "A" }, description: "work" })

    Component {
        id: fixture
        QtObject {
            id: fake
            signal failed(int action, var result)
            signal started(var timesheet, int origin, var names)
            signal trackingBegan(var timesheet)
            signal entriesWritten()
            property bool busy: false
            property bool locked: false
            function refresh() {}
            property var tracker: QtObject {
                function restartTimesheet(url, token, id, cb) { calls.push(["restart", id]); cb(restartAnswer) }
                function startTracking(url, token, project, activity, description, cb) {
                    calls.push(["start", project, activity, description])
                    cb({ ok: true, data: { id: 8, project: { id: project }, activity: { id: activity }, description: description } })
                }
            }
            property var connection: QtObject {
                property bool configured: true
                property string url: "https://k"
                property string token: "t"
                property var tracker: fake.tracker
            }
            property var catalog: QtObject {
                function hydrate(list) { return list }
                function catalogs() { return ({}) }
            }
            property var settings: QtObject { property string lastUsedProjectId: ""; property string lastUsedActivityId: ""; function set() { } function mergeMaps() { } }
            property var timer: Parts.SessionTimer { session: fake; loaded: true }
        }
    }

    function init() {
        calls = []
        failures = []
        starts = []
    }

    function run(answer) {
        restartAnswer = answer
        const f = createTemporaryObject(fixture, this)
        f.failed.connect(function(action, result) { failures.push(action) })
        f.started.connect(function(ts, origin) { starts.push(origin) })
        f.timer.continueEntry(stopped)
        return f
    }

    function test_refused_restart_starts_a_new_entry() {
        run({ ok: false, error: { type: ProviderUtil.ErrorType.Forbidden, status: 403 } })
        compare(calls, [["restart", 7], ["start", 3, 4, "work"]])
        compare(starts, [Ui.Session.Origin.Start])
        compare(failures, [])
    }

    function test_network_failure_starts_nothing() {
        run({ ok: false, error: { type: ProviderUtil.ErrorType.Network, status: 0 } })
        compare(calls, [["restart", 7]])
        compare(failures, [Ui.Session.Action.Continue])
    }

    // A 502 or 504 of a proxy often comes after the server restarted the entry: no second one.
    function test_server_error_starts_nothing() {
        run({ ok: false, error: { type: ProviderUtil.ErrorType.Server, status: 502 } })
        compare(calls, [["restart", 7]])
        compare(failures, [Ui.Session.Action.Continue])
    }

    function test_unknown_error_starts_nothing() {
        run({ ok: false, error: { type: ProviderUtil.ErrorType.Unknown } })
        compare(calls, [["restart", 7]])
        compare(failures, [Ui.Session.Action.Continue])
    }

    function test_offline_starts_nothing() {
        run({ ok: false, error: { type: ProviderUtil.ErrorType.Offline } })
        compare(calls, [["restart", 7]])
        compare(failures, [Ui.Session.Action.Continue])
    }

    function test_unknown_project_starts_nothing() {
        restartAnswer = { ok: false, error: { type: ProviderUtil.ErrorType.Forbidden, status: 403 } }
        const f = createTemporaryObject(fixture, this)
        f.failed.connect(function(action) { failures.push(action) })
        f.timer.continueEntry({ id: 7, description: "x" })
        compare(calls, [["restart", 7]])
        compare(failures, [Ui.Session.Action.Continue])
    }
}
