import QtQml
import "../../code/timeTracker.js" as TimeTracker
import "../../code/kimaiApi.js" as KimaiApi
import "../../code/profiles.js" as Profiles
import "../../code/platform.js" as Platform
import "../../code/sharedConfig.js" as SharedConfig
import "../../code/offlineOwner.js" as Owner
import ".." as Ui

/**
 * Profiles, the active profile's token and the connection state; the
 * Connection page's token and test actions.
 *
 *   open() ─▶ shared.json ─▶ [reset old] ─▶ settings.apply ─▶ useProfile
 *   useProfile(p) ─▶ loadToken ─▶ sync.openFor(p, t) ─▶ applyToken ─▶ session.refresh, plugin probes
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
    /** The error of the last failed refresh (null when fine), for ApiErrors.withServer. */
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
            return resetOld(shared, null).then(function(fresh) {
                return useShared(fresh)
            })
        })
    }

    function useShared(shared) {
        session.settings.apply(shared)
        profiles = Profiles.parseProfiles(shared ? shared.profilesJson : "", shared ? shared.kimaiUrl : "")
        return useProfile(Profiles.profileById(profiles, shared ? shared.activeProfileId : "default"))
    }

    /** The old settings were reset: views drop what they hold for the old profiles. */
    signal oldReset()

    /**
     * Settings of a version before the setup wizard (sharedConfig.js needsReset): once,
     * tokens cleared and every setting at its default, so the wizard runs. Resolves with
     * the settings to load. `own` is a connection the caller holds besides shared.json
     * (the widget's Plasma settings, or null): without shared.json it counts as old too,
     * and its profiles' tokens are cleared as well.
     */
    function resetOld(shared, own) {
        const old = shared || own
        if (!SharedConfig.needsReset(old)) {
            return Promise.resolve(shared)
        }
        const fresh = SharedConfig.resetShared()
        const ids = SharedConfig.profileIds(old).concat(SharedConfig.profileIds(own))
        const clears = ids.map(function(id) {
            return Platform.clearToken(session.dataSource, id).catch(function() {})
        })
        session.catalog.invalidate()
        oldReset()
        return Promise.all(clears).then(function() {
            return Platform.saveShared(session.dataSource, fresh)
        }).then(function() { return fresh }, function() { return fresh })
    }

    /** Counts profile switches, and a changed URL or token: an answer asked under an older one belongs to another server or account. */
    property int generation: 0
    /** Hash of the last token that was set, kept over a cleared one to tell another account (never the token). */
    property int lastTokenHash: 0

    /** Wraps a read's callback: dropped when the profile changed before the answer came. */
    function current(callback) {
        const asked = generation
        return function(result) {
            if (asked === generation) {
                callback(result)
            }
        }
    }

    /** Switches to `p`: its offline outbox, its token, a refresh. */
    function useProfile(p) {
        // Another profile: its first answers are pending again (views show loading rows).
        if (!profile || !p || profile.id !== p.id || url !== TimeTracker.resolveUrl(p)) {
            generation++
            lastTokenHash = 0
            session.timer.apply(null)
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
        // The token first: the waiting changes of the profile are settled with its own token, not
        // with the one of the profile before (this.token holds that until applyToken).
        let unreadable = false
        return loadToken(p).catch(function() {
            unreadable = true
            return ""
        }).then(function(t) {
            return session.sync.openFor(p, t).then(function() { return unreadable ? failed() : applyToken(t) })
        }).catch(failed)
    }

    /** Looks the token up again (the demo route can bring one later). */
    function reloadToken() {
        return useProfile(profile)
    }

    function loadToken(p) {
        // Internal builds route the demo address and bring its token.
        const routed = KimaiApi.routeToken(p.url)
        return routed ? Promise.resolve(routed) : Platform.loadToken(session.dataSource, p.id)
    }

    function failed() {
        token = ""
        tokenLoaded = true
        state = error
    }

    /** `t` is the token of the active profile. */
    function applyToken(t) {
        // Another account on the same profile (also after a cleared token in between):
        // answers asked with the old token are dropped.
        const previous = token ? Owner.markOf(token) : lastTokenHash
        if (t && previous && previous !== Owner.markOf(t)) {
            generation++
        }
        lastTokenHash = t ? Owner.markOf(t) : lastTokenHash
        token = t || ""
        tokenLoaded = true
        state = token ? online : unconfigured
        if (!token) {
            return
        }
        // Whose token it is decides whether the waiting changes may go out: asked beside the
        // first refresh, not before it (a server that answers slowly must not hold the views).
        session.sync.verify()
        session.refresh()
        session.filmDay.resolveMode(Ui.Session.Probe.Cached)
        session.trips.resolve(Ui.Session.Probe.Cached)
    }

    /** The answer of a running-entry fetch decides the state; a good one clears an error. */
    function observe(result) {
        if (result.ok) {
            state = online
            lastError = null
            return
        }
        state = error
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
