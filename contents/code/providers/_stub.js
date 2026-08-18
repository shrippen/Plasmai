.pragma library
.import "../providerUtil.js" as Util

function unsupported(op, callback) {
    if (typeof callback === "function") {
        callback(Util.fail({
            type: Util.ErrorType.Unsupported,
            status: 0,
            detail: op + " is not implemented for this provider yet"
        }))
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
        ErrorType: Util.ErrorType,
        DEFAULT_CUSTOMER_COLOR: Util.DEFAULT_CUSTOMER_COLOR,
        normalizeUrl: Util.normalizeUrl,
        setSession: function(/* session */) {},
        testConnection: wrap("testConnection"),
        fetchActiveTimesheet: wrap("fetchActiveTimesheet"),
        fetchRecentTimesheets: wrap("fetchRecentTimesheets"),
        startTracking: wrap("startTracking"),
        stopTracking: wrap("stopTracking"),
        restartTimesheet: wrap("restartTimesheet"),
        patchTimesheet: wrap("patchTimesheet"),
        createTimesheet: wrap("createTimesheet"),
        deleteTimesheet: wrap("deleteTimesheet"),
        createCustomer: wrap("createCustomer"),
        createProject: wrap("createProject"),
        createActivity: wrap("createActivity"),
        loadProjects: wrap("loadProjects"),
        loadActivities: wrap("loadActivities"),
        loadAllActivities: wrap("loadAllActivities"),
        loadCustomers: wrap("loadCustomers"),
        fetchTimesheetsRange: wrap("fetchTimesheetsRange"),
        fetchCurrentUser: wrap("fetchCurrentUser"),
        preferenceMap: function(/* user */) { return ({}) },
        workDaySecondsFromPrefs: function(/* prefs, date */) { return 0 },
        workWeekSecondsFromPrefs: function(/* prefs, date */) { return 0 }
    }
}
