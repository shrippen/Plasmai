import QtQuick
import QtTest
import "../../contents/ui/session" as Parts
import "../../contents/code/statsData.js" as StatsData

/** SessionStats against a recording session: the range grows in whole weeks, one flow for widget and app. */
TestCase {
    name: "SessionStats"

    property var fetches: []
    property var answers: []
    property int refreshes: 0

    Component {
        id: fixture
        QtObject {
            id: fake
            property var connection: QtObject { property bool configured: true }
            property var entries: QtObject {
                function fetchRange(begin, end, cb) { fetches.push({ begin: begin, end: end }); answers.push(cb) }
            }
            property var catalog: QtObject {
                signal updated()
                function hydrate(list) { return list.map(function(e) { return Object.assign({ hydrated: true }, e) }) }
            }
            property var totals: QtObject {
                property var weekEntries: []
                function refresh() { refreshes++ }
            }
            property var trips: QtObject {
                signal changed(int change, var data)
                property bool available: true
                property var ping: ({})
                function fetch(range, cb) { fetches.push({ trips: range }); answers.push(cb) }
            }
            property var stats: Parts.SessionStats { session: fake }
        }
    }

    function init() {
        fetches = []
        answers = []
        refreshes = 0
    }

    function stats() {
        return createTemporaryObject(fixture, this).stats
    }

    function weekFetches() {
        return fetches.filter(function(f) { return !f.trips })
    }

    // Opening refreshes the totals, asks for trips and prefetches the weeks.
    function test_open_prefetches() {
        const s = stats()
        s.open()
        compare(refreshes, 1)
        compare(fetches.length, 2)
        verify(s.shown)
        const span = StatsData.prefetchSpan(new Date())
        compare(weekFetches()[0].begin.getTime(), span.begin.getTime())
        compare(weekFetches()[0].end.getTime(), span.end.getTime())
        verify(s.loading)
    }

    function test_load_answer_sets_range_and_covers() {
        const s = stats()
        const now = new Date()
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        answers[0]({ ok: true, data: [{ id: 1 }] })
        verify(!s.loading)
        compare(s.timesheets.length, 1)
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        compare(weekFetches().length, 1)
    }

    // The behaviour of the widget: a second ask grows the loaded range.
    function test_load_grows_range() {
        const s = stats()
        const now = new Date()
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        answers[0]({ ok: true, data: [{ id: 1 }] })
        const before = s.rangeBeginMs
        const earlier = StatsData.addDays(now, -20)
        s.load(StatsData.startOfDay(earlier), StatsData.endOfDay(earlier))
        compare(weekFetches().length, 2)
        compare(weekFetches()[1].end.getTime(), s.rangeEndMs)
        verify(weekFetches()[1].begin.getTime() < before)
    }

    // An offline answer shows but is not remembered as loaded.
    function test_offline_answer_is_not_loaded() {
        const s = stats()
        const now = new Date()
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        answers[0]({ ok: true, offline: true, data: [{ id: 1 }] })
        compare(s.timesheets.length, 1)
        compare(s.rangeBeginMs, 0)
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        compare(weekFetches().length, 2)
    }

    function test_failed_answer_keeps_state() {
        const s = stats()
        const now = new Date()
        s.load(StatsData.startOfDay(now), StatsData.endOfDay(now))
        answers[0]({ ok: false })
        verify(!s.loading)
        compare(s.timesheets.length, 0)
    }

    function test_trips_answer_and_change() {
        const f = createTemporaryObject(fixture, this)
        f.stats.loadTrips()
        answers[0]({ ok: true, data: [{ id: 9 }] })
        compare(f.stats.trips.length, 1)
        f.trips.changed(0, null)
        compare(f.stats.trips, null)
    }

    function test_no_plugin_clears_trips() {
        const f = createTemporaryObject(fixture, this)
        f.stats.trips = [1]
        f.trips.available = false
        f.stats.loadTrips()
        compare(f.stats.trips, null)
        compare(fetches.length, 0)
    }

    // The totals' week fills the range while the view is closed, never while it shows entries.
    function test_week_seed_only_when_not_shown() {
        const f = createTemporaryObject(fixture, this)
        f.totals.weekEntries = [{ id: 1 }]
        compare(f.stats.timesheets.length, 1)
        verify(f.stats.rangeBeginMs > 0)
        f.stats.open()
        f.totals.weekEntries = [{ id: 2 }, { id: 3 }]
        compare(f.stats.timesheets.length, 1)
        f.stats.close()
        f.totals.weekEntries = [{ id: 2 }, { id: 3 }]
        compare(f.stats.timesheets.length, 2)
    }

    function test_catalog_update_rehydrates() {
        const f = createTemporaryObject(fixture, this)
        f.totals.weekEntries = [{ id: 1 }]
        f.catalog.updated()
        verify(f.stats.timesheets[0].hydrated)
    }

    function test_forget() {
        const s = stats()
        s.timesheets = [{ id: 1 }]
        s.rangeBeginMs = 5
        s.trips = [1]
        s.forget()
        compare(s.timesheets.length, 0)
        compare(s.rangeBeginMs, 0)
        compare(s.trips, null)
    }
}
