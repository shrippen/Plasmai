import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/session" as Parts
import "../../contents/code/kimaiApi.js" as KimaiApi

/**
 * SessionTrips against a recording tracker: suggestions, commute and the
 * answers a Kimai demo does not give (409, errors). Answers are held until
 * the test releases them, to see the busy state in between.
 */
TestCase {
    name: "SessionTrips"

    property var held: []
    property var calls: []

    Component {
        id: fixture
        QtObject {
            id: fake
            property var tracker: QtObject {
                function hold(name, args) { calls.push([name].concat(args.slice(0, -1))); held.push(args[args.length - 1]) }
                function acceptTripSuggestion(url, token, id, body, cb) { hold("accept", [id, body, cb]) }
                function dismissTripSuggestion(url, token, id, cb) { hold("dismiss", [id, cb]) }
                function createTrip(url, token, body, cb) { hold("create", [body, cb]) }
                function deleteTrip(url, token, id, cb) { hold("remove", [id, cb]) }
                function patchTrip(url, token, id, body, cb) { hold("patch", [id, body, cb]) }
                function detectMileage(url, token, options, cb) {
                    calls.push(["detect", url, options.key])
                    cb({ state: KimaiApi.PluginState.PRESENT, data: { permissions: { view: true } }, cacheEntry: null })
                }
                function fetchMileageMeta(url, token, cb) { calls.push(["meta"]) }
                function fetchVehicles(url, token, cb) { calls.push(["vehicles"]) }
            }
            property var connection: QtObject {
                property bool configured: true
                property var capabilities: ({ mileage: true })
                property string url: "https://k"
                property string token: "t"
                property var profile: null
                property var tracker: fake.tracker
            }
            property var settings: QtObject {
                property bool showTrips: true
                property string pluginProbesJson: ""
                function mergeMaps(map) { }
            }
            property var sync: QtObject { property bool offline: false; property int unsynced: 0 }
            property var trips: Parts.SessionTrips {
                session: fake
                state: KimaiApi.PluginState.PRESENT
                ping: ({ permissions: { view: true, editOwn: true }, profile: { commuteKm: 12 } })
            }
        }
    }

    Component { id: signalSpy; SignalSpy { } }

    function init() {
        held = []
        calls = []
    }

    function trips() {
        const f = createTemporaryObject(fixture, this)
        verify(f.trips.canEdit)
        return f
    }

    function spy(target) {
        return createTemporaryObject(signalSpy, this, { target: target, signalName: "changed" })
    }

    // The probe and the plugin's meta data are asked of the active tracker.
    function test_probeThroughTracker() {
        const f = trips()
        let done = false

        f.trips.resolve(Ui.Session.Probe.Cached, function() { done = true })

        verify(done)
        compare(calls[0].slice(0, 2), ["detect", "https://k"])
        compare(calls.slice(1).map(c => c[0]), ["meta", "vehicles"])
    }

    function test_acceptSignalsAndReleasesBusy() {
        const f = trips()
        const changes = spy(f.trips)
        let got = null

        f.trips.acceptSuggestion({ id: 3 }, function(r) { got = r })
        verify(f.trips.busy)
        compare(calls[0].slice(0, 2), ["accept", 3])
        held[0]({ ok: true, data: { id: 9 } })

        verify(!f.trips.busy)
        verify(got.ok)
        compare(changes.count, 1)
        compare(changes.signalArguments[0][0], Ui.Session.TripChange.Accepted)
        compare(changes.signalArguments[0][1].id, 3)
    }

    // Accepted or dismissed elsewhere meanwhile: the list is stale all the same.
    function test_acceptConflictCountsAsAccepted() {
        const f = trips()
        const changes = spy(f.trips)
        let got = null

        f.trips.acceptSuggestion({ id: 3 }, function(r) { got = r })
        held[0]({ ok: false, error: { status: 409 } })

        verify(got.ok)
        compare(changes.count, 1)
        compare(changes.signalArguments[0][0], Ui.Session.TripChange.Accepted)
    }

    function test_acceptFailureIsSilent() {
        const f = trips()
        const changes = spy(f.trips)
        let got = null

        f.trips.acceptSuggestion({ id: 3 }, function(r) { got = r })
        held[0]({ ok: false, error: { status: 500, detail: "x" } })

        verify(!got.ok)
        compare(changes.count, 0)
        verify(!f.trips.busy)
    }

    function test_dismissSignals() {
        const f = trips()
        const changes = spy(f.trips)

        f.trips.dismissSuggestion({ id: 4 }, null)
        held[0]({ ok: true })

        compare(changes.count, 1)
        compare(changes.signalArguments[0][0], Ui.Session.TripChange.Dismissed)
        compare(changes.signalArguments[0][1].id, 4)
    }

    function test_saveRoutesToAcceptWithSuggestion() {
        const f = trips()

        f.trips.save({}, null, { distanceKm: 5 }, { id: 8 }, null)

        compare(calls[0][0], "accept")
        compare(calls[0][1], 8)
    }

    function test_saveRoutesToPatchAndCreate() {
        const f = trips()

        f.trips.save({ distanceKm: 5 }, 2, {}, null, null)
        compare(calls[0].slice(0, 2), ["patch", 2])
        held[0]({ ok: false, error: {} })

        f.trips.save({ distanceKm: 5 }, null, {}, null, null)
        compare(calls[1][0], "create")
    }

    function test_commuteUsesProfileKmOnlyOffline() {
        const f = trips()

        f.trips.logCommute(null)
        verify(calls[0][1].distanceKm === undefined)
        held[0]({ ok: true, data: {} })

        f.sync.offline = true
        f.trips.logCommute(null)
        compare(calls[1][1].distanceKm, 12)
        compare(calls[1][1].purpose, "commute")
    }

    function test_commuteSignalsSaved() {
        const f = trips()
        const changes = spy(f.trips)

        f.trips.logCommute(null)
        held[0]({ ok: true, data: { id: 5 } })

        compare(changes.count, 1)
        compare(changes.signalArguments[0][0], Ui.Session.TripChange.Saved)
        compare(changes.signalArguments[0][1].id, 5)
    }

    function test_nothingWithoutEditRight() {
        const f = trips()
        f.trips.ping = { permissions: { view: true, editOwn: false } }

        f.trips.save({ distanceKm: 1 }, null, {}, null, null)
        f.trips.acceptSuggestion({ id: 1 }, null)
        f.trips.dismissSuggestion({ id: 1 }, null)
        f.trips.logCommute(null)

        compare(calls.length, 0)
    }
}
