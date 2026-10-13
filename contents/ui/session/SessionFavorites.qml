import QtQml
import "../../code/favorites.js" as Favorites

/** Pinned project/activity pairs (shared setting pinnedActivities), resolved against the catalog. */
QtObject {
    id: favorites

    property QtObject session: null

    /** Rows: { projectId, activityId, projectName, activityName, customerColor, activityKnown }. */
    property var pinned: []

    function resolve() {
        const cat = session.catalog
        const entries = Favorites.resolvePinnedEntries(session.settings.pinnedActivities, cat.projects,
                                                       cat.activitiesByProject, cat.customersById, cat.activities)
        if (JSON.stringify(entries) !== JSON.stringify(pinned)) {
            pinned = entries
        }
        // Activities not in the whole catalog: load their project's list for the names.
        for (let i = 0; i < entries.length; i++) {
            const pid = String(entries[i].projectId)
            if (!entries[i].activityKnown && !cat.activitiesByProject[pid] && cat.projects.length > 0) {
                cat.loadActivities(pid, function() {})
            }
        }
    }

    function toggle(projectId, activityId) {
        session.settings.set({ pinnedActivities: Favorites.togglePinned(session.settings.pinnedActivities, projectId, activityId) })
        resolve()
    }

    function isPinned(projectId, activityId) {
        return Favorites.isPinned(session.settings.pinnedActivities, projectId, activityId)
    }
}
