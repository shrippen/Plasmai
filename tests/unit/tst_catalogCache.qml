import QtQuick
import QtTest
import "../../contents/code/catalogCache.js" as Cache

TestCase {
    name: "CatalogCache"

    function init() {
        Cache.clear()
    }

    function test_storeHydrateHasCatalog() {
        Cache.store("default", {
            customers: [{ id: 1 }],
            projects: [{ id: 2 }],
            activities: [{ id: 3 }]
        })
        verify(Cache.hasCatalog("default"))
        verify(!Cache.hasCatalog("other"))
        verify(Cache.isFresh("default"))
        compare(Cache.load().projects.length, 1)

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

    function test_hydrateKeepsLoadedAt() {
        var old = Date.now() - Cache.FRESH_MS - 1000
        Cache.hydrate({ profileId: "p", customers: [], projects: [{ id: 1 }], activities: [], loadedAt: old })
        verify(Cache.hasCatalog("p"))
        verify(!Cache.isFresh("p"))
    }

    function test_storeEntities() {
        Cache.storeEntities("default", [{ id: 1 }], [{ id: 2 }], [])
        verify(Cache.isFresh("default"))
        compare(Cache.load().customers[0].id, 1)
    }

    function test_exportPayloadRoundTrip() {
        Cache.store("p", { customers: [{ id: 1 }], projects: [], activities: [] })
        var dumped = Cache.exportPayload()
        Cache.clear()
        Cache.hydrate(dumped)
        verify(Cache.hasCatalog("p"))
    }
}
