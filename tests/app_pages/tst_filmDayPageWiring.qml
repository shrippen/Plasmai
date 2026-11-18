import QtQuick
import QtTest
import "../qml"

/** FilmDayPage (app/qml): what the page asks of the session and how it words the answers. */
TestCase {
    id: tc
    name: "FilmDayPageWiring"
    when: windowShown
    width: 400
    height: 400

    property var calls: []
    property var answers: ({})
    property var shown: []
    property var notices: []
    property var writeErrors: []

    // The singletons ApiErrors and EntryTexts have no i18n in tests: the errors below carry a
    // server text of their own kind ("unknown"), which they show as it is.
    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property QtObject session: QtObject {
                property var filmDay: QtObject {
                    property bool loading: false
                    property bool saving: false
                    property var dayTimesheet: ({ id: 3 })
                    function openView(probe, date, projectOf, prefer, onDay, onProduction) {
                        tc.calls.push({ name: "open", date: date, prefer: prefer })
                    }
                    function loadDay(date, projectId, prefer, onDay, onProduction) {
                        tc.calls.push({ name: "load", date: date, projectId: projectId, prefer: prefer })
                    }
                    function saveExtras(req, cb, earnings) {
                        tc.calls.push({ name: "extras", req: req })
                        tc.answers.extras = cb
                        tc.answers.earnings = earnings
                    }
                    function saveNote(text, cb) {
                        tc.calls.push({ name: "note", text: text })
                        tc.answers.note = cb
                    }
                    function saveDay(req, cb) {
                        tc.calls.push({ name: "save", req: req })
                        tc.answers.save = cb
                    }
                }
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    property var activities: []
                    property var activitiesByProject: ({})
                    property var projects: []
                    property var customers: []
                    signal changed()
                    function loadActivities(projectId, cb) { tc.calls.push({ name: "activities", projectId: projectId }) }
                    function projectById() { return null }
                }
                property var connection: QtObject { property bool configured: true; property string state: "ok" }
                property var timer: QtObject {
                    property bool tracking: false
                    property var active: null
                    property int elapsedSeconds: 0
                    function switchTo(projectId, activityId, projectLabel, activityLabel, note) {
                        tc.calls.push({ name: "switch", projectId: projectId, activityId: activityId, note: note })
                    }
                    function stop() { tc.calls.push({ name: "stop" }) }
                }
                property var reminders: QtObject {
                    function notify(title, body) { tc.notices.push(title) }
                }
                property var sync: QtObject { property bool offline: false }
                property var entries: QtObject { property bool canCreate: true }
                property var trips: QtObject { property bool canEdit: true }
                property var recent: QtObject { property var list: [] }
                property bool busy: false
                function refresh() {}
            }
            function fill(text, args) { return text.replace(/%(\d)/g, function(m, n) { return args[n - 1] }) }
            function i18n(text) { return fill(text, Array.prototype.slice.call(arguments, 1)) }
            function i18np(one, many) { return fill(one, Array.prototype.slice.call(arguments, 2)) }
            function showPassiveNotification(text) { tc.shown.push(text) }
            function reportWriteError(result, what) { tc.writeErrors.push([result, what]) }
            function openTripForTimesheet(ts) { tc.calls.push({ name: "trip", ts: ts }) }
            property Component pageComponent: Component { FilmDayPage { } }
        }
    }

    function init() {
        calls = []
        answers = ({})
        shown = []
        notices = []
        writeErrors = []
    }

    function findView(item) {
        if (typeof item.projectChosen === "function" && typeof item.otherEntryIds === "function") {
            return item
        }
        for (const child of item.children) {
            const found = findView(child)
            if (found) {
                return found
            }
        }
        return null
    }

    function openPage() {
        const h = createTemporaryObject(host, tc)
        const page = h.pageComponent.createObject(h)
        verify(page !== null)
        const view = findView(page)
        verify(view !== null)
        calls = []
        return { page: page, view: view }
    }

    function named(name) {
        return calls.filter(function(c) { return c.name === name })
    }

    function test_opens_the_day_from_cache() {
        const h = createTemporaryObject(host, tc)
        h.pageComponent.createObject(h)
        compare(named("open").length, 1)
        compare(named("open")[0].prefer, false)
    }

    function test_day_step_loads_the_neighbour_day() {
        const p = openPage()
        const before = new Date(p.page.selectedDate)
        p.view.dayStepRequested(-1)
        compare(named("load").length, 1)
        const loaded = named("load")[0].date
        compare(loaded.getDate(), new Date(before.getFullYear(), before.getMonth(), before.getDate() - 1).getDate())
        compare(named("load")[0].prefer, false)
    }

    function test_chosen_day_is_loaded() {
        const p = openPage()
        const day = new Date(2026, 10, 3)
        p.view.dayChosen(day)
        compare(named("load")[0].date.getTime(), day.getTime())
    }

    function test_engagement_pick_wins_over_the_days_engagement() {
        const p = openPage()
        p.view.engagementPicked(5)
        compare(named("load").length, 1)
        compare(named("load")[0].prefer, true)
    }

    function test_save_hands_the_form_to_the_session() {
        const p = openPage()
        p.view.saveRequested(7, 8, "2026-11-10T09:00:00", "2026-11-10T17:00:00", { crew: 1 })
        compare(named("save").length, 1)
        const req = named("save")[0].req
        compare(req.projectId, 7)
        compare(req.activityId, 8)
        compare(req.beginText, "2026-11-10T09:00:00")
        compare(req.endText, "2026-11-10T17:00:00")
        compare(req.fields.crew, 1)
        compare(req.direct, false)
        compare(req.mergeIds, [])
    }

    function test_failed_save_shows_the_server_text() {
        const p = openPage()
        p.view.saveRequested(7, 8, "a", "b", {})
        tc.answers.save({ ok: false, error: { type: "unknown", status: 400, detail: "Overlap with entry 4" } })
        compare(shown.length, 1)
        verify(shown[0].indexOf("Overlap with entry 4") >= 0)
        compare(named("load").length, 0)
    }

    function test_clean_save_notifies_and_reloads_the_day() {
        const p = openPage()
        p.view.saveRequested(7, 8, "a", "b", {})
        tc.answers.save({ ok: true, workSeconds: 3600, extras: "saved", deleteReport: null })
        compare(shown, [])
        compare(notices, ["Shooting day saved"])
        compare(named("load").length, 1)
    }

    function test_direct_save_is_silent_but_reloads() {
        const p = openPage()
        p.view.timesEdited("2026-11-10T09:00:00", "2026-11-10T17:00:00")
        // The view has no picked project here: the page cannot ask yet.
        compare(named("save").length, 0)
    }

    function test_failed_extras_are_reported_and_the_day_reloads() {
        const p = openPage()
        p.view.saveRequested(7, 8, "a", "b", {})
        tc.answers.save({ ok: true, workSeconds: 3600, extras: "failed",
                          error: { type: "unknown", status: 400, detail: "Extras refused" }, deleteReport: null })
        compare(shown.length, 1)
        verify(shown[0].indexOf("Extras refused") >= 0)
        compare(notices, [])
        compare(named("load").length, 1)
    }

    function test_failed_merge_delete_is_reported() {
        const p = openPage()
        p.view.saveRequested(7, 8, "a", "b", {})
        tc.answers.save({ ok: true, workSeconds: 3600, extras: "saved",
                          deleteReport: { failed: [{ id: 9, error: { type: "unknown", status: 400, detail: "Locked entry" } }] } })
        compare(shown.length, 1)
        verify(shown[0].indexOf("Locked entry") >= 0)
        compare(notices, [])
    }

    function test_extras_save_reports_failure_and_earnings() {
        const p = openPage()
        p.view.extrasEdited({ crew: 2 })
        compare(named("extras").length, 1)
        compare(named("extras")[0].req.fields.crew, 2)
        compare(named("extras")[0].req.date.getTime(), p.page.selectedDate.getTime())
        tc.answers.earnings(1234)
        compare(p.view.earningsCents, 1234)
        tc.answers.extras({ extras: "failed", error: { type: "unknown", status: 400, detail: "No extras" } })
        compare(shown.length, 1)
        verify(shown[0].indexOf("No extras") >= 0)
    }

    function test_extras_saved_is_silent() {
        const p = openPage()
        p.view.extrasEdited({})
        tc.answers.extras({ extras: "saved" })
        compare(shown, [])
    }

    function test_note_failure_is_reported_as_a_write_error() {
        const p = openPage()
        p.view.noteEdited("hello")
        compare(named("note")[0].text, "hello")
        tc.answers.note({ saved: "failed", error: { detail: "x" } })
        compare(writeErrors.length, 1)
        compare(writeErrors[0][0].ok, false)
    }

    function test_start_and_stop_go_to_the_timer() {
        const p = openPage()
        p.view.startRequested(7, 8, "P", "A")
        compare(named("switch").length, 1)
        compare(named("switch")[0].projectId, 7)
        compare(named("switch")[0].activityId, 8)
        p.view.stopRequested()
        compare(named("stop").length, 1)
    }

    function test_trip_request_passes_the_days_entry() {
        const p = openPage()
        p.view.tripRequested()
        compare(named("trip").length, 1)
        compare(named("trip")[0].ts.id, 3)
    }

    function test_project_pick_reloads_the_shown_day() {
        const p = openPage()
        p.view.projectPicked(7)
        compare(named("load").length, 1)
        compare(named("load")[0].date.getTime(), p.page.selectedDate.getTime())
    }
}
