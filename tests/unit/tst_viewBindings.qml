import QtQuick
import QtTest
import "../../contents/ui"

/**
 * FilmDayBinding and TripSheetBinding with stand-in views and a recording session:
 * what a view signal asks of the session and which signals the host gets back.
 * The words of the messages need i18n, which tests run without; the app page
 * tests (tests/app_pages) cover them with a stub.
 */
TestCase {
    id: tc
    name: "ViewBindings"

    property var calls: []

    Component {
        id: sessionFixture
        QtObject {
            property var catalog: QtObject { property var projectPickerModel: [1] }
            property var connection: QtObject { property bool configured: true }
            property var entries: QtObject { property bool canCreate: true }
            property var sync: QtObject { property bool offline: true }
            property var setup: QtObject { }
            property var timer: QtObject {
                function switchTo(project, activity, projectLabel, activityLabel, note) {
                    tc.calls.push(["switch", project, activity, note])
                }
                function stop() { tc.calls.push(["stop"]) }
            }
            property var trips: QtObject {
                property bool canEdit: true
                property var ping: ({ marker: "ping" })
                property var meta: ({ marker: "meta" })
                property var vehicles: [1, 2]
                function save(body, id, form, suggestion, cb) { tc.calls.push(["tripSave", body, id, suggestion, cb]) }
                function remove(id, cb) { tc.calls.push(["tripRemove", id, cb]) }
            }
            property var filmDay: QtObject {
                function loadDay(date, projectId, prefer, onDay, onProduction) {
                    tc.calls.push(["load", date, projectId, prefer])
                }
                function saveDay(req, cb) { tc.calls.push(["save", req, cb]) }
                function saveNote(text, cb) { tc.calls.push(["note", text, cb]) }
            }
            property bool busy: false
        }
    }

    Component {
        id: filmViewFixture
        Item {
            property var projectPickerModel: []
            property bool configured: false
            property bool showCreateActions: false
            property bool tripsAvailable: false
            property bool onlineActions: false
            property var projectCombo: ({ currentIndex: 0, currentItem: { value: { id: 7 } } })
            property var activityCombo: ({ currentIndex: 0, currentItem: { value: { id: 8 } } })
            property bool mergeOthers: false
            property bool extrasVisible: false
            property int effectiveBreakMinutes: 0
            signal projectPicked(var projectId)
            signal dayStepRequested(int deltaDays)
            signal dayChosen(var date)
            signal saveRequested(var projectId, var activityId, string beginText, string endText, var filmDayFields)
            signal timesEdited(string beginText, string endText)
            signal extrasEdited(var filmDayFields)
            signal engagementPicked(var projectId)
            signal noteEdited(string text)
            signal startRequested(var projectId, var activityId, string projectLabel, string activityLabel)
            signal stopRequested()
            function noteText() { return "typed" }
            function otherEntryIds() { return [] }
            function currentEntryFields() { return { crew: 1 } }
        }
    }

    Component {
        id: tripViewFixture
        Item {
            property bool configured: false
            property var ping: null
            property var meta: null
            property var vehicles: []
            property var places: null
            property var serverErrors: ({})
            property string errorText: ""
            signal saveRequested(var body, var tripId, var form)
            signal deleteRequested(var tripId)
        }
    }

    Component {
        id: filmBindingFixture
        FilmDayBinding { }
    }

    Component {
        id: tripBindingFixture
        TripSheetBinding { }
    }

    Component { id: spyFixture; SignalSpy { } }

    // Made by hand and destroyed in cleanup(): the framework's own cleanup of temporary
    // objects would take the session before its binding, which then reads a session that is gone.
    property var made: []

    function init() {
        calls = []
    }

    function cleanup() {
        for (const o of made.reverse()) {
            o.destroy()
        }
        made = []
        wait(0)
    }

    function make(component, props) {
        const o = component.createObject(tc, props || {})
        made.push(o)
        return o
    }

    function filmBinding(props) {
        const s = make(sessionFixture)
        const v = make(filmViewFixture)
        const b = make(filmBindingFixture, Object.assign({ session: s, view: v }, props || {}))
        return { s: s, v: v, b: b }
    }

    function test_film_view_shows_what_the_session_has() {
        const f = filmBinding()
        compare(f.v.projectPickerModel, [1])
        compare(f.v.configured, true)
        compare(f.v.showCreateActions, true)
        compare(f.v.tripsAvailable, true)
        compare(f.v.onlineActions, false)
    }

    function test_day_step_loads_the_next_day() {
        const f = filmBinding()
        const day = new Date(2026, 10, 30)
        f.b.selectedDate = day
        f.v.dayStepRequested(1)
        compare(calls[0][0], "load")
        compare(calls[0][1].getDate(), 1)
        compare(calls[0][2], 7)
        compare(calls[0][3], false)
        compare(f.b.selectedDate.getMonth(), 11)
    }

    function test_save_form_sends_the_request_and_blocks_while_cannot_save() {
        const f = filmBinding({ canSave: false })
        f.v.saveRequested(7, 8, "b", "e", {})
        compare(calls.length, 0)

        f.b.canSave = true
        const started = createTemporaryObject(spyFixture, tc, { target: f.b, signalName: "saveStarted" })
        f.v.saveRequested(7, 8, "b", "e", { crew: 2 })
        compare(started.count, 1)
        compare(calls[0][0], "save")
        compare(calls[0][1].projectId, 7)
        compare(calls[0][1].direct, false)
        compare(calls[0][1].note, "typed")
    }

    function test_times_edit_is_a_direct_save_of_the_shown_entry() {
        const f = filmBinding()
        f.v.timesEdited("b", "e")
        compare(calls[0][1].projectId, 7)
        compare(calls[0][1].activityId, 8)
        compare(calls[0][1].direct, true)
        compare(calls[0][1].fields.crew, 1)
    }

    function test_refused_save_goes_to_the_host_and_does_not_reload() {
        const f = filmBinding()
        const failed = createTemporaryObject(spyFixture, tc, { target: f.b, signalName: "failed" })
        const saved = createTemporaryObject(spyFixture, tc, { target: f.b, signalName: "saved" })
        f.v.saveRequested(7, 8, "b", "e", {})
        calls[0][2]({ ok: false, error: { detail: "x" } })
        compare(failed.count, 1)
        compare(failed.signalArguments[0][0].detail, "x")
        compare(saved.count, 0)
        compare(calls.length, 1)
    }

    function test_note_failure_reaches_the_host() {
        const f = filmBinding()
        const failed = createTemporaryObject(spyFixture, tc, { target: f.b, signalName: "noteFailed" })
        f.v.noteEdited("n")
        calls[0][2]({ saved: "saved" })
        compare(failed.count, 0)
        calls[0][2]({ saved: "failed", error: { detail: "x" } })
        compare(failed.count, 1)
    }

    function test_start_and_stop_go_to_the_timer() {
        const f = filmBinding()
        f.v.startRequested(7, 8, "P", "A")
        compare(calls[0], ["switch", 7, 8, "typed"])
        f.v.stopRequested()
        compare(calls[1], ["stop"])
    }

    function test_late_answer_after_the_binding_is_gone() {
        const f = filmBinding()
        f.v.saveRequested(7, 8, "b", "e", {})
        const answer = calls[0][2]
        f.b.destroy()
        made.splice(made.indexOf(f.b), 1)
        wait(0)
        answer({ ok: false, error: { detail: "x" } })
        compare(calls.length, 1)
    }

    function tripBinding(props) {
        const s = make(sessionFixture)
        const v = make(tripViewFixture)
        const b = make(tripBindingFixture, Object.assign({ session: s, view: v }, props || {}))
        return { s: s, v: v, b: b }
    }

    function test_trip_form_shows_what_the_session_has() {
        const t = tripBinding()
        compare(t.v.ping.marker, "ping")
        compare(t.v.meta.marker, "meta")
        compare(t.v.vehicles, [1, 2])
        compare(t.v.configured, true)
        verify(t.v.places === t.s.setup)
    }

    function test_trip_save_passes_the_suggestion_and_reports_done() {
        const t = tripBinding({ suggestion: { id: 5 } })
        const done = createTemporaryObject(spyFixture, tc, { target: t.b, signalName: "done" })
        t.v.saveRequested({ km: 3 }, 9, { f: 1 })
        compare(calls[0][0], "tripSave")
        compare(calls[0][2], 9)
        compare(calls[0][3].id, 5)
        calls[0][4]({ ok: true, data: { id: 9 } })
        compare(done.count, 1)
        compare(done.signalArguments[0][0].id, 9)
    }

    function test_trip_delete_reports_done_without_a_trip() {
        const t = tripBinding()
        const done = createTemporaryObject(spyFixture, tc, { target: t.b, signalName: "done" })
        t.v.deleteRequested(4)
        compare(calls[0][1], 4)
        calls[0][2]({ ok: true })
        compare(done.count, 1)
        verify(!done.signalArguments[0][0])
    }

    function test_trip_failure_lands_on_the_form() {
        const t = tripBinding()
        const done = createTemporaryObject(spyFixture, tc, { target: t.b, signalName: "done" })
        t.v.saveRequested({ km: 3 }, null, {})
        calls[0][4]({ ok: false, error: { type: "unknown", status: 400, detail: "Locked", fields: { km: "bad" } } })
        compare(t.v.errorText, "Locked")
        compare(t.v.serverErrors.km, "bad")
        compare(done.count, 0)
    }
}
