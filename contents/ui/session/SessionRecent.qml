import QtQml
import "../../code/kimaiApi.js" as KimaiApi

/** The latest stopped entries, one per project and activity. */
QtObject {
    id: recent

    property QtObject session: null

    property var list: []
    readonly property var last: list.length > 0 ? list[0] : null

    function refresh() {
        const c = session.connection
        c.tracker.fetchRecentTimesheets(c.url, c.token, session.settings.recentCount, function(result) {
            if (!result.ok) {
                return
            }
            // Only replace the model when it changed: a new array resets the list delegates and closes open row menus.
            const fresh = session.catalog.hydrate(KimaiApi.deduplicateRecent(result.data || []))
            if (JSON.stringify(fresh) !== JSON.stringify(list)) {
                list = fresh
            }
        })
    }
}
