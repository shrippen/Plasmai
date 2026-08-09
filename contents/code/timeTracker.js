.pragma library

/**
 * Time-tracker provider registry.
 *
 * Plasmai talks to backends through this façade. Kimai is the reference
 * implementation (`kimaiApi.js`). New services should expose the same
 * method names and callback shape: callback({ ok, data } | { ok:false, error }).
 *
 * Required methods (mirror kimaiApi.js):
 *   testConnection(url, token, cb)
 *   fetchActiveTimesheet(url, token, cb)
 *   fetchRecentTimesheets(url, token, size, cb)
 *   startTracking(url, token, projectId, activityId, description, cb)
 *   stopTracking(url, token, timesheetId, cb)
 *   restartTimesheet(url, token, timesheetId, cb)
 *   patchTimesheet(url, token, timesheetId, fields, cb)
 *   loadProjects(url, token, cb)
 *   loadActivities(url, token, projectId, cb)
 *   loadCustomers(url, token, cb)
 *   fetchTimesheetsRange(url, token, beginDate, endDate, cb)
 *   fetchCurrentUser(url, token, cb)
 *   preferenceMap(user) / workDaySecondsFromPrefs / workWeekSecondsFromPrefs
 *
 * Canonical timesheet DTO fields the UI understands (providers may nest
 * Kimai-style project/activity objects; helpers in kimaiApi normalize them):
 *   id, begin, end, duration, description,
 *   project{id,name,customer?}, activity{id,name}
 *
 * Suggested next providers (easy → harder):
 *   1. Clockify  — API key, workspaces, start/stop time entries
 *   2. Toggl Track — API token, similar entry model
 *   3. SolidTime — FOSS, REST, Kimai-like concepts
 *   4. Super Productivity — if HTTP API enabled
 *   5. Local JSON file — offline/demo backend (no server)
 */

.import "./kimaiApi.js" as KimaiApi
.import "./providers/_stub.js" as Stub

var PROVIDER_KIMAI = "kimai"
var PROVIDER_CLOCKIFY = "clockify"
var PROVIDER_TOGGL = "toggl"
var PROVIDER_SOLIDTIME = "solidtime"

/**
 * Registry metadata for UI (connection settings, docs).
 * `implemented: true` means api() returns a working backend.
 */
var PROVIDERS = [
    {
        id: PROVIDER_KIMAI,
        name: "Kimai",
        implemented: true,
        needsUrl: true,
        authLabel: "API token",
        hint: "Self-hosted Kimai — https://www.kimai.org/"
    },
    {
        id: PROVIDER_CLOCKIFY,
        name: "Clockify",
        implemented: false,
        needsUrl: false,
        defaultUrl: "https://api.clockify.me/api/v1",
        authLabel: "API key",
        hint: "Easy next target: API key auth, projects + time entries start/stop."
    },
    {
        id: PROVIDER_TOGGL,
        name: "Toggl Track",
        implemented: false,
        needsUrl: false,
        defaultUrl: "https://api.track.toggl.com/api/v9",
        authLabel: "API token",
        hint: "Popular SaaS; clear REST docs for running timers."
    },
    {
        id: PROVIDER_SOLIDTIME,
        name: "SolidTime",
        implemented: false,
        needsUrl: true,
        authLabel: "API token",
        hint: "Open-source tracker with a REST API; similar domain model to Kimai."
    }
]

function listProviders() {
    return PROVIDERS.slice()
}

function providerMeta(providerId) {
    var id = normalizeProviderId(providerId)
    for (var i = 0; i < PROVIDERS.length; i++) {
        if (PROVIDERS[i].id === id) {
            return PROVIDERS[i]
        }
    }
    return PROVIDERS[0]
}

function normalizeProviderId(providerId) {
    var id = String(providerId || PROVIDER_KIMAI).toLowerCase()
    for (var i = 0; i < PROVIDERS.length; i++) {
        if (PROVIDERS[i].id === id) {
            return id
        }
    }
    return PROVIDER_KIMAI
}

function isImplemented(providerId) {
    return !!providerMeta(providerId).implemented
}

/**
 * Resolve the API module/object for a profile provider id.
 * Call sites: TimeTracker.api(providerId).fetchActiveTimesheet(url, token, cb)
 */
function api(providerId) {
    var id = normalizeProviderId(providerId)
    if (id === PROVIDER_KIMAI) {
        return KimaiApi
    }
    // When a provider ships, import it above and return it here.
    // Example:
    //   if (id === PROVIDER_CLOCKIFY) return ClockifyApi
    return Stub.notImplementedApi(id)
}

/** Display name for combo boxes. */
function providerDisplayName(providerId) {
    return providerMeta(providerId).name
}

function providerIds() {
    var ids = []
    for (var i = 0; i < PROVIDERS.length; i++) {
        ids.push(PROVIDERS[i].id)
    }
    return ids
}

function providerNames() {
    var names = []
    for (var i = 0; i < PROVIDERS.length; i++) {
        var p = PROVIDERS[i]
        names.push(p.implemented ? p.name : (p.name + " (soon)"))
    }
    return names
}
