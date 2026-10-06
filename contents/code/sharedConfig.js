.pragma library

var SHARED_KEYS = [
    "kimaiUrl",
    "profilesJson",
    "activeProfileId",
    "pinnedActivities",
    "refreshInterval",
    "recentCount",
    "workDayBegin",
    "workDayEnd",
    "latitude",
    "longitude",
    "popupShowSparkline",
    "desktopShowSparkline",
    "showSparklineArcs",
    "showElapsedInPanel",
    "showProjectInPanel",
    "showActivityInPanel",
    "showCustomerColorInPanel",
    "showProjectColorInPanel",
    "popupShowWorkSummary",
    "popupShowFavorites",
    "popupShowRecent",
    "popupShowContinue",
    "popupShowNewActivity",
    "desktopShowWorkSummary",
    "desktopShowFavorites",
    "desktopShowRecent",
    "desktopShowNewActivity",
    "showFavorites",
    "confirmBeforeStop",
    "confirmStartBeforePreviousEnd",
    "idleStopEnabled",
    "idleStopMinutes",
    "notifyOnStart",
    "notifyOnStop",
    "notifyOnIdleStop",
    "notifyForgotToStart",
    "lastUsedProjectId",
    "lastUsedActivityId",
    "lastUsedProjectName",
    "lastUsedActivityName",
    "pluginProbesJson",
    "showTrips",
    "locationName",
    "touchMode",
    "visualStyle",
    "trackingIndicator",
    "settingsVersion"
]

/**
 * Version of the settings in shared.json; every write through Platform.patchShared
 * carries it. Settings without it were written by a version before the setup wizard
 * (2.3.x and older): they are reset once (needsReset, resetShared), so the wizard runs.
 *
 *   shared.json  ──▶ needsReset? ──yes──▶ clear tokens, write resetShared() ──▶ wizard
 *                         │no
 *                         ▼
 *                  load as before
 */
var SETTINGS_VERSION = 2
var VERSION_KEY = "settingsVersion"

/** The single profile of a fresh start (profiles.js defaultProfiles()). */
var DEFAULT_PROFILES_JSON = '[{"id":"default","name":"Default","url":"","provider":"kimai"}]'

/**
 * main.xml's defaults of SHARED_KEYS (tests/test_shared_defaults.py keeps them equal;
 * profilesJson is the default profile instead of "", which applyToConfiguration skips).
 * Written in full on a reset: the app reads only the keys shared.json has.
 */
var DEFAULTS = {
    kimaiUrl: "",
    profilesJson: DEFAULT_PROFILES_JSON,
    activeProfileId: "default",
    pinnedActivities: "",
    refreshInterval: 30,
    recentCount: 10,
    workDayBegin: "08:00",
    workDayEnd: "18:00",
    latitude: 52.52,
    longitude: 13.405,
    popupShowSparkline: true,
    desktopShowSparkline: true,
    showSparklineArcs: true,
    showElapsedInPanel: true,
    showProjectInPanel: true,
    showActivityInPanel: false,
    showCustomerColorInPanel: false,
    showProjectColorInPanel: false,
    popupShowWorkSummary: true,
    popupShowFavorites: true,
    popupShowRecent: true,
    popupShowContinue: true,
    popupShowNewActivity: true,
    desktopShowWorkSummary: true,
    desktopShowFavorites: true,
    desktopShowRecent: true,
    desktopShowNewActivity: true,
    showFavorites: true,
    confirmBeforeStop: false,
    confirmStartBeforePreviousEnd: true,
    idleStopEnabled: false,
    idleStopMinutes: 15,
    notifyOnStart: true,
    notifyOnStop: true,
    notifyOnIdleStop: true,
    notifyForgotToStart: false,
    lastUsedProjectId: "",
    lastUsedActivityId: "",
    lastUsedProjectName: "",
    lastUsedActivityName: "",
    pluginProbesJson: "",
    showTrips: true,
    locationName: "",
    touchMode: 0,
    visualStyle: 0,
    trackingIndicator: 0
}

/** Settings of a version before the setup wizard: some setting, but no settings version. */
function needsReset(shared) {
    if (!shared || typeof shared !== "object") {
        return false
    }
    if (Number(shared[VERSION_KEY]) >= SETTINGS_VERSION) {
        return false
    }
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        if (SHARED_KEYS[i] !== VERSION_KEY && Object.prototype.hasOwnProperty.call(shared, SHARED_KEYS[i])) {
            return true
        }
    }
    return false
}

/** Every setting at its default, with the current settings version. */
function resetShared() {
    var obj = {}
    for (var key in DEFAULTS) {
        obj[key] = DEFAULTS[key]
    }
    obj[VERSION_KEY] = SETTINGS_VERSION
    return obj
}

/** Profile ids whose tokens a reset clears: those in the settings, and "default". */
function profileIds(shared) {
    var ids = ["default"]
    var list = []
    try {
        list = JSON.parse((shared && shared.profilesJson) || "[]") || []
    } catch (e) {
        list = []
    }
    for (var i = 0; i < list.length; i++) {
        var id = list[i] && list[i].id ? String(list[i].id) : ""
        if (id && ids.indexOf(id) < 0) {
            ids.push(id)
        }
    }
    return ids
}

function applyToConfiguration(config, shared) {
    if (!shared || !config) {
        return false
    }
    var changed = false
    var sharedProfilesJsonIsEmpty = (typeof shared.profilesJson === "string" && shared.profilesJson.length === 0)
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        var key = SHARED_KEYS[i]
        if (!Object.prototype.hasOwnProperty.call(shared, key)) {
            continue
        }
        // Guard against "empty string" shared values clobbering a valid local
        // config during KCM tab reloads. The Connection page expects profiles
        // to stay stable unless profilesJson is truly absent.
        if (sharedProfilesJsonIsEmpty
            && (key === "profilesJson" || key === "activeProfileId")
            && typeof config.profilesJson === "string"
            && config.profilesJson.length > 0) {
            continue
        }
        if (config[key] !== shared[key]) {
            config[key] = shared[key]
            changed = true
        }
    }
    // Migrate legacy showFavorites into the new per-surface flags when missing.
    if (Object.prototype.hasOwnProperty.call(shared, "showFavorites")
        && !Object.prototype.hasOwnProperty.call(shared, "popupShowFavorites")) {
        config.popupShowFavorites = shared.showFavorites
        config.desktopShowFavorites = shared.showFavorites
        changed = true
    }
    return changed
}

/**
 * Data kept in shared.json as JSON maps (plugin probes). The Plasmoid and
 * the app both write them, so they
 * are never written as a whole from a possibly stale in-memory copy: callers
 * send them as a three-way merge (mergeDataPatch) and settings-wide writes
 * leave them out (fromConfiguration(config, { withoutDataMaps: true })).
 */
var DATA_MAP_KEYS = ["pluginProbesJson"]

function isDataMapKey(key) {
    return DATA_MAP_KEYS.indexOf(key) >= 0
}

function fromConfiguration(config, options) {
    if (!config) {
        return {}
    }
    var withoutDataMaps = !!(options && options.withoutDataMaps)
    var obj = {}
    var hasNonEmptyProfilesJson = (typeof config.profilesJson === "string" && config.profilesJson.length > 0)
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        var key = SHARED_KEYS[i]
        if (withoutDataMaps && isDataMapKey(key)) {
            continue
        }
        if (key === "profilesJson") {
            if (hasNonEmptyProfilesJson) {
                obj[key] = config[key]
            }
            continue
        }
        if (key === "activeProfileId") {
            if (hasNonEmptyProfilesJson
                && typeof config.activeProfileId === "string"
                && config.activeProfileId.length > 0) {
                obj[key] = config[key]
            }
            continue
        }
        obj[key] = config[key]
    }
    return obj
}

/**
 * When other KCM tabs persist their own keys, they merge into existing shared.json.
 * If existing shared.json already has an empty profilesJson (from a previous clobber),
 * replace it with the in-memory non-empty profilesJson so tab switching does not
 * re-persist the empty value.
 */
function sanitizeProfilesForPersistence(base, configuration) {
    if (!base || !configuration) {
        return base
    }
    // Treat missing profilesJson as “clobbered” too.
    // Some KCM tabs persist patches that omit profilesJson/activeProfileId; if
    // shared.json was previously written without those keys, we must not keep
    // persisting that broken state.
    var baseHasProfilesJson = Object.prototype.hasOwnProperty.call(base, "profilesJson")
    var baseProfilesEmpty = !baseHasProfilesJson
        || (typeof base.profilesJson === "string" && base.profilesJson.length === 0)
    var configProfilesNonEmpty = (typeof configuration.profilesJson === "string"
                                    && configuration.profilesJson.length > 0)
    if (baseProfilesEmpty && configProfilesNonEmpty) {
        base.profilesJson = configuration.profilesJson
        var baseHasActiveProfileId = Object.prototype.hasOwnProperty.call(base, "activeProfileId")
        var baseActiveProfileIdEmpty = !baseHasActiveProfileId
            || (typeof base.activeProfileId === "string" && base.activeProfileId.length === 0)
        if (baseActiveProfileIdEmpty
            && typeof configuration.activeProfileId === "string"
            && configuration.activeProfileId.length > 0) {
            base.activeProfileId = configuration.activeProfileId
        }
    }
    return base
}

function firstNonEmptyString() {
    for (var i = 0; i < arguments.length; i++) {
        var value = arguments[i]
        if (typeof value === "string" && value.length > 0) {
            return value
        }
    }
    return ""
}

/** cfg_activeProfileId defaults to "default"; treat that as unset when shared has a real selection. */
function firstMeaningfulActiveProfileId(cfgId, sharedId, configId) {
    if (typeof cfgId === "string" && cfgId.length > 0 && cfgId !== "default") {
        return cfgId
    }
    if (typeof sharedId === "string" && sharedId.length > 0) {
        return sharedId
    }
    if (typeof configId === "string" && configId.length > 0) {
        return configId
    }
    return firstNonEmptyString(cfgId, sharedId, configId)
}

/**
 * Resolve the best available Connection-page values from local cfg_*,
 * shared.json, and the live plasmoid configuration.
 *
 * The KCM can re-enter Connection with blank cfg_* fields after visiting
 * shared-backed tabs. In that case we must fall back to live/shared values
 * before the page synthesizes a default-only profile list.
 */
function resolveConnectionState(cfg, shared, configuration) {
    cfg = cfg || {}
    shared = shared || {}
    configuration = configuration || {}

    function profilesJsonIsOnlyDefault(jsonStr) {
        if (typeof jsonStr !== "string" || jsonStr.length === 0) {
            return false
        }
        try {
            var parsed = JSON.parse(jsonStr)
            return Array.isArray(parsed)
                && parsed.length === 1
                && parsed[0]
                && String(parsed[0].id) === "default"
        } catch (e) {
            return false
        }
    }

    var cfgProfilesJson = typeof cfg.profilesJson === "string" ? cfg.profilesJson : ""
    var sharedProfilesJson = typeof shared.profilesJson === "string" ? shared.profilesJson : ""
    var configProfilesJson = typeof configuration.profilesJson === "string" ? configuration.profilesJson : ""

    var profilesJson
    // Plasma reinjects default-only cfg_profilesJson on tab re-entry while
    // shared.json keeps the applied profile list.
    if (sharedProfilesJson.length > 0
        && (cfgProfilesJson.length === 0 || profilesJsonIsOnlyDefault(cfgProfilesJson))
        && !profilesJsonIsOnlyDefault(sharedProfilesJson)) {
        profilesJson = sharedProfilesJson
    } else {
        profilesJson = firstNonEmptyString(cfgProfilesJson, sharedProfilesJson, configProfilesJson)
    }

    var activeProfileId = firstMeaningfulActiveProfileId(
        cfg.activeProfileId,
        shared.activeProfileId,
        configuration.activeProfileId
    )

    // cfg may carry a non-default activeProfileId while profilesJson is still
    // default-only — prefer shared when the active id is missing from the list.
    if (sharedProfilesJson.length > 0
        && typeof shared.activeProfileId === "string"
        && shared.activeProfileId.length > 0
        && shared.activeProfileId !== "default"
        && profilesJsonIsOnlyDefault(profilesJson)) {
        profilesJson = sharedProfilesJson
        activeProfileId = shared.activeProfileId
    }

    return {
        profilesJson: profilesJson,
        activeProfileId: activeProfileId || "default",
        kimaiUrl: firstNonEmptyString(
            cfg.kimaiUrl,
            shared.kimaiUrl,
            configuration.kimaiUrl
        )
    }
}

function merge(base, patch) {
    var obj = {}
    var i
    var key
    if (base) {
        for (i = 0; i < SHARED_KEYS.length; i++) {
            key = SHARED_KEYS[i]
            if (Object.prototype.hasOwnProperty.call(base, key)) {
                obj[key] = base[key]
            }
        }
    }
    if (patch) {
        for (i = 0; i < SHARED_KEYS.length; i++) {
            key = SHARED_KEYS[i]
            if (Object.prototype.hasOwnProperty.call(patch, key)) {
                obj[key] = patch[key]
            }
        }
    }
    return obj
}

function parseMapJson(text) {
    if (!text || typeof text !== "string") {
        return {}
    }
    try {
        var data = JSON.parse(text)
        return (data && typeof data === "object" && !Array.isArray(data)) ? data : {}
    } catch (e) {
        return {}
    }
}

/**
 * Three-way merge of a JSON map (B9): the top-level keys that changed from
 * baseJson (what this process last saw) to nextJson (what it wants to
 * write) are applied onto freshJson (what is on disk now, possibly written
 * by the other app). Keys nobody here touched keep the disk value, so a
 * film day the Plasmoid saved is not lost when the app saves another one.
 * Returns the merged JSON text.
 */
function mergeMapJson(freshJson, baseJson, nextJson) {
    var fresh = parseMapJson(freshJson)
    var base = parseMapJson(baseJson)
    var next = parseMapJson(nextJson)
    var out = {}
    var k
    for (k in fresh) {
        out[k] = fresh[k]
    }
    var seen = {}
    for (k in base) {
        seen[k] = true
    }
    for (k in next) {
        seen[k] = true
    }
    for (k in seen) {
        var inBase = Object.prototype.hasOwnProperty.call(base, k)
        var inNext = Object.prototype.hasOwnProperty.call(next, k)
        if (inBase && inNext && JSON.stringify(base[k]) === JSON.stringify(next[k])) {
            continue
        }
        if (inNext) {
            out[k] = next[k]
        } else {
            delete out[k]
        }
    }
    return JSON.stringify(out)
}

/**
 * The patch to write onto `existing` (shared.json as loaded just now):
 * data-map keys that have an entry in `bases` are three-way merged, every
 * other key is taken as is.
 */
function mergeDataPatch(existing, bases, patch) {
    var out = {}
    for (var key in (patch || {})) {
        if (isDataMapKey(key) && bases && Object.prototype.hasOwnProperty.call(bases, key)) {
            var fresh = existing && typeof existing[key] === "string" ? existing[key] : ""
            out[key] = mergeMapJson(fresh, bases[key], patch[key])
        } else {
            out[key] = patch[key]
        }
    }
    return out
}

/** Parse KConfig / shared.json values for SpinBox and Int entries. */
function coerceInt(value, fallback, min, max) {
    var n = parseInt(value, 10)
    if (isNaN(n)) {
        n = parseInt(fallback, 10)
    }
    if (isNaN(n)) {
        n = 0
    }
    if (typeof min === "number") {
        n = Math.max(min, n)
    }
    if (typeof max === "number") {
        n = Math.min(max, n)
    }
    return n
}
