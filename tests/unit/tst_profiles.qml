import QtQuick
import QtTest
import "../../contents/code/profiles.js" as Profiles

TestCase {
    name: "Profiles"

    function test_defaultWhenEmpty() {
        var list = Profiles.parseProfiles("", "")
        compare(list.length, 1)
        compare(list[0].id, "default")
        compare(list[0].provider, "kimai")
    }

    function test_legacyUrl() {
        var list = Profiles.parseProfiles("", "https://ki.example/")
        compare(list[0].url, "https://ki.example/")
        compare(list[0].id, "default")
    }

    function test_parseJson() {
        var json = '[{"id":"p1","name":"Work","url":"https://a.example","provider":"clockify"}]'
        var list = Profiles.parseProfiles(json, "")
        compare(list.length, 1)
        compare(list[0].id, "p1")
        compare(list[0].provider, "clockify")
        compare(list[0].name, "Work")
    }

    function test_invalidJsonFallsBack() {
        var list = Profiles.parseProfiles("{not json", "https://legacy")
        compare(list[0].url, "https://legacy")
    }

    function test_profileById() {
        var list = Profiles.parseProfiles('[{"id":"a"},{"id":"b"}]', "")
        compare(Profiles.profileById(list, "b").id, "b")
        compare(Profiles.profileById(list, "missing").id, "a")
        compare(Profiles.profileById([], "x"), null)
    }

    function test_accountForProfile() {
        compare(Profiles.accountForProfile("default"), "api-token")
        compare(Profiles.accountForProfile(""), "api-token")
        compare(Profiles.accountForProfile("p1"), "api-token:p1")
    }

    function test_serializeRoundTrip() {
        var list = Profiles.parseProfiles('[{"id":"x","name":"X","url":"https://u","provider":"kimai"}]', "")
        var again = Profiles.parseProfiles(Profiles.serializeProfiles(list), "")
        compare(again[0].id, "x")
        compare(again[0].url, "https://u")
    }

    function test_showsConnection() {
        var one = Profiles.parseProfiles('[{"id":"a"}]', "")
        var two = Profiles.parseProfiles('[{"id":"a"},{"id":"b"}]', "")
        verify(!Profiles.showsConnection(one, true, "online"))
        verify(Profiles.showsConnection(two, true, "online"))
        verify(Profiles.showsConnection(one, false, "online"))
        verify(Profiles.showsConnection(one, true, "error"))
        verify(Profiles.showsConnection(one, true, "connecting"))
        verify(Profiles.showsConnection(one, true, "offline"))
    }

    function test_withDemoProfile() {
        // The untouched default profile (no URL) makes way for the demo.
        var list = Profiles.withDemoProfile(Profiles.defaultProfiles(), "https://demo.invalid", "Demo")
        compare(list.length, 1)
        compare(list[0].id, "demo")
        compare(list[0].url, "https://demo.invalid")
        // Real profiles stay; the demo is added once.
        var real = Profiles.parseProfiles('[{"id":"a","url":"https://kimai.example"}]', "")
        var both = Profiles.withDemoProfile(real, "https://demo.invalid", "Demo")
        compare(both.length, 2)
        compare(Profiles.withDemoProfile(both, "https://demo.invalid", "Demo").length, 2)
    }

    function test_activeIndex() {
        var list = Profiles.parseProfiles('[{"id":"a"},{"id":"b"}]', "")
        compare(Profiles.activeIndex(list, "b"), 1)
        compare(Profiles.activeIndex(list, "missing"), 0)
        compare(Profiles.activeIndex([], "a"), 0)
    }

    function test_withField() {
        var list = Profiles.parseProfiles('[{"id":"a","name":"A"},{"id":"b","name":"B"}]', "")
        var out = Profiles.withField(list, 1, "name", "New")
        compare(out[1].name, "New")
        compare(out[0].name, "A")
        // The input stays untouched.
        compare(list[1].name, "B")
        compare(Profiles.withField(list, 5, "name", "x").length, 2)
        compare(Profiles.withField(list, -1, "name", "x")[0].name, "A")
    }

    function test_withProvider() {
        var json = '[{"id":"a","provider":"kimai","url":"https://k","workspaceId":"w","userId":"u","organizationId":"o","memberId":"m"}]'
        var list = Profiles.parseProfiles(json, "")
        var out = Profiles.withProvider(list, 0, "toggl", "https://api.toggl.test")
        compare(out[0].provider, "toggl")
        compare(out[0].url, "https://api.toggl.test")
        compare(out[0].workspaceId, "")
        compare(out[0].userId, "")
        compare(out[0].organizationId, "")
        compare(out[0].memberId, "")
        compare(out[0].id, "a")
        compare(list[0].provider, "kimai")
        compare(Profiles.withProvider(list, 3, "toggl", "").length, 1)
    }

    // Picking the service a profile already has (ComboBox.activated fires for it too) keeps its address and ids.
    function test_withSameProviderKeepsProfile() {
        const json = '[{"id":"a","provider":"kimai","url":"https://k","workspaceId":"w","userId":"u","organizationId":"o","memberId":"m"}]'
        const list = Profiles.parseProfiles(json, "")
        const out = Profiles.withProvider(list, 0, "kimai", "")
        compare(out[0].url, "https://k")
        compare(out[0].workspaceId, "w")
        compare(out[0].memberId, "m")
    }

    function test_withNewProfile() {
        var list = Profiles.parseProfiles('[{"id":"a","name":"Profile 2"}]', "")
        var out = Profiles.withNewProfile(list, function(n) { return "Profile " + n })
        compare(out.length, 2)
        // "Profile 2" is taken: the count is 2, so the next free number is 3.
        compare(out[1].name, "Profile 3")
        compare(out[1].provider, "kimai")
        compare(out[1].url, "")
        verify(out[1].id !== "a")
        compare(list.length, 1)
    }

    function test_withoutProfile() {
        var list = Profiles.parseProfiles('[{"id":"a"},{"id":"b"}]', "")
        var out = Profiles.withoutProfile(list, 0)
        compare(out.length, 1)
        compare(out[0].id, "b")
        compare(list.length, 2)
        // The last profile cannot go.
        compare(Profiles.withoutProfile(out, 0).length, 1)
        compare(Profiles.withoutProfile(list, 7).length, 2)
    }

    function test_ensured() {
        var out = Profiles.ensured([], "https://k.example")
        compare(out.length, 1)
        compare(out[0].id, "default")
        compare(out[0].url, "https://k.example")
        compare(Profiles.ensured([], "")[0].url, "")
        var one = [{ id: "x" }]
        compare(Profiles.ensured(one, "https://k.example"), one)
    }
}
