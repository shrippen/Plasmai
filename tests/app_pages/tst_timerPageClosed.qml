import QtQuick
import QtTest
import "../qml"

/** TimerPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "TimerPageClosed"
    when: windowShown
    width: 400
    height: 400

    property var pending: []

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property int visualStyle: 0
            property QtObject session: QtObject {
                property var catalog: QtObject {
                    property var projectPickerModel: []
                    property var activities: []
                    property var activitiesByProject: ({})
                    property var projects: []
                    property var customers: []
                    property var customersById: ({})
                    function loadActivities(projectId, cb) { tc.pending.push(function() { cb([]) }) }
                }
                property var connection: QtObject {
                    property bool configured: true
                    property string state: "ok"
                    property string errorText: ""
                    property var profiles: []
                    property var profile: null
                    property var capabilities: ({})
                }
                property var timer: QtObject {
                    property bool tracking: true
                    property var active: ({ id: 5, project: { id: 1 } })
                    property int elapsedSeconds: 0
                    property bool hasLastUsed: false
                    property bool savingDescription: false
                    property string description: ""
                    property string project: ""
                    property string customer: ""
                    property var draft: ({})
                    property var colorInfo: ({ color: "#000" })
                    property string hintKey: ""
                }
                property var entries: QtObject { property bool canCreate: true }
                property var recent: QtObject { property var list: []; property var last: null }
                property var totals: QtObject {
                    property bool hasWorkContract: false
                    property int remainingTodaySeconds: 0
                    property int remainingWeekSeconds: 0
                    property int todayTargetSeconds: 0
                    property int weekEffectiveTargetSeconds: 0
                    property int todayLiveSeconds: 0
                    property int weekLiveSeconds: 0
                    property var todayEntries: []
                }
                property var settings: QtObject {
                    property bool confirmStartBeforePreviousEnd: false
                    property bool confirmBeforeStop: false
                    property int workDayBegin: 0
                    property int workDayEnd: 0
                }
                property var favorites: QtObject { property var pinned: []; function isPinned() { return false } }
                property var filmDay: QtObject { property bool available: false }
                property var sync: QtObject { property bool offline: false; function isUnsynced() { return false } }
                property var reminders: QtObject { property bool idlePending: false; property int pendingMs: 0 }
                property var trips: QtObject { property bool canEdit: false }
                property var setup: QtObject { property bool showWizard: false }
            }
            function showPassiveNotification() {}
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { TimerPage { } }
        }
    }

    function init() {
        pending = []
    }

    function findView(item, signalName) {
        if (typeof item[signalName] === "function") {
            return item
        }
        for (const child of item.children) {
            const found = findView(child, signalName)
            if (found) {
                return found
            }
        }
        return null
    }

    /** Opens the page, lets `open` start a request, destroys it, calls the stored answer; returns what it threw. */
    function lateAnswers(open) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        pending = []
        open(obj)
        compare(pending.length, 1)
        obj.destroy()
        wait(0)

        const thrown = []
        for (const cb of pending.splice(0)) {
            try { cb() } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_edit_activities_answer_does_not_throw() {
        compare(lateAnswers(function(p) { p.openEdit() }), [])
    }

    function test_late_project_activities_answer_does_not_throw() {
        compare(lateAnswers(function(p) {
            p.openEdit()
            wait(0)
            pending = []
            const view = findView(p, "projectChosen")
            verify(view !== null)
            view.projectChosen(7)
        }), [])
    }

    function test_late_new_activity_answer_does_not_throw() {
        compare(lateAnswers(function(p) {
            p.showNewActivityForm = true
            const view = findView(p, "projectActivated")
            verify(view !== null)
            view.projectActivated(-1)
        }), [])
    }
}
