import QtQml
import "../../code/dateTimeFormat.js" as DTF
import "../../code/entityNames.js" as Names
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

    /**
     * Add (id null) or edit entry `id`; on success the dropped fields are reported and all refreshes, a failure is failed(Save).
     * begin / end are checked and sent as stamps with an offset; a refused time sends nothing: result.invalid is a
     * TimesheetFields.TimeProblem.
     */
    function write(id, fields, callback) {
        const c = session.connection
        const checked = TimesheetFields.timeFields(fields, TimesheetFields.TimeCheck.ENTRY, Date.now())
        if (checked.problem !== TimesheetFields.TimeProblem.NONE) {
            const refused = { ok: false, invalid: checked.problem }
            session.failed(Ui.Session.Action.Save, refused)
            callback(refused)
            return
        }
        fields = checked.fields
        const done = function(result) {
            if (result.ok) {
                session.noteDropped(result)
                session.entriesWritten()
                session.refresh()
            } else {
                session.failed(Ui.Session.Action.Save, result)
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
            session.entriesWritten()
            session.refresh()
        })
    }

    /** done() once deleted. */
    function remove(ts, done) {
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
            session.entriesWritten()
            session.refresh()
            if (done) {
                done()
            }
        })
    }

    /** Splits a stopped entry at `at`: patches its end, creates a twin from there to the original end; done() once both exist. */
    function split(ts, at, done) {
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
        c.tracker.patchTimesheet(c.url, c.token, ts.id, { end: DTF.localDateTimeString(parts.firstEnd) }, function(result) {
            if (!result.ok) {
                session.busy = false
                session.failed(Ui.Session.Action.Split, result)
                return
            }
            const twin = {
                project: Names.projectId(ts), activity: Names.activityId(ts),
                begin: DTF.localDateTimeString(parts.secondBegin),
                end: DTF.localDateTimeString(parts.secondEnd),
                description: parts.description, billable: parts.billable, tags: parts.tags
            }
            c.tracker.createTimesheet(c.url, c.token, twin, function(second) {
                session.busy = false
                session.entriesWritten()
                if (!second.ok) {
                    session.failed(Ui.Session.Action.SplitSecond, second)
                }
                session.refresh()
                if (second.ok && done) {
                    done()
                }
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
                // The widget's catalog cache would hide the new entity until it is stale.
                session.catalog.invalidate()
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
