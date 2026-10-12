import QtQml
import "../../code/timeTracker.js" as TimeTracker
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/profiles.js" as Profiles
import "../../code/platform.js" as Platform
import "../../code/sharedConfig.js" as SharedConfig
import ".." as Ui

/**
 * Profiles, the active profile's token and the connection state; the
 * Connection page's token and test actions.
 *
 *   open() ─▶ shared.json ─▶ [reset old] ─▶ settings.apply ─▶ useProfile
 *   useProfile(p) ─▶ sync.openFor(p) ─▶ readToken ─▶ session.refresh, plugin probes
 */
QtObject {
    id: connection

    property QtObject session: null

    /** States; the strings are the ones the views have always compared with. */
    readonly property string unconfigured: "offline"
    readonly property string connecting: "connecting"
    readonly property string online: "online"
    readonly property string error: "error"
    readonly property string needsSetup: "needsSetup"

    // ── State, read only for views ──
    property string state: unconfigured
    /** The server's status text of the last failed refresh ("" when fine). */
    property string errorText: ""
    /** The error of the last failed refresh (null when fine), for ApiErrors.text. */
    property var lastError: null
    property var profiles: []
    property var profile: null
    property bool tokenLoaded: false
    readonly property bool configured: token.length > 0
    readonly property string providerId: profile && profile.provider ? profile.provider : TimeTracker.PROVIDER_KIMAI
    readonly property var meta: TimeTracker.providerMeta(providerId)
    readonly property var capabilities: TimeTracker.providerCapabilities(providerId)
    readonly property string url: TimeTracker.resolveUrl(profile)

    // ── Layer only ──
    property string token: ""
    /** The provider, wrapped by the offline layer when it has one (Kimai). */
    readonly property var tracker: session.sync.state ? session.sync.state.tracker : TimeTracker.api(providerId)

    /** Reads shared.json and connects the active profile. */
    function open() {
        if (state !== online) {
            state = connecting
        }
        return Platform.loadShared(session.dataSource).then(function(shared) {
            if (session.setupMode === Ui.Session.Setup.Report && (!shared || SharedConfig.needsReset(shared))) {
                state = needsSetup
                return null
            }
            return resetOld(shared).then(function(fresh) {
                return useShared(fresh)
            })
        })
    }

    function useShared(shared) {
        session.settings.apply(shared)
        profiles = Profiles.parseProfiles(shared ? shared.profilesJson : "", shared ? shared.kimaiUrl : "")
        return useProfile(Profiles.profileById(profiles, shared ? shared.activeProfileId : "default"))
    }

    /**
     * Settings of a version before the setup wizard (sharedConfig.js needsReset): once,
     * tokens cleared and every setting at its default, so the wizard runs. Resolves with
     * the settings to load.
     */
    function resetOld(shared) {
        if (!SharedConfig.needsReset(shared)) {
            return Promise.resolve(shared)
        }
        const fresh = SharedConfig.resetShared()
        const clears = SharedConfig.profileIds(shared).map(function(id) {
            return Platform.clearToken(session.dataSource, id).catch(function() {})
        })
        return Promise.all(clears).then(function() {
            return Platform.saveShared(session.dataSource, fresh)
        }).then(function() { return fresh }, function() { return fresh })
    }

    /** Switches to `p`: its offline outbox, its token, a refresh. */
    function useProfile(p) {
        // Another profile: its first answers are pending again (views show loading rows).
        if (!profile || !p || profile.id !== p.id) {
            session.timer.loaded = false
            session.recent.loaded = false
            session.catalog.loaded = false
        }
        profile = p
        if (!p) {
            token = ""
            tokenLoaded = true
            state = unconfigured
            return Promise.resolve()
        }
        TimeTracker.applySession(providerId, p)
        return session.sync.openFor(p).then(readToken)
    }

    /** Looks the token up again (the demo route can bring one later). */
    function reloadToken() {
        return useProfile(profile)
    }

    function readToken() {
        // Internal builds route the demo address and bring its token.
        const routed = KimaiApi.routeToken(profile.url)
        const pending = routed ? Promise.resolve(routed) : Platform.loadToken(session.dataSource, profile.id)
        return pending.then(function(t) {
            token = t || ""
            tokenLoaded = true
            state = token ? online : unconfigured
            if (!token) {
                return
            }
            session.refresh()
            session.filmDay.resolveMode(Ui.Session.Probe.Cached)
            session.trips.resolve(Ui.Session.Probe.Cached)
        }).catch(function() {
            token = ""
            tokenLoaded = true
            state = error
        })
    }

    /** The answer of a running-entry fetch decides the state; a good one clears an error. */
    function observe(result) {
        if (result.ok) {
            state = online
            errorText = ""
            lastError = null
            return
        }
        state = error
        errorText = result.error ? (result.error.statusText || "") : ""
        lastError = result.error || null
    }

    /** Connection keys for Platform.patchShared. */
    function config() {
        return {
            kimaiUrl: profile ? (profile.url || "") : "",
            profilesJson: profiles ? Profiles.serializeProfiles(profiles) : "",
            activeProfileId: profile ? profile.id : "default"
        }
    }

    // ── Connection page ──

    function metaOf(id) {
        return TimeTracker.providerMeta(id)
    }

    /** shared.json as stored (the Connection page edits profiles before they are used). */
    function loadStored() {
        return Platform.loadShared(session.dataSource)
    }

    /** Writes kimaiUrl, profilesJson, activeProfileId. */
    function saveProfiles(keys) {
        return Platform.patchShared(session.dataSource, keys, keys)
    }

    /** Resolves true when the profile has a token in secure storage. */
    function hasToken(profileId) {
        return Platform.loadToken(session.dataSource, profileId).then(function(t) {
            return !!(t && t.length > 0)
        })
    }

    function saveToken(profileId, value) {
        return Platform.saveToken(session.dataSource, profileId, value)
    }

    function clearToken(profileId) {
        return Platform.clearToken(session.dataSource, profileId)
    }

    /**
     * Tests `p` with its stored token. steps: noToken(), testing(url),
     * done(result), failed(err) (the token store failed).
     */
    function test(p, steps) {
        const target = TimeTracker.resolveUrl(p)
        const api = TimeTracker.applySession(p.provider || TimeTracker.PROVIDER_KIMAI, p)
        Platform.loadToken(session.dataSource, p.id).then(function(t) {
            if (!t) {
                steps.noToken()
                return
            }
            steps.testing(target)
            api.testConnection(target, t, steps.done)
        }).catch(function(err) {
            steps.failed(err)
        })
    }
}
