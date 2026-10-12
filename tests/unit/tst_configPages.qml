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

    function backend() {
        return {
            loadSharedConfig: function(_ds, cb) { cb(shared ? JSON.parse(JSON.stringify(shared)) : null) },
            saveSharedConfig: function(_ds, obj, cb) { shared = obj; if (cb) { cb(true) } },
            loadToken: function(_ds, id, cb) { cb(tokens[id] || "", null) },
            saveToken: function(_ds, id, token, cb) { tokens[id] = token; cb(true, null) },
            clearToken: function(_ds, id, cb) { delete tokens[id]; cb(true, null) },
            loadCatalogCacheText: function(_ds, cb) { cb(catalogText) },
            loadCatalogCache: function(_ds, cb) { cb(catalogText ? JSON.parse(catalogText) : null) },
            saveCatalogCache: function(_ds, payload, cb) { catalogText = JSON.stringify(payload); if (cb) { cb(true) } }
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
        page.loadProjects(true)
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
