.pragma library
.import "./dateTimeFormat.js" as DTF

var ErrorType = {
    Network: "network",
    Unauthorized: "unauthorized",
    Forbidden: "forbidden",
    NotFound: "not_found",
    Server: "server",
    Unknown: "unknown",
    // URL, token, workspace or organization missing: set up the connection.
    NotConfigured: "not_configured",
    // A required field or id is missing or malformed: detail names it.
    InvalidInput: "invalid_input",
    // The action needs the server and the app has none right now.
    Offline: "offline",
    // The server changed an entry that has a queued change.
    Conflict: "conflict",
    // A day cache answers only what it has stored (never shown).
    CacheMiss: "cache"
}

var DEFAULT_CUSTOMER_COLOR = "#d2d6de"

function normalizeUrl(url) {
    if (!url) {
        return ""
    }
    var s = String(url).replace(/\/+$/, "")
    s = s.replace(/^(HTTPS?)(:)/i, function(m, p1, p2) { return p1.toLowerCase() + p2 })
    return s
}

function parseJson(responseText, fallback) {
    try {
        return JSON.parse(responseText)
    } catch (e) {
        return fallback
    }
}

function parseApiError(status, statusText, responseText) {
    var body = parseJson(responseText, {})
    var detail = body.title || body.detail || body.message || body.error
        || body["hydra:description"] || ""

    if (status === 0) {
        return { type: ErrorType.Network, status: 0, detail: detail }
    }
    if (status === 401) {
        return { type: ErrorType.Unauthorized, status: 401, detail: detail }
    }
    if (status === 403) {
        return { type: ErrorType.Forbidden, status: 403, detail: detail }
    }
    if (status === 404) {
        return { type: ErrorType.NotFound, status: 404, detail: detail }
    }
    if (status >= 500) {
        return { type: ErrorType.Server, status: status, detail: detail }
    }
    return { type: ErrorType.Unknown, status: status, detail: detail || statusText }
}

/** The text the server sent with an error; "" when it sent none or the error is the app's own (NotConfigured). */
function serverText(error) {
    if (!error || error.type === ErrorType.NotConfigured) {
        return ""
    }
    return error.detail || error.statusText || ""
}

function ok(data) {
    return { ok: true, data: data }
}

function fail(error) {
    return { ok: false, error: error }
}

/** Requests still waiting for an answer longer than this are aborted. */
var REQUEST_TIMEOUT_MS = 30000
var TIMEOUT_MESSAGE = "Request timed out"

var pendingRequests = []

function untrackRequest(entry) {
    var i = pendingRequests.indexOf(entry)
    if (i >= 0) {
        pendingRequests.splice(i, 1)
    }
}

/**
 * QML's XMLHttpRequest has no timeout. The applet calls this from a Timer;
 * it aborts overdue requests, whose callback then fires once with status 0
 * and a "Request timed out" message, so busy flags are always released.
 * Returns the number of aborted requests.
 */
function abortStaleRequests(nowMs) {
    var now = (typeof nowMs === "number") ? nowMs : Date.now()
    var stale = []
    for (var i = 0; i < pendingRequests.length; i++) {
        if (pendingRequests[i].deadline <= now) {
            stale.push(pendingRequests[i])
        }
    }
    for (i = 0; i < stale.length; i++) {
        untrackRequest(stale[i])
        stale[i].timedOut = true
        try {
            stale[i].xhr.abort()
        } catch (e) {
        }
        stale[i].finish(0, JSON.stringify({ message: TIMEOUT_MESSAGE }), TIMEOUT_MESSAGE)
    }
    return stale.length
}

function pendingRequestCount() {
    return pendingRequests.length
}

/** Test hook: function() returning an XMLHttpRequest-like object (null = real XHR). */
var requestFactory = null

function setRequestFactory(factory) {
    requestFactory = factory || null
}

function newXhr() {
    return requestFactory ? requestFactory() : new XMLHttpRequest()
}

function runRequest(xhr, body, callback) {
    var entry = { xhr: xhr, deadline: Date.now() + REQUEST_TIMEOUT_MS, timedOut: false, finished: false }
    // onerror and DONE can both fire; abort() also reports DONE. Answer once.
    entry.finish = function(status, responseText, statusText) {
        if (entry.finished) {
            return
        }
        entry.finished = true
        untrackRequest(entry)
        callback(status, responseText, statusText)
    }
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4 || entry.timedOut) {
            return
        }
        entry.finish(xhr.status, xhr.responseText, xhr.statusText)
    }
    xhr.onerror = function() {
        if (!entry.timedOut) {
            entry.finish(0, "", "Network error")
        }
    }
    pendingRequests.push(entry)
    if (body !== undefined) {
        xhr.send(body)
    } else {
        xhr.send()
    }
}

/** Whether a request needs the service's address; Optional falls back to a default. */
var UrlMode = { Optional: "optional", Required: "required" }

/** How a 404 reads: an error, or an empty answer. */
var NotFoundMode = { Error: "error", Empty: "empty" }

function configFail(detail) {
    return fail({ type: ErrorType.NotConfigured, status: 0, detail: detail })
}

/**
 * The request frame of a service, once for Clockify, Toggl and SolidTime.
 * A service names only what is its own:
 *   apiBase(url)            full base address of its API
 *   headers(token)          its authorization headers, { name: value }
 *   urlMode                 UrlMode, whether an empty address is a config error
 *   notFound                NotFoundMode
 *   unwrap(body)            optional, takes the payload out of the body
 *   session()               its context (workspace, user), set by the profile
 *   ready()                 whether the context is complete
 *   resolve(url, token, cb) looks the context up; cb(ok) or cb(fail)
 *   notReadyDetail          the config error when resolve left it incomplete
 * Returns { request, getJson, withSession }; a missing token (or required address)
 * answers a config error without sending:
 *   request(method, url, token, endpoint, body, isJson, callback)
 *   getJson(url, token, endpoint, emptyValue, callback)  an empty answer becomes emptyValue
 *   withSession(url, token, callback)  resolves the context once, then reuses it
 */
function requestFrame(spec) {
    function lacksAccess(url, token) {
        return !token || (spec.urlMode === UrlMode.Required && !url)
    }

    function open(method, url, endpoint, token, isJson) {
        var xhr = newXhr()
        xhr.open(method, spec.apiBase(url) + endpoint, true)
        var headers = spec.headers(token)
        for (var name in headers) {
            xhr.setRequestHeader(name, headers[name])
        }
        xhr.setRequestHeader("Accept", "application/json")
        if (isJson) {
            xhr.setRequestHeader("Content-Type", "application/json")
        }
        return xhr
    }

    function request(method, url, token, endpoint, body, isJson, callback) {
        if (lacksAccess(url, token)) {
            callback(configFail(""))
            return
        }
        var xhr = open(method, url, endpoint, token, isJson)
        runRequest(xhr, body, function(status, responseText, statusText) {
            if (status >= 200 && status < 300) {
                callback(ok(parseJson(responseText, null)))
            } else if (status === 404 && spec.notFound === NotFoundMode.Empty) {
                callback(ok(null))
            } else {
                callback(fail(parseApiError(status, statusText, responseText)))
            }
        })
    }

    function getJson(url, token, endpoint, emptyValue, callback) {
        request("GET", url, token, endpoint, undefined, false, function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            var body = spec.unwrap ? spec.unwrap(result.data) : result.data
            callback(ok(body !== null && body !== undefined ? body : emptyValue))
        })
    }

    function withSession(url, token, callback) {
        if (spec.ready()) {
            callback(ok(spec.session()))
            return
        }
        spec.resolve(url, token, function(result) {
            if (!result.ok) {
                callback(result)
                return
            }
            if (!spec.ready()) {
                callback(configFail(spec.notReadyDetail))
                return
            }
            callback(ok(spec.session()))
        })
    }

    return {
        request: request,
        getJson: getJson,
        withSession: withSession
    }
}

/** UTC ISO 8601 without fractional seconds, ending in Z. */
function isoUtc(date) {
    var d = date || new Date()
    return d.getUTCFullYear() + "-" + DTF.pad2(d.getUTCMonth() + 1) + "-" + DTF.pad2(d.getUTCDate())
        + "T" + DTF.pad2(d.getUTCHours()) + ":" + DTF.pad2(d.getUTCMinutes()) + ":" + DTF.pad2(d.getUTCSeconds()) + "Z"
}

/**
 * Parse ISO-8601 duration (Clockify PT… form) or numeric seconds to seconds.
 */
function parseIsoDurationToSeconds(iso) {
    if (iso === null || iso === undefined || iso === "") {
        return 0
    }
    var s = String(iso).trim()
    if (/^\d+$/.test(s)) {
        return parseInt(s, 10) || 0
    }
    var num = parseFloat(s)
    if (!isNaN(num) && s.charAt(0) !== "P") {
        return Math.max(0, Math.floor(num))
    }
    if (s.charAt(0) !== "P") {
        return 0
    }
    var match = /^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/i.exec(s)
    if (!match) {
        return 0
    }
    var days = parseInt(match[1] || "0", 10)
    var hours = parseInt(match[2] || "0", 10)
    var mins = parseInt(match[3] || "0", 10)
    var secs = parseFloat(match[4] || "0")
    return days * 86400 + hours * 3600 + mins * 60 + Math.floor(secs)
}

function utf8ToBytes(str) {
    var bytes = []
    var i = 0
    var code
    str = String(str)
    while (i < str.length) {
        code = str.charCodeAt(i++)
        if (code < 0x80) {
            bytes.push(code)
        } else if (code < 0x800) {
            bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
        } else if (code >= 0xD800 && code <= 0xDBFF && i < str.length) {
            var next = str.charCodeAt(i++)
            code = 0x10000 + (((code & 0x3FF) << 10) | (next & 0x3FF))
            bytes.push(
                0xF0 | (code >> 18),
                0x80 | ((code >> 12) & 0x3F),
                0x80 | ((code >> 6) & 0x3F),
                0x80 | (code & 0x3F)
            )
        } else {
            bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
        }
    }
    return bytes
}

/** Pure-JS base64 (UTF-8 safe) for Toggl Basic auth. */
function base64Encode(str) {
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var bytes = utf8ToBytes(str)
    var output = ""
    var i = 0
    while (i < bytes.length) {
        var b0 = bytes[i++]
        var b1 = i < bytes.length ? bytes[i++] : 0
        var b2 = i < bytes.length ? bytes[i++] : 0
        var triplet = (b0 << 16) | (b1 << 8) | b2
        output += chars.charAt((triplet >> 18) & 63)
        output += chars.charAt((triplet >> 12) & 63)
        output += i - 2 < bytes.length ? chars.charAt((triplet >> 6) & 63) : "="
        output += i - 1 < bytes.length ? chars.charAt(triplet & 63) : "="
    }
    return output
}

function basicAuthHeader(user, pass) {
    return "Basic " + base64Encode(String(user) + ":" + String(pass))
}

function normalizeCustomerColor(color) {
    var c = String(color || "").trim()
    if (!c) {
        return DEFAULT_CUSTOMER_COLOR
    }
    if (c.charAt(0) !== "#") {
        c = "#" + c
    }
    return c
}

function unwrapData(body) {
    if (body && body.data !== undefined) {
        return body.data
    }
    return body
}

function durationSecondsFromRange(begin, end, nowMs) {
    if (!begin) {
        return 0
    }
    var start = new Date(begin)
    if (isNaN(start.getTime())) {
        return 0
    }
    var endMs = nowMs || Date.now()
    if (end) {
        var stop = new Date(end)
        if (!isNaN(stop.getTime())) {
            endMs = stop.getTime()
        }
    }
    return Math.max(0, Math.floor((endMs - start.getTime()) / 1000))
}
