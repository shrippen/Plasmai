import QtQml
import "../../code/mileage.js" as Mileage
import "../../code/statsData.js" as StatsData

/**
 * What the statistics view shows: the entries of the loaded range and the trips of
 * this week and month. The range only grows, in whole weeks; an offline answer (the
 * snapshot) does not count as loaded, so the next ask fetches again once online.
 *
 *   open ─▶ trips + prefetch of a few weeks      load(begin, end) ─▶ grows the range
 */
QtObject {
    id: stats

    property QtObject session: null

    /** Set by the view while it is shown: the week's entries from the totals no longer replace the range. */
    property bool shown: false
    property var timesheets: []
    property double rangeBeginMs: 0
    property double rangeEndMs: 0
    property bool loading: false
    /** Trips of this week and month (kimai-anfahrten), null = no plugin or not loaded. */
    property var trips: null

    /** The view opens: fresh totals, trips, and a few weeks so day/week switchers work at once. */
    function open() {
        session.totals.refresh()
        loadTrips()
        const span = StatsData.prefetchSpan(new Date())
        load(span.begin, span.end)
    }

    /** Makes the entries cover [begin, end]; fetches only what is missing. */
    function load(begin, end) {
        if (!session.connection.configured || !begin || !end) {
            return
        }
        const span = StatsData.missingSpan(rangeBeginMs, rangeEndMs, timesheets.length, begin, end)
        if (!span) {
            rehydrate()
            return
        }
        loading = true
        session.entries.fetchRange(span.begin, span.end, function(result) {
            loading = false
            if (!result.ok) {
                return
            }
            timesheets = result.data || []
            rangeBeginMs = result.offline ? 0 : span.begin.getTime()
            rangeEndMs = result.offline ? 0 : span.end.getTime()
        })
    }

    function loadTrips() {
        if (!session.trips.available) {
            trips = null
            return
        }
        const now = new Date()
        const range = Mileage.hasFeature(session.trips.ping, "dateRange") ? StatsData.tripRangeFor(now) : { year: now.getFullYear() }
        session.trips.fetch(range, function(r) {
            trips = r.ok ? r.data : null
        })
    }

    /** Forgets the loaded range and the trips (another profile, a pull to refresh). */
    function forget() {
        timesheets = []
        rangeBeginMs = 0
        rangeEndMs = 0
        trips = null
    }

    /** Outside the view the week's entries stand in for its first range. */
    function seed(weekEntries, now) {
        if (shown && timesheets.length) {
            return
        }
        timesheets = weekEntries
        rangeBeginMs = StatsData.startOfWeek(now).getTime()
        rangeEndMs = StatsData.endOfWeek(now).getTime()
    }

    /** The catalog answered: the loaded entries take its names. */
    function rehydrate() {
        if (timesheets.length) {
            timesheets = session.catalog.hydrate(timesheets)
        }
    }

    Component.onCompleted: {
        session.trips.changed.connect(function() { trips = null })
        session.catalog.updated.connect(rehydrate)
        session.totals.weekEntriesChanged.connect(function() { seed(session.totals.weekEntries, new Date()) })
    }
}
