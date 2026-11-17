import QtQuick
import QtTest
import "../qml"

/** ConnectionPage (app/qml): an answer that arrives after the page is gone touches nothing. */
TestCase {
    id: tc
    name: "ConnectionPageClosed"
    when: windowShown
    width: 400
    height: 400

    property var pending: []
    property var rejected: []
    property var testHandlers: null
    property int opened: 0

    /** A promise whose answers the test delivers by hand. */
    function thenable() {
        const p = {}
        p.then = function(cb) { tc.pending.push(cb); return p }
        p.catch = function(cb) { tc.rejected.push(cb); return p }
        return p
    }

    // Stands in for `root` of main.qml: the page reads root.session.
    Component {
        id: host
        Item {
            id: root
            property int visualStyle: 0
            // The button handlers format their status texts.
            function i18n(text) { return text }
            property QtObject session: QtObject {
                property var connection: QtObject {
                    function hasToken() { return tc.thenable() }
                    function loadStored() { return tc.thenable() }
                    function saveToken() { return tc.thenable() }
                    function clearToken() { return tc.thenable() }
                    function saveProfiles() {}
                    function test(profile, handlers) { tc.testHandlers = handlers }
                }
                property var setup: QtObject {
                    function listProviders() { return [{ id: "kimai", name: "Kimai", defaultUrl: "" }] }
                    function providerMeta() { return { defaultUrl: "" } }
                    function providerName() { return "Kimai" }
                }
                property var sync: QtObject { property bool offline: false }
                function open() { tc.opened++ }
            }
            // Created here: the page finds `root` in its creation context.
            property Component pageComponent: Component { ConnectionPage { } }
        }
    }

    function init() {
        pending = []
        rejected = []
        testHandlers = null
        opened = 0
    }

    /** The button of the page with this icon. */
    function findButton(item, iconName) {
        if (item.icon !== undefined && item.icon.name === iconName && typeof item.clicked === "function") {
            return item
        }
        for (const child of item.children) {
            const found = findButton(child, iconName)
            if (found) {
                return found
            }
        }
        return null
    }

    /** Opens the page with a profile, lets `open` start a request, destroys the page. */
    function closedPage(open) {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        obj.profiles = [{ id: "p1", name: "One", url: "https://x", provider: "kimai" }]
        obj.selectedIndex = 0
        pending = []
        rejected = []
        open(obj)
        obj.destroy()
        wait(0)
    }

    function thrownBy(callbacks, arg) {
        const thrown = []
        for (const cb of callbacks) {
            try { cb(arg) } catch (e) { thrown.push(String(e)) }
        }
        return thrown
    }

    function test_late_token_check_does_not_throw() {
        closedPage(function(p) { p.checkStoredToken() })
        compare(pending.length, 1)
        compare(thrownBy(pending, true), [])
    }

    function test_late_stored_state_does_not_throw() {
        closedPage(function(p) { p.loadSharedState() })
        verify(pending.length > 0)
        compare(thrownBy(pending, { kimaiUrl: "https://x", profilesJson: "", activeProfileId: "p1" }), [])
    }

    function test_late_save_token_does_not_throw() {
        closedPage(function(p) {
            findButton(p, "document-save").clicked()
            compare(pending.length, 1)
        })
        compare(thrownBy(pending), [])
    }

    function test_late_save_token_still_applies() {
        closedPage(function(p) { findButton(p, "document-save").clicked() })
        thrownBy(pending)
        compare(opened, 1)
    }

    function test_late_save_token_failure_does_not_throw() {
        closedPage(function(p) { findButton(p, "document-save").clicked() })
        compare(thrownBy(rejected, "x"), [])
    }

    function test_late_clear_token_does_not_throw() {
        closedPage(function(p) { findButton(p, "edit-delete").clicked() })
        compare(pending.length, 1)
        compare(thrownBy(pending), [])
    }

    function test_late_clear_token_still_applies() {
        closedPage(function(p) { findButton(p, "edit-delete").clicked() })
        thrownBy(pending)
        compare(opened, 1)
    }

    function test_late_clear_token_failure_does_not_throw() {
        closedPage(function(p) { findButton(p, "edit-delete").clicked() })
        compare(thrownBy(rejected, "x"), [])
    }

    function test_late_test_answers_do_not_throw() {
        closedPage(function(p) { findButton(p, "network-connect").clicked() })
        verify(testHandlers !== null)
        const calls = [
            function() { testHandlers.noToken() },
            function() { testHandlers.testing("https://x") },
            function() { testHandlers.done({ ok: true }) },
            function() { testHandlers.done({ ok: false, error: {} }) },
            function() { testHandlers.failed("x") }
        ]
        compare(thrownBy(calls), [])
    }

    /** The ids of workspace and user, which Clockify, Toggl and SolidTime need, survive the test. */
    function test_test_keeps_workspace_ids() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        obj.profiles = [{ id: "p1", name: "One", url: "https://x", provider: "clockify" }]
        obj.selectedIndex = 0
        findButton(obj, "network-connect").clicked()
        verify(testHandlers !== null)
        // The status text throws here (ApiErrors has no i18n in tests), after the profiles are taken.
        thrownBy([function() { testHandlers.done({ ok: true, data: { workspaceId: "w1", userId: "u1" } }) }])
        compare(obj.profiles[0].workspaceId, "w1")
        compare(obj.profiles[0].userId, "u1")
        compare(obj.profiles[0].id, "p1")
        obj.destroy()
    }

    /** A profile added while the test runs stays; the ids go to the tested one. */
    function test_test_answer_keeps_profile_added_meanwhile() {
        const h = createTemporaryObject(host, tc)
        const obj = h.pageComponent.createObject(h)
        verify(obj !== null)
        obj.profiles = [{ id: "p1", name: "One", url: "https://x", provider: "clockify" }]
        obj.selectedIndex = 0
        findButton(obj, "network-connect").clicked()
        verify(testHandlers !== null)
        obj.profiles = obj.profiles.concat([{ id: "p2", name: "Two", url: "https://y", provider: "kimai" }])
        obj.selectedIndex = 1
        thrownBy([function() { testHandlers.done({ ok: true, data: { workspaceId: "w1" } }) }])
        compare(obj.profiles.length, 2)
        compare(obj.profiles[0].workspaceId, "w1")
        compare(obj.selectedIndex, 1)
        obj.destroy()
    }
}
