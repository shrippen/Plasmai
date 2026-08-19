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

    function test_applyToConfiguration_doesNotClobberProfilesJsonOnEmptyShared() {
        var config = { profilesJson: '[{"id":"p1","name":"Work","url":"https://a.example","provider":"clockify"}]' }
        SharedConfig.applyToConfiguration(config, { profilesJson: "" })
        compare(config.profilesJson.length > 0, true)
        verify(config.profilesJson.indexOf('"p1"') >= 0)
    }

    function test_sanitizeProfilesForPersistence_replacesEmptyBaseProfilesJson() {
        var configuration = {
            profilesJson: '[{"id":"p1","name":"Work","url":"https://a.example","provider":"clockify"}]',
            activeProfileId: "p1"
        }

        // Existing shared.json is already clobbered: profilesJson == "".
        // Another KCM tab persists only unrelated keys; the merge must keep profiles.
        var base = { profilesJson: "", activeProfileId: "default", pinnedActivities: "old" }
        var sanitizedBase = SharedConfig.sanitizeProfilesForPersistence(base, configuration)
        verify(sanitizedBase.profilesJson.length > 0)
        verify(sanitizedBase.profilesJson.indexOf('"p1"') >= 0)

        var merged = SharedConfig.merge(sanitizedBase, { pinnedActivities: "new" })
        verify(merged.profilesJson.length > 0)
        verify(merged.profilesJson.indexOf('"p1"') >= 0)
    }

    function test_sanitizeProfilesForPersistence_keepsProfilesWhenBaseMissingProfilesJson() {
        var configuration = {
            profilesJson: '[{"id":"p1","name":"Work","url":"https://a.example","provider":"clockify"}]',
            activeProfileId: "p1"
        }

        // Simulate existing shared.json where profilesJson/activeProfileId were
        // missing entirely (not just an empty string). This can happen when a
        // KCM tab persisted a patch without profilesJson/activeProfileId and
        // the merge wrote the incomplete object back.
        var base = { pinnedActivities: "old" }

        var sanitizedBase = SharedConfig.sanitizeProfilesForPersistence(base, configuration)
        verify(sanitizedBase.profilesJson.length > 0)
        verify(sanitizedBase.profilesJson.indexOf('"p1"') >= 0)

        var merged = SharedConfig.merge(sanitizedBase, { pinnedActivities: "new" })
        verify(merged.profilesJson.length > 0)
        verify(merged.profilesJson.indexOf('"p1"') >= 0)
    }

    function test_resolveConnectionState_prefersNonEmptyCfgThenSharedThenLive() {
        var resolved = SharedConfig.resolveConnectionState(
            {
                kimaiUrl: "",
                profilesJson: '[{"id":"cfg","name":"Cfg","url":"https://cfg.example","provider":"kimai"}]',
                activeProfileId: ""
            },
            {
                kimaiUrl: "https://shared.example",
                profilesJson: '[{"id":"shared","name":"Shared","url":"https://shared.example","provider":"kimai"}]',
                activeProfileId: "shared"
            },
            {
                kimaiUrl: "https://live.example",
                profilesJson: '[{"id":"live","name":"Live","url":"https://live.example","provider":"kimai"}]',
                activeProfileId: "live"
            }
        )

        verify(resolved.profilesJson.indexOf('"cfg"') >= 0)
        compare(resolved.activeProfileId, "shared")
        compare(resolved.kimaiUrl, "https://shared.example")
    }

    function test_resolveConnectionState_prefersSharedWhenCfgActiveProfileIsDefault() {
        // KCM injects cfg_activeProfileId="default" while the user selected a
        // non-default active profile in shared.json. Connection must use the
        // shared selection instead of the placeholder.
        var resolved = SharedConfig.resolveConnectionState(
            {
                kimaiUrl: "",
                profilesJson: "",
                activeProfileId: "default"
            },
            {
                kimaiUrl: "https://shared.example",
                profilesJson: '[{"id":"p1","name":"Profile 1","url":"https://p1.example","provider":"kimai"}]',
                activeProfileId: "p1"
            },
            {
                kimaiUrl: "",
                profilesJson: "",
                activeProfileId: ""
            }
        )

        verify(resolved.profilesJson.indexOf('"p1"') >= 0)
        compare(resolved.activeProfileId, "p1")
        compare(resolved.kimaiUrl, "https://shared.example")
    }

    function test_resolveConnectionState_fallsBackToLiveProfilesWhenCfgAndSharedBlank() {
        var resolved = SharedConfig.resolveConnectionState(
            {
                kimaiUrl: "",
                profilesJson: "",
                activeProfileId: ""
            },
            {
                kimaiUrl: "",
                profilesJson: "",
                activeProfileId: ""
            },
            {
                kimaiUrl: "https://live.example",
                profilesJson: '[{"id":"live","name":"Live","url":"https://live.example","provider":"clockify"}]',
                activeProfileId: "live"
            }
        )

        verify(resolved.profilesJson.indexOf('"live"') >= 0)
        compare(resolved.activeProfileId, "live")
        compare(resolved.kimaiUrl, "https://live.example")
    }

    function test_resolveConnectionState_prefersSharedWhenCfgProfilesJsonIsDefaultOnly() {
        // KCM can keep cfg_activeProfileId on the applied profile while
        // cfg_profilesJson is still the default-only placeholder.
        var resolved = SharedConfig.resolveConnectionState(
            {
                kimaiUrl: "",
                profilesJson: '[{"id":"default","name":"Default","url":"","provider":"kimai"}]',
                activeProfileId: "p1"
            },
            {
                kimaiUrl: "https://shared.example",
                profilesJson: '[{"id":"default","name":"Default","url":"","provider":"kimai"},{"id":"p1","name":"Profile 2","url":"","provider":"kimai"}]',
                activeProfileId: "p1"
            },
            {
                kimaiUrl: "",
                profilesJson: "",
                activeProfileId: ""
            }
        )

        verify(resolved.profilesJson.indexOf('"p1"') >= 0)
        compare(resolved.activeProfileId, "p1")
        compare(resolved.kimaiUrl, "https://shared.example")
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
        verify(SharedConfig.SHARED_KEYS.indexOf("lastUsedProjectId") >= 0)
        verify(SharedConfig.SHARED_KEYS.indexOf("notifyForgotToStart") >= 0)
        verify(SharedConfig.SHARED_KEYS.indexOf("confirmStartBeforePreviousEnd") >= 0)
    }

    function test_coerceInt() {
        compare(SharedConfig.coerceInt("15", 1, 1, 240), 15)
        compare(SharedConfig.coerceInt("bogus", 30, 10, 300), 30)
        compare(SharedConfig.coerceInt(0, 15, 1, 240), 1)
        compare(SharedConfig.coerceInt(999, 15, 1, 240), 240)
    }
}
