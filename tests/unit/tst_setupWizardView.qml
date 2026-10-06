import QtQuick
import QtTest
import "../../contents/ui" as Shared
import "../../contents/code/platform.js" as Platform
import "../../contents/code/kimaiApi.js" as KimaiApi

/**
 * SetupWizard.qml driven like a person would: system check, service, a
 * connection against a fake Kimai, the token store, the Day step. Platform
 * and network are fakes; nothing leaves the test.
 */
TestCase {
    name: "SetupWizardView"
    when: windowShown

    property var systemCheck: ({})
    property bool storeWorks: true
    property var storedTokens: ({})
    property var responses: []
    property var requests: []

    Component {
        id: wizardComponent
        Shared.SetupWizard {
            width: 400
        }
    }

    SignalSpy {
        id: connectedSpy
        signalName: "connected"
    }

    SignalSpy {
        id: finishedSpy
        signalName: "finished"
    }

    function fakeBackend() {
        return {
            checkSystem: function(ds, cb) { cb(systemCheck) },
            saveToken: function(ds, id, token, cb) {
                if (!storeWorks) {
                    cb(false, "No secure storage for the token: unavailable")
                    return
                }
                storedTokens[id] = token
                cb(true, null)
            }
        }
    }

    // One queued answer per request: { status, body }.
    function fakeXhr() {
        var xhr = {
            readyState: 0, status: 0, statusText: "", responseText: "", url: "", headers: {},
            onreadystatechange: null, onerror: null,
            open: function(method, url) { xhr.url = url },
            setRequestHeader: function(name, value) { xhr.headers[name] = value },
            getResponseHeader: function() { return null },
            abort: function() {},
            send: function() {
                requests.push(xhr)
                var next = responses.shift()
                if (!next) {
                    return
                }
                xhr.status = next.status
                xhr.responseText = JSON.stringify(next.body)
                xhr.readyState = 4
                xhr.onreadystatechange()
            }
        }
        return xhr
    }

    function init() {
        systemCheck = {}
        storeWorks = true
        storedTokens = {}
        responses = []
        requests = []
        Platform.setBackend(fakeBackend())
        KimaiApi.setRequestFactory(fakeXhr)
        connectedSpy.clear()
        finishedSpy.clear()
    }

    function cleanup() {
        KimaiApi.setRequestFactory(null)
    }

    function makeWizard() {
        var w = createTemporaryObject(wizardComponent, this)
        connectedSpy.target = w
        finishedSpy.target = w
        tryCompare(w, "checking", false)
        return w
    }

    function field(w, name) {
        var f = findChild(w, name)
        verify(f, name)
        return f
    }

    function test_noSystemStepWithoutFindings() {
        var w = makeWizard()
        compare(w.stepList, ["service", "access", "day"])
        compare(w.step, "service")
        compare(w.providerId, "kimai")
    }

    function test_connectKimaiAndFinish() {
        var w = makeWizard()
        w.stepIndex = 1
        compare(w.step, "access")
        field(w, "setupUrlField").text = "kimai.example.com/de/timesheet/"
        field(w, "setupTokenField").text = "Bearer abc123\n"
        responses = [
            { status: 200, body: { version: "2.67.0" } },
            { status: 200, body: { alias: "Anna B.", username: "anna" } }
        ]
        w.connect()
        tryCompare(w, "step", "day")

        compare(requests[0].url, "https://kimai.example.com/api/version")
        compare(requests[0].headers["Authorization"], "Bearer abc123")
        compare(storedTokens["default"], "abc123")
        compare(w.accountLabel, "Anna B.")

        compare(connectedSpy.count, 1)
        var patch = connectedSpy.signalArguments[0][0]
        compare(patch.activeProfileId, "default")
        compare(patch.kimaiUrl, "https://kimai.example.com")
        var profiles = JSON.parse(patch.profilesJson)
        compare(profiles[0].provider, "kimai")
        compare(profiles[0].name, "Kimai")
        compare(profiles[0].url, "https://kimai.example.com")

        field(w, "setupBeginField").setTime(7, 30)
        field(w, "setupEndField").setTime(16, 0)
        w.finish()
        compare(finishedSpy.count, 1)
        var day = finishedSpy.signalArguments[0][0]
        compare(day.workDayBegin, "07:30")
        compare(day.workDayEnd, "16:00")
        compare(day.notifyForgotToStart, false)
        verify(day.latitude === undefined)
    }

    function test_failedTestStoresNothing() {
        var w = makeWizard()
        w.stepIndex = 1
        field(w, "setupUrlField").text = "https://kimai.example.com"
        field(w, "setupTokenField").text = "wrong"
        responses = [{ status: 401, body: { message: "Unauthorized" } }]
        w.connect()
        tryCompare(w, "busy", false)
        compare(w.step, "access")
        verify(w.errorText.length > 0)
        compare(Object.keys(storedTokens).length, 0)
        compare(connectedSpy.count, 0)
    }

    function test_missingInput() {
        var w = makeWizard()
        w.stepIndex = 1
        w.connect()
        verify(w.errorText.length > 0)
        compare(requests.length, 0)
        field(w, "setupUrlField").text = "https://kimai.example.com"
        w.connect()
        verify(w.errorText.length > 0)
        compare(requests.length, 0)
    }

    function test_storeFailureIsReported() {
        storeWorks = false
        var w = makeWizard()
        w.stepIndex = 1
        field(w, "setupUrlField").text = "https://kimai.example.com"
        field(w, "setupTokenField").text = "abc"
        responses = [{ status: 200, body: { version: "2.67.0" } }]
        w.connect()
        tryCompare(w, "busy", false)
        compare(w.step, "access")
        verify(w.errorText.indexOf("unavailable") >= 0)
        compare(connectedSpy.count, 0)
    }

    function test_systemStepUntilFixed() {
        systemCheck = { secretTool: false, secretService: "unknown", notifySend: true, osId: "debian", osLike: "" }
        var w = makeWizard()
        compare(w.step, "system")
        compare(w.blockingIssue.command, "sudo apt install libsecret-tools")

        systemCheck = { secretTool: true, secretService: "yes", notifySend: true, osId: "debian", osLike: "" }
        w.checkSystem()
        tryCompare(w, "checking", false)
        compare(w.blockingIssue, null)
        // The step stays, so Next leads on to the service.
        compare(w.stepList, ["system", "service", "access", "day"])
        w.stepIndex++
        compare(w.step, "service")
    }

    function test_skip() {
        var w = makeWizard()
        w.finished({})
        compare(finishedSpy.count, 1)
        compare(Object.keys(finishedSpy.signalArguments[0][0]).length, 0)
    }

    function test_cloudServiceUsesDefaultAddress() {
        var w = makeWizard()
        w.providerId = "toggl"
        compare(w.showUrlField, false)
        compare(w.urlCheck.url, "https://api.track.toggl.com/api/v9")
    }
}
