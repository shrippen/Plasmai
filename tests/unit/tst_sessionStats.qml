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
            property var connection: QtObject { property bool configured: true; property int generation: 0
                function current(cb) { const g = generation; return function(r) { if (g === generation) { cb(r) } } }
            }
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
            signal entriesWritten()
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

    // The totals' week fills an empty range.
    function test_week_seeds_an_empty_range() {
        const f = createTemporaryObject(fixture, this)
        f.totals.weekEntries = [{ id: 1, begin: new Date().toISOString() }]
        compare(f.stats.timesheets.length, 1)
        verify(f.stats.rangeBeginMs > 0)
    }

    // A loaded range of several weeks keeps its older entries; only this week's are replaced.
    function test_week_seed_never_shrinks_the_range() {
        const f = createTemporaryObject(fixture, this)
        const now = new Date()
        f.stats.load(StatsData.addDays(now, -30), now)
        const old = new Date(now.getTime() - 20 * 86400000).toISOString()
        answers[0]({ ok: true, data: [{ id: 1, begin: old }, { id: 2, begin: now.toISOString() }] })
        const before = f.stats.rangeBeginMs
        f.totals.weekEntries = [{ id: 3, begin: now.toISOString() }]
        compare(f.stats.rangeBeginMs, before)
        compare(f.stats.timesheets.map(function(e) { return e.id }).sort(), [1, 3])
    }

    // The loading of an overlapping ask: the preload runs, the view pages six weeks back and
    // the answers come in reverse order. The week asked for must be loaded in the end.
    function test_overlapping_loads_keep_the_union() {
        const s = stats()
        s.open()
        const preload = answers[1]
        const now = new Date()
        const far = StatsData.addDays(now, -42)
        s.load(far, StatsData.addDays(far, 6))
        compare(weekFetches().length, 2)
        answers[2]({ ok: true, data: [{ id: 2 }] })
        verify(!s.loading)
        preload({ ok: true, data: [{ id: 1 }] })
        compare(s.timesheets.length, 1)
        compare(s.timesheets[0].id, 2)
        verify(s.rangeBeginMs <= StatsData.startOfDay(far).getTime())
        compare(weekFetches().length, 2)
    }

    function test_loading_stays_until_the_latest_answer() {
        const s = stats()
        s.open()
        const far = StatsData.addDays(new Date(), -42)
        s.load(far, far)
        answers[1]({ ok: true, data: [] })
        verify(s.loading)
        answers[2]({ ok: true, data: [] })
        verify(!s.loading)
    }

    // Another profile: the loaded entries go and an answer of the old one is dropped.
    function test_profile_switch_forgets_and_drops_old_answers() {
        const f = createTemporaryObject(fixture, this)
        f.stats.load(new Date(), new Date())
        f.connection.generation++
        answers[0]({ ok: true, data: [{ id: 1 }] })
        compare(f.stats.timesheets.length, 0)
        compare(f.stats.rangeBeginMs, 0)
        verify(!f.stats.loading)
        f.stats.timesheets = [{ id: 5 }]
        f.stats.rangeBeginMs = 5
        f.connection.generation++
        compare(f.stats.timesheets.length, 0)
        compare(f.stats.rangeBeginMs, 0)
    }

    // A write (see tst_sessionStale for the real ones) makes the range stale: the next open
    // starts over with the preload only; without one it fetches nothing new.
    function test_write_makes_the_range_stale() {
        const f = createTemporaryObject(fixture, this)
        const far = StatsData.addDays(new Date(), -60)
        f.stats.open()
        answers[1]({ ok: true, data: [{ id: 1 }] })
        f.stats.load(far, far)
        answers[2]({ ok: true, data: [{ id: 1 }, { id: 2 }] })
        const n = weekFetches().length
        f.stats.open()
        compare(weekFetches().length, n)
        f.entriesWritten()
        verify(f.stats.stale)
        f.stats.open()
        compare(weekFetches().length, n + 1)
        const span = StatsData.prefetchSpan(new Date())
        compare(weekFetches()[n].begin.getTime(), span.begin.getTime())
        verify(!f.stats.stale)
        compare(f.stats.timesheets.length, 0)
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
