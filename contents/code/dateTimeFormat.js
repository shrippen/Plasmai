.pragma library

/**
 * Locale-aware date/time display helpers and digit-segment utilities
 * for click-to-select fields (year/month/day, hour/minute).
 */

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

function pad4(n) {
    var s = String(n)
    while (s.length < 4) {
        s = "0" + s
    }
    return s.slice(-4)
}

function localeDateFormat() {
    // Locale.ShortFormat === 1 (avoid Locale enum in pragma library)
    return Qt.locale().dateFormat(1)
}

function localeTimeFormat() {
    var fmt = Qt.locale().timeFormat(1)
    fmt = String(fmt).replace(/:ss/gi, "").replace(/\.sss/gi, "")
    return fmt
}

function formatLocaleDate(date) {
    var d = coerceDate(date)
    if (!d) {
        return ""
    }
    return Qt.locale().toString(d, localeDateFormat())
}

/** Coerce QML date / Date / string into a local JS Date at noon, or null. */
function coerceDate(value) {
    if (value === null || value === undefined || value === "") {
        return null
    }
    if (typeof value === "number" && !isNaN(value)) {
        var fromMs = new Date(value)
        if (!isNaN(fromMs.getTime())) {
            return new Date(fromMs.getFullYear(), fromMs.getMonth(), fromMs.getDate(), 12, 0, 0, 0)
        }
        return null
    }
    if (typeof value.getTime === "function") {
        var t = value.getTime()
        if (!isNaN(t)) {
            return new Date(value.getFullYear(), value.getMonth(), value.getDate(), 12, 0, 0, 0)
        }
        return null
    }
    if (typeof value === "string") {
        return parseLocaleDate(value)
    }
    // Some QML date bridges expose y/m/d fields
    if (typeof value === "object") {
        var y = value.getFullYear ? value.getFullYear() : value.year
        var m = value.getMonth ? value.getMonth() : (typeof value.month === "number" ? value.month - 1 : NaN)
        var day = value.getDate ? value.getDate() : value.day
        if (!isNaN(y) && !isNaN(m) && !isNaN(day)) {
            var built = new Date(y, m, day, 12, 0, 0, 0)
            if (!isNaN(built.getTime())) {
                return built
            }
        }
    }
    return null
}

function formatLocaleTime(hours, minutes) {
    var d = new Date(2000, 0, 1, hours, minutes, 0, 0)
    return Qt.locale().toString(d, localeTimeFormat())
}

function parseLocaleDate(text) {
    var t = String(text || "").trim()
    if (!t) {
        return null
    }
    var d = Date.fromLocaleString(Qt.locale(), t, localeDateFormat())
    if (d && typeof d.getTime === "function" && !isNaN(d.getTime())) {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12, 0, 0, 0)
    }
    // Digit-segment fallback when fromLocaleString disagrees with toString formatting
    var roles = dateSegmentRoles(localeDateFormat())
    var segs = digitSegments(t)
    if (roles.length >= 3 && segs.length >= 3) {
        var y = 1970
        var m = 1
        var day = 1
        for (var i = 0; i < 3; i++) {
            var n = parseInt(segs[i].text, 10)
            if (isNaN(n)) {
                return null
            }
            if (roles[i] === "y") {
                if (segs[i].text.length <= 2) {
                    y = n >= 70 ? 1900 + n : 2000 + n
                } else {
                    y = n
                }
            } else if (roles[i] === "M") {
                m = n
            } else if (roles[i] === "d") {
                day = n
            }
        }
        if (m >= 1 && m <= 12 && day >= 1 && day <= daysInMonth(y, m - 1)) {
            var parsed = new Date(y, m - 1, day, 12, 0, 0, 0)
            if (!isNaN(parsed.getTime())) {
                return parsed
            }
        }
    }
    // Fallback ISO
    var iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(t)
    if (iso) {
        var isoDate = new Date(parseInt(iso[1], 10), parseInt(iso[2], 10) - 1, parseInt(iso[3], 10), 12, 0, 0, 0)
        if (!isNaN(isoDate.getTime())) {
            return isoDate
        }
    }
    return null
}

function parseLocaleTime(text) {
    var t = String(text || "").trim()
    if (!t) {
        return null
    }
    var d = Date.fromLocaleString(Qt.locale(), t, localeTimeFormat())
    if (d && typeof d.getTime === "function" && !isNaN(d.getTime())) {
        return { hours: d.getHours(), minutes: d.getMinutes() }
    }
    // Digit segments: hour then minute (ignore am/pm text)
    var roles = timeSegmentRoles(localeTimeFormat())
    var segs = digitSegments(t)
    var hours = null
    var minutes = null
    var si = 0
    for (var r = 0; r < roles.length && si < segs.length; r++) {
        var n = parseInt(segs[si].text, 10)
        si++
        if (isNaN(n)) {
            continue
        }
        if (roles[r] === "H") {
            hours = n
        } else if (roles[r] === "m") {
            minutes = n
        }
    }
    if (hours !== null && minutes !== null && hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59) {
        return { hours: hours, minutes: minutes }
    }
    var m = /^(\d{1,2}):(\d{2})$/.exec(t)
    if (m) {
        var h = parseInt(m[1], 10)
        var min = parseInt(m[2], 10)
        if (!isNaN(h) && !isNaN(min) && h <= 23 && min <= 59) {
            return { hours: h, minutes: min }
        }
    }
    return null
}

/** Consecutive digit runs in text: [{ start, end, text }] (end exclusive). */
function digitSegments(text) {
    var s = String(text || "")
    var segs = []
    var i = 0
    while (i < s.length) {
        if (s.charAt(i) >= "0" && s.charAt(i) <= "9") {
            var start = i
            while (i < s.length && s.charAt(i) >= "0" && s.charAt(i) <= "9") {
                i++
            }
            segs.push({ start: start, end: i, text: s.substring(start, i) })
        } else {
            i++
        }
    }
    return segs
}

/**
 * Infer segment roles from a Qt date format string, in display order.
 * Returns array of "y"|"M"|"d" matching digit segment order.
 */
function dateSegmentRoles(format) {
    var fmt = String(format || localeDateFormat())
    var roles = []
    var i = 0
    while (i < fmt.length) {
        var c = fmt.charAt(i)
        var lower = c.toLowerCase()
        if (lower === "y" || lower === "m" || lower === "d") {
            var role = lower === "y" ? "y" : (lower === "m" ? "M" : "d")
            while (i < fmt.length && fmt.charAt(i).toLowerCase() === lower) {
                i++
            }
            // Skip duplicate width tokens already counted
            if (roles.length === 0 || roles[roles.length - 1] !== role) {
                roles.push(role)
            }
        } else {
            i++
        }
    }
    return roles
}

/**
 * Time segment roles from format: "H" hour, "m" minute (and optional "a" ampm ignored as digits).
 */
function timeSegmentRoles(format) {
    var fmt = String(format || localeTimeFormat())
    var roles = []
    var i = 0
    while (i < fmt.length) {
        var c = fmt.charAt(i)
        if (c === "H" || c === "h") {
            while (i < fmt.length && (fmt.charAt(i) === "H" || fmt.charAt(i) === "h")) {
                i++
            }
            if (roles.length === 0 || roles[roles.length - 1] !== "H") {
                roles.push("H")
            }
        } else if (c === "m") {
            while (i < fmt.length && fmt.charAt(i) === "m") {
                i++
            }
            if (roles.length === 0 || roles[roles.length - 1] !== "m") {
                roles.push("m")
            }
        } else {
            i++
        }
    }
    if (roles.length === 0) {
        return ["H", "m"]
    }
    return roles
}

function yearFieldWidth(format) {
    var fmt = String(format || localeDateFormat())
    var m = /y+/i.exec(fmt)
    return m ? Math.min(4, m[0].length) : 4
}

function segmentMaxLen(role, format) {
    if (role === "y") {
        return yearFieldWidth(format)
    }
    return 2
}

function segmentAtCursor(text, cursorPos) {
    var segs = digitSegments(text)
    if (segs.length === 0) {
        return -1
    }
    // Prefer the segment that contains cursor; at a boundary, prefer the one to the right
    // unless cursor is at end of text.
    for (var i = 0; i < segs.length; i++) {
        if (cursorPos >= segs[i].start && cursorPos < segs[i].end) {
            return i
        }
    }
    for (var j = 0; j < segs.length; j++) {
        if (cursorPos === segs[j].end) {
            if (j + 1 < segs.length && cursorPos === segs[j + 1].start) {
                return j + 1
            }
            return j
        }
    }
    if (cursorPos <= segs[0].start) {
        return 0
    }
    return segs.length - 1
}

function clampInt(value, min, max) {
    var n = parseInt(value, 10)
    if (isNaN(n)) {
        return min
    }
    return Math.max(min, Math.min(max, n))
}

function daysInMonth(year, monthIndex) {
    return new Date(year, monthIndex + 1, 0).getDate()
}

/**
 * Apply a typed digit buffer to one date segment; returns new Date or null.
 */
function applyDateSegment(date, roles, segmentIndex, digitBuffer) {
    if (!date || isNaN(date.getTime()) || segmentIndex < 0 || segmentIndex >= roles.length) {
        return null
    }
    var y = date.getFullYear()
    var m = date.getMonth() + 1
    var d = date.getDate()
    var role = roles[segmentIndex]
    var raw = String(digitBuffer || "")
    if (raw.length === 0) {
        return date
    }
    if (role === "y") {
        if (raw.length >= 4) {
            y = clampInt(raw.slice(0, 4), 1970, 2100)
        } else if (raw.length === 2) {
            var yy = clampInt(raw, 0, 99)
            y = yy >= 70 ? 1900 + yy : 2000 + yy
        } else if (raw.length === 1) {
            return null
        } else {
            y = clampInt(raw, 1970, 2100)
        }
    } else if (role === "M") {
        m = clampInt(raw, 1, 12)
    } else if (role === "d") {
        d = clampInt(raw, 1, daysInMonth(y, m - 1))
    }
    d = Math.min(d, daysInMonth(y, m - 1))
    return new Date(y, m - 1, d, 12, 0, 0, 0)
}

function applyTimeSegment(hours, minutes, roles, segmentIndex, digitBuffer) {
    var h = hours
    var min = minutes
    if (segmentIndex < 0 || segmentIndex >= roles.length) {
        return { hours: h, minutes: min }
    }
    var role = roles[segmentIndex]
    var raw = String(digitBuffer || "")
    if (raw.length === 0) {
        return { hours: h, minutes: min }
    }
    if (role === "H") {
        h = clampInt(raw, 0, 23)
    } else if (role === "m") {
        min = clampInt(raw, 0, 59)
    }
    return { hours: h, minutes: min }
}

function datePlaceholder() {
    // Example using today's structure in locale format
    return formatLocaleDate(new Date(2000, 0, 31))
}

function timePlaceholder() {
    return formatLocaleTime(23, 59)
}
