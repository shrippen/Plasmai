import QtQml
import "../../code/timeTracker.js" as TimeTracker
import "../../code/platform.js" as Platform
import "../../code/offline.js" as Offline
import "../../code/offlineOutbox.js" as Outbox
import "../../code/offlineState.js" as OfflineState
import "../../code/filmDaySync.js" as FilmDaySync

/**
 * The offline layer of the active profile (offline.js, Kimai only): reads
 * answer from the snapshot, writes wait in the outbox. Each client keeps its
 * own files (session.offlinePrefix + profile id).
 */
QtObject {
    id: sync

    property QtObject session: null

    /** The offline.js session (layer only). */
    property var state: null
    /** Bumped by offline.js on every change, so the bindings below re-read it. */
    property int revision: 0

    // A refresh answers a dozen reads within a second: the snapshot is saved once after them.
    property var pendingSave: null
    property Timer saveTimer: Timer {
        interval: 1000
        onTriggered: sync.flushSave()
    }

    function flushSave() {
        const save = pendingSave
        pendingSave = null
        if (save) {
            save()
        }
    }

    Component.onDestruction: flushSave()

    readonly property bool offline: revision >= 0 && !!state && Offline.isOffline(state)
    /** What is wrong with the outbox's file (OfflineState.StorageError; no text), "" = nothing. */
    readonly property string storageError: revision >= 0 && state ? state.storageError : OfflineState.StorageError.NONE
    readonly property int unsynced: revision >= 0 && state ? Outbox.pendingCount(state) : 0
    /** When the snapshot was last written from a server answer (ms, 0 = never). */
    readonly property double stateAt: revision >= 0 && state ? OfflineState.stateAt(state) : 0
    /** Ops that failed or conflict. */
    readonly property int stuck: ops.filter(function(op) { return op.state !== OfflineState.State.PENDING }).length
    /** The outbox in order (UnsyncedList). */
    readonly property var ops: revision >= 0 && state ? Outbox.ops(state) : []

    /** Opens the outbox of `p` (resolves once loaded); the same profile keeps its session. */
    function openFor(p) {
        const providerId = p && p.provider ? p.provider : TimeTracker.PROVIDER_KIMAI
        const inner = TimeTracker.api(providerId)
        const key = providerId === TimeTracker.PROVIDER_KIMAI && p
            ? session.offlinePrefix + String(p.id).replace(/[^A-Za-z0-9_-]/g, "_") : ""
        if (state && state.host.key === key && state.inner === inner) {
            return state.outboxBlocked ? Outbox.loadOutbox(state) : Promise.resolve()
        }
        // The old session's deferred save would be replaced by the new one's.
        flushSave()
        if (state) {
            Offline.close(state)
        }
        const s = Offline.createSession(inner, {
            key: key,
            url: function() { return session.connection.url },
            token: function() { return session.connection.token },
            load: function(name) { return Platform.loadLocal(session.dataSource, name) },
            save: function(name, obj) { return Platform.saveLocal(session.dataSource, name, obj) },
            defer: function(fn) {
                sync.pendingSave = fn
                sync.saveTimer.start()
            },
            changed: function() { sync.revision++ },
            idChanged: function(localId, serverId) { session.timer.followId(localId, serverId) }
        })
        state = s
        return Offline.load(s).then(function() {
            FilmDaySync.restoreMemo(session.filmDay.context(), OfflineState.filmDays(s))
        })
    }

    function isUnsynced(entryId) {
        return revision >= 0 && !!state && Outbox.isUnsynced(state, entryId)
    }

    function retry(opId) {
        Outbox.retry(state, opId, function() {
            session.entriesWritten()
            session.refresh()
        })
    }

    /** Conflict: send the local change anyway. */
    function overwrite(opId) {
        Outbox.overwrite(state, opId, function() {
            session.entriesWritten()
            session.refresh()
        })
    }

    function discard(opId) {
        Outbox.discard(state, opId)
        session.entriesWritten()
        session.refresh()
    }

    /** Film day answers kept with the snapshot (filmDaySync's memo). */
    function rememberFilmDays(part) {
        if (state) {
            OfflineState.rememberFilmDays(state, part)
        }
    }
}
