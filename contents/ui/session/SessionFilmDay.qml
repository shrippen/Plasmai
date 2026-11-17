import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/entityNames.js" as Names
import "../../code/filmDaySync.js" as FilmDaySync
import "../../code/filmDays.js" as FilmDays
import "../../code/dateTimeFormat.js" as DTF
import ".." as Ui

/**
 * Film day extras of the Drehzettel plugin (filmDaySync.js): the plugin
 * probe and every call of the film day view, with this profile's context.
 *
 *   resolveMode ─▶ mode (NO_PLUGIN, NO_PERMISSION, OFFLINE, SERVER) ─▶ available
 *   openView / loadDay ─▶ the shown day (cached answer at once, the live one when
 *                         it differs) and later the production's shooting day
 *   saveDay ─▶ span check, entry and extras, then the other entries of a merge
 *   saveExtras / saveNote ─▶ outbox when offline
 *
 * The loaded day (dayTimesheet, dayServer, dayMode, noteEntry, savedNote) stays
 * here: a save diffs against it, whichever page asks. A view only shows it.
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
    /** The day last loaded: the entry shown, the plugin's JSON (server mode), the load's mode. */
    property var dayTimesheet: null
    property var dayServer: null
    property string dayMode: ""
    /** Entry the note belongs to (running or the day's), null before it exists. */
    property var noteEntry: null
    /** The note as last loaded or saved (its entry's description). */
    property string savedNote: ""
    property bool loading: false
    /** True while a save that blocks the view runs (not a direct edit). */
    property bool saving: false
    /** Only the latest load may answer (fast day steps, project picks). */
    property int loadSerial: 0
    /** The ids filmDaySync reads from an entry. */
    readonly property var ids: ({ projectOf: Names.projectId, activityOf: Names.activityId })

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
        FilmDaySync.resolveMode(c.url, c.token, profileId, cache, { force: probe === Ui.Session.Probe.Fresh, tracker: c.tracker }, function(r) {
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

    /**
     * Loads after the mode is known (plugin present or not); see loadDay.
     * projectOf(): the project the view has picked by then (null: none).
     */
    function openView(probe, date, projectOf, preferSelected, onDay, onProduction) {
        if (!session.connection.configured) {
            return
        }
        loading = true
        resolveMode(probe, function() {
            loadDay(date, projectOf(), preferSelected, onDay, onProduction)
        })
    }

    /**
     * Loads the day: the entry, the plugin's extras and what the view shows of them.
     * projectId: the project the view has picked (null: none). Cached days answer
     * at once, the live answer follows when it differs.
     *   onDay({ date, r, day, info, currency })  r: filmDaySync.resolveDay,
     *     info: filmDaySync.viewInfo, currency: of the project's customer
     *   onProduction({ number, activityId })  the production's shooting day, once
     *     counted; activityId (or null): the engagement's usual film activity
     * Both stay silent when a newer load started.
     */
    function loadDay(date, projectId, preferSelected, onDay, onProduction) {
        if (!session.connection.configured) {
            return
        }
        loading = true
        const serial = ++loadSerial
        const cat = session.catalog
        // One engagement per day decides the project; the plugin's day summary
        // decides which of the project's entries is the film day.
        FilmDaySync.openDay(context(), date, projectId, ids, cat.hydrate, function(r, entries) {
            if (serial !== loadSerial) {
                return
            }
            // A day the server answered: the plugin is reachable again.
            if (r.day.mode === FilmDaySync.Mode.SERVER && mode === FilmDaySync.Mode.OFFLINE) {
                mode = FilmDaySync.Mode.SERVER
            }
            loading = false
            dayTimesheet = r.match
            dayServer = r.day.server
            dayMode = r.day.mode
            const info = FilmDaySync.viewInfo(r, {
                entries: entries, active: session.timer.tracking ? session.timer.active : null,
                recent: session.recent.list, daysFromToday: -DTF.daysBefore(date, new Date()),
                ids: ids,
                labelOf: function(ts) {
                    return Names.displayActivityName(ts, cat.activities, cat.activitiesByProject)
                        + " · " + Names.displayProjectName(ts, cat.projects)
                },
                timeOf: FilmDays.spanText
            })
            noteEntry = info.timesheet
            savedNote = FilmDays.noteOf(info.timesheet)
            onDay({
                date: date, r: r, day: r.day, info: info,
                currency: Names.customerCurrencyOfProject(cat.projectById(r.projectId), cat.customers)
            })
            loadProduction(serial, date, r, info, onProduction)
        }, preferSelected)
    }

    /** Production shooting day of the engagement, once counted. */
    function loadProduction(serial, date, r, info, onProduction) {
        if (!onProduction || !r.engagement || !r.engagement.validFrom) {
            return
        }
        FilmDaySync.productionDay(context(), r.projectId, info.activityId, r.activityIds,
                                  String(r.engagement.validFrom), DTF.localDateString(date), ids, function(count) {
            if (serial !== loadSerial || !count) {
                return
            }
            onProduction({
                // A day without its entry yet (before the start) is the next shooting day.
                number: count.includesDay ? count.count : (info.phase === "before" ? count.count + 1 : 0),
                activityId: count.activityId
            })
        })
    }

    /** The day's entry is no longer shown. */
    function forgetDay() {
        dayTimesheet = null
    }

    /**
     * Saves entry and extras of the shown day, then deletes the other entries of a
     * merge. req = { projectId, activityId, date, beginText, endText, fields,
     * direct (a direct edit: no busy state), mergeIds, breakMinutes, note (for a
     * new entry) }. callback(result) as filmDaySync.saveDay, plus invalid
     * (FilmDays.SpanProblem; nothing was sent), deleteReport (null without a merge;
     * else filmDaySync.deleteEntries) and workSeconds. The deletion runs whether or
     * not anybody still waits for the answer.
     */
    function saveDay(req, callback) {
        if (saving) {
            return
        }
        const span = FilmDays.checkSpan(req.beginText, req.endText)
        if (span.problem !== FilmDays.SpanProblem.NONE) {
            callback({ ok: false, invalid: span.problem })
            return
        }
        saving = !req.direct
        const existingId = FilmDays.saveTargetId(dayTimesheet, req.projectId, Names.projectId)
        const fields = {
            begin: DTF.localDateTimeString(new Date(span.beginMs)),
            end: DTF.localDateTimeString(new Date(span.endMs)),
            project: req.projectId,
            activity: req.activityId
        }
        // A new entry takes the note typed before it existed.
        if (!existingId) {
            fields.description = req.note
        }
        FilmDaySync.saveDay(context(), {
            projectId: req.projectId,
            dateStr: DTF.localDateString(req.date),
            existingId: existingId,
            timesheetFields: fields,
            fields: req.fields,
            server: dayServer,
            dayMode: dayMode
        }, function(result) {
            result.invalid = FilmDays.SpanProblem.NONE
            result.deleteReport = null
            result.workSeconds = FilmDays.workSecondsFromSpan(span.beginMs, span.endMs, req.breakMinutes)
            if (result.ok) {
                session.entriesWritten()
            }
            if (!result.ok || !req.mergeIds || req.mergeIds.length === 0) {
                saving = false
                callback(result)
                return
            }
            FilmDaySync.deleteEntries(context(), req.mergeIds, function(report) {
                session.entriesWritten()
                saving = false
                result.deleteReport = report
                callback(result)
            })
        })
    }

    /**
     * Saves the extras of the shown day; req = { projectId, date, fields }.
     * callback(result) as filmDaySync.saveExtras. After a save the plugin's day
     * summary follows: earnings(payCents).
     */
    function saveExtras(req, callback, earnings) {
        const c = session.connection
        const dateStr = DTF.localDateString(req.date)
        FilmDaySync.saveExtras(context(), {
            projectId: req.projectId, dateStr: dateStr, fields: req.fields, server: dayServer, dayMode: dayMode
        }, function(result) {
            if (result.server) {
                dayServer = result.server
            }
            callback(result)
            if (result.extras !== "saved" || !KimaiApi.drehzettelHasFeature(ping, "daySummary")) {
                return
            }
            c.tracker.fetchDaySummary(c.url, c.token, req.projectId, dateStr, function(sres) {
                if (sres.ok && sres.data && typeof sres.data.payCents === "number") {
                    earnings(sres.data.payCents)
                }
            })
        })
    }

    /** The note is the entry's description; before the entry exists it goes with Start / Save. */
    function saveNote(text, callback) {
        FilmDaySync.saveNote(context(), {
            timesheetId: noteEntry ? noteEntry.id : null, note: text, previous: savedNote
        }, function(result) {
            if (result.saved === "saved") {
                savedNote = result.note
                session.entriesWritten()
            }
            callback(result)
        })
    }
}
