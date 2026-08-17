import QtQuick
import QtTest
import "../../contents/code/maintenanceCache.js" as Cache

TestCase {
    name: "MaintenanceCache"

    function init() {
        Cache.clear()
    }

    function test_fingerprintIgnoresWhitespaceAndHash() {
        var a = Cache.entityFingerprint(
            [{ id: 1, color: " #AABBCC " }],
            [{ id: 2, color: "aabbcc" }],
            []
        )
        var b = Cache.entityFingerprint(
            [{ id: 1, color: "#aabbcc" }],
            [{ id: 2, color: "#AABBCC" }],
            []
        )
        compare(a, b)
    }

    function test_fingerprintOrderIndependent() {
        var a = Cache.entityFingerprint(
            [{ id: 2, color: "#111111" }, { id: 1, color: "#000000" }], [], [])
        var b = Cache.entityFingerprint(
            [{ id: 1, color: "#000000" }, { id: 2, color: "#111111" }], [], [])
        compare(a, b)
    }

    function test_storeHydrateHasCatalog() {
        Cache.store("default", {
            customers: [{ id: 1 }],
            projects: [{ id: 2 }],
            activities: [{ id: 3 }],
            customerGroups: [{ entries: [{ shifted: true }] }],
            groupCount: 1,
            shiftedCount: 1,
            settingsKey: "1|22|#a|#b|#c|#d|#e|#f|#g"
        })
        verify(Cache.hasCatalog("default"))
        verify(!Cache.hasCatalog("other"))
        verify(Cache.isFresh("default"))
        var loaded = Cache.load()
        compare(loaded.projects.length, 1)
        compare(loaded.groupCount, 1)
        compare(Cache.countShifted(loaded.customerGroups), 1)

        Cache.clear()
        verify(!Cache.hasCatalog("default"))
        var payload = {
            profileId: "default",
            customers: [{ id: 1 }],
            projects: [{ id: 9 }],
            activities: [],
            loadedAt: Date.now()
        }
        verify(Cache.hydrate(payload))
        compare(Cache.load().projects[0].id, 9)
    }

    function test_storeEntitiesClearsGroupsWhenIdsChange() {
        Cache.store("default", {
            customers: [{ id: 1, color: "#111" }],
            projects: [{ id: 2, color: "#222" }],
            activities: [],
            customerGroups: [{ entries: [] }],
            groupCount: 1,
            settingsKey: "keep"
        })
        var changed = Cache.storeEntities("default",
            [{ id: 1, color: "#111" }],
            [{ id: 99, color: "#222" }],
            [])
        verify(changed)
        compare(Cache.load().groupCount, 0)
        compare(Cache.load().settingsKey, "")
    }

    function test_exportPayloadRoundTrip() {
        Cache.store("p", { customers: [{ id: 1 }], projects: [], activities: [] })
        var dumped = Cache.exportPayload()
        Cache.clear()
        Cache.hydrate(dumped)
        verify(Cache.hasCatalog("p"))
    }
}
