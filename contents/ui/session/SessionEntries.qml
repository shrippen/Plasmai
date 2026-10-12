import QtQml
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/timesheetFields.js" as TimesheetFields
import ".." as Ui

/**
 * Stopped entries and master data: add, edit, delete, split, ranges for the
 * statistics, tags for the tag picker (pass this object as its tagSource).
 */
QtObject {
    id: entries

    property QtObject session: null

    /** Master data and multi-entry changes need the server (offline.js: online only). */
    readonly property bool canCreate: session.connection.capabilities.createEntities && !session.sync.offline

    /** Add (id null) or edit entry `id`; on success the dropped fields are reported and all refreshes. */
    function write(id, fields, callback) {
        const c = session.connection
        const done = function(result) {
            if (result.ok) {
                session.noteDropped(result)
                session.refresh()
            }
            callback(result)
        }
        if (id !== null && id !== undefined) {
            c.tracker.patchTimesheet(c.url, c.token, id, fields, done)
            return
        }
        c.tracker.createTimesheet(c.url, c.token, fields, done)
    }

    /** Edits a stopped entry (busy, failures as failed(Save)). */
    function edit(ts, fields) {
        if (!ts || !ts.id) {
            return
        }
        const c = session.connection
        session.busy = true
        c.tracker.patchTimesheet(c.url, c.token, ts.id, fields, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Save, result)
                return
            }
            session.noteDropped(result)
            session.refresh()
        })
    }

    function remove(ts) {
        if (!ts || !ts.id) {
            return
        }
        const c = session.connection
        session.busy = true
        c.tracker.deleteTimesheet(c.url, c.token, ts.id, function(result) {
            session.busy = false
            if (!result.ok) {
                session.failed(Ui.Session.Action.Delete, result)
                return
            }
            session.refresh()
        })
    }

    /** Splits a stopped entry at `at`: patches its end, creates a twin from there to the original end. */
    function split(ts, at) {
        if (!ts || !ts.id || !at) {
            return
        }
        // Same as the Plasmoid: split must fall inside the entry; the twin
        // keeps project/activity (write keys project/activity, not *Id),
        // description, billable and tags, with a local end stamp.
        const parts = TimesheetFields.splitStoppedEntry(ts, at)
        if (!parts.ok) {
            session.failed(Ui.Session.Action.SplitRange, null)
            return
        }
        const c = session.connection
        session.busy = true
        c.tracker.patchTimesheet(c.url, c.token, ts.id, { end: KimaiApi.localDateTimeString(parts.firstEnd) }, function(result) {
            if (!result.ok) {
                session.busy = false
                session.failed(Ui.Session.Action.Split, result)
                return
            }
            const twin = {
                project: KimaiApi.projectId(ts), activity: KimaiApi.activityId(ts),
                begin: KimaiApi.localDateTimeString(parts.secondBegin),
                end: KimaiApi.localDateTimeString(parts.secondEnd),
                description: parts.description, billable: parts.billable, tags: parts.tags
            }
            c.tracker.createTimesheet(c.url, c.token, twin, function(second) {
                session.busy = false
                if (!second.ok) {
                    session.failed(Ui.Session.Action.SplitSecond, second)
                }
                session.refresh()
            })
        })
    }

    /** kind: "customer", "project" or "activity" (CreateEntityDialog's modes). */
    function createEntity(kind, fields, callback) {
        const c = session.connection
        const calls = { customer: "createCustomer", project: "createProject", activity: "createActivity" }
        if (!calls[kind]) {
            return
        }
        session.busy = true
        c.tracker[calls[kind]](c.url, c.token, fields, function(result) {
            session.busy = false
            if (result.ok) {
                session.refresh()
            }
            if (callback) {
                callback(result)
            }
        })
    }

    /** Entries between two dates, filled in from the catalog (statistics). */
    function fetchRange(begin, end, callback) {
        const c = session.connection
        if (!c.token) {
            return
        }
        c.tracker.fetchTimesheetsRange(c.url, c.token, begin, end, function(result) {
            if (result.ok) {
                result.data = session.catalog.hydrate(result.data || [])
            }
            callback(result)
        })
    }

    /** The tracker's tags matching `query` (tag picker); no token or no tags: an empty answer. */
    function loadTags(query, callback) {
        const c = session.connection
        if (!c.url || !c.token || typeof c.tracker.loadTags !== "function") {
            callback({ ok: false, data: [] })
            return
        }
        c.tracker.loadTags(c.url, c.token, query, callback)
    }
}
