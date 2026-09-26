.pragma library

/**
 * Demo mode: an in-memory Kimai (with the Drehzettel and Anfahrten plugins)
 * behind the reserved address DEMO_URL, which no real server can have.
 * kimaiApi.createRequest() hands requests to that address to request()
 * instead of the network. The data is made up relative to today (a camera
 * assistant with a TV engagement, a web client, admin work); writes live
 * until the app closes. Nothing is stored on the device.
 */

var DEMO_URL = "https://demo.invalid"
var DEMO_TOKEN = "demo"

var HOUR = 3600
var DAY_MS = 86400000

var CUSTOMERS = [
    { id: 1, name: "Northlight Pictures", color: "#d65d0e", visible: true, currency: "EUR" },
    { id: 2, name: "Studio Weber", color: "#458588", visible: true, currency: "EUR" },
    { id: 3, name: "Internal", color: "#689d6a", visible: true, currency: "EUR" }
]
var PROJECTS = [
    { id: 10, name: "Harbour Lights – Season 2", customer: 1, color: "#fe8019" },
    { id: 11, name: "Website relaunch", customer: 2, color: "#83a598" },
    { id: 12, name: "Admin", customer: 3, color: "#8ec07c" }
]
var ACTIVITIES = [
    { id: 20, name: "Shooting", color: "#fabd2f" },
    { id: 21, name: "Travel", color: "#b8bb26" },
    { id: 22, name: "Prep", color: "#d3869b" },
    { id: 23, name: "Design", color: "#83a598" },
    { id: 24, name: "Development", color: "#458588" },
    { id: 25, name: "Meeting", color: "#b16286" },
    { id: 26, name: "Bookkeeping", color: "#689d6a" }
]

var FILM_PROJECT = 10
var SHOOTING = 20
var TRAVEL = 21
var DAY_RATE_CENTS = 38000
var HOURLY_CENTS = 3800

var state = null

function isDemoUrl(url) {
    return String(url || "").replace(/\/+$/, "") === DEMO_URL
}

// ── Dates ────────────────────────────────────────────────────────────────

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

function dateKey(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

/** Kimai's stamp: local time with offset, "2026-09-22T08:00:00+0200". */
function stamp(ms) {
    var d = new Date(ms)
    var off = -d.getTimezoneOffset()
    var sign = off >= 0 ? "+" : "-"
    off = Math.abs(off)
    return dateKey(d) + "T" + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
        + sign + pad2(Math.floor(off / 60)) + pad2(off % 60)
}

/** "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM[:SS]" (local; any offset is ignored) → ms. */
function parseLocal(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(String(text || ""))
    if (!m) {
        return NaN
    }
    return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0)).getTime()
}

function dayStart(ms) {
    var d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

function at(day, hours, minutes) {
    var d = new Date(day)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hours, minutes).getTime()
}

// ── Data ─────────────────────────────────────────────────────────────────

function byId(list, id) {
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].id) === String(id)) {
            return list[i]
        }
    }
    return null
}

/** Small stable variation per day (0..n-1), so the history looks lived in. */
function vary(day, n) {
    var x = Math.floor(day / DAY_MS) * 2654435761 % 4294967296
    return Math.floor((x / 4294967296) * n)
}

function addEntry(project, activity, begin, end, description) {
    var e = { id: state.nextId++, project: project, activity: activity, begin: begin,
              end: end, description: description || "", tags: [], billable: project !== 12 }
    state.entries.push(e)
    return e
}

function addTrip(entry, destination, km) {
    state.trips.push({ id: state.nextTripId++, date: dateKey(new Date(entry.begin)),
                       departure: stamp(entry.begin), arrival: stamp(entry.end),
                       purpose: "business", vehicle: "own_car", vehicleId: 1, licensePlate: "PL-AI 42",
                       start: "Home", destination: destination, distanceKm: km, roundTrip: true,
                       totalKm: km * 2, overnight: false, project: entry.project, timesheet: entry.id,
                       comment: "", source: "manual" })
}

function fillDay(day, today) {
    var weekday = new Date(day).getDay() // 0 = Sunday
    var v = vary(day, 4) * 5
    if (weekday === 0 || weekday === 6) {
        if (weekday === 6 && vary(day, 3) === 0) {
            addEntry(12, 26, at(day, 10, 0), at(day, 11, 10 + v))
        }
        return
    }
    var filming = day >= state.engagementFrom && weekday <= 4
    if (day === state.engagementFrom) {
        // First day of the engagement: travel to the location.
        var drive = addEntry(FILM_PROJECT, TRAVEL, at(day, 10, 0), at(day, 13, 25), "To the location")
        addTrip(drive, "Harbour studios", 168)
        state.filmDays[dateKey(new Date(day))] = { dayType: "travel" }
        return
    }
    if (filming) {
        var commute = addEntry(FILM_PROJECT, TRAVEL, at(day, 6, 50 + v % 10), at(day, 7, 25 + v % 10))
        addTrip(commute, "Harbour studios", 23.5)
        addEntry(FILM_PROJECT, SHOOTING, at(day, 7, 30 + v % 10), at(day, 18 + vary(day, 3), 15 + v))
        state.filmDays[dateKey(new Date(day))] = { catering: true }
        return
    }
    if (weekday === 5) {
        addEntry(11, 24, at(day, 9, 15), at(day, 12, 40 + v), "Checkout flow")
        addEntry(12, 26, at(day, 13, 30), at(day, 15, 0 + v))
        return
    }
    addEntry(11, vary(day, 2) ? 23 : 24, at(day, 9, 0), at(day, 12, 30 + v))
    addEntry(11, 25, at(day, 13, 15), at(day, 14, 0))
    addEntry(11, 24, at(day, 14, 10), at(day, 17, 30 + v))
}

/** Rebuild the demo data around nowDate (default: now). */
function reset(nowDate) {
    var now = (nowDate || new Date()).getTime()
    var today = dayStart(now)
    state = {
        now: now,
        fixedNow: !!nowDate,
        entries: [],
        trips: [],
        filmDays: {},
        customers: CUSTOMERS.slice(),
        projects: PROJECTS.slice(),
        activities: ACTIVITIES.slice(),
        nextId: 1000,
        nextTripId: 1,
        engagementFrom: today - 16 * DAY_MS,
        engagementTo: today + 30 * DAY_MS
    }
    // Two months of history; shooting days since the engagement began.
    for (var d = today - 60 * DAY_MS; d < today; d += DAY_MS) {
        fillDay(dayStart(d + 2 * HOUR * 1000), today)
    }
    // Today: on a shooting day the shoot is running, otherwise work on the website.
    var earliest = at(today, 0, 5)
    var weekday = new Date(today).getDay()
    if (weekday >= 1 && weekday <= 4 && at(today, 7, 40) < now) {
        addTrip(addEntry(FILM_PROJECT, TRAVEL, at(today, 6, 55), at(today, 7, 30)), "Harbour studios", 23.5)
        addEntry(FILM_PROJECT, SHOOTING, at(today, 7, 35), null)
        state.filmDays[dateKey(new Date(today))] = { catering: true }
    } else {
        var begin = Math.max(earliest, now - 85 * 60000)
        if (begin - 55 * 60000 > earliest) {
            addEntry(11, 25, begin - 55 * 60000, begin - 15 * 60000, "Weekly call")
        }
        addEntry(11, 24, begin, null, "Checkout flow")
    }
}

function nowMs() {
    return state.fixedNow ? state.now : Date.now()
}

// ── JSON shapes ──────────────────────────────────────────────────────────

function customerJson(c) {
    return { id: c.id, name: c.name, color: c.color, visible: true, currency: c.currency || "EUR" }
}

function projectJson(p) {
    var c = byId(state.customers, p.customer)
    return { id: p.id, name: p.name, customer: p.customer, color: p.color, visible: true,
             parentTitle: c ? c.name : "", globalActivities: true, billable: true }
}

function activityJson(a) {
    return { id: a.id, name: a.name, project: a.project || null, color: a.color, visible: true, parentTitle: null }
}

function durationOf(e) {
    return e.end ? Math.round((e.end - e.begin) / 1000) : 0
}

function entryJson(e) {
    var p = byId(state.projects, e.project) || { id: e.project, name: "", color: null, customer: 0 }
    var c = byId(state.customers, p.customer) || { id: 0, name: "", color: null }
    var a = byId(state.activities, e.activity) || { id: e.activity, name: "", color: null }
    return {
        id: e.id, begin: stamp(e.begin), end: e.end ? stamp(e.end) : null, duration: durationOf(e),
        description: e.description, tags: e.tags.slice(), billable: e.billable, exported: false, user: 1,
        project: { id: p.id, name: p.name, color: p.color, customer: { id: c.id, name: c.name, color: c.color } },
        activity: { id: a.id, name: a.name, color: a.color, project: null },
        metaFields: []
    }
}

function sortedEntries(desc) {
    return state.entries.slice().sort(function(a, b) { return desc ? b.begin - a.begin : a.begin - b.begin })
}

// ── Timesheets ───────────────────────────────────────────────────────────

function applyFields(e, f) {
    if (f.project !== undefined) e.project = Number(f.project)
    if (f.activity !== undefined) e.activity = Number(f.activity)
    if (f.description !== undefined) e.description = String(f.description || "")
    if (f.tags !== undefined) e.tags = Array.isArray(f.tags) ? f.tags.slice() : []
    if (f.billable !== undefined) e.billable = !!f.billable
    if (f.begin) e.begin = parseLocal(f.begin)
    if (f.end !== undefined) e.end = f.end ? parseLocal(f.end) : null
}

function stopRunning() {
    for (var i = 0; i < state.entries.length; i++) {
        if (!state.entries[i].end) {
            state.entries[i].end = nowMs()
        }
    }
}

function timesheets(method, rest, q, body) {
    if (method === "GET" && rest === "/active") {
        return ok(sortedEntries(true).filter(function(e) { return !e.end }).map(entryJson))
    }
    if (method === "GET" && rest === "/recent") {
        return ok(sortedEntries(true).slice(0, Number(q.size) || 10).map(entryJson))
    }
    if (method === "GET" && rest === "") {
        var from = parseLocal(q.begin)
        var to = parseLocal(q.end)
        var list = sortedEntries(false).filter(function(e) {
            return (isNaN(from) || e.begin >= from) && (isNaN(to) || e.begin <= to)
                && (!q.project || String(e.project) === String(q.project))
                && (!q.activity || String(e.activity) === String(q.activity))
        })
        var size = Number(q.size) || list.length || 1
        var page = Number(q.page) || 1
        var slice = list.slice((page - 1) * size, page * size)
        return page > 1 && slice.length === 0 ? notFound() : ok(slice.map(entryJson))
    }
    if (method === "POST" && rest === "") {
        var f = body || {}
        if (!f.project || !f.activity) {
            return { status: 400, body: { message: "begin, project and activity are required" } }
        }
        if (!f.begin) {
            stopRunning()
        }
        var e = addEntry(Number(f.project), Number(f.activity), nowMs(), null, f.description)
        applyFields(e, f)
        return ok(entryJson(e))
    }
    var m = /^\/(\d+)(\/stop|\/restart)?$/.exec(rest)
    var entry = m ? byId(state.entries, m[1]) : null
    if (!entry) {
        return notFound()
    }
    if (method === "PATCH" && m[2] === "/stop") {
        entry.end = entry.end || nowMs()
        return ok(entryJson(entry))
    }
    if (method === "PATCH" && m[2] === "/restart") {
        stopRunning()
        var copy = addEntry(entry.project, entry.activity, nowMs(), null, entry.description)
        copy.tags = entry.tags.slice()
        return ok(entryJson(copy))
    }
    if (method === "PATCH") {
        applyFields(entry, body || {})
        return ok(entryJson(entry))
    }
    if (method === "DELETE") {
        state.entries.splice(state.entries.indexOf(entry), 1)
        return { status: 204, body: null }
    }
    return notFound()
}

function create(list, body, extra) {
    var item = { id: state.nextId++, name: String((body && body.name) || "") }
    for (var k in extra) {
        item[k] = extra[k]
    }
    list.push(item)
    return item
}

// ── Drehzettel ───────────────────────────────────────────────────────────

function engagementOn(dateStr, projectId) {
    var day = parseLocal(dateStr)
    if (isNaN(day) || day < state.engagementFrom || day > state.engagementTo) {
        return null
    }
    if (projectId && String(projectId) !== String(FILM_PROJECT)) {
        return null
    }
    return {
        engagementId: 5, projectId: FILM_PROJECT, projectName: PROJECTS[0].name,
        customerName: CUSTOMERS[0].name, rulesetName: "TV FFS 2025", crewRole: "1st AC",
        validFrom: dateKey(new Date(state.engagementFrom)), validTo: dateKey(new Date(state.engagementTo)),
        toggleDefault: true, azvEligible: true, travelDays: "counted"
    }
}

function filmDayJson(dateStr) {
    var d = state.filmDays[dateStr] || {}
    var weekday = new Date(parseLocal(dateStr)).getDay()
    return {
        date: dateStr, engagementId: 5,
        breakMinutes: d.breakMinutes === undefined ? null : d.breakMinutes,
        catering: !!d.catering, category: d.category || null, note: d.note || null,
        dayType: d.dayType || "workday", productionDay: d.productionDay || null,
        extraPayCents: d.extraPayCents || 0, shootingDayNumber: d.shootingDayNumber || null,
        defaultBreakMinutes: 45,
        effectiveCategory: d.category || (weekday === 0 ? "sunday" : weekday === 6 ? "saturday" : "workday")
    }
}

function filmEntry(dateStr) {
    var day = parseLocal(dateStr)
    var best = null
    for (var i = 0; i < state.entries.length; i++) {
        var e = state.entries[i]
        if (e.project === FILM_PROJECT && e.end && dayStart(e.begin) === day
                && (!best || durationOf(e) > durationOf(best))) {
            best = e
        }
    }
    return best
}

function summaryJson(dateStr) {
    var e = filmEntry(dateStr)
    var fd = filmDayJson(dateStr)
    if (!e) {
        return { date: dateStr, engagementId: 5, hasEntry: false, begin: null, end: null, workMinutes: 0,
                 breakMinutes: 0, payCents: null, extraPayCents: 0, currency: "EUR", dayNumber: null }
    }
    var breakMinutes = fd.breakMinutes === null ? fd.defaultBreakMinutes : fd.breakMinutes
    var work = Math.max(0, Math.round(durationOf(e) / 60) - breakMinutes)
    var overtime = Math.max(0, work - 600)
    return {
        date: dateStr, engagementId: 5, hasEntry: true, begin: stamp(e.begin), end: stamp(e.end),
        workMinutes: work, breakMinutes: breakMinutes, overtime: [], nightMinutes: 0, underMinutes: 0,
        category: fd.effectiveCategory, dayNumber: new Date(e.begin).getDay() || 7,
        shootingDayNumber: fd.shootingDayNumber,
        payCents: DAY_RATE_CENTS + Math.round(overtime / 60 * HOURLY_CENTS * 1.25) + fd.extraPayCents,
        extraPayCents: fd.extraPayCents, currency: "EUR", warnings: []
    }
}

var FILM_DAY_KEYS = ["breakMinutes", "catering", "category", "note", "dayType", "productionDay",
                     "extraPayCents", "shootingDayNumber"]

function drehzettel(method, rest, q, body) {
    if (rest === "/ping") {
        return ok({ installed: true, pluginVersion: "0.1.0", apiVersions: ["v1"],
                    permissions: { view: true, manage: false },
                    features: ["errorCodes", "engagements", "defaults", "extraPay", "daySummary", "shootingDayNumber"] })
    }
    var date = q.date || dateKey(new Date(nowMs()))
    if (rest === "/v1/engagements") {
        var e = engagementOn(date, null)
        return ok(e ? [e] : [])
    }
    if (rest === "/v1/engagement-status") {
        var s = engagementOn(date, q.project)
        return ok({ active: !!s, engagementId: s ? 5 : null, toggleDefault: !!s, rulesetName: s ? s.rulesetName : null })
    }
    var m = /^\/v1\/(film-days|days)\/(\d{4}-\d{2}-\d{2})(\/summary)?$/.exec(rest)
    if (!m || !engagementOn(m[2], q.project)) {
        return { status: 404, body: { error: "No active engagement", code: "no_engagement" } }
    }
    if (m[1] === "days") {
        return ok(summaryJson(m[2]))
    }
    if (method === "PUT") {
        var d = state.filmDays[m[2]] = state.filmDays[m[2]] || {}
        for (var i = 0; i < FILM_DAY_KEYS.length; i++) {
            var k = FILM_DAY_KEYS[i]
            if (body && body.hasOwnProperty(k)) {
                d[k] = body[k]
            }
        }
    }
    return ok(filmDayJson(m[2]))
}

// ── Anfahrten ────────────────────────────────────────────────────────────

var TRIP_KEYS = ["date", "departure", "arrival", "purpose", "vehicle", "vehicleId", "start", "destination",
                 "distanceKm", "roundTrip", "overnight", "project", "timesheet", "comment"]

function tripJson(t) {
    var out = {}
    for (var k in t) {
        out[k] = t[k]
    }
    out.totalKm = t.roundTrip ? t.distanceKm * 2 : t.distanceKm
    return out
}

function mileage(method, rest, q, body) {
    if (rest === "/ping") {
        return ok({ installed: true, apiVersions: ["v1"],
                    features: ["tripTimesheet", "dateRange", "acceptFields", "commuteCheck"],
                    permissions: { view: true, editOwn: true, deleteOwn: true, editLocked: false,
                                   viewTeam: false, viewOther: false, editOther: false },
                    profile: { commuteKm: 23.5, defaultVehicle: "own_car", defaultVehicleId: 1, dawarichConfigured: false },
                    lockedMonths: [] })
    }
    if (rest === "/meta") {
        return ok({ purposes: [{ value: "commute", label: "Commute" }, { value: "business", label: "Business trip" },
                               { value: "private", label: "Private" }],
                    vehicles: [{ value: "own_car", label: "Own car" }, { value: "company_car", label: "Company car" },
                               { value: "bicycle", label: "Bicycle" }, { value: "public_transport", label: "Public transport" }],
                    taxProfiles: [] })
    }
    if (rest === "/vehicles") {
        return ok([{ id: 1, name: "Car", type: "own_car", licensePlate: "PL-AI 42", active: true }])
    }
    if (rest === "/suggestions") {
        return ok([])
    }
    if (rest === "/trips" && method === "GET") {
        var from = q.from || (q.year ? q.year + "-" + (q.month ? pad2(+q.month) : "01") + "-01" : "0000")
        var to = q.to || (q.year ? q.year + "-" + (q.month ? pad2(+q.month) : "12") + "-31" : "9999")
        return ok(state.trips.filter(function(t) { return t.date >= from && t.date <= to }).map(tripJson))
    }
    if (rest === "/trips" && method === "POST") {
        var t = { id: state.nextTripId++, source: "manual", licensePlate: "PL-AI 42", roundTrip: false }
        for (var i = 0; i < TRIP_KEYS.length; i++) {
            if (body && body.hasOwnProperty(TRIP_KEYS[i])) {
                t[TRIP_KEYS[i]] = body[TRIP_KEYS[i]]
            }
        }
        state.trips.push(t)
        return { status: 201, body: tripJson(t) }
    }
    var m = /^\/trips\/(\d+)$/.exec(rest)
    var trip = m ? byId(state.trips, m[1]) : null
    if (!trip) {
        return notFound()
    }
    if (method === "PATCH") {
        for (var j = 0; j < TRIP_KEYS.length; j++) {
            if (body && body.hasOwnProperty(TRIP_KEYS[j])) {
                trip[TRIP_KEYS[j]] = body[TRIP_KEYS[j]]
            }
        }
    }
    if (method === "DELETE") {
        state.trips.splice(state.trips.indexOf(trip), 1)
        return { status: 204, body: null }
    }
    return ok(tripJson(trip))
}

// ── Router ───────────────────────────────────────────────────────────────

function ok(body) {
    return { status: 200, body: body }
}

function notFound() {
    return { status: 404, body: { message: "Not found" } }
}

function queryOf(text) {
    var q = {}
    var parts = String(text || "").split("&")
    for (var i = 0; i < parts.length; i++) {
        if (!parts[i]) {
            continue
        }
        var kv = parts[i].split("=")
        q[decodeURIComponent(kv[0])] = decodeURIComponent((kv[1] || "").replace(/\+/g, " "))
    }
    return q
}

/** Answer one request: { status, body }. */
function handle(method, url, bodyText) {
    if (!state) {
        reset()
    }
    var path = String(url).slice(DEMO_URL.length)
    var qi = path.indexOf("?")
    var q = queryOf(qi >= 0 ? path.slice(qi + 1) : "")
    path = qi >= 0 ? path.slice(0, qi) : path
    var body = null
    try {
        body = bodyText ? JSON.parse(bodyText) : null
    } catch (e) {
        return { status: 400, body: { message: "Invalid JSON" } }
    }
    if (path === "/api/version") {
        return ok({ version: "2.67.0", versionId: 26700, copyright: "Kimai demo" })
    }
    if (path === "/api/users/me") {
        var prefs = [{ name: "work_contract_type", value: "day" }]
        var days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (var i = 0; i < days.length; i++) {
            prefs.push({ name: "work_" + days[i], value: String(i < 5 ? 8 * HOUR : 0) })
        }
        return ok({ id: 1, username: "demo", alias: "Alex Demo", preferences: prefs })
    }
    if (path === "/api/customers") {
        return method === "POST" ? ok(customerJson(create(state.customers, body, { color: "#928374", currency: "EUR" })))
                                 : ok(state.customers.map(customerJson))
    }
    if (path === "/api/projects") {
        return method === "POST" ? ok(projectJson(create(state.projects, body, { customer: Number(body && body.customer), color: "#928374" })))
                                 : ok(state.projects.map(projectJson))
    }
    if (path === "/api/activities") {
        if (method === "POST") {
            return ok(activityJson(create(state.activities, body, { project: body && body.project ? Number(body.project) : null, color: "#928374" })))
        }
        return ok(state.activities.filter(function(a) {
            return !a.project || !q.project || String(a.project) === String(q.project)
        }).map(activityJson))
    }
    if (path === "/api/tags/find") {
        return ok([])
    }
    if (path.indexOf("/api/timesheets") === 0) {
        return timesheets(method, path.slice("/api/timesheets".length), q, body)
    }
    if (path.indexOf("/api/drehzettel") === 0) {
        return drehzettel(method, path.slice("/api/drehzettel".length), q, body)
    }
    if (path.indexOf("/api/mileage") === 0) {
        return mileage(method, path.slice("/api/mileage".length), q, body)
    }
    return notFound()
}

/** XMLHttpRequest stand-in: answers from handle(), a moment later like a network would. */
function request() {
    var xhr = {
        readyState: 0, status: 0, statusText: "", responseText: "",
        onreadystatechange: null, onerror: null,
        method: "GET", url: "",
        open: function(method, url) {
            xhr.method = method
            xhr.url = url
            xhr.readyState = 1
        },
        setRequestHeader: function() {},
        getResponseHeader: function() { return null },
        abort: function() {
            xhr.aborted = true
        },
        send: function(body) {
            var answer = handle(xhr.method, xhr.url, body)
            function deliver() {
                if (xhr.aborted) {
                    return
                }
                xhr.status = answer.status
                xhr.statusText = answer.status === 200 ? "OK" : ""
                xhr.responseText = answer.body === null || answer.body === undefined ? "" : JSON.stringify(answer.body)
                xhr.readyState = 4
                if (xhr.onreadystatechange) {
                    xhr.onreadystatechange()
                }
            }
            if (typeof Qt !== "undefined" && Qt.callLater) {
                Qt.callLater(deliver)
            } else {
                deliver()
            }
        }
    }
    return xhr
}
