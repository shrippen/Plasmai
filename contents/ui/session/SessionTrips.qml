import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/mileage.js" as Mileage
import ".." as Ui

/**
 * Trips of the kimai-anfahrten plugin (MileageBundle): the probe, the
 * plugin's meta data and vehicles, and every trip call and flow.
 *
 *   resolve ─▶ state, ping ─▶ available / canEdit ─▶ meta + vehicles (once per profile)
 */
QtObject {
    id: trips

    property QtObject session: null

    /** The server's trips changed: change is Session.TripChange, data the trip, id or suggestion. */
    signal changed(int change, var data)

    /** A call is under way; one at a time. */
    property bool busy: false
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

    /** range: { from, to } (the dateRange feature) or none: every open suggestion. */
    function fetchSuggestions(callback, range) {
        const c = session.connection
        c.tracker.fetchTripSuggestions(c.url, c.token, range || null, callback)
    }

    /**
     * Saves a trip: accepts the suggestion, patches tripId or creates one.
     * An empty patch changes nothing and answers ok without a call.
     * callback(r) is optional, a page may be gone by then; changed() tells every view.
     */
    function save(body, tripId, form, suggestion, callback) {
        if (!canEdit || busy) {
            return
        }
        const c = session.connection
        const tracker = c.tracker
        if (suggestion) {
            busy = true
            tracker.acceptTripSuggestion(c.url, c.token, suggestion.id,
                Mileage.acceptBodyFromForm(ping, form, suggestion), answered(Ui.Session.TripChange.Saved, null, callback))
            return
        }
        const isNew = tripId === null || tripId === undefined
        if (!isNew && Mileage.isEmptyBody(body)) {
            if (callback) {
                callback({ ok: true, data: null })
            }
            return
        }
        busy = true
        const answer = answered(Ui.Session.TripChange.Saved, null, callback)
        if (isNew) {
            tracker.createTrip(c.url, c.token, body, answer)
            return
        }
        tracker.patchTrip(c.url, c.token, tripId, body, answer)
    }

    function remove(tripId, callback) {
        if (!available || busy) {
            return
        }
        const c = session.connection
        busy = true
        c.tracker.deleteTrip(c.url, c.token, tripId, answered(Ui.Session.TripChange.Removed, tripId, callback))
    }

    /** Takes a detected trip as suggested; 409 (settled elsewhere meanwhile) counts as done. */
    function acceptSuggestion(sg, callback) {
        if (!canEdit || busy || !sg) {
            return
        }
        const c = session.connection
        busy = true
        c.tracker.acceptTripSuggestion(c.url, c.token, sg.id, {}, answered(Ui.Session.TripChange.Accepted, sg, callback, true))
    }

    function dismissSuggestion(sg, callback) {
        if (!canEdit || busy || !sg) {
            return
        }
        const c = session.connection
        busy = true
        c.tracker.dismissTripSuggestion(c.url, c.token, sg.id, answered(Ui.Session.TripChange.Dismissed, sg, callback))
    }

    /** Logs today's commute; offline (or behind waiting changes) the waiting trip shows the profile's distance. */
    function logCommute(callback) {
        if (!canEdit || busy) {
            return
        }
        const c = session.connection
        const local = session.sync.offline || session.sync.unsynced > 0
        busy = true
        c.tracker.createTrip(c.url, c.token,
            Mileage.commuteBody(Mileage.dateString(new Date()), local ? Mileage.commuteKm(ping) : null),
            answered(Ui.Session.TripChange.Saved, null, callback))
    }

    /** The answer of a call: frees busy, reports the change, then calls the caller's callback. */
    function answered(change, subject, callback, conflictIsDone) {
        return function(r) {
            busy = false
            const settled = conflictIsDone && r.error && r.error.status === 409
            if (r.ok || settled) {
                changed(change, subject || r.data)
            }
            if (callback) {
                callback(settled ? { ok: true, data: null } : r)
            }
        }
    }
}
