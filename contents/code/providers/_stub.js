.pragma library

/**
 * Shared helpers for unfinished time-tracker providers.
 * Each provider module must expose the same surface as kimaiApi.js
 * (see timeTracker.js).
 */

function unsupported(op, callback) {
    if (typeof callback === "function") {
        callback({
            ok: false,
            error: {
                type: "unsupported",
                status: 0,
                detail: op + " is not implemented for this provider yet"
            }
        })
    }
}

function notImplementedApi(providerId) {
    var label = providerId || "provider"
    function wrap(name) {
        return function() {
            var cb = arguments[arguments.length - 1]
            unsupported(label + "." + name, typeof cb === "function" ? cb : null)
        }
    }
    return {
        providerId: providerId,
        ErrorType: {
            Network: "network",
            Unauthorized: "unauthorized",
            Forbidden: "forbidden",
            NotFound: "not_found",
            Server: "server",
            Unknown: "unknown",
            Unsupported: "unsupported"
        },
        normalizeUrl: function(url) {
            if (!url) {
                return ""
            }
            return String(url).replace(/\/+$/, "")
        },
        testConnection: wrap("testConnection"),
        fetchActiveTimesheet: wrap("fetchActiveTimesheet"),
        fetchRecentTimesheets: wrap("fetchRecentTimesheets"),
        startTracking: wrap("startTracking"),
        stopTracking: wrap("stopTracking"),
        restartTimesheet: wrap("restartTimesheet"),
        patchTimesheet: wrap("patchTimesheet"),
        loadProjects: wrap("loadProjects"),
        loadActivities: wrap("loadActivities"),
        loadCustomers: wrap("loadCustomers"),
        fetchTimesheetsRange: wrap("fetchTimesheetsRange"),
        fetchCurrentUser: wrap("fetchCurrentUser"),
        preferenceMap: function() { return ({}) },
        workDaySecondsFromPrefs: function() { return 0 },
        workWeekSecondsFromPrefs: function() { return 0 }
    }
}
