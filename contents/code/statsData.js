.pragma library
.import "./kimaiApi.js" as KimaiApi

/**
 * Stats aggregations for the secondary statistics view.
 * Timesheets are Kimai-shaped: { begin, end, duration, billable, project, activity }.
 */

var BILLABLE_ALL = "all"
var BILLABLE_ONLY = "billable"
var BILLABLE_NONE = "nonbillable"

var PALETTE = [
    "#3584e4", "#33d17a", "#f66151", "#e5a50a", "#9141ac",
    "#1c71d8", "#2ec27e", "#c01c28", "#e66100", "#813d9c",
    "#62a0ea", "#57e389", "#ed333b", "#f8e45c", "#c061cb"
]

function filterBillable(entries, mode) {
    var list = entries || []
    var out = []
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!e) {
            continue
        }
        if (mode === BILLABLE_ONLY && !e.billable) {
            continue
        }
        if (mode === BILLABLE_NONE && e.billable) {
            continue
        }
        out.push(e)
    }
    return out
}

function isBillable(entry) {
    return !!(entry && entry.billable)
}

function addDays(date, days) {
    var d = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12, 0, 0, 0)
    d.setDate(d.getDate() + days)
    return d
}

function startOfDay(date) {
    return KimaiApi.startOfLocalDay(date)
}

function endOfDay(date) {
    return KimaiApi.endOfLocalDay(date)
}

function startOfWeek(date) {
    return KimaiApi.startOfWeekMonday(date)
}

function endOfWeek(date) {
    return KimaiApi.endOfWeekSunday(date)
}

function sameLocalDay(a, b) {
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate()
}

function formatDayLabel(date) {
    if (!date || typeof date.getTime !== "function" || isNaN(date.getTime())) {
        return ""
    }
    return Qt.locale().toString(date, Qt.locale().dateFormat(1))
}

function formatWeekLabel(weekStart) {
    if (!weekStart || typeof weekStart.getTime !== "function" || isNaN(weekStart.getTime())) {
        return ""
    }
    var end = addDays(weekStart, 6)
    var fmt = Qt.locale().dateFormat(1)
    return Qt.locale().toString(weekStart, fmt) + " – " + Qt.locale().toString(end, fmt)
}

function paletteColor(index) {
    return PALETTE[Math.abs(index) % PALETTE.length]
}

function colorForKey(key, customersById, timesheetHint) {
    if (timesheetHint && timesheetHint.project) {
        return KimaiApi.customerColorOfProject(timesheetHint.project, customersById || {})
    }
    var hash = 0
    var s = String(key || "")
    for (var i = 0; i < s.length; i++) {
        hash = ((hash << 5) - hash) + s.charCodeAt(i)
        hash |= 0
    }
    return paletteColor(hash)
}

/**
 * Clip entry overlap into [rangeStart, rangeEnd] and return seconds.
 */
function overlapSeconds(entry, rangeStart, rangeEnd, nowMs) {
    if (!entry || !entry.begin) {
        return 0
    }
    var begin = new Date(entry.begin)
    if (isNaN(begin.getTime())) {
        return 0
    }
    var endMs = (typeof nowMs === "number") ? nowMs : Date.now()
    if (entry.end) {
        var end = new Date(entry.end)
        if (!isNaN(end.getTime())) {
            endMs = end.getTime()
        }
    }
    var startMs = Math.max(begin.getTime(), rangeStart.getTime())
    var stopMs = Math.min(endMs, rangeEnd.getTime() + 1)
    if (stopMs <= startMs) {
        return 0
    }
    return Math.floor((stopMs - startMs) / 1000)
}

function entriesOverlappingDay(entries, dayDate, nowMs) {
    var dayStart = startOfDay(dayDate)
    var dayEnd = endOfDay(dayDate)
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        if (overlapSeconds(entries[i], dayStart, dayEnd, nowMs) > 0) {
            out.push(entries[i])
        }
    }
    return out
}

function entriesOverlappingWeek(entries, weekStart, nowMs) {
    var ws = startOfWeek(weekStart)
    var we = endOfWeek(ws)
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        if (overlapSeconds(entries[i], ws, we, nowMs) > 0) {
            out.push(entries[i])
        }
    }
    return out
}

/**
 * 24 hourly buckets for a local day. Returns [{ hour, seconds }, ...].
 */
function hourlyBreakdown(entries, dayDate, nowMs) {
    var dayStart = startOfDay(dayDate)
    var buckets = []
    var h
    for (h = 0; h < 24; h++) {
        buckets.push({ hour: h, seconds: 0, label: (h < 10 ? "0" : "") + h })
    }
    var dayEntries = entriesOverlappingDay(entries, dayDate, nowMs)
    for (var i = 0; i < dayEntries.length; i++) {
        var entry = dayEntries[i]
        var begin = new Date(entry.begin)
        var endMs = nowMs || Date.now()
        if (entry.end) {
            var end = new Date(entry.end)
            if (!isNaN(end.getTime())) {
                endMs = end.getTime()
            }
        }
        var cursor = Math.max(begin.getTime(), dayStart.getTime())
        var stop = Math.min(endMs, endOfDay(dayDate).getTime() + 1)
        while (cursor < stop) {
            var curDate = new Date(cursor)
            var hour = curDate.getHours()
            var nextHour = new Date(curDate.getFullYear(), curDate.getMonth(), curDate.getDate(), hour + 1, 0, 0, 0)
            var sliceEnd = Math.min(stop, nextHour.getTime())
            buckets[hour].seconds += Math.floor((sliceEnd - cursor) / 1000)
            cursor = sliceEnd
        }
    }
    return buckets
}

/**
 * Per weekday stacked project seconds for one week.
 * Returns {
 *   days: [{ date, label, totalSeconds, stacks: [{ key, name, seconds, color }] }],
 *   legend: [{ key, name, color }]
 * }
 */
function weeklyProjectStacks(entries, weekStart, customersById, nowMs, maxProjects) {
    var ws = startOfWeek(weekStart)
    var limit = (typeof maxProjects === "number" && maxProjects > 0) ? maxProjects : 6
    var projectTotals = {}
    var dayModels = []
    var d
    for (d = 0; d < 7; d++) {
        var day = addDays(ws, d)
        var dayStart = startOfDay(day)
        var dayEnd = endOfDay(day)
        var stacksMap = {}
        for (var i = 0; i < (entries || []).length; i++) {
            var entry = entries[i]
            var secs = overlapSeconds(entry, dayStart, dayEnd, nowMs)
            if (secs <= 0) {
                continue
            }
            var pid = String(KimaiApi.projectId(entry) || "_none")
            var pname = KimaiApi.projectName(entry)
            if (!pname) {
                pname = (pid === "_none" || pid === "0") ? "—" : ("#" + pid)
            }
            if (!stacksMap[pid]) {
                stacksMap[pid] = {
                    key: pid,
                    name: pname,
                    seconds: 0,
                    color: colorForKey(pid, customersById, entry)
                }
            }
            stacksMap[pid].seconds += secs
            if (!projectTotals[pid]) {
                projectTotals[pid] = { key: pid, name: pname, seconds: 0, color: stacksMap[pid].color }
            }
            projectTotals[pid].seconds += secs
        }
        var stacks = []
        for (var k in stacksMap) {
            if (stacksMap.hasOwnProperty(k)) {
                stacks.push(stacksMap[k])
            }
        }
        stacks.sort(function(a, b) { return b.seconds - a.seconds })
        var total = 0
        for (var s = 0; s < stacks.length; s++) {
            total += stacks[s].seconds
        }
        dayModels.push({
            date: day,
            // Locale.ShortFormat === 1
            label: Qt.locale().dayName(day.getDay(), 1),
            totalSeconds: total,
            stacks: stacks
        })
    }

    var legendKeys = []
    for (var pk in projectTotals) {
        if (projectTotals.hasOwnProperty(pk)) {
            legendKeys.push(projectTotals[pk])
        }
    }
    legendKeys.sort(function(a, b) { return b.seconds - a.seconds })
    var top = legendKeys.slice(0, limit)
    var topSet = {}
    for (var t = 0; t < top.length; t++) {
        topSet[top[t].key] = true
    }

    // Collapse non-top into "Other" per day for readability
    for (d = 0; d < dayModels.length; d++) {
        var kept = []
        var other = 0
        var stacks2 = dayModels[d].stacks
        for (var j = 0; j < stacks2.length; j++) {
            if (topSet[stacks2[j].key]) {
                kept.push(stacks2[j])
            } else {
                other += stacks2[j].seconds
            }
        }
        if (other > 0) {
            kept.push({ key: "_other", name: "Other", seconds: other, color: "#9a9996" })
        }
        dayModels[d].stacks = kept
    }

    if (legendKeys.length > limit) {
        top.push({ key: "_other", name: "Other", color: "#9a9996", seconds: 0 })
    }
    return { days: dayModels, legend: top }
}

/**
 * Week timeline: one horizontal row per day, segments placed on a 0–24h axis.
 * Shows Mon–Fri by default; includes Sat/Sun when they have tracked time.
 * Segments are keyed by project+activity and colored via Kimai cascade.
 *
 * Returns {
 *   days: [{ label, date, totalSeconds, segments: [{
 *     key, name, projectName, activityName, color,
 *     startHour, endHour, seconds
 *   }] }],
 *   legend: [{ key, name, color }],
 *   hourMin, hourMax   // display window from business hours, expanded if needed
 * }
 */
function weeklyHourTimeline(entries, weekStart, customersById, nowMs, maxLegend, workBegin, workEnd) {
    var ws = startOfWeek(weekStart)
    var limit = (typeof maxLegend === "number" && maxLegend > 0) ? maxLegend : 8
    var dayModels = []
    var legendMap = {}
    var weekendActive = false
    var globalHourMin = 24
    var globalHourMax = 0
    var hasActivity = false
    var d

    var beginMin = KimaiApi.parseTimeToMinutes(
        workBegin, KimaiApi.parseTimeToMinutes(KimaiApi.DEFAULT_WORK_DAY_BEGIN, 8 * 60))
    var endMin = KimaiApi.parseTimeToMinutes(
        workEnd, KimaiApi.parseTimeToMinutes(KimaiApi.DEFAULT_WORK_DAY_END, 18 * 60))
    var businessHourMin = beginMin / 60
    var businessHourMax = endMin / 60
    if (!(businessHourMax > businessHourMin)) {
        businessHourMin = 8
        businessHourMax = 18
    }
    for (d = 0; d < 7; d++) {
        var day = addDays(ws, d)
        var dayStart = startOfDay(day)
        var dayEnd = endOfDay(day)
        var dayStartMs = dayStart.getTime()
        var dayEndMs = dayEnd.getTime() + 1
        var segments = []
        var total = 0

        for (var i = 0; i < (entries || []).length; i++) {
            var entry = entries[i]
            var secs = overlapSeconds(entry, dayStart, dayEnd, nowMs)
            if (secs <= 0) {
                continue
            }
            var begin = new Date(entry.begin)
            if (isNaN(begin.getTime())) {
                continue
            }
            var endMs = (typeof nowMs === "number") ? nowMs : Date.now()
            if (entry.end) {
                var end = new Date(entry.end)
                if (!isNaN(end.getTime())) {
                    endMs = end.getTime()
                }
            }
            var segStartMs = Math.max(begin.getTime(), dayStartMs)
            var segEndMs = Math.min(endMs, dayEndMs)
            if (segEndMs <= segStartMs) {
                continue
            }

            var startHour = (segStartMs - dayStartMs) / 3600000
            var endHour = (segEndMs - dayStartMs) / 3600000
            // Clamp into [0, 24]
            startHour = Math.max(0, Math.min(24, startHour))
            endHour = Math.max(0, Math.min(24, endHour))
            if (endHour <= startHour) {
                continue
            }

            var pid = String(KimaiApi.projectId(entry) || "_none")
            var aid = String(KimaiApi.activityId(entry) || "_none")
            var key = pid + ":" + aid
            var pname = KimaiApi.projectName(entry) || ((pid === "_none" || pid === "0") ? "—" : ("#" + pid))
            var aname = KimaiApi.activityName(entry) || ((aid === "_none" || aid === "0") ? "—" : ("#" + aid))
            var label = pname + " · " + aname
            var color = KimaiApi.effectiveColorFromTimesheet(entry, customersById || {})
            if (color === KimaiApi.DEFAULT_CUSTOMER_COLOR && !KimaiApi.activityColor(entry.activity)) {
                color = paletteColor(key.length + pid.length)
            }

            segments.push({
                key: key,
                name: label,
                projectName: pname,
                activityName: aname,
                color: color,
                startHour: startHour,
                endHour: endHour,
                seconds: Math.floor((segEndMs - segStartMs) / 1000)
            })
            total += Math.floor((segEndMs - segStartMs) / 1000)

            if (!legendMap[key]) {
                legendMap[key] = { key: key, name: label, color: color, seconds: 0 }
            }
            legendMap[key].seconds += Math.floor((segEndMs - segStartMs) / 1000)

            if (startHour < globalHourMin) {
                globalHourMin = startHour
            }
            if (endHour > globalHourMax) {
                globalHourMax = endHour
            }
            hasActivity = true
        }

        segments.sort(function(a, b) { return a.startHour - b.startHour })

        if (d >= 5 && total > 0) {
            weekendActive = true
        }

        dayModels.push({
            date: day,
            label: Qt.locale().dayName(day.getDay(), 1),
            totalSeconds: total,
            segments: segments
        })
    }

    // Mon–Fri unless weekend has activity
    var visibleDays = weekendActive ? dayModels : dayModels.slice(0, 5)

    // Base window = configured business hours; expand for this week if activity spills outside
    var hourMin = businessHourMin
    var hourMax = businessHourMax
    if (hasActivity && globalHourMax > globalHourMin) {
        if (globalHourMin < hourMin) {
            hourMin = globalHourMin
        }
        if (globalHourMax > hourMax) {
            hourMax = globalHourMax
        }
    }
    // Snap outward to whole hours for readable axis ticks
    hourMin = Math.max(0, Math.floor(hourMin))
    hourMax = Math.min(24, Math.ceil(hourMax))
    if (hourMax <= hourMin) {
        hourMax = Math.min(24, hourMin + 1)
    }

    var legend = []
    for (var lk in legendMap) {
        if (legendMap.hasOwnProperty(lk)) {
            legend.push(legendMap[lk])
        }
    }
    legend.sort(function(a, b) { return b.seconds - a.seconds })
    if (legend.length > limit) {
        var kept = legend.slice(0, limit)
        var otherSecs = 0
        for (var oi = limit; oi < legend.length; oi++) {
            otherSecs += legend[oi].seconds || 0
        }
        if (otherSecs > 0) {
            kept.push({ key: "_other", name: "Other", color: "#9a9996", seconds: otherSecs })
        }
        legend = kept
    }

    return {
        days: visibleDays,
        legend: legend,
        hourMin: hourMin,
        hourMax: hourMax,
        weekendIncluded: weekendActive,
        businessHourMin: businessHourMin,
        businessHourMax: businessHourMax
    }
}

/**
 * Activity distribution: [{ key, name, seconds, color, ratio }, ...]
 */
function activityBreakdown(entries, rangeStart, rangeEnd, nowMs, limit, customersById) {
    var map = {}
    var order = []
    for (var i = 0; i < (entries || []).length; i++) {
        var entry = entries[i]
        var secs = overlapSeconds(entry, rangeStart, rangeEnd, nowMs)
        if (secs <= 0) {
            continue
        }
        var aid = String(KimaiApi.activityId(entry) || "_none")
        var aname = KimaiApi.activityName(entry)
        if (!aname) {
            aname = (aid === "_none" || aid === "0") ? "—" : ("#" + aid)
        }
        if (!map[aid]) {
            var color = KimaiApi.effectiveColorFromTimesheet(entry, customersById || {})
            // If nothing in the Kimai cascade had a color, use a stable palette tint.
            if (!KimaiApi.activityColor(entry.activity)
                && !(entry.project && KimaiApi.projectColor(entry.project))
                && color === KimaiApi.DEFAULT_CUSTOMER_COLOR) {
                color = paletteColor(order.length)
            }
            map[aid] = {
                key: aid,
                name: aname,
                seconds: 0,
                color: color
            }
            order.push(aid)
        }
        map[aid].seconds += secs
    }
    order.sort(function(a, b) { return map[b].seconds - map[a].seconds })
    var max = (typeof limit === "number" && limit > 0) ? limit : order.length
    var total = 0
    var out = []
    var other = 0
    for (var j = 0; j < order.length; j++) {
        total += map[order[j]].seconds
        if (j < max) {
            out.push(map[order[j]])
        } else {
            other += map[order[j]].seconds
        }
    }
    if (other > 0) {
        out.push({ key: "_other", name: "Other", seconds: other, color: "#9a9996" })
    }
    for (var r = 0; r < out.length; r++) {
        out[r].ratio = total > 0 ? out[r].seconds / total : 0
    }
    return { rows: out, totalSeconds: total }
}

function sumSecondsInRange(entries, rangeStart, rangeEnd, nowMs) {
    var total = 0
    for (var i = 0; i < (entries || []).length; i++) {
        total += overlapSeconds(entries[i], rangeStart, rangeEnd, nowMs)
    }
    return total
}
