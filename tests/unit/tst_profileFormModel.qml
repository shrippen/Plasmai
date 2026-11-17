import QtQuick
import QtTest
import "../../contents/ui" as Ui

/** The profile list of the Connection form (contents/ui/ProfileFormModel.qml) without a page. */
TestCase {
    id: tc
    name: "ProfileFormModel"

    property int edits: 0
    property int resets: 0
    property int urlResets: 0
    property int switched: 0

    QtObject {
        id: fakeSession
        property var setup: QtObject {
            function providerMeta(id) { return { defaultUrl: id === "toggl" ? "https://api.toggl.test" : "" } }
        }
    }

    Component {
        id: formComponent
        Ui.ProfileFormModel {
            session: fakeSession
            providers: [{ id: "kimai", name: "Kimai" }, { id: "toggl", name: "Toggl" }]
            profiles: [
                { id: "a", name: "A", url: "https://a.example", provider: "kimai" },
                { id: "b", name: "B", url: "https://b.example", provider: "toggl", workspaceId: "w" }
            ]
            onEdited: tc.edits++
            onFieldsReset: { tc.resets++; tc.insideReset = updatingFields }
            onUrlReset: tc.urlResets++
            onProviderSwitched: tc.switched++
        }
    }

    property bool insideReset: false

    function init() {
        edits = 0
        resets = 0
        urlResets = 0
        switched = 0
    }

    function make() {
        const f = createTemporaryObject(formComponent, tc)
        verify(f)
        return f
    }

    function test_ensureSelectionPicksActive() {
        const f = make()
        f.ensureSelection("b", "")
        compare(f.selectedIndex, 1)
        compare(f.selectedProviderIndex, 1)
        compare(resets, 1)
        verify(insideReset)
        verify(!f.updatingFields)
    }

    function test_ensureSelectionFillsEmptyList() {
        const f = make()
        f.profiles = []
        f.ensureSelection("default", "https://x.example/")
        compare(f.profiles.length, 1)
        compare(f.profiles[0].url, "https://x.example")
        compare(edits, 1)
    }

    function test_updateSelectedIsBlockedWhileUpdatingFields() {
        const f = make()
        f.updatingFields = true
        f.updateSelected("url", "https://z.example")
        compare(f.profiles[0].url, "https://a.example")
        compare(edits, 0)
        f.updatingFields = false
        f.updateSelected("url", "https://z.example")
        compare(f.profiles[0].url, "https://z.example")
        compare(edits, 1)
    }

    function test_renameRefusesATakenName() {
        const f = make()
        verify(!f.rename(" B "))
        compare(f.profiles[0].name, "A")
        verify(f.rename("C"))
        compare(f.profiles[0].name, "C")
    }

    function test_changeProviderTakesDefaultUrlAndForgetsIds() {
        const f = make()
        f.select(1)
        f.changeProvider("kimai")
        compare(f.profiles[1].provider, "kimai")
        compare(f.profiles[1].url, "")
        compare(f.profiles[1].workspaceId, "")
        compare(urlResets, 1)
        compare(switched, 1)
        f.changeProvider("toggl")
        compare(f.profiles[1].url, "https://api.toggl.test")
    }

    function test_commitUrlNormalizesAndResetsField() {
        const f = make()
        f.commitUrl("https://n.example/")
        compare(f.profiles[0].url, "https://n.example")
        compare(urlResets, 1)
        f.commitUrl("https://m.example")
        compare(urlResets, 1)
    }

    function test_activateReturnsSelectedId() {
        const f = make()
        f.select(1)
        compare(f.activate("https://b.example/"), "b")
        compare(f.profiles[1].url, "https://b.example")
    }

    function test_addSelectsNewProfile() {
        const f = make()
        f.add(function(n) { return "Profile " + n })
        compare(f.profiles.length, 3)
        compare(f.selectedIndex, 2)
        compare(f.profiles[2].name, "Profile 3")
        compare(resets, 1)
    }

    function test_removeReportsActiveRemoved() {
        const f = make()
        f.select(1)
        verify(f.removeSelected("b"))
        compare(f.profiles.length, 1)
        compare(f.selectedIndex, 0)
        // The last profile stays.
        verify(!f.removeSelected("a"))
        compare(f.profiles.length, 1)
    }

    function test_removeOfAnotherProfileKeepsActive() {
        const f = make()
        verify(!f.removeSelected("b"))
        compare(f.profiles[0].id, "b")
    }

    function test_applyTestedSetsIdsOnTheTestedProfile() {
        const f = make()
        f.applyTested("b", { workspaceId: "w2" })
        compare(f.profiles[1].workspaceId, "w2")
        compare(edits, 1)
    }

    function test_applyTestedKeepsProfilesAddedMeanwhile() {
        const f = make()
        // The test of "a" runs; the user adds a profile; the answer comes.
        f.add(function(n) { return "Profile " + n })
        f.applyTested("a", { workspaceId: "w1" })
        compare(f.profiles.length, 3)
        compare(f.profiles[0].workspaceId, "w1")
        compare(f.selectedIndex, 2)
        compare(f.profiles[2].name, "Profile 3")
    }

    function test_applyTestedOfARemovedProfileDoesNothing() {
        const f = make()
        f.removeSelected("zzz")
        edits = 0
        f.applyTested("a", { workspaceId: "w1" })
        compare(f.profiles.length, 1)
        compare(edits, 0)
    }
}
