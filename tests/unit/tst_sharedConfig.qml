import QtQuick
import QtTest
import "../../contents/code/sharedConfig.js" as SharedConfig

TestCase {
    name: "SharedConfig"

    function test_mergePatchWins() {
        var merged = SharedConfig.merge(
            { kimaiUrl: "https://old", recentCount: 5, touchMode: 0 },
            { kimaiUrl: "https://new", idleStopMinutes: 10 }
        )
        compare(merged.kimaiUrl, "https://new")
        compare(merged.recentCount, 5)
        compare(merged.idleStopMinutes, 10)
        compare(merged.touchMode, 0)
    }

    function test_applyToConfiguration() {
        var config = { kimaiUrl: "a", recentCount: 3 }
        var changed = SharedConfig.applyToConfiguration(config, { kimaiUrl: "b", recentCount: 3 })
        verify(changed)
        compare(config.kimaiUrl, "b")
        compare(config.recentCount, 3)
    }

    function test_legacyFavoritesMigration() {
        var config = {}
        SharedConfig.applyToConfiguration(config, { showFavorites: false })
        compare(config.popupShowFavorites, false)
        compare(config.desktopShowFavorites, false)
    }

    function test_fromConfigurationCopiesKnownKeys() {
        var config = { kimaiUrl: "https://x", unknown: 1 }
        var obj = SharedConfig.fromConfiguration(config)
        compare(obj.kimaiUrl, "https://x")
        verify(!Object.prototype.hasOwnProperty.call(obj, "unknown"))
        verify(SharedConfig.SHARED_KEYS.indexOf("pinnedActivities") >= 0)
        verify(SharedConfig.SHARED_KEYS.indexOf("touchMode") >= 0)
        verify(SharedConfig.SHARED_KEYS.indexOf("showCustomerColorInPanel") >= 0)
        verify(SharedConfig.SHARED_KEYS.indexOf("showProjectColorInPanel") >= 0)
    }
}
