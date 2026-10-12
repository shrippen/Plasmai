import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/catalogCache.js" as CatalogCache
import "../../code/platform.js" as Platform

/**
 * Customers, projects and activities of the active profile, and the
 * picker models built from them.
 *
 *   refresh() ─┬─ loadProjects ──────▶ projects ─┐
 *              ├─ loadCustomers ─────▶ customers ├─▶ [useCache: catalog-cache.json]
 *              └─ loadAllActivities ─▶ activities┘
 *   loadActivities(project) ─▶ activitiesByProject[project] ─▶ picker model
 *   all three answered ─▶ names filled in again (recent, timer, totals) ─▶ updated()
 */
QtObject {
    id: catalog

    property QtObject session: null

    /**
     * Widget: keep a fresh catalog in CatalogCache (and catalog-cache.json for
     * the Favorites settings) instead of fetching it on every refresh.
     */
    property bool useCache: false

    property var projects: []
    property var customers: []
    property var customersById: ({})
    /** The whole activity catalog (loadActivities needs a project). */
    property var activities: []
    property var activitiesByProject: ({})
    /** The first answer of this profile's catalog is in (views show loading rows before). */
    property bool loaded: false

    /** SearchableCombo-shaped project items for every picker. */
    readonly property var projectPickerModel: KimaiApi.projectPickerItems(projects, customers)

    onProjectsChanged: session.favorites.resolve()
    onActivitiesChanged: session.favorites.resolve()
    onActivitiesByProjectChanged: session.favorites.resolve()

    /** A full catalog answer is in; the other parts show its names already. */
    signal updated()

    function refresh() {
        const c = session.connection
        const profileId = c.profile ? c.profile.id : ""
        if (useCache && CatalogCache.isFresh(profileId) && projects.length > 0) {
            loaded = true
            return
        }

        // Three answers; a cache write needs all of them from the server.
        let waiting = 3
        let fromServer = true
        function done(result) {
            fromServer = fromServer && result.ok && !result.offline
            waiting--
            if (waiting > 0) {
                return
            }
            loaded = true
            refill()
            updated()
            if (!useCache || !fromServer) {
                return
            }
            CatalogCache.storeEntities(profileId, customers, projects, activities)
            Platform.saveCatalog(session.dataSource, CatalogCache.exportPayload())
        }

        c.tracker.loadProjects(c.url, c.token, function(result) {
            if (result.ok) {
                projects = result.data || []
            }
            done(result)
        })
        c.tracker.loadCustomers(c.url, c.token, function(result) {
            if (result.ok) {
                customers = result.data || []
                customersById = indexById(customers)
            }
            done(result)
        })
        if (typeof c.tracker.loadAllActivities !== "function") {
            done({ ok: true })
            return
        }
        c.tracker.loadAllActivities(c.url, c.token, function(result) {
            if (result.ok) {
                activities = result.data || []
            }
            done(result)
        })
    }

    /** The next refresh asks the server, not the cache (a reload, a new project). */
    function invalidate() {
        CatalogCache.clear()
    }

    /** Entries loaded before the catalog get their names now, not on the next refresh. */
    function refill() {
        session.recent.rehydrate()
        session.totals.rehydrate()
        if (session.timer.active) {
            session.timer.apply(hydrate([session.timer.active])[0])
        }
    }

    function projectById(projectId) {
        if (!projectId) {
            return null
        }
        for (let i = 0; i < projects.length; i++) {
            if (String(projects[i].id) === String(projectId)) {
                return projects[i]
            }
        }
        return null
    }

    /** Loads (and caches) project-scoped activities, then hands back a picker model. */
    function loadActivities(projectId, callback) {
        if (!projectId) {
            callback(KimaiApi.activityPickerItems(activities, null, null, customersById))
            return
        }
        const cached = activitiesByProject[String(projectId)]
        if (cached) {
            callback(KimaiApi.activityPickerItems(cached, projectId, projectById(projectId), customersById))
            return
        }
        const c = session.connection
        c.tracker.loadActivities(c.url, c.token, projectId, function(result) {
            if (!result.ok) {
                callback(KimaiApi.activityPickerItems(activities, projectId, projectById(projectId), customersById))
                return
            }
            const copy = Object.assign({}, activitiesByProject)
            copy[String(projectId)] = result.data || []
            activitiesByProject = copy
            callback(KimaiApi.activityPickerItems(result.data || [], projectId, projectById(projectId), customersById))
        })
    }

    /** Project, activity and customer objects filled in from the catalog. */
    function hydrate(list) {
        return KimaiApi.hydrateTimesheets(list || [], projects, activities, activitiesByProject)
    }

    /** The catalogs timerSession.js reads. */
    function catalogs() {
        return { projects: projects, activities: activities, activitiesByProject: activitiesByProject, customersById: customersById }
    }

    function indexById(list) {
        const out = {}
        for (let i = 0; i < list.length; i++) {
            out[String(list[i].id)] = list[i]
        }
        return out
    }
}
