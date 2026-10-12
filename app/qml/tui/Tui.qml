import QtQml
import "../../contents/ui" as Ui
import "../platform/appBackend.js" as AppBackend
import "../../contents/code/platform.js" as Platform
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/dayModel.js" as DayModel
import "../../contents/code/statsData.js" as StatsData
import "tuiView.js" as View

/**
 * The terminal client (`plasmai-app --tui`): the same Session as the app,
 * drawn as text. Keys: 1–9 or ↑↓ Enter start or switch to a recent entry,
 * s stop, t day, w week, r refresh, Esc back, q quit.
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
    readonly property int maxNumberKey: 9

    property string view: viewMain
    property int selected: 0
    property string message: ""

    property Ui.Session session: Ui.Session {
        offlinePrefix: "tui-"
        onRecentChanged: tui.selected = Math.min(tui.selected, Math.max(0, recent.length - 1))
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
        target: tui.session
        function onConnectionChanged() { tui.draw() }
        function onActiveChanged() { tui.draw() }
        function onRecentChanged() { tui.draw() }
    }

    function handle(key) {
        if (key === "q" || key === "quit") {
            Qt.quit()
            return
        }
        if (key === "escape") {
            view = viewMain
        } else if (key === "t") {
            view = viewDay
        } else if (key === "w") {
            view = viewWeek
        } else if (key === "r") {
            session.refresh()
        } else if (key === "s") {
            session.stop()
        } else if (view === viewMain) {
            handleMain(key)
        }
        draw()
    }

    function handleMain(key) {
        const count = session.recent.length
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
            session.continueEntry(session.recent[selected])
            return
        }
        if (key === "enter" && count > 0) {
            session.continueEntry(session.recent[selected])
        }
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
            mainKeys: i18n("1–9 start · s stop · t day · w week · r refresh · q quit"),
            subKeys: i18n("Esc back · s stop · r refresh · q quit")
        }
    }

    function statusOf() {
        if (session.connection === session.needsSetup || session.connection === session.unconfigured) {
            return { text: i18n("Set up a connection in the Plasmai app first"), style: View.Style.DANGER }
        }
        if (session.connection === session.error) {
            return { text: i18n("Server not reachable"), style: View.Style.DANGER }
        }
        if (session.offline) {
            return { text: i18n("Offline · %1 not synced", session.unsynced), style: View.Style.PRIMARY }
        }
        if (session.connection === session.connecting) {
            return { text: i18n("Connecting…"), style: View.Style.DIM }
        }
        return { text: i18n("Online"), style: View.Style.OK }
    }

    function baseModel() {
        const status = statusOf()
        return {
            profileName: session.profile ? (session.profile.name || "") : "",
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

        const a = session.active
        terminal.render(View.main(Object.assign(model, {
            tracking: session.tracking,
            activity: a ? KimaiApi.activityName(a) : "",
            project: a ? KimaiApi.projectName(a) : "",
            elapsed: session.elapsedSeconds,
            todaySeconds: session.todaySeconds,
            weekSeconds: session.weekSeconds,
            recent: session.recent.map(function(r) {
                return { title: KimaiApi.activityName(r), sub: KimaiApi.projectName(r) + (r.description ? " · " + r.description : "") }
            }),
            selected: selected,
            message: message
        }), size, t))
    }

    function dayModel() {
        const now = new Date()
        const blocks = DayModel.blocks(session.todayEntries, now, now.getTime()).map(function(b) {
            return Object.assign(b, { label: KimaiApi.activityName(b.entry) + " · " + KimaiApi.projectName(b.entry) })
        })
        return {
            title: Qt.locale().toString(now, "dddd, d. MMMM"),
            blocks: blocks,
            workFrom: hours(session.workDayBegin, 8),
            workTo: hours(session.workDayEnd, 17),
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
            grid: DayModel.weekGrid(session.weekEntries, now, now.getTime()),
            dayNames: names,
            todayIndex: (now.getDay() + 6) % 7
        }
    }

    function failureText(action, result) {
        const detail = result && result.error ? (result.error.detail || result.error.statusText || "") : ""
        const what = action === session.actionStop ? i18n("Could not stop tracking")
                   : action === session.actionRefresh ? i18n("Could not refresh")
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
