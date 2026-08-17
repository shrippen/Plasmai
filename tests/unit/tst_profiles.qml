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
}
