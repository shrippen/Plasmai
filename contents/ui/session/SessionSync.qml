import QtQml
import "../../code/timeTracker.js" as TimeTracker
import "../../code/platform.js" as Platform
import "../../code/offline.js" as Offline
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

    readonly property bool offline: revision >= 0 && !!state && Offline.isOffline(state)
    readonly property int unsynced: revision >= 0 && state ? Offline.pendingCount(state) : 0
    /** When the snapshot was last written from a server answer (ms, 0 = never). */
    readonly property double stateAt: revision >= 0 && state ? Offline.stateAt(state) : 0
    /** Ops that failed or conflict. */
    readonly property int stuck: ops.filter(function(op) { return op.state !== Offline.State.PENDING }).length
    /** The outbox in order (UnsyncedList). */
    readonly property var ops: revision >= 0 && state ? Offline.ops(state) : []

    /** Opens the outbox of `p` (resolves once loaded); the same profile keeps its session. */
    function openFor(p) {
        const providerId = p && p.provider ? p.provider : TimeTracker.PROVIDER_KIMAI
        const inner = TimeTracker.api(providerId)
        const key = providerId === TimeTracker.PROVIDER_KIMAI && p
            ? session.offlinePrefix + String(p.id).replace(/[^A-Za-z0-9_-]/g, "_") : ""
        if (state && state.host.key === key && state.inner === inner) {
            return Promise.resolve()
        }
        const s = Offline.createSession(inner, {
            key: key,
            url: function() { return session.connection.url },
            token: function() { return session.connection.token },
            load: function(name) { return Platform.loadLocal(session.dataSource, name) },
            save: function(name, obj) {
                return Platform.saveLocal(session.dataSource, name, obj).catch(function(err) {
                    console.warn("Plasmai: could not save", name, err)
                })
            },
            changed: function() { sync.revision++ },
            idChanged: function(localId, serverId) { session.timer.followId(localId, serverId) }
        })
        state = s
        return Offline.load(s).then(function() {
            FilmDaySync.restoreMemo(session.filmDay.context(), Offline.filmDays(s))
        })
    }

    function isUnsynced(entryId) {
        return revision >= 0 && !!state && Offline.isUnsynced(state, entryId)
    }

    function retry(opId) {
        Offline.retry(state, opId, function() { session.refresh() })
    }

    /** Conflict: send the local change anyway. */
    function overwrite(opId) {
        Offline.overwrite(state, opId, function() { session.refresh() })
    }

    function discard(opId) {
        Offline.discard(state, opId)
        session.refresh()
    }

    /** Film day answers kept with the snapshot (filmDaySync's memo). */
    function rememberFilmDays(part) {
        if (state) {
            Offline.rememberFilmDays(state, part)
        }
    }
}
