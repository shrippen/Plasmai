import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/filmDaySync.js" as FilmDaySync
import ".." as Ui

/**
 * Film day extras of the Drehzettel plugin (filmDaySync.js): the plugin
 * probe and every call of the film day view, with this profile's context.
 *
 *   resolveMode ─▶ mode (NO_PLUGIN, NO_PERMISSION, OFFLINE, SERVER) ─▶ available
 *   openDay ─▶ cached answer at once, the live one when it differs
 *   saveDay / saveExtras / saveNote / deleteEntries ─▶ outbox when offline
 */
QtObject {
    id: filmDay

    property QtObject session: null

    property string mode: FilmDaySync.Mode.NO_PLUGIN
    property var ping: null
    /** Plain cache handed to filmDaySync (engagement lists); not reactive. */
    property var memo: ({})
    readonly property string profileKey: FilmDaySync.profileKey(session.connection.profile ? session.connection.profile.id : "",
                                                                 session.connection.url)
    /** Offered only with the Drehzettel plugin and its view permission, like trips. */
    readonly property bool available: session.connection.configured && session.connection.capabilities.filmDays
        && mode !== FilmDaySync.Mode.NO_PLUGIN && mode !== FilmDaySync.Mode.NO_PERMISSION
    /** The ids filmDaySync reads from an entry. */
    readonly property var ids: ({ projectOf: KimaiApi.projectId, activityOf: KimaiApi.activityId })

    /** The context every filmDaySync call takes. */
    function context() {
        const c = session.connection
        return {
            url: c.url,
            token: c.token,
            profileKey: profileKey,
            persist: function(part) { session.sync.rememberFilmDays(part) },
            mode: mode,
            ping: ping,
            memo: memo,
            tracker: c.tracker
        }
    }

    /** Probes the plugin (cached 24 h per profile in pluginProbesJson); probe: Session.Probe. */
    function resolveMode(probe, callback) {
        const c = session.connection
        const profileId = c.profile ? c.profile.id : ""
        if (!c.token || !c.capabilities.drehzettelApi) {
            mode = FilmDaySync.Mode.NO_PLUGIN
            if (callback) {
                callback()
            }
            return
        }
        const cache = KimaiApi.parsePluginCache(session.settings.pluginProbesJson)
        FilmDaySync.resolveMode(c.url, c.token, profileId, cache, { force: probe === Ui.Session.Probe.Fresh }, function(r) {
            mode = r.mode
            ping = r.ping
            if (r.probeCache) {
                session.settings.mergeMaps({ pluginProbesJson: JSON.stringify(r.probeCache) })
            }
            if (callback) {
                callback()
            }
        })
    }

    /** One engagement per day decides the project; callback(r, entries) (filmDaySync.openDay). */
    function openDay(date, selectedProjectId, callback, preferSelected) {
        FilmDaySync.openDay(context(), date, selectedProjectId, ids, session.catalog.hydrate, function(r, entries) {
            // A day the server answered: the plugin is reachable again.
            if (r.day.mode === FilmDaySync.Mode.SERVER && mode === FilmDaySync.Mode.OFFLINE) {
                mode = FilmDaySync.Mode.SERVER
            }
            callback(r, entries)
        }, preferSelected)
    }

    /** What the view shows of an opened day (pure, filmDaySync.viewInfo). */
    function viewInfo(r, opts) {
        return FilmDaySync.viewInfo(r, opts)
    }

    /** Production shooting day of the engagement; callback(count) once counted. */
    function productionDay(projectId, activityId, activityIds, fromDateStr, dateStr, callback) {
        FilmDaySync.productionDay(context(), projectId, activityId, activityIds, fromDateStr, dateStr, ids, callback)
    }

    /**
     * Saves the extras; callback(result) as filmDaySync.saveExtras. After a save the
     * plugin's day summary follows: earnings(payCents).
     */
    function saveExtras(req, callback, earnings) {
        const c = session.connection
        FilmDaySync.saveExtras(context(), req, function(result) {
            callback(result)
            if (result.extras !== "saved" || !KimaiApi.drehzettelHasFeature(ping, "daySummary")) {
                return
            }
            KimaiApi.fetchDaySummary(c.url, c.token, req.projectId, req.dateStr, function(sres) {
                if (sres.ok && sres.data && typeof sres.data.payCents === "number") {
                    earnings(sres.data.payCents)
                }
            })
        })
    }

    function saveNote(req, callback) {
        FilmDaySync.saveNote(context(), req, callback)
    }

    function saveDay(req, callback) {
        FilmDaySync.saveDay(context(), req, callback)
    }

    function deleteEntries(entryIds, callback) {
        FilmDaySync.deleteEntries(context(), entryIds, callback)
    }
}
