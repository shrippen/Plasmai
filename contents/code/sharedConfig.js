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
    "locationName",
    "colorDistinctionEnabled",
    "colorSimilarityPercent",
    "touchMode"
]

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

function fromConfiguration(config) {
    if (!config) {
        return {}
    }
    var obj = {}
    var hasNonEmptyProfilesJson = (typeof config.profilesJson === "string" && config.profilesJson.length > 0)
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        var key = SHARED_KEYS[i]
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
