.pragma library

var SHARED_KEYS = [
    "kimaiUrl",
    "profilesJson",
    "activeProfileId",
    "pinnedActivities",
    "refreshInterval",
    "recentCount",
    "showElapsedInPanel",
    "showProjectInPanel",
    "confirmBeforeStop",
    "idleStopEnabled",
    "idleStopMinutes",
    "notifyOnStart",
    "notifyOnStop",
    "notifyOnIdleStop"
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
