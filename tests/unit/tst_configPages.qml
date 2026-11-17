import QtQuick
import QtTest
import "../../contents/ui/config" as Config
import "../../contents/code/kimaiApi.js" as KimaiApi
import "../../contents/code/demoKimai.js" as DemoKimai
import "../../contents/code/platform.js" as Platform
import "../../contents/code/profiles.js" as Profiles
import "../../contents/code/sharedConfig.js" as SharedConfig
import "../../contents/code/catalogCache.js" as CatalogCache

/**
 * The settings dialog's pages on the session layer: each loads without a
 * QML error, reads shared.json and writes through the layer. Plasma's
 * `plasmoid.configuration` is a plain object here; the platform backend is
 * an in-memory shared.json, token and catalog store; the server is the demo
 * Kimai.
 */
TestCase {
    name: "ConfigPages"
    when: windowShown
    // The pages load only while shown.
    visible: true
    width: 900
    height: 700

    /** What the pages read as plasmoid.configuration (context lookup). */
    property var plasmoid: ({ configuration: {}, userConfiguring: true })

    property var shared: null
    property var tokens: ({})
    property string catalogText: ""

    // Demo Kimai whose next `holdNext` requests wait in `held` until the test runs them.
    property var held: []
    property int holdNext: 0
    // Requests to this path answer 500 instead of reaching the demo.
    property string failPath: ""
    property int delivered: 0
    property int catalogSaves: 0

    function gatedRoute() {
        const test = this
        return {
            handles: DemoKimai.isDemoUrl,
            token: DemoKimai.ROUTE.token,
            request: function() {
                const xhr = DemoKimai.request()
                const send = xhr.send
                xhr.send = function(body) {
                    const answer = xhr.onreadystatechange
                    xhr.onreadystatechange = function() {
                        answer()
                        test.delivered++
                    }
                    if (test.failPath && xhr.url.indexOf(test.failPath) >= 0) {
                        Qt.callLater(function() {
                            xhr.status = 500
                            xhr.readyState = 4
                            xhr.onreadystatechange()
                        })
                        return
                    }
                    if (test.holdNext <= 0) {
                        send(body)
                        return
                    }
                    test.holdNext--
                    test.held = test.held.concat([function() { send(body) }])
                }
                return xhr
            }
        }
    }

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb(tokens[id] || "", null) },
            saveToken: function(_ds, id, token, cb) { tokens[id] = token; cb(true, null) },
            clearToken: function(_ds, id, cb) { delete tokens[id]; cb(true, null) },
            loadCatalogCacheText: function(_ds, cb) { cb(catalogText) },
            loadCatalogCache: function(_ds, cb) { cb(catalogText ? JSON.parse(catalogText) : null) },
            saveCatalogCache: function(_ds, payload, cb) { catalogSaves++; catalogText = JSON.stringify(payload); if (cb) { cb(true) } }
        }
    }

    function demoShared() {
        const list = Profiles.withDemoProfile(Profiles.defaultProfiles(), DemoKimai.DEMO_URL, "Demo")
        const s = { profilesJson: Profiles.serializeProfiles(list), activeProfileId: "demo", pinnedActivities: "" }
        s[SharedConfig.VERSION_KEY] = SharedConfig.SETTINGS_VERSION
        return s
    }

    Component { id: connectionPage; Config.ConfigConnection { width: 900; height: 700 } }
    Component { id: favoritesPage; Config.ConfigFavorites { width: 900; height: 700 } }
    Component { id: behaviorPage; Config.ConfigBehavior { width: 900; height: 700 } }
    Component { id: displayPage; Config.ConfigDisplay { width: 900; height: 700 } }

    function initTestCase() {
        KimaiApi.setUrlRoute(DemoKimai.ROUTE)
    }

    function cleanupTestCase() {
        KimaiApi.setUrlRoute(null)
    }

    function init() {
        failOnWarning(/TypeError|ReferenceError|is not a function|Cannot (read|assign)/)
        DemoKimai.reset()
        CatalogCache.clear()
        shared = demoShared()
        tokens = { demo: DemoKimai.ROUTE.token }
        catalogText = ""
        catalogSaves = 0
        held = []
        holdNext = 0
        failPath = ""
        delivered = 0
        KimaiApi.setUrlRoute(gatedRoute())
        plasmoid = { configuration: SharedConfig.fromConfiguration(SharedConfig.DEFAULTS), userConfiguring: true }
    }

    /** A page with the in-memory backend (the page's own setBackend runs first). */
    function open(component) {
        const page = createTemporaryObject(component, this)
        verify(page)
        Platform.setBackend(backend())
        page.pageEntered()
        return page
    }

    function test_connectionTokenAndTest() {
        const page = open(connectionPage)
        tryVerify(function() { return page.profiles.length > 0 && page.selectedProfile.id === "demo" })
        tryCompare(page, "hasStoredToken", true)
        compare(page.providers[0].id, "kimai")

        // Test connection: the stored token against the demo Kimai.
        page.testingConnection = true
        page.session.connection.test(page.selectedProfile, {
            noToken: function() { page.testingConnection = false },
            testing: function() {},
            done: function(r) { page.testingConnection = !r.ok },
            failed: function() { page.testingConnection = true }
        })
        tryCompare(page, "testingConnection", false)

        page.session.connection.clearToken("demo")
        page.checkStoredToken()
        tryCompare(page, "hasStoredToken", false)

        page.persistShared()
        tryVerify(function() { return shared.activeProfileId === "demo" && shared.profilesJson.length > 0 })
    }

    function test_favoritesFetchAndStore() {
        plasmoid.configuration.profilesJson = shared.profilesJson
        plasmoid.configuration.activeProfileId = "demo"
        const page = open(favoritesPage)
        // pageEntered starts the page's own load (timer, then fetch). Let it end first: its late
        // answer would otherwise reset activityRowModel and loadingActivities under the steps below.
        tryVerify(function() { return page.session.catalog.cached("demo") !== null }, 5000)
        tryCompare(page, "loadingProjects", false)
        tryCompare(page, "loadingActivities", false)
        CatalogCache.clear()
        catalogText = ""

        page.loadProjects(true)
        tryVerify(function() { return catalogText.length > 0 }, 5000)
        tryVerify(function() { return page.availableProjects.length > 0 }, 5000)
        tryCompare(page, "loadingActivities", false)
        verify(page.allActivities.length > 0)
        // Stored for the widget: catalog-cache.json and memory.
        verify(catalogText.length > 0)
        verify(page.session.catalog.cached("demo") !== null)

        page.fetchActivitiesForProject(page.availableProjects[0])
        tryCompare(page, "loadingActivities", false)
        verify(page.activityRowModel.length > 0)

        page.toggleActivity(page.availableProjects[0].id, page.allActivities[0].id)
        page.persistShared()
        tryVerify(function() { return shared.pinnedActivities.length > 0 })
    }

    /** A favourites page whose first load (no cache) waits at its first request. */
    function pageWithHeldLoad() {
        plasmoid.configuration.profilesJson = shared.profilesJson
        plasmoid.configuration.activeProfileId = "demo"
        holdNext = 1
        const page = open(favoritesPage)
        tryVerify(function() { return held.length === 1 }, 5000)
        verify(page.loadingProjects)
        return page
    }

    // Reload while the first load runs: the first load's late answer is dropped, it does not overwrite the stored catalog.
    function test_favoritesLateFirstLoadIsDropped() {
        const page = pageWithHeldLoad()
        page.beginLoadingUi()
        page.loadProjects(true)
        tryVerify(function() { return catalogSaves === 1 }, 5000)
        tryCompare(page, "loadingProjects", false)

        // The first load now answers; unless dropped, it goes on to projects and activities.
        const before = delivered
        held[0]()
        tryVerify(function() { return delivered > before }, 5000)
        wait(300)
        compare(catalogSaves, 1)
    }

    // Reload while the first load runs: the first load's answer does not end the loading state of the second.
    function test_favoritesEarlyFirstLoadKeepsLoading() {
        plasmoid.configuration.profilesJson = shared.profilesJson
        plasmoid.configuration.activeProfileId = "demo"
        holdNext = 2
        const page = open(favoritesPage)
        tryVerify(function() { return held.length === 1 }, 5000)
        page.beginLoadingUi()
        page.loadProjects(true)
        tryVerify(function() { return held.length === 2 }, 5000)

        held[0]()
        tryVerify(function() { return delivered > 0 }, 5000)
        wait(300)
        verify(page.loadingProjects)
        compare(catalogSaves, 0)

        held[1]()
        tryCompare(page, "loadingProjects", false)
        tryVerify(function() { return catalogSaves === 1 }, 5000)
    }

    // An older load stopped at its activities: a newer load that fails still ends the activities' spinner.
    function test_favoritesFailedReloadEndsActivitiesLoading() {
        plasmoid.configuration.profilesJson = shared.profilesJson
        plasmoid.configuration.activeProfileId = "demo"
        const page = open(favoritesPage)
        tryCompare(page, "loadingProjects", false)
        CatalogCache.clear()
        catalogText = ""
        page.loadingActivities = true
        failPath = "/api/projects"
        page.loadProjects(true)
        tryCompare(page, "loadingProjects", false)
        tryCompare(page, "loadingActivities", false)
    }

    // A stored catalog of another profile or server is not shown: its ids are not this account's.
    function test_favoritesTakesOnlyItsOwnCatalog() {
        plasmoid.configuration.profilesJson = shared.profilesJson
        plasmoid.configuration.activeProfileId = "demo"
        const page = open(favoritesPage)
        tryVerify(function() { return !!page.activeProfile })
        const url = page.activeProfile.url
        const catalog = function(profileId, from) {
            return { profileId: profileId, url: from, projects: [{ id: 1, name: "P" }], customers: [], activities: [] }
        }
        verify(!page.applyPayloadIfUsable(catalog("other", url)))
        verify(!page.applyPayloadIfUsable(catalog("demo", "https://other.test")))
        verify(!page.applyPayloadIfUsable(catalog("demo", "")))
        verify(page.applyPayloadIfUsable(catalog("demo", url)))
    }

    function test_behaviorAndDisplayLoad() {
        const behavior = open(behaviorPage)
        tryCompare(behavior, "ready", true)
        behavior.persistBehaviorConfig()
        tryVerify(function() { return shared.idleStopMinutes !== undefined })

        const display = open(displayPage)
        tryCompare(display, "ready", true)
        display.persistDisplayConfig()
        tryVerify(function() { return shared.visualStyle !== undefined })
    }
}
