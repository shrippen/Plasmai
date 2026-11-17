import QtQml
import "../../code/mileage.js" as Mileage
import "../../code/statsData.js" as StatsData

/**
 * What the statistics view shows: the entries of the loaded range and the trips of
 * this week and month. The range only grows, in whole weeks; an offline answer (the
 * snapshot) does not count as loaded, so the next ask fetches again once online.
 *
 *   open ─▶ trips + prefetch of a few weeks      load(begin, end) ─▶ grows the range
 *
 * Only the latest request answers. Another profile forgets everything; a write marks
 * the range stale, and the next open fetches it again.
 */
QtObject {
    id: stats

    property QtObject session: null

    property var timesheets: []
    property double rangeBeginMs: 0
    property double rangeEndMs: 0
    property bool loading: false
    /** Trips of this week and month (kimai-anfahrten), null = no plugin or not loaded. */
    property var trips: null

    /** Counts the requests: only the latest answers (asks overlap, answers come in any order). */
    property int serial: 0
    /** The range the running request fetches; it covers the loaded one and every ask since. */
    property double askedBeginMs: 0
    property double askedEndMs: 0
    /** A write ended since the range was loaded. */
    property bool stale: false

    /** The view opens: fresh totals, trips, a stale range again, and a few weeks so day/week switchers work at once. */
    function open() {
        session.totals.refresh()
        loadTrips()
        if (stale && rangeEndMs) {
            fetchSpan(new Date(rangeBeginMs), new Date(rangeEndMs))
        }
        const span = StatsData.prefetchSpan(new Date())
        load(span.begin, span.end)
    }

    /** Makes the entries cover [begin, end]; fetches only what is missing, grown from what is loaded or on its way. */
    function load(begin, end) {
        if (!session.connection.configured || !begin || !end) {
            return
        }
        const running = askedEndMs > 0
        const span = StatsData.missingSpan(running ? askedBeginMs : rangeBeginMs, running ? askedEndMs : rangeEndMs,
                                           running ? 1 : timesheets.length, begin, end)
        if (!span) {
            rehydrate()
            return
        }
        fetchSpan(span.begin, span.end)
    }

    function fetchSpan(begin, end) {
        const c = session.connection
        const asked = ++serial
        stale = false
        loading = true
        askedBeginMs = begin.getTime()
        askedEndMs = end.getTime()
        session.entries.fetchRange(begin, end, c.current(function(result) {
            if (asked !== serial) {
                return
            }
            loading = false
            askedBeginMs = 0
            askedEndMs = 0
            if (!result.ok) {
                return
            }
            timesheets = result.data || []
            // An offline answer (the snapshot) does not count as loaded: fetch again once online.
            rangeBeginMs = result.offline ? 0 : begin.getTime()
            rangeEndMs = result.offline ? 0 : end.getTime()
        }))
    }

    function loadTrips() {
        if (!session.trips.available) {
            trips = null
            return
        }
        const now = new Date()
        const range = Mileage.hasFeature(session.trips.ping, "dateRange") ? StatsData.tripRangeFor(now) : { year: now.getFullYear() }
        session.trips.fetch(range, session.connection.current(function(r) {
            trips = r.ok ? r.data : null
        }))
    }

    /** Forgets the loaded range, the trips and the requests on their way (another profile, a pull to refresh). */
    function forget() {
        serial++
        loading = false
        askedBeginMs = 0
        askedEndMs = 0
        stale = false
        timesheets = []
        rangeBeginMs = 0
        rangeEndMs = 0
        trips = null
    }

    /**
     * The totals' week stands in for an empty range, and replaces its own week in a loaded one;
     * a range that does not reach this week stays as it is.
     */
    function seed(weekEntries, now) {
        const begin = StatsData.startOfWeek(now).getTime()
        const end = StatsData.endOfWeek(now).getTime()
        if (!timesheets.length) {
            timesheets = weekEntries
            rangeBeginMs = begin
            rangeEndMs = end
            return
        }
        if (rangeBeginMs && rangeBeginMs <= begin && rangeEndMs >= end) {
            timesheets = StatsData.replaceWeek(timesheets, weekEntries, begin, end)
        }
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
        session.connection.generationChanged.connect(forget)
        session.busyChanged.connect(function() {
            if (!session.busy) {
                stale = true
            }
        })
        session.totals.weekEntriesChanged.connect(function() { seed(session.totals.weekEntries, new Date()) })
    }
}
