import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/mileage.js" as Mileage
import ".." as Ui

/**
 * Trips of the kimai-anfahrten plugin (MileageBundle): the probe, the
 * plugin's meta data and vehicles, and every trip call.
 *
 *   resolve ─▶ state, ping ─▶ available / canEdit ─▶ meta + vehicles (once per profile)
 */
QtObject {
    id: trips

    property QtObject session: null

    property string state: KimaiApi.PluginState.UNKNOWN
    property var ping: null
    property var meta: null
    property var vehicles: []
    property string profileKey: ""
    readonly property bool available: session.connection.configured && session.connection.capabilities.mileage
        && session.settings.showTrips
        && state === KimaiApi.PluginState.PRESENT && KimaiApi.mileageCanView(ping)
    readonly property bool canEdit: available && Mileage.can(ping, "editOwn")

    /** Probes the plugin (cached 24 h per profile in pluginProbesJson); probe: Session.Probe. */
    function resolve(probe, callback) {
        const c = session.connection
        const key = KimaiApi.pluginCacheKey(c.profile ? c.profile.id : "", c.url, KimaiApi.MILEAGE_PLUGIN)
        if (key !== profileKey) {
            profileKey = key
            state = KimaiApi.PluginState.UNKNOWN
            ping = null
            meta = null
            vehicles = []
        }
        if (!c.token || !c.capabilities.mileage || !session.settings.showTrips) {
            if (callback) {
                callback()
            }
            return
        }
        const cache = KimaiApi.parsePluginCache(session.settings.pluginProbesJson)
        KimaiApi.detectMileage(c.url, c.token, { cache: cache, key: key, force: probe === Ui.Session.Probe.Fresh }, function(det) {
            state = det.state
            ping = det.data || null
            if (det.cacheEntry) {
                session.settings.mergeMaps({ pluginProbesJson: JSON.stringify(KimaiApi.storePluginCache(cache, key, det.cacheEntry)) })
            }
            if (available && !meta) {
                c.tracker.fetchMileageMeta(c.url, c.token, function(r) {
                    if (r.ok) {
                        meta = r.data
                    }
                })
                c.tracker.fetchVehicles(c.url, c.token, function(r) {
                    if (r.ok) {
                        vehicles = r.data
                    }
                })
            }
            if (callback) {
                callback()
            }
        })
    }

    /** query: { from, to } with the dateRange feature, else { year[, month] }. */
    function fetch(query, callback) {
        const c = session.connection
        c.tracker.fetchTrips(c.url, c.token, query, callback)
    }

    function fetchSuggestions(callback) {
        const c = session.connection
        c.tracker.fetchTripSuggestions(c.url, c.token, null, callback)
    }

    function create(body, callback) {
        const c = session.connection
        c.tracker.createTrip(c.url, c.token, body, callback)
    }

    function patch(tripId, body, callback) {
        const c = session.connection
        c.tracker.patchTrip(c.url, c.token, tripId, body, callback)
    }

    function remove(tripId, callback) {
        const c = session.connection
        c.tracker.deleteTrip(c.url, c.token, tripId, callback)
    }

    function accept(suggestionId, body, callback) {
        const c = session.connection
        c.tracker.acceptTripSuggestion(c.url, c.token, suggestionId, body, callback)
    }

    function dismiss(suggestionId, callback) {
        const c = session.connection
        c.tracker.dismissTripSuggestion(c.url, c.token, suggestionId, callback)
    }
}
