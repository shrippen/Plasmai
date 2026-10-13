import QtQml
import "../../code/workTotals.js" as WorkTotals

/**
 * Today and this week: tracked time, targets, absence credit (holiday /
 * WorkContract plugin) and what is left, live while the timer runs.
 */
QtObject {
    id: totals

    property QtObject session: null

    property real todaySeconds: 0
    property real weekSeconds: 0
    property real todayTargetSeconds: 0
    property real weekTargetSeconds: 0
    /** Week target less public holidays and absences. */
    property real weekEffectiveTargetSeconds: 0
    property bool hasWorkContract: false
    property var prefs: ({})
    property var absences: []
    property var publicHolidays: []
    property var todayEntries: []
    property var weekEntries: []
    property real todayCreditSeconds: 0
    property real weekCreditSeconds: 0

    // Totals include the running entry up to their load; add the timer's progress since.
    property real elapsedAnchor: 0
    readonly property real progressSeconds: session.timer.tracking ? Math.max(0, session.timer.elapsedSeconds - elapsedAnchor) : 0
    readonly property real todayLiveSeconds: todaySeconds + progressSeconds
    readonly property real weekLiveSeconds: weekSeconds + progressSeconds
    readonly property real remainingTodaySeconds: hasWorkContract ? (todayTargetSeconds - todayLiveSeconds + todayCreditSeconds) : 0
    readonly property real remainingWeekSeconds: hasWorkContract ? (weekEffectiveTargetSeconds - weekLiveSeconds + weekCreditSeconds) : 0

    /** Plain cache handed to workTotals.js (user, absences); not reactive. */
    property var memo: ({})

    function refresh() {
        const c = session.connection
        if (!c.token) {
            return
        }
        WorkTotals.load({ tracker: c.tracker, url: c.url, token: c.token, memo: memo,
                          holidayBundle: c.capabilities.holidayBundle }, new Date(), function(t) {
            prefs = t.prefs
            hasWorkContract = t.hasWorkContract
            todayTargetSeconds = t.todayTargetSeconds
            weekTargetSeconds = t.weekTargetSeconds
            weekEffectiveTargetSeconds = t.weekEffectiveTargetSeconds
            absences = t.absences
            publicHolidays = t.publicHolidays
            if (!t.entriesLoaded) {
                return
            }
            weekCreditSeconds = t.weekAbsenceCreditSeconds
            todayCreditSeconds = t.todayAbsenceCreditSeconds
            weekEntries = session.catalog.hydrate(t.weekEntries)
            todayEntries = session.catalog.hydrate(t.todayEntries)
            todaySeconds = t.todaySeconds
            weekSeconds = t.weekSeconds
            elapsedAnchor = session.timer.elapsedSeconds
        })
    }

    /** Names from a catalog that came after the entries. */
    function rehydrate() {
        weekEntries = session.catalog.hydrate(weekEntries)
        todayEntries = session.catalog.hydrate(todayEntries)
    }
}
