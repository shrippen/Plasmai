import QtQml
import "../../code/platform.js" as Platform
import "../../code/timeTracker.js" as TimeTracker
import "../../code/geocode.js" as Geocode

/**
 * First start (SetupWizard) and place search: what the wizard asks of the
 * platform and the tracker, and applying its results to the session.
 * Works without a session too (the wizard's own instance: dataSource only).
 *
 *   wizard ─▶ checkSystem ─▶ testConnection ─▶ saveToken ─▶ fetchUser ─▶ connected(patch)
 *   host   ─▶ applyConnection(patch) ─▶ awaitingDay ─▶ finish(patch)
 */
QtObject {
    id: setup

    property QtObject session: null
    /** Plasmoid: its P5Support DataSource; follows the session's when there is one. */
    property var dataSource: session ? session.dataSource : null

    /** The wizard connected a profile; its Day step stays until it is finished or skipped. */
    property bool awaitingDay: false
    /** The wizard shows while no profile is connected, or until its Day step is done. */
    readonly property bool showWizard: !!session && ((session.connection.tokenLoaded && !session.connection.configured) || awaitingDay)

    // ── Provider facts (timeTracker.js) ──

    /** Every provider's meta (id, name, needsUrl, defaultUrl, …), in display order. */
    function listProviders() {
        return TimeTracker.listProviders()
    }

    function providerMeta(id) {
        return TimeTracker.providerMeta(id)
    }

    function providerName(id) {
        return TimeTracker.providerDisplayName(id)
    }

    function normalizeProvider(id) {
        return TimeTracker.normalizeProviderId(id)
    }

    // ── Wizard ──

    /** What blocks storing the token (Platform.checkSystem); resolves with the check's result. */
    function checkSystem() {
        return Platform.checkSystem(dataSource)
    }

    /** Tests a token before it is stored; callback(result) with the server's user in result.data. */
    function testConnection(providerId, profile, url, token, callback) {
        TimeTracker.applySession(providerId, profile).testConnection(url, token, callback)
    }

    function saveToken(profileId, token) {
        return Platform.saveToken(dataSource, profileId, token)
    }

    /** The account behind the token, for the wizard's "Connected as …". */
    function fetchUser(providerId, url, token, callback) {
        TimeTracker.api(providerId).fetchCurrentUser(url, token, callback)
    }

    /** Places for a name (Nominatim); callback({ ok, results: [{ displayName, latitude, longitude }], error }). */
    function searchPlace(query, callback) {
        Geocode.search(query, callback)
    }

    /** The best place for a trip's start or destination (trip map); callback(place or null). */
    function lookupPlace(query, callback) {
        Geocode.lookup(query, callback)
    }

    // ── Applying the results (needs the session) ──

    /** The Look step changed the visual style: shown at once, then saved. */
    function applyStyle(style) {
        session.settings.set({ visualStyle: style })
    }

    /** The profile works (token tested and stored). */
    function applyConnection(patch) {
        awaitingDay = true
        session.settings.set(patch).then(session.connection.open, session.connection.open)
    }

    /** Day step done ({} when skipped). */
    function finish(patch) {
        awaitingDay = false
        if (Object.keys(patch).length === 0) {
            return
        }
        session.settings.set(patch).then(session.connection.open, session.connection.open)
    }
}
