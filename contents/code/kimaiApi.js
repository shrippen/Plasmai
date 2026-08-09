.pragma library

var ErrorType = {
    Network: "network",
    Unauthorized: "unauthorized",
    Forbidden: "forbidden",
    NotFound: "not_found",
    Server: "server",
    Unknown: "unknown"
}

function normalizeUrl(url) {
    if (!url) {
        return ""
    }
    return String(url).replace(/\/+$/, "")
}

function createRequest(method, kimaiUrl, endpoint, apiToken, isJson) {
    var xhr = new XMLHttpRequest()
    xhr.open(method, normalizeUrl(kimaiUrl) + endpoint, true)
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken)
    xhr.setRequestHeader("Accept", "application/json")
    if (isJson) {
        xhr.setRequestHeader("Content-Type", "application/json")
    }
    return xhr
}

function runRequest(xhr, body, callback) {
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) {
            return
        }
        callback(xhr.status, xhr.responseText, xhr.statusText)
    }
    xhr.onerror = function() {
        callback(0, "", "Network error")
    }
    if (body !== undefined) {
        xhr.send(body)
    } else {
        xhr.send()
    }
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
    var detail = body.title || body.detail || body.message || body["hydra:description"] || ""

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

var DEFAULT_CUSTOMER_COLOR = "#d2d6de"

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

function getJson(kimaiUrl, apiToken, endpoint, emptyValue, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var xhr = createRequest("GET", kimaiUrl, endpoint, apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, emptyValue)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function testConnection(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/version", {}, callback)
}

function fetchActiveTimesheet(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/timesheets/active", [], callback)
}

function fetchRecentTimesheets(kimaiUrl, apiToken, size, callback) {
    getJson(kimaiUrl, apiToken, "/api/timesheets/recent?size=" + (size || 10), [], callback)
}

function loadProjects(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/projects?visible=3&order=ASC&orderBy=name", [], callback)
}

function loadCustomers(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/customers?visible=3&order=ASC&orderBy=name", [], callback)
}

function loadActivities(kimaiUrl, apiToken, projectId, callback) {
    if (!projectId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    getJson(kimaiUrl, apiToken, "/api/activities?project=" + projectId + "&visible=3&order=ASC&orderBy=name", [], callback)
}

function activityProjectId(activity) {
    if (!activity || activity.project === null || activity.project === undefined || activity.project === "") {
        return 0
    }
    if (typeof activity.project === "object") {
        return activity.project.id || 0
    }
    return activity.project
}

function customerIdOfProject(project) {
    if (!project || project.customer === null || project.customer === undefined) {
        return 0
    }
    if (typeof project.customer === "object") {
        return project.customer.id || 0
    }
    return project.customer
}

function buildCustomersById(customers) {
    var map = {}
    for (var i = 0; i < (customers || []).length; i++) {
        var customer = customers[i]
        map[customer.id] = {
            id: customer.id,
            name: customer.name || "",
            color: normalizeCustomerColor(customer.color)
        }
    }
    return map
}

function customerNameOfProject(project, customersById) {
    if (!project) {
        return ""
    }
    if (typeof project.customer === "object" && project.customer && project.customer.name) {
        return project.customer.name
    }
    var cid = customerIdOfProject(project)
    if (cid && customersById && customersById[cid]) {
        return customersById[cid].name || customersById[cid]
    }
    return ""
}

function customerColorOfProject(project, customersById) {
    if (!project) {
        return DEFAULT_CUSTOMER_COLOR
    }
    if (typeof project.customer === "object" && project.customer && project.customer.color) {
        return normalizeCustomerColor(project.customer.color)
    }
    var cid = customerIdOfProject(project)
    if (cid && customersById && customersById[cid] && customersById[cid].color) {
        return normalizeCustomerColor(customersById[cid].color)
    }
    return DEFAULT_CUSTOMER_COLOR
}

function customerColorFromTimesheet(timesheet, customersById) {
    if (!timesheet || !timesheet.project) {
        return DEFAULT_CUSTOMER_COLOR
    }
    return customerColorOfProject(timesheet.project, customersById)
}

function customerNameFromTimesheet(timesheet, customersById) {
    if (!timesheet || !timesheet.project) {
        return ""
    }
    return customerNameOfProject(timesheet.project, customersById)
}

function splitActivitiesForProject(activities, projectId) {
    var projectSpecific = []
    var globalActivities = []
    var list = activities || []
    for (var i = 0; i < list.length; i++) {
        var activity = list[i]
        var pid = activityProjectId(activity)
        if (!pid) {
            globalActivities.push(activity)
        } else if (pid === projectId) {
            projectSpecific.push(activity)
        }
    }
    return { projectSpecific: projectSpecific, global: globalActivities }
}

function activitiesListModel(activities, projectId) {
    var split = splitActivitiesForProject(activities, projectId)
    var rows = []
    var i
    for (i = 0; i < split.projectSpecific.length; i++) {
        rows.push({
            section: "project",
            activity: split.projectSpecific[i]
        })
    }
    for (i = 0; i < split.global.length; i++) {
        rows.push({
            section: "global",
            activity: split.global[i]
        })
    }
    return rows
}

function projectsGroupedByCustomer(projects, customers) {
    var customersById = buildCustomersById(customers)

    var groups = {}
    var order = []
    var i
    for (i = 0; i < (projects || []).length; i++) {
        var project = projects[i]
        var name = customerNameOfProject(project, customersById) || "Other"
        if (!groups[name]) {
            groups[name] = {
                color: customerColorOfProject(project, customersById),
                projects: []
            }
            order.push(name)
        }
        groups[name].projects.push(project)
    }

    order.sort(function(a, b) {
        if (a === "Other") {
            return 1
        }
        if (b === "Other") {
            return -1
        }
        return a.localeCompare(b)
    })

    var rows = []
    for (i = 0; i < order.length; i++) {
        var customerName = order[i]
        var group = groups[customerName]
        var list = group.projects
        list.sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
        for (var p = 0; p < list.length; p++) {
            rows.push({
                customerName: customerName,
                customerColor: group.color || customerColorOfProject(list[p], customersById),
                project: list[p]
            })
        }
    }
    return rows
}

function projectPickerItems(projects, customers) {
    var rows = projectsGroupedByCustomer(projects, customers)
    var items = []
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var customerName = row.customerName || ""
        var projectName = row.project.name || ""
        items.push({
            label: projectName,
            searchText: customerName + " " + projectName,
            section: customerName,
            color: normalizeCustomerColor(row.customerColor),
            value: row.project
        })
    }
    return items
}

function activityPickerItems(activities, projectId) {
    var rows = activitiesListModel(activities, projectId)
    var items = []
    for (var i = 0; i < rows.length; i++) {
        var activity = rows[i].activity
        items.push({
            label: activity.name,
            searchText: activity.name,
            section: rows[i].section,
            color: "",
            value: activity
        })
    }
    return items
}

function startTracking(kimaiUrl, apiToken, projectId, activityId, description, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("POST", kimaiUrl, "/api/timesheets", apiToken, true)
    var data = {
        begin: new Date().toISOString().slice(0, 19),
        project: projectId,
        activity: activityId,
        description: description || "",
        exported: false,
        billable: false
    }

    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function stopTracking(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken || !timesheetId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId + "/stop", apiToken, true)
    runRequest(xhr, "{}", function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(null))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function restartTimesheet(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken || !timesheetId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId + "/restart", apiToken, true)
    runRequest(xhr, "{}", function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function patchTimesheet(kimaiUrl, apiToken, timesheetId, fields, callback) {
    if (!kimaiUrl || !apiToken || !timesheetId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId, apiToken, true)
    runRequest(xhr, JSON.stringify(fields || {}), function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function fetchCurrentUser(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/users/me", {}, callback)
}

function localDateTimeString(date) {
    function pad(n) {
        return (n < 10 ? "0" : "") + n
    }
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
        + "T" + pad(date.getHours()) + ":" + pad(date.getMinutes()) + ":" + pad(date.getSeconds())
}

function startOfLocalDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0)
}

function endOfLocalDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 0)
}

function startOfWeekMonday(date) {
    var d = startOfLocalDay(date)
    var day = d.getDay()
    var offset = day === 0 ? 6 : day - 1
    d.setDate(d.getDate() - offset)
    return d
}

function endOfWeekSunday(date) {
    var start = startOfWeekMonday(date)
    return new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6, 23, 59, 59, 0)
}

function kimaiWeekday(date) {
    var day = date.getDay()
    return day === 0 ? 7 : day
}

function preferenceMap(user) {
    var map = {}
    var prefs = (user && user.preferences) ? user.preferences : []
    for (var i = 0; i < prefs.length; i++) {
        if (prefs[i] && prefs[i].name) {
            map[prefs[i].name] = prefs[i].value
        }
    }
    return map
}

function parseSecondsPref(value) {
    var n = parseInt(value, 10)
    return isNaN(n) ? 0 : Math.max(0, n)
}

function parseWeekdaySet(csv, fallback) {
    var parts = String(csv || fallback || "").split(",")
    var set = {}
    var count = 0
    for (var i = 0; i < parts.length; i++) {
        var n = parseInt(parts[i], 10)
        if (!isNaN(n) && n >= 1 && !set[n]) {
            set[n] = true
            count++
        }
    }
    return { set: set, count: count }
}

function workDaySecondsFromPrefs(prefs, date) {
    if (!prefs) {
        return 0
    }
    var type = String(prefs.work_contract_type || "")
    var weekday = kimaiWeekday(date)
    var dayKeys = {
        1: "work_monday",
        2: "work_tuesday",
        3: "work_wednesday",
        4: "work_thursday",
        5: "work_friday",
        6: "work_saturday",
        7: "work_sunday"
    }

    if (type === "day") {
        return parseSecondsPref(prefs[dayKeys[weekday]])
    }

    if (type === "week") {
        var weekDays = parseWeekdaySet(prefs.work_days_week, "1,2,3,4,5")
        if (!weekDays.set[weekday]) {
            return 0
        }
        var weekHours = parseSecondsPref(prefs.hours_per_week)
        if (weekHours <= 0 || weekDays.count <= 0) {
            return 0
        }
        return Math.round(weekHours / weekDays.count)
    }

    if (type === "month") {
        var monthDays = parseWeekdaySet(prefs.work_days_month, "1,2,3,4,5")
        if (!monthDays.set[weekday]) {
            return 0
        }
        // Approximate daily target from monthly hours / ~21.67 workdays.
        var monthHours = parseSecondsPref(prefs.hours_per_month)
        return monthHours > 0 ? Math.round(monthHours / 21.67) : 0
    }

    return 0
}

function workWeekSecondsFromPrefs(prefs, date) {
    if (!prefs) {
        return 0
    }
    var type = String(prefs.work_contract_type || "")
    if (type === "week") {
        return parseSecondsPref(prefs.hours_per_week)
    }
    if (type === "day" || type === "month") {
        var start = startOfWeekMonday(date)
        var total = 0
        for (var i = 0; i < 7; i++) {
            var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            total += workDaySecondsFromPrefs(prefs, day)
        }
        return total
    }
    return 0
}

function timesheetDurationSeconds(timesheet, nowMs) {
    if (!timesheet) {
        return 0
    }
    if (timesheet.duration !== null && timesheet.duration !== undefined && Number(timesheet.duration) > 0) {
        return Number(timesheet.duration)
    }
    if (timesheet.begin) {
        var begin = new Date(timesheet.begin)
        if (!isNaN(begin.getTime())) {
            var endMs = nowMs || Date.now()
            if (timesheet.end) {
                var end = new Date(timesheet.end)
                if (!isNaN(end.getTime())) {
                    endMs = end.getTime()
                }
            }
            return Math.max(0, Math.floor((endMs - begin.getTime()) / 1000))
        }
    }
    return Number(timesheet.duration) || 0
}

function sumTimesheetDurations(entries, nowMs) {
    var total = 0
    for (var i = 0; i < (entries || []).length; i++) {
        total += timesheetDurationSeconds(entries[i], nowMs)
    }
    return total
}

function fetchTimesheetsRange(kimaiUrl, apiToken, beginDate, endDate, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var begin = encodeURIComponent(localDateTimeString(beginDate))
    var end = encodeURIComponent(localDateTimeString(endDate))
    var page = 1
    var size = 100
    var collected = []

    function fetchPage() {
        var endpoint = "/api/timesheets?begin=" + begin + "&end=" + end
            + "&page=" + page + "&size=" + size + "&orderBy=begin&order=ASC"
        var xhr = createRequest("GET", kimaiUrl, endpoint, apiToken, false)
        runRequest(xhr, undefined, function(status, responseText, statusText) {
            if (status !== 200) {
                callback(fail(parseApiError(status, statusText, responseText)))
                return
            }
            var batch = parseJson(responseText, [])
            for (var i = 0; i < batch.length; i++) {
                collected.push(batch[i])
            }
            if (batch.length >= size && page < 20) {
                page++
                fetchPage()
            } else {
                callback(ok(collected))
            }
        })
    }

    fetchPage()
}

function formatDuration(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    return (hours < 10 ? "0" : "") + hours + ":" +
           (minutes < 10 ? "0" : "") + minutes + ":" +
           (secs < 10 ? "0" : "") + secs
}

function formatDurationShort(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    if (hours > 0) {
        return hours + "h " + minutes + "m"
    }
    return minutes + "m"
}

function projectName(timesheet) {
    if (!timesheet || !timesheet.project) {
        return ""
    }
    return timesheet.project.name || ""
}

function activityName(timesheet) {
    if (!timesheet || !timesheet.activity) {
        return ""
    }
    return timesheet.activity.name || ""
}

function projectId(timesheet) {
    if (!timesheet || !timesheet.project) {
        return 0
    }
    return timesheet.project.id || 0
}

function activityId(timesheet) {
    if (!timesheet || !timesheet.activity) {
        return 0
    }
    return timesheet.activity.id || 0
}

function deduplicateRecent(entries) {
    var seen = {}
    var result = []
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        var key = projectId(entry) + ":" + activityId(entry)
        if (seen[key]) {
            continue
        }
        seen[key] = true
        result.push(entry)
    }
    return result
}

/** Kimai calendar defaults for calendar.businessHours.begin / .end */
var DEFAULT_WORK_DAY_BEGIN = "08:00"
var DEFAULT_WORK_DAY_END = "18:00"
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
    var dayStart = startOfLocalDay(dayDate || new Date())
    var dayEnd = endOfLocalDay(dayDate || new Date())
    var dayStartMs = dayStart.getTime()
    var dayEndMs = dayEnd.getTime()
    var now = (typeof nowMs === "number" && !isNaN(nowMs)) ? nowMs : Date.now()
    var intervals = []

    for (var i = 0; i < (entries || []).length; i++) {
        var entry = entries[i]
        if (!entry || !entry.begin) {
            continue
        }
        var begin = new Date(entry.begin)
        if (isNaN(begin.getTime())) {
            continue
        }
        var endMs = now
        if (entry.end) {
            var end = new Date(entry.end)
            if (!isNaN(end.getTime())) {
                endMs = end.getTime()
            }
        }
        var startMs = Math.max(begin.getTime(), dayStartMs)
        var stopMs = Math.min(endMs, dayEndMs + 1000)
        if (stopMs <= startMs) {
            continue
        }
        intervals.push({
            startSec: Math.max(0, Math.floor((startMs - dayStartMs) / 1000)),
            endSec: Math.min(DAY_SECONDS, Math.ceil((stopMs - dayStartMs) / 1000))
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

    return {
        businessStart: (beginMin * 60) / DAY_SECONDS,
        businessEnd: (endMin * 60) / DAY_SECONDS,
        now: Math.max(0, Math.min(1, secondsOfLocalDay(day) / DAY_SECONDS)),
        segments: segments
    }
}
