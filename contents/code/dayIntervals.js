.pragma library
.import "./dateTimeFormat.js" as DTF
.import "./sharedConfig.js" as SharedConfig

/**
 * A day's entries as intervals and as the model of the day chart (sparkline);
 * work hours of the day.
 */

var DEFAULT_WORK_DAY_BEGIN = SharedConfig.DEFAULTS.workDayBegin

var DEFAULT_WORK_DAY_END = SharedConfig.DEFAULTS.workDayEnd

var DAY_SECONDS = 24 * 3600

function parseTimeToMinutes(value, fallbackMinutes) {
    var fallback = (typeof fallbackMinutes === "number" && !isNaN(fallbackMinutes))
        ? fallbackMinutes
        : 0
    var text = String(value || "").trim()
    if (!text) {
        return fallback
    }
    var parts = text.split(":")
    var hours = parseInt(parts[0], 10)
    var minutes = parts.length > 1 ? parseInt(parts[1], 10) : 0
    if (isNaN(hours) || isNaN(minutes)) {
        return fallback
    }
    hours = Math.max(0, Math.min(23, hours))
    minutes = Math.max(0, Math.min(59, minutes))
    return hours * 60 + minutes
}

/** True when `date` (or now) is inside configured work hours. Overnight ranges wrap. */
function isWithinWorkHours(beginText, endText, date) {
    var d = date && !isNaN(date.getTime()) ? date : new Date()
    var nowMin = d.getHours() * 60 + d.getMinutes()
    var beginMin = parseTimeToMinutes(beginText, 8 * 60)
    var endMin = parseTimeToMinutes(endText, 18 * 60)
    if (beginMin === endMin) {
        return true
    }
    if (beginMin < endMin) {
        return nowMin >= beginMin && nowMin < endMin
    }
    return nowMin >= beginMin || nowMin < endMin
}

function secondsOfLocalDay(date) {
    if (!date || isNaN(date.getTime())) {
        return 0
    }
    return date.getHours() * 3600 + date.getMinutes() * 60 + date.getSeconds()
}

/**
 * Clip timesheet entries to the local calendar day and return intervals
 * as seconds-from-midnight [{ startSec, endSec }, ...] sorted ascending.
 */
function dayIntervalsFromTimesheets(entries, dayDate, nowMs) {
    var dayStart = DTF.startOfLocalDay(dayDate || new Date())
    var dayEnd = DTF.endOfLocalDay(dayDate || new Date())
    var dayStartMs = dayStart.getTime()
    var dayEndMs = dayEnd.getTime()
    var now = (typeof nowMs === "number" && !isNaN(nowMs)) ? nowMs : Date.now()
    var intervals = []

    for (var i = 0; i < (entries || []).length; i++) {
        var entry = entries[i]
        if (!entry || !entry.begin) {
            continue
        }
        var begin = DTF.parseStamp(entry.begin)
        if (isNaN(begin.getTime())) {
            continue
        }
        var endMs = now
        if (entry.end) {
            var end = DTF.parseStamp(entry.end)
            if (!isNaN(end.getTime())) {
                endMs = end.getTime()
            }
        }
        var startMs = Math.max(begin.getTime(), dayStartMs)
        var stopMs = Math.min(endMs, dayEndMs + 1000)
        if (stopMs <= startMs) {
            continue
        }
        // Wall-clock seconds (not ms since midnight): on DST days the day has
        // 23/25 h and elapsed time would be off by an hour against the
        // business-hours / "now" markers.
        var startSec = startMs <= dayStartMs ? 0 : secondsOfLocalDay(new Date(startMs))
        var endSec = stopMs > dayEndMs ? DAY_SECONDS
            : secondsOfLocalDay(new Date(stopMs)) + (stopMs % 1000 > 0 ? 1 : 0)
        if (endSec <= startSec) {
            // Fall-back hour repeats wall-clock times; keep the duration.
            endSec = Math.min(DAY_SECONDS, startSec + Math.ceil((stopMs - startMs) / 1000))
        }
        intervals.push({
            startSec: Math.max(0, startSec),
            endSec: Math.min(DAY_SECONDS, endSec)
        })
    }

    intervals.sort(function(a, b) {
        return a.startSec - b.startSec
    })
    return intervals
}

/**
 * Split chronological day intervals into normal vs overtime using the daily
 * work-contract target (first targetSeconds of tracked time = normal).
 */
function splitIntervalsByQuota(intervals, targetSeconds) {
    var remaining = (typeof targetSeconds === "number" && targetSeconds > 0)
        ? Math.floor(targetSeconds)
        : -1
    var out = []

    for (var i = 0; i < (intervals || []).length; i++) {
        var start = intervals[i].startSec
        var end = intervals[i].endSec
        if (!(end > start)) {
            continue
        }
        var duration = end - start

        if (remaining < 0) {
            out.push({ startSec: start, endSec: end, overtime: false })
            continue
        }
        if (remaining <= 0) {
            out.push({ startSec: start, endSec: end, overtime: true })
            continue
        }
        if (duration <= remaining) {
            out.push({ startSec: start, endSec: end, overtime: false })
            remaining -= duration
            continue
        }
        out.push({ startSec: start, endSec: start + remaining, overtime: false })
        out.push({ startSec: start + remaining, endSec: end, overtime: true })
        remaining = 0
    }
    return out
}

/**
 * Model for DaySparkline: fractions of a 24h day in [0, 1].
 * workBegin/End are "HH:MM" (Kimai calendar.businessHours defaults 08:00–18:00).
 * viewStart/viewEnd zoom to business hours ±1h, expanded to cover all segments and now.
 */
function buildDaySparklineModel(entries, targetSeconds, workBegin, workEnd, nowMs) {
    var now = (typeof nowMs === "number" && !isNaN(nowMs)) ? nowMs : Date.now()
    var day = new Date(now)
    var beginMin = parseTimeToMinutes(workBegin, parseTimeToMinutes(DEFAULT_WORK_DAY_BEGIN, 8 * 60))
    var endMin = parseTimeToMinutes(workEnd, parseTimeToMinutes(DEFAULT_WORK_DAY_END, 18 * 60))
    if (endMin <= beginMin) {
        endMin = Math.min(24 * 60, beginMin + 1)
    }

    var intervals = dayIntervalsFromTimesheets(entries, day, now)
    var painted = splitIntervalsByQuota(intervals, targetSeconds)
    var segments = []
    for (var i = 0; i < painted.length; i++) {
        segments.push({
            start: painted[i].startSec / DAY_SECONDS,
            end: painted[i].endSec / DAY_SECONDS,
            overtime: !!painted[i].overtime
        })
    }

    var businessStart = (beginMin * 60) / DAY_SECONDS
    var businessEnd = (endMin * 60) / DAY_SECONDS
    var nowFrac = Math.max(0, Math.min(1, secondsOfLocalDay(day) / DAY_SECONDS))
    var hour = 1 / 24
    var viewStart = businessStart - hour
    var viewEnd = businessEnd + hour
    for (i = 0; i < segments.length; i++) {
        if (segments[i].start < viewStart) {
            viewStart = segments[i].start
        }
        if (segments[i].end > viewEnd) {
            viewEnd = segments[i].end
        }
    }
    if (nowFrac < viewStart) {
        viewStart = nowFrac
    }
    if (nowFrac > viewEnd) {
        viewEnd = nowFrac
    }
    viewStart = Math.max(0, viewStart)
    viewEnd = Math.min(1, viewEnd)
    if (viewEnd - viewStart < hour) {
        var mid = (viewStart + viewEnd) / 2
        viewStart = Math.max(0, mid - hour / 2)
        viewEnd = Math.min(1, viewStart + hour)
        if (viewEnd - viewStart < hour) {
            viewStart = Math.max(0, viewEnd - hour)
        }
    }

    return {
        businessStart: businessStart,
        businessEnd: businessEnd,
        now: nowFrac,
        segments: segments,
        viewStart: viewStart,
        viewEnd: viewEnd
    }
}
