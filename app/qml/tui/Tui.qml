import QtQml
import "../../contents/ui" as Ui
import "../platform/appBackend.js" as AppBackend
import "../../contents/code/platform.js" as Platform
import "../../contents/code/entityNames.js" as Names
import "../../contents/code/dayModel.js" as DayModel
import "../../contents/code/statsData.js" as StatsData
import "../../contents/code/sharedConfig.js" as SharedConfig
import "tuiView.js" as View

/**
 * The terminal client (`plasmai-app --tui`): the same Session as the app,
 * drawn as text. Keys: 1–9 or ↑↓ Enter start or switch to a recent entry,
 * s stop, t day, w week, r refresh, Esc back, q quit; u lists the waiting changes
 * (↑↓ select, r send again, a send a parked group here, d discard; y confirms).
 *
 *   Terminal.keyPressed ──▶ handle() ──▶ Session actions
 *   Session state / 1 s tick ──▶ draw() ──▶ View.main|day|week ──▶ Terminal.render
 *
 * Context properties from tuimain.cpp: terminal, TokenStore, FileStore,
 * plasmaiDemoBuild, tuiDemo; i18n() from the app's catalogs.
 */
QtObject {
    id: tui

    readonly property string viewMain: "main"
    readonly property string viewDay: "day"
    readonly property string viewWeek: "week"
    readonly property string viewUnsynced: "unsynced"
    /** The keys that open a view. */
    readonly property var viewKeys: ({ "t": viewDay, "w": viewWeek, "u": viewUnsynced })
    readonly property int maxNumberKey: 9

    property string view: viewMain
    property int selected: 0
    property string message: ""
    /** The row selected in the list of waiting changes. */
    property int listSelected: 0
    /** What waits for a "y": { action (View.Action), item }, or null. */
    property var asked: null

    property Ui.Session session: Ui.Session {
        offlinePrefix: "tui-"
        onFailed: function(action, result) { tui.message = tui.failureText(action, result) }
        onStarted: tui.message = ""
        onStopped: tui.message = ""
    }

    property Timer drawTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: tui.draw()
    }

    property Connections keys: Connections {
        target: terminal
        function onKeyPressed(key) { tui.handle(key) }
        function onResized() { tui.draw() }
    }

    property Connections changes: Connections {
        target: tui.session.connection
        function onStateChanged() { tui.draw() }
    }

    property Connections timerChanges: Connections {
        target: tui.session.timer
        function onActiveChanged() { tui.draw() }
    }

    property Connections recentChanges: Connections {
        target: tui.session.recent
        function onListChanged() {
            tui.selected = Math.min(tui.selected, Math.max(0, tui.session.recent.list.length - 1))
            tui.draw()
        }
    }

    function handle(key) {
        if (key === "q" || key === "quit") {
            Qt.quit()
            return
        }
        if (view === viewUnsynced && handleUnsynced(key)) {
            draw()
            return
        }
        if (key === "escape") {
            view = viewMain
            asked = null
        } else if (viewKeys[key]) {
            view = viewKeys[key]
        } else if (key === "r") {
            session.refresh()
        } else if (key === "s") {
            session.timer.stop()
        } else if (view === viewMain) {
            handleMain(key)
        }
        draw()
    }

    function handleMain(key) {
        const count = session.recent.list.length
        if (key === "up") {
            selected = Math.max(0, selected - 1)
            return
        }
        if (key === "down") {
            selected = Math.min(Math.max(0, count - 1), selected + 1)
            return
        }
        const number = parseInt(key, 10)
        if (!isNaN(number) && number >= 1 && number <= Math.min(maxNumberKey, count)) {
            selected = number - 1
            restart(session.recent.list[selected])
            return
        }
        if (key === "enter" && count > 0) {
            restart(session.recent.list[selected])
        }
    }

    /** Keys of the list of waiting changes; false for a key that is not for the list. */
    function handleUnsynced(key) {
        const items = unsyncedItems()
        if (asked) {
            const pending = asked
            asked = null
            if (key === "y") {
                perform(pending)
            }
            return true
        }
        if (key === "up" || key === "down") {
            const next = listSelected + (key === "up" ? -1 : 1)
            listSelected = Math.max(0, Math.min(Math.max(0, items.length - 1), next))
            return true
        }
        const item = items[listSelected]
        const action = View.unsyncedAction(key, item)
        if (action === View.Action.NONE) {
            return false
        }
        asked = { action: action, item: item }
        return true
    }

    /** The waiting changes, then the parked groups, as rows of the list. */
    function unsyncedItems() {
        const ops = session.sync.ops.map(function(op) {
            return { kind: View.ItemKind.OP, id: op.opId, title: Ui.ApiErrors.opKindText(op),
                     sub: Ui.ApiErrors.opStateText(op), canAdopt: false }
        })
        const groups = session.sync.groups.map(function(group) {
            return { kind: View.ItemKind.GROUP, id: group.id, title: Ui.ApiErrors.heldGroupText(group),
                     sub: Ui.ApiErrors.heldHint(group), canAdopt: group.canAdopt, group: group }
        })
        return ops.concat(groups)
    }

    function perform(pending) {
        const item = pending.item
        if (pending.action === View.Action.RETRY) {
            session.sync.retry(item.id)
        } else if (pending.action === View.Action.ADOPT) {
            session.sync.adopt(item.id)
        } else if (item.kind === View.ItemKind.GROUP) {
            session.sync.discardGroup(item.id)
        } else {
            session.sync.discard(item.id)
        }
    }

    /** The question for what waits for a "y". */
    function questionText() {
        if (!asked) {
            return ""
        }
        const item = asked.item
        let question = i18n("Send this change again?")
        if (asked.action === View.Action.ADOPT) {
            question = Ui.ApiErrors.adoptQuestion(item.group)
        } else if (asked.action === View.Action.DISCARD) {
            question = item.kind === View.ItemKind.GROUP ? Ui.ApiErrors.discardGroupQuestion(item.group) : i18n("Discard this change?")
        }
        return i18n("%1 (y = yes, any other key = no)", question)
    }

    /** Continues a recent entry; while another runs, switches to it (no confirmation here). */
    function restart(ts) {
        if (session.timer.requestRestart(ts) !== Ui.Session.Restart.Confirm) {
            return
        }
        session.timer.switchTo(Names.projectId(ts), Names.activityId(ts), Names.projectName(ts),
                               Names.activityName(ts), ts.description || "")
    }

    // ── Drawing ──

    function words() {
        return {
            idle: i18n("Nothing is running"),
            today: i18n("Today"),
            week: i18n("Week"),
            recent: i18n("Recent"),
            noRecent: i18n("No recent entries"),
            noEntries: i18n("No entries this week"),
            noGaps: i18n("No gaps in the work day"),
            gaps: i18n("Gaps:"),
            total: i18n("Total"),
            unsyncedTitle: i18n("Not synced"),
            unsyncedKeys: i18n("↑↓ select · r send again · a send here · d discard · Esc back"),
            allSynced: i18n("Everything is synced."),
            mainKeys: i18n("1–9 start · s stop · t day · w week · r refresh · q quit"),
            subKeys: i18n("Esc back · s stop · r refresh · q quit")
        }
    }

    function statusOf() {
        const c = session.connection
        if (c.state === c.needsSetup || c.state === c.unconfigured) {
            return { text: i18n("Set up a connection in the Plasmai app first"), style: View.Style.DANGER }
        }
        if (c.state === c.error) {
            return { text: i18n("Server not reachable"), style: View.Style.DANGER }
        }
        if (session.sync.storageError !== "") {
            return { text: Ui.ApiErrors.storageText(session.sync.storageError), style: View.Style.DANGER }
        }
        if (session.sync.held > 0 || session.sync.stuck > 0) {
            return { text: i18n("Changes need a decision · u"), style: View.Style.DANGER }
        }
        if (session.sync.offline) {
            return { text: i18n("Offline · %1 not synced", session.sync.unsynced), style: View.Style.PRIMARY }
        }
        if (c.state === c.connecting) {
            return { text: i18n("Connecting…"), style: View.Style.DIM }
        }
        return { text: i18n("Online"), style: View.Style.OK }
    }

    function baseModel() {
        const status = statusOf()
        return {
            profileName: session.connection.profile ? (session.connection.profile.name || "") : "",
            statusText: status.text,
            statusStyle: status.style
        }
    }

    function draw() {
        const size = { columns: terminal.columns, rows: terminal.rows }
        const t = words()
        const model = baseModel()

        if (view === viewDay) {
            terminal.render(View.day(Object.assign(model, dayModel()), size, t))
            return
        }
        if (view === viewWeek) {
            terminal.render(View.week(Object.assign(model, weekModel()), size, t))
            return
        }

        if (view === viewUnsynced) {
            const items = unsyncedItems()
            listSelected = Math.min(listSelected, Math.max(0, items.length - 1))
            terminal.render(View.unsynced(Object.assign(model, {
                items: items, selected: listSelected, question: questionText(), message: message
            }), size, t))
            return
        }

        const a = session.timer.active
        terminal.render(View.main(Object.assign(model, {
            tracking: session.timer.tracking,
            activity: a ? Names.activityName(a) : "",
            project: a ? Names.projectName(a) : "",
            elapsed: session.timer.elapsedSeconds,
            todaySeconds: session.totals.todaySeconds,
            weekSeconds: session.totals.weekSeconds,
            recent: session.recent.list.map(function(r) {
                return { title: Names.activityName(r), sub: Names.projectName(r) + (r.description ? " · " + r.description : "") }
            }),
            selected: selected,
            message: message
        }), size, t))
    }

    function dayModel() {
        const now = new Date()
        const blocks = DayModel.blocks(session.totals.todayEntries, now, now.getTime()).map(function(b) {
            return Object.assign(b, { label: Names.activityName(b.entry) + " · " + Names.projectName(b.entry) })
        })
        return {
            title: Qt.locale().toString(now, "dddd, d. MMMM"),
            blocks: blocks,
            workFrom: hours(session.settings.workDayBegin, hours(SharedConfig.DEFAULTS.workDayBegin, 0)),
            workTo: hours(session.settings.workDayEnd, hours(SharedConfig.DEFAULTS.workDayEnd, 0)),
            untilHour: now.getHours() + now.getMinutes() / 60
        }
    }

    /** "08:30" → 8.5; `fallback` when unreadable. */
    function hours(hhmm, fallback) {
        const parts = String(hhmm || "").split(":")
        const h = parseInt(parts[0], 10)
        const m = parseInt(parts[1] || "0", 10)
        return isNaN(h) ? fallback : h + (isNaN(m) ? 0 : m / 60)
    }

    function weekModel() {
        const now = new Date()
        const monday = StatsData.startOfWeek(now)
        const names = []
        for (let d = 0; d < 7; d++) {
            names.push(Qt.locale().toString(StatsData.addDays(monday, d), "ddd"))
        }
        return {
            title: StatsData.formatWeekLabel(monday),
            grid: DayModel.weekGrid(session.totals.weekEntries, now, now.getTime()),
            dayNames: names,
            todayIndex: (now.getDay() + 6) % 7
        }
    }

    function failureText(action, result) {
        const detail = result && result.error ? Ui.ApiErrors.withServer(result.error) : ""
        const what = action === Ui.Session.Action.Stop ? i18n("Could not stop tracking")
                   : action === Ui.Session.Action.Refresh ? i18n("Could not refresh")
                   : i18n("Could not start tracking")
        return detail ? what + ": " + detail : what
    }

    // ── Start ──

    function startDemo() {
        const hook = Qt.createComponent("TuiDemo.qml")
        if (hook.status !== Component.Ready) {
            message = i18n("This build has no demo")
            session.open()
            return
        }
        hook.createObject(tui).start(session)
    }

    Component.onCompleted: {
        Platform.setBackend(AppBackend.create(TokenStore, FileStore))
        if (tuiDemo) {
            startDemo()
        } else {
            session.open()
        }
        draw()
    }
}
