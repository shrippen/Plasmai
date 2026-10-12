import QtQml
import "../../code/kimaiApi.js" as KimaiApi

/** The latest stopped entries, one per project and activity. */
QtObject {
    id: recent

    property QtObject session: null

    property var list: []
    readonly property var last: list.length > 0 ? list[0] : null
    /** The first answer of this profile is in (views show loading rows before). */
    property bool loaded: false

    function refresh() {
        const c = session.connection
        c.tracker.fetchRecentTimesheets(c.url, c.token, session.settings.recentCount, function(result) {
            loaded = true
            if (!result.ok) {
                return
            }
            show(session.catalog.hydrate(KimaiApi.deduplicateRecent(result.data || [])))
        })
    }

    /** Names from a catalog that came after the list. */
    function rehydrate() {
        show(session.catalog.hydrate(list))
    }

    // Only replace the model when it changed: a new array resets the list delegates and closes open row menus.
    function show(fresh) {
        if (JSON.stringify(fresh) !== JSON.stringify(list)) {
            list = fresh
        }
    }
}
