.pragma library

/**
 * Time-tracker provider registry.
 * Profiles store `provider` (default kimai). Network calls go through api(providerId).
 * Shared UI helpers (duration formatting, pickers, sparkline) stay in kimaiApi.js.
 */

.import "./kimaiApi.js" as KimaiApi
.import "./providers/_stub.js" as Stub
.import "./providers/clockify.js" as ClockifyApi
.import "./providers/toggl.js" as TogglApi
.import "./providers/solidtime.js" as SolidTimeApi

var PROVIDER_KIMAI = "kimai"
var PROVIDER_CLOCKIFY = "clockify"
var PROVIDER_TOGGL = "toggl"
var PROVIDER_SOLIDTIME = "solidtime"

var PROVIDERS = [
    {
        id: PROVIDER_KIMAI,
        name: "Kimai",
        implemented: true,
        needsUrl: true,
        defaultUrl: "",
        urlPlaceholder: "https://kimai.example.com",
        authLabelKey: "token",
        hintKey: "kimai",
        capabilities: {
            statistics: true,
            colorDistinction: true,
            billableFilter: true,
            workContract: true
        }
    },
    {
        id: PROVIDER_CLOCKIFY,
        name: "Clockify",
        implemented: true,
        needsUrl: false,
        defaultUrl: "https://api.clockify.me/api/v1",
        urlPlaceholder: "https://api.clockify.me/api/v1",
        authLabelKey: "key",
        hintKey: "clockify",
        // Project colors exist, but no Kimai-style customer/activity colors or
        // global activity catalog — color distinction / Maintenance are Kimai-only.
        capabilities: {
            statistics: true,
            colorDistinction: false,
            billableFilter: true,
            workContract: false
        }
    },
    {
        id: PROVIDER_TOGGL,
        name: "Toggl Track",
        implemented: true,
        needsUrl: false,
        defaultUrl: "https://api.track.toggl.com/api/v9",
        urlPlaceholder: "https://api.track.toggl.com/api/v9",
        authLabelKey: "token",
        hintKey: "toggl",
        capabilities: {
            statistics: true,
            colorDistinction: false,
            billableFilter: true,
            workContract: false
        }
    },
    {
        id: PROVIDER_SOLIDTIME,
        name: "SolidTime",
        implemented: true,
        needsUrl: true,
        defaultUrl: "https://api.solidtime.io",
        urlPlaceholder: "https://api.solidtime.io",
        authLabelKey: "token",
        hintKey: "solidtime",
        // No entity colors from the API; range stats still work.
        capabilities: {
            statistics: true,
            colorDistinction: false,
            billableFilter: true,
            workContract: false
        }
    }
]

function listProviders() {
    return PROVIDERS.slice()
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

function providerMeta(providerId) {
    var id = normalizeProviderId(providerId)
    for (var i = 0; i < PROVIDERS.length; i++) {
        if (PROVIDERS[i].id === id) {
            return PROVIDERS[i]
        }
    }
    return PROVIDERS[0]
}

/** Feature flags for the active tracker (statistics, color distinction, …). */
function providerCapabilities(providerId) {
    var meta = providerMeta(providerId)
    var caps = meta.capabilities || {}
    return {
        statistics: caps.statistics === true,
        colorDistinction: caps.colorDistinction === true,
        billableFilter: caps.billableFilter === true,
        workContract: caps.workContract === true
    }
}

function isImplemented(providerId) {
    return !!providerMeta(providerId).implemented
}

function api(providerId) {
    var id = normalizeProviderId(providerId)
    if (id === PROVIDER_KIMAI) {
        return KimaiApi
    }
    if (id === PROVIDER_CLOCKIFY) {
        return ClockifyApi
    }
    if (id === PROVIDER_TOGGL) {
        return TogglApi
    }
    if (id === PROVIDER_SOLIDTIME) {
        return SolidTimeApi
    }
    return Stub.notImplementedApi(id)
}

function resolveUrl(profile) {
    var meta = providerMeta(profile && profile.provider)
    var url = profile && profile.url ? String(profile.url) : ""
    url = KimaiApi.normalizeUrl(url)
    if (!url && meta.defaultUrl) {
        return meta.defaultUrl
    }
    return url
}

function sessionFromProfile(profile) {
    var p = profile || {}
    return {
        workspaceId: p.workspaceId || "",
        userId: p.userId || "",
        organizationId: p.organizationId || "",
        memberId: p.memberId || "",
        projectsById: {},
        clientsById: {},
        tasksById: {}
    }
}

function applySession(providerId, profile) {
    var a = api(providerId)
    if (a && typeof a.setSession === "function") {
        a.setSession(sessionFromProfile(profile))
    }
    return a
}

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
        names.push(PROVIDERS[i].name)
    }
    return names
}

/**
 * Aggregate timesheets by project for the stats view.
 * Returns [{ name, seconds, color }, ...] sorted by seconds desc.
 */
function projectBreakdown(timesheets, customersById, limit) {
    var map = {}
    var order = []
    var i
    for (i = 0; i < (timesheets || []).length; i++) {
        var ts = timesheets[i]
        var pid = KimaiApi.projectId(ts)
        var key = String(pid || "_none")
        if (!map[key]) {
            map[key] = {
                name: KimaiApi.projectName(ts) || "—",
                seconds: 0,
                color: KimaiApi.effectiveColorFromProject(
                    (ts && typeof ts.project === "object") ? ts.project : null,
                    customersById || {})
            }
            order.push(key)
        }
        map[key].seconds += KimaiApi.timesheetDurationSeconds(ts)
    }
    order.sort(function(a, b) {
        return map[b].seconds - map[a].seconds
    })
    var max = (typeof limit === "number" && limit > 0) ? limit : order.length
    var out = []
    for (i = 0; i < order.length && i < max; i++) {
        out.push(map[order[i]])
    }
    return out
}
