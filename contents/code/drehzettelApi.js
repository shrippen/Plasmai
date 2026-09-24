.pragma library
.import "./kimaiApi.js" as KimaiApi

/**
 * Client for the Drehzettel plugin's external-client API
 * (KimaiPlugin\DrehzettelBundle, endpoints under /api/drehzettel/...).
 *
 * The plugin is optional and Kimai-only: every call here is a no-op unless
 * the active profile is a Kimai profile whose server has the plugin
 * installed. Callers should gate on ping()'s "installed" flag first.
 *
 * Auth and JSON handling reuse Kimai's own API (same Bearer token, same
 * base URL) - see kimai-drehzettel-bundle/research/api-external-clients.md
 * for why the plugin's routes need no separate client setup.
 */

var API_BASE = "/api/drehzettel"

/** DayCategory enum values (KimaiPlugin\DrehzettelBundle\Enum\DayCategory). */
var CATEGORIES = ["workday", "saturday", "sunday", "holiday"]

var pingCacheByUrl = {}
var PING_CACHE_MS = 30 * 60 * 1000

function resetPingCache() {
    pingCacheByUrl = {}
}

function cachedPing(kimaiUrl, nowMs) {
    var entry = pingCacheByUrl[KimaiApi.normalizeUrl(kimaiUrl)]
    if (!entry) {
        return null
    }
    var now = nowMs || Date.now()
    if (now - entry.atMs > PING_CACHE_MS) {
        return null
    }
    return entry.result
}

function storePing(kimaiUrl, result) {
    pingCacheByUrl[KimaiApi.normalizeUrl(kimaiUrl)] = { result: result, atMs: Date.now() }
}

/**
 * Whether the Drehzettel plugin is installed on this Kimai instance, and
 * which API major versions it serves. Cached per URL for 30 minutes -
 * installed and not-installed results alike, since a 404 here just means
 * "not installed", not an error worth re-checking on every popup open.
 */
function ping(kimaiUrl, apiToken, callback) {
    var cached = cachedPing(kimaiUrl)
    if (cached) {
        callback(KimaiApi.ok(cached))
        return
    }
    if (!kimaiUrl || !apiToken) {
        callback(KimaiApi.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var xhr = KimaiApi.createRequest("GET", kimaiUrl, API_BASE + "/ping", apiToken, false)
    KimaiApi.runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            var body = KimaiApi.parseJson(responseText, {})
            var result = {
                installed: !!body.installed,
                pluginVersion: body.pluginVersion || "",
                apiVersions: Array.isArray(body.apiVersions) ? body.apiVersions : []
            }
            storePing(kimaiUrl, result)
            callback(KimaiApi.ok(result))
            return
        }
        if (status === 404) {
            var notInstalled = { installed: false, pluginVersion: "", apiVersions: [] }
            storePing(kimaiUrl, notInstalled)
            callback(KimaiApi.ok(notInstalled))
            return
        }
        callback(KimaiApi.fail(KimaiApi.parseApiError(status, statusText, responseText)))
    })
}

function supportsV1(pingResult) {
    return !!(pingResult && pingResult.installed
        && pingResult.apiVersions && pingResult.apiVersions.indexOf("v1") >= 0)
}

function dateParam(date) {
    return KimaiApi.localDateString(date instanceof Date ? date : new Date(date))
}

/** Whether project+date fall inside an active engagement for the token holder. */
function engagementStatus(kimaiUrl, apiToken, projectId, date, callback) {
    if (!kimaiUrl || !apiToken || !projectId) {
        callback(KimaiApi.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var endpoint = API_BASE + "/v1/engagement-status?project=" + encodeURIComponent(String(projectId))
        + "&date=" + encodeURIComponent(dateParam(date))
    var xhr = KimaiApi.createRequest("GET", kimaiUrl, endpoint, apiToken, false)
    KimaiApi.runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(KimaiApi.ok(KimaiApi.parseJson(responseText, {})))
        } else {
            callback(KimaiApi.fail(KimaiApi.parseApiError(status, statusText, responseText)))
        }
    })
}

function filmDayEndpoint(projectId, date) {
    return API_BASE + "/v1/film-days/" + encodeURIComponent(dateParam(date))
        + "?project=" + encodeURIComponent(String(projectId))
}

/** The stored film-day fields for this project+date, or null if none exist yet. */
function filmDayGet(kimaiUrl, apiToken, projectId, date, callback) {
    if (!kimaiUrl || !apiToken || !projectId) {
        callback(KimaiApi.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var xhr = KimaiApi.createRequest("GET", kimaiUrl, filmDayEndpoint(projectId, date), apiToken, false)
    KimaiApi.runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(KimaiApi.ok(KimaiApi.parseJson(responseText, {})))
        } else if (status === 404) {
            // No active engagement for this project/date after all (e.g. it just
            // ended) - treat like "nothing saved yet" rather than an error.
            callback(KimaiApi.ok(null))
        } else {
            callback(KimaiApi.fail(KimaiApi.parseApiError(status, statusText, responseText)))
        }
    })
}

/** fields: { breakMinutes, catering, category, note } - upserts the day (PUT). */
function filmDayPut(kimaiUrl, apiToken, projectId, date, fields, callback) {
    if (!kimaiUrl || !apiToken || !projectId) {
        callback(KimaiApi.fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var data = {
        breakMinutes: (f.breakMinutes === null || f.breakMinutes === undefined || f.breakMinutes === "")
            ? null : Number(f.breakMinutes),
        catering: !!f.catering,
        category: f.category || null,
        note: f.note || ""
    }
    var xhr = KimaiApi.createRequest("PUT", kimaiUrl, filmDayEndpoint(projectId, date), apiToken, true)
    KimaiApi.runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        if (status >= 200 && status < 300) {
            callback(KimaiApi.ok(KimaiApi.parseJson(responseText, {})))
        } else {
            callback(KimaiApi.fail(KimaiApi.parseApiError(status, statusText, responseText)))
        }
    })
}
