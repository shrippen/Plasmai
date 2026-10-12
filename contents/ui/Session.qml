import QtQml
import "../code/providerUtil.js" as ProviderUtil
import "session"

/**
 * The session layer (ROADMAP pillar 8): everything a view needs of the
 * tracker, without a view. QtQml only, so the terminal client runs it
 * without a window. Views bind to its parts and call their actions; only
 * the layer talks to providers and Platform.
 *
 *   view (app page, widget, TUI, config page, setup wizard)
 *     │ binds to state, calls actions, words the signals
 *     ▼
 *   Session ─┬─ connection  profiles, token, state, provider capabilities
 *            ├─ settings    shared.json keys, set(patch)
 *            ├─ catalog     customers, projects, activities, picker models
 *            ├─ timer       running entry, start / switch / stop, description
 *            ├─ recent      recent entries        favorites   pins
 *            ├─ entries     create, edit, delete, split, ranges, tags
 *            ├─ totals      today, week, targets, what is left
 *            ├─ sync        offline outbox (offline.js)
 *            ├─ filmDay     Drehzettel plugin (filmDaySync.js)
 *            ├─ trips       kimai-anfahrten plugin (mileage)
 *            ├─ reminders   idle, forgot to start, notifications
 *            └─ setup       system check, connection test, place search
 *     │
 *     ▼
 *   tracker (Offline-wrapped provider) · Platform (shared.json, tokens, files)
 *
 * No texts: failures come as failed(action, result); the view words them.
 * Platform.setBackend() must have run before open().
 */
QtObject {
    id: session

    /** Actions named in failed(). */
    enum Action { Start, Stop, Switch, Continue, Refresh, Save, Delete, Split, SplitRange, SplitSecond }
    /** How a timer of this client began (started()). */
    enum Origin { Start, Switch, Continue }
    /** Plugin probes: the 24 h cache, or ask the server again. */
    enum Probe { Cached, Fresh }
    /** What a start, a pinned start or a restart request did. */
    enum Restart { Ignored, Started, Continued, Hint, Confirm }
    /** Settings missing or older than the setup wizard. */
    enum Setup { Report, Run }
    /** After discarding idle time. */
    enum AfterIdle { Stop, Continue }

    // ── Inputs ──
    /** Plasmoid: its P5Support DataSource for Platform's scripts; app and TUI: null. */
    property var dataSource: null
    /** Prefix of the offline files; each client keeps its own outbox ("tui-", "app-"). */
    property string offlinePrefix: "tui-"
    /**
     * Report: missing or old settings only set connection.state to needsSetup (TUI: set up
     * in the app). Run: the host shows the setup wizard; old settings are reset first.
     */
    property int setupMode: Session.Setup.Report

    // ── Parts ──
    readonly property SessionConnection connection: SessionConnection { session: session }
    readonly property SessionSettings settings: SessionSettings { session: session }
    readonly property SessionCatalog catalog: SessionCatalog { session: session }
    readonly property SessionTimer timer: SessionTimer { session: session }
    readonly property SessionRecent recent: SessionRecent { session: session }
    readonly property SessionFavorites favorites: SessionFavorites { session: session }
    readonly property SessionEntries entries: SessionEntries { session: session }
    readonly property SessionTotals totals: SessionTotals { session: session }
    readonly property SessionSync sync: SessionSync { session: session }
    readonly property SessionFilmDay filmDay: SessionFilmDay { session: session }
    readonly property SessionTrips trips: SessionTrips { session: session }
    readonly property SessionReminders reminders: SessionReminders { session: session }
    readonly property SessionSetup setup: SessionSetup { session: session }

    /** A refresh or a write runs (one flag for the busy indicator). */
    property bool busy: false

    signal failed(int action, var result)
    /** A start of this client went through; names: { project, activity } as the view showed them. */
    signal started(var timesheet, int origin, var names)
    signal stopped(var timesheet, var names)
    /** The timer went from idle to running: a start here, or one found by a refresh. */
    signal trackingBegan(var timesheet)
    /** Saved, but the server dropped these fields ("billable" without edit_billable). */
    signal droppedFields(var fields)

    // Keeps polling after an error too, so it recovers by itself once the network is back.
    property Timer pollTimer: Timer {
        interval: Math.max(5, session.settings.refreshInterval) * 1000
        repeat: true
        running: session.connection.configured
                 && (session.connection.state === session.connection.online
                     || session.connection.state === session.connection.error)
        onTriggered: session.refresh()
    }

    // QML XMLHttpRequest has no timeout: abort hung requests so busy cannot stay stuck.
    property Timer watchdog: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: ProviderUtil.abortStaleRequests(Date.now())
    }

    /** Reads shared.json, picks the active profile, loads its token and refreshes. */
    function open() {
        return connection.open()
    }

    /** Running entry, recents, catalogs, totals and pins. */
    function refresh() {
        if (!connection.token) {
            return
        }
        timer.refresh()
        recent.refresh()
        catalog.refresh()
        totals.refresh()
        favorites.resolve()
    }

    /** A write answered: report the fields the server dropped. */
    function noteDropped(result) {
        if (result && result.droppedFields && result.droppedFields.indexOf("billable") >= 0) {
            droppedFields(result.droppedFields)
        }
    }
}
