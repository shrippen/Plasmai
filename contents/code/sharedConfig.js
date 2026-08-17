.pragma library

var SHARED_KEYS = [
    "kimaiUrl",
    "profilesJson",
    "activeProfileId",
    "pinnedActivities",
    "refreshInterval",
    "recentCount",
    "useBlurBackground",
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
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        var key = SHARED_KEYS[i]
        if (!Object.prototype.hasOwnProperty.call(shared, key)) {
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
    var obj = {}
    for (var i = 0; i < SHARED_KEYS.length; i++) {
        var key = SHARED_KEYS[i]
        obj[key] = config[key]
    }
    return obj
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
