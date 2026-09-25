.pragma library

var ErrorType = {
    Network: "network",
    Unauthorized: "unauthorized",
    Forbidden: "forbidden",
    NotFound: "not_found",
    Server: "server",
    Unknown: "unknown",
    Unsupported: "unsupported"
}

var DEFAULT_CUSTOMER_COLOR = "#d2d6de"

function normalizeUrl(url) {
    if (!url) {
        return ""
    }
    return String(url).replace(/\/+$/, "")
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

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

/** UTC ISO 8601 without fractional seconds, ending in Z. */
function isoUtc(date) {
    var d = date || new Date()
    return d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate())
        + "T" + pad2(d.getUTCHours()) + ":" + pad2(d.getUTCMinutes()) + ":" + pad2(d.getUTCSeconds()) + "Z"
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
    if (body && body.data !== undefined && body.data !== null) {
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
