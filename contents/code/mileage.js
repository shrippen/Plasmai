.pragma library

/**
 * Trips of the Kimai MileageBundle (kimai-anfahrten, /api/mileage): the trip
 * form shared by the Plasmoid's TripSheet and the app's TripsPage, request
 * bodies, month/range helpers and km totals. Requests live in kimaiApi.js
 * (fetchTrips, createTrip, …); nothing here touches QML or the network.
 *
 * Form shape (strings where the UI edits text):
 *   { id, date "YYYY-MM-DD", purpose, vehicle, vehicleId, start, destination,
 *     distanceKm "12,5", roundTrip, withTimes, departure "HH:MM",
 *     arrival "HH:MM", comment, project, timesheet }
 * Only the token owner's trips: the `user` parameter is never sent.
 */

var Purpose = {
    COMMUTE: "commute",
    BUSINESS: "business",
    PRIVATE: "private"
}

var DEFAULT_VEHICLE = "own_car"
/** Trip::MAX_DISTANCE / MAX_COMMENT of the plugin. */
var MAX_DISTANCE_KM = 10000
var MAX_COMMENT = 1000

/**
 * Plugin values when /meta is not loaded (labels come from the caller's i18n),
 * in the plugin's order: pickers keep their index when /meta arrives later.
 */
var PURPOSES = ["commute", "business", "private"]
var VEHICLES = ["own_car", "rental_car", "company_car", "motorcycle", "bicycle", "public_transport", "other"]

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

function dateString(date) {
    if (!date || isNaN(date.getTime())) {
        return ""
    }
    return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function isDateString(s) {
    return /^\d{4}-\d{2}-\d{2}$/.test(String(s || ""))
}

function isTimeString(s) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(s || ""))
    return !!m && Number(m[1]) <= 23 && Number(m[2]) <= 59
}

/** "YYYY-MM-DD" → local Date at midnight, or null. */
function parseDateString(s) {
    if (!isDateString(s)) {
        return null
    }
    var p = String(s).split("-")
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    // Date() rolls 2026-09-31 over to October: only real calendar days count.
    return (isNaN(d.getTime()) || dateString(d) !== String(s)) ? null : d
}

/** { from, to } of the calendar month containing date (both inclusive). */
function monthRange(date) {
    var d = date || new Date()
    var first = new Date(d.getFullYear(), d.getMonth(), 1)
    var last = new Date(d.getFullYear(), d.getMonth() + 1, 0)
    return { from: dateString(first), to: dateString(last) }
}

/** { from, to } of the Monday-based week containing date. */
function weekRange(date) {
    var d = date || new Date()
    var day = d.getDay() === 0 ? 7 : d.getDay()
    var monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (day - 1))
    var sunday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)
    return { from: dateString(monday), to: dateString(sunday) }
}

function addMonths(date, delta) {
    var d = date || new Date()
    return new Date(d.getFullYear(), d.getMonth() + delta, 1)
}

// ── ping ────────────────────────────────────────────────────────────────

function hasFeature(ping, feature) {
    return !!ping && Array.isArray(ping.features) && ping.features.indexOf(feature) >= 0
}

/** permissions[name] of the ping; "view" is true for a plugin without permissions (never seen, defensive). */
function can(ping, name) {
    if (!ping || !ping.permissions || typeof ping.permissions !== "object") {
        return name === "view"
    }
    return ping.permissions[name] === true
}

function profileOf(ping) {
    return (ping && ping.profile && typeof ping.profile === "object") ? ping.profile : {}
}

/** The profile's commute distance in km, or null (not set / 0). */
function commuteKm(ping) {
    var km = Number(profileOf(ping).commuteKm)
    return km > 0 ? km : null
}

/** "YYYY-MM" of dateStr is closed for this user (and they may not edit closed months). */
function isMonthLocked(ping, dateStr) {
    if (!ping || !Array.isArray(ping.lockedMonths) || !isDateString(dateStr)) {
        return false
    }
    if (can(ping, "editLocked")) {
        return false
    }
    return ping.lockedMonths.indexOf(String(dateStr).substring(0, 7)) >= 0
}

// ── form ────────────────────────────────────────────────────────────────

function emptyForm(ping, dateStr) {
    var profile = profileOf(ping)
    return {
        id: null,
        date: isDateString(dateStr) ? dateStr : dateString(new Date()),
        purpose: Purpose.BUSINESS,
        vehicle: profile.defaultVehicle ? String(profile.defaultVehicle) : DEFAULT_VEHICLE,
        vehicleId: (profile.defaultVehicleId !== undefined && profile.defaultVehicleId !== null) ? profile.defaultVehicleId : null,
        start: "",
        destination: "",
        distanceKm: "",
        roundTrip: false,
        withTimes: false,
        departure: "",
        arrival: "",
        comment: "",
        project: null,
        timesheet: null
    }
}

/**
 * "HH:MM" of a trip timestamp as the plugin wrote it (it formats in the
 * user's Kimai timezone, which is also how it reads "HH:MM" back), or "".
 */
function timeOfStamp(stamp) {
    var m = /T(\d{2}):(\d{2})/.exec(String(stamp || ""))
    return m ? m[1] + ":" + m[2] : ""
}

function formatKm(km) {
    var n = Number(km)
    if (!isFinite(n)) {
        return ""
    }
    var rounded = Math.round(n * 10) / 10
    return String(rounded)
}

/** Km for display, locale formatted ("139,5", "1.234,6", "47"); forms use formatKm. */
function displayKm(km, locale) {
    var n = Number(km)
    if (km === "" || km === null || km === undefined || !isFinite(n)) {
        return ""
    }
    var rounded = Math.round(n * 10) / 10
    var decimals = rounded % 1 === 0 ? 0 : 1
    return rounded.toLocaleString(locale || Qt.locale(), "f", decimals)
}

/** API trip JSON → form. */
function formFromTrip(trip) {
    var t = trip || {}
    var departure = timeOfStamp(t.departure)
    var arrival = timeOfStamp(t.arrival)
    return {
        id: t.id === undefined ? null : t.id,
        date: isDateString(t.date) ? t.date : dateString(new Date()),
        purpose: t.purpose || Purpose.BUSINESS,
        vehicle: t.vehicle || DEFAULT_VEHICLE,
        vehicleId: t.vehicleId === undefined ? null : t.vehicleId,
        start: t.start || "",
        destination: t.destination || "",
        distanceKm: (t.distanceKm === null || t.distanceKm === undefined) ? "" : formatKm(t.distanceKm),
        roundTrip: t.roundTrip === true,
        withTimes: departure.length > 0 || arrival.length > 0,
        departure: departure,
        arrival: arrival,
        comment: t.comment || "",
        project: t.project === undefined ? null : t.project,
        timesheet: t.timesheet === undefined ? null : t.timesheet
    }
}

/**
 * New trip linked to a Kimai entry: its day, project and id (the plugin
 * sets the project from the timesheet as well). A business trip by default.
 */
function formForTimesheet(ping, timesheet, projectIdOf) {
    // Kimai writes begin in the user's timezone: its date part is the entry's day there.
    var m = timesheet && timesheet.begin ? /^(\d{4}-\d{2}-\d{2})/.exec(String(timesheet.begin)) : null
    var form = emptyForm(ping, m ? m[1] : "")
    if (timesheet && timesheet.id !== undefined && timesheet.id !== null) {
        form.timesheet = timesheet.id
    }
    var pid = timesheet && typeof projectIdOf === "function" ? projectIdOf(timesheet) : null
    if (pid !== null && pid !== undefined && pid !== "") {
        form.project = pid
    }
    return form
}

/** "12,5" / "12.5" / 12.5 → 12.5; "" / invalid → null. */
function parseDistance(value) {
    if (value === null || value === undefined) {
        return null
    }
    if (typeof value === "number") {
        return isFinite(value) ? value : null
    }
    var s = String(value).replace(/\s|km/gi, "").replace(",", ".")
    if (!s.length || !/^\d*\.?\d+$|^\d+\.$/.test(s)) {
        return null
    }
    var n = Number(s)
    return isFinite(n) ? n : null
}

/**
 * Field errors of a form as { field: code }:
 *   date "invalid" | "locked", distanceKm "required" | "invalid",
 *   departure/arrival "invalid", arrival "beforeDeparture", comment "tooLong".
 * A commute may leave the distance empty when the profile has a commute
 * distance (the plugin fills it in).
 */
function validateForm(form, ping) {
    var f = form || {}
    var errors = {}
    if (!isDateString(f.date) || !parseDateString(f.date)) {
        errors.date = "invalid"
    } else if (isMonthLocked(ping, f.date)) {
        errors.date = "locked"
    }
    var text = String(f.distanceKm === null || f.distanceKm === undefined ? "" : f.distanceKm).trim()
    if (!text.length) {
        var isNew = f.id === null || f.id === undefined
        var profileFillsIn = isNew && f.purpose === Purpose.COMMUTE && commuteKm(ping) !== null
        if (!profileFillsIn) {
            errors.distanceKm = "required"
        }
    } else {
        var km = parseDistance(text)
        if (km === null || km <= 0 || km > MAX_DISTANCE_KM) {
            errors.distanceKm = "invalid"
        }
    }
    if (f.withTimes) {
        if (f.departure && !isTimeString(f.departure)) {
            errors.departure = "invalid"
        }
        if (f.arrival && !isTimeString(f.arrival)) {
            errors.arrival = "invalid"
        }
        if (!errors.departure && !errors.arrival && f.departure && f.arrival
                && normTime(f.arrival) <= normTime(f.departure)) {
            errors.arrival = "beforeDeparture"
        }
    }
    if (String(f.comment || "").trim().length > MAX_COMMENT) {
        errors.comment = "tooLong"
    }
    return errors
}

function normTime(s) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(s || ""))
    return m ? pad2(Number(m[1])) + ":" + m[2] : ""
}

function hasErrors(errors) {
    for (var k in (errors || {})) {
        return true
    }
    return false
}

function nullIfEmpty(s) {
    var t = String(s === null || s === undefined ? "" : s).trim()
    return t.length ? t : null
}

/** Full request body of a form (all editable fields). */
function toApi(form, ping) {
    var f = form || {}
    var body = {
        date: f.date,
        purpose: f.purpose || Purpose.BUSINESS,
        vehicle: f.vehicle || DEFAULT_VEHICLE,
        start: nullIfEmpty(f.start),
        destination: nullIfEmpty(f.destination),
        distanceKm: parseDistance(f.distanceKm),
        roundTrip: f.roundTrip === true,
        departure: f.withTimes && f.departure ? normTime(f.departure) : null,
        arrival: f.withTimes && f.arrival ? normTime(f.arrival) : null,
        comment: nullIfEmpty(f.comment),
        project: (f.project === "" || f.project === undefined) ? null : f.project
    }
    if (f.vehicleId !== undefined) {
        body.vehicleId = (f.vehicleId === "" ? null : f.vehicleId)
    }
    if (hasFeature(ping, "tripTimesheet")) {
        body.timesheet = (f.timesheet === "" || f.timesheet === undefined) ? null : f.timesheet
    }
    return body
}

/**
 * Body for POST (original null: every set field) or PATCH (only the keys
 * that differ from the loaded trip). A new commute without distance leaves
 * distanceKm out, so the plugin takes the profile's commute distance.
 */
function toApiBody(form, original, ping) {
    var body = toApi(form, ping)
    if (!original) {
        var out = {}
        for (var k in body) {
            if (body[k] === null || body[k] === undefined) {
                continue
            }
            out[k] = body[k]
        }
        return out
    }
    var base = toApi(formFromTrip(original), ping)
    var patch = {}
    for (var key in body) {
        if (JSON.stringify(body[key]) !== JSON.stringify(base[key])) {
            patch[key] = body[key]
        }
    }
    return patch
}

function isEmptyBody(body) {
    for (var k in (body || {})) {
        return false
    }
    return true
}

/** POST body of "commute today": the plugin fills distance and addresses. */
function commuteBody(dateStr) {
    return { purpose: Purpose.COMMUTE, date: isDateString(dateStr) ? dateStr : dateString(new Date()) }
}

/**
 * Accept body for a suggestion: optional purpose/vehicle, and with the
 * acceptFields feature project/distanceKm/comment/timesheet.
 */
function acceptBody(ping, options) {
    var o = options || {}
    var body = {}
    if (o.purpose) {
        body.purpose = o.purpose
    }
    if (o.vehicle) {
        body.vehicle = o.vehicle
    }
    if (hasFeature(ping, "acceptFields")) {
        var keys = ["project", "distanceKm", "comment", "timesheet"]
        for (var i = 0; i < keys.length; i++) {
            var v = o[keys[i]]
            if (v !== undefined && v !== null && v !== "") {
                body[keys[i]] = keys[i] === "distanceKm" ? parseDistance(v) : v
            }
        }
    }
    return body
}

/**
 * Form showing a suggestion before it is accepted ("Edit and accept"): date,
 * route and times as detected (read-only in the sheet), purpose, vehicle
 * and distance to adjust.
 */
function formFromSuggestion(ping, suggestion) {
    var sg = suggestion || {}
    var start = new Date(String(sg.start || ""))
    var end = new Date(String(sg.end || ""))
    var form = emptyForm(ping, isNaN(start.getTime()) ? "" : dateString(start))
    form.purpose = sg.purpose || Purpose.BUSINESS
    if (sg.vehicle) {
        form.vehicle = String(sg.vehicle)
    }
    form.start = sg.from || ""
    form.destination = sg.to || ""
    form.distanceKm = (sg.distanceKm === null || sg.distanceKm === undefined) ? "" : formatKm(sg.distanceKm)
    if (!isNaN(start.getTime()) && !isNaN(end.getTime())) {
        form.withTimes = true
        form.departure = pad2(start.getHours()) + ":" + pad2(start.getMinutes())
        form.arrival = pad2(end.getHours()) + ":" + pad2(end.getMinutes())
    }
    if (sg.project !== undefined && sg.project !== null) {
        form.project = sg.project
    }
    if (sg.timesheet !== undefined && sg.timesheet !== null) {
        form.timesheet = sg.timesheet
    }
    return form
}

/** Accept body from an edited suggestion form (see acceptBody). */
function acceptBodyFromForm(ping, form, suggestion) {
    var f = form || {}
    var sg = suggestion || {}
    var opts = { purpose: f.purpose, vehicle: f.vehicle, comment: nullIfEmpty(f.comment) }
    var km = parseDistance(f.distanceKm)
    if (km !== null && km !== Number(sg.distanceKm)) {
        opts.distanceKm = km
    }
    if (f.project !== null && f.project !== undefined && String(f.project) !== String(sg.project)) {
        opts.project = f.project
    }
    if (f.timesheet !== null && f.timesheet !== undefined && String(f.timesheet) !== String(sg.timesheet)) {
        opts.timesheet = f.timesheet
    }
    return acceptBody(ping, opts)
}

// ── lists and totals ────────────────────────────────────────────────────

/** Trip km counting the return leg (the plugin's totalKm, else distance × 2 for round trips). */
function tripKm(trip) {
    if (!trip) {
        return 0
    }
    if (typeof trip.totalKm === "number" && isFinite(trip.totalKm)) {
        return trip.totalKm
    }
    var km = Number(trip.distanceKm) || 0
    return trip.roundTrip ? km * 2 : km
}

/**
 * { count, km, byPurpose: { commute, business, private } } of the trips
 * whose date is within [fromStr, toStr] (both inclusive, "YYYY-MM-DD";
 * empty = unbounded).
 */
function summarize(trips, fromStr, toStr) {
    var out = { count: 0, km: 0, byPurpose: { commute: 0, business: 0, "private": 0 } }
    for (var i = 0; i < (trips || []).length; i++) {
        var t = trips[i]
        if (!t || !isDateString(t.date)) {
            continue
        }
        if (fromStr && t.date < fromStr) {
            continue
        }
        if (toStr && t.date > toStr) {
            continue
        }
        var km = tripKm(t)
        out.count += 1
        out.km += km
        if (out.byPurpose.hasOwnProperty(t.purpose)) {
            out.byPurpose[t.purpose] += km
        }
    }
    out.km = Math.round(out.km * 10) / 10
    for (var p in out.byPurpose) {
        out.byPurpose[p] = Math.round(out.byPurpose[p] * 10) / 10
    }
    return out
}

/** Trips sorted newest first (date, then departure, then id). */
function sortTrips(trips) {
    var copy = (trips || []).slice()
    copy.sort(function(a, b) {
        if (a.date !== b.date) {
            return a.date < b.date ? 1 : -1
        }
        var da = String(a.departure || "")
        var db = String(b.departure || "")
        if (da !== db) {
            return da < db ? 1 : -1
        }
        return (Number(b.id) || 0) - (Number(a.id) || 0)
    })
    return copy
}

/** Trips linked to one Kimai entry. */
function tripsForTimesheet(trips, timesheetId) {
    var out = []
    for (var i = 0; i < (trips || []).length; i++) {
        if (trips[i] && trips[i].timesheet !== null && trips[i].timesheet !== undefined
                && String(trips[i].timesheet) === String(timesheetId)) {
            out.push(trips[i])
        }
    }
    return out
}

/** "From → To" of a trip or suggestion, with whatever is known. */
function routeText(from, to) {
    var a = String(from || "").trim()
    var b = String(to || "").trim()
    if (a && b) {
        return a + " → " + b
    }
    return a || b
}

/**
 * Label of a value: the translated fallback map first (the plugin's /meta
 * labels are always English), else the /meta list ([{value,label}]), else the value.
 */
function labelOf(list, value, fallback) {
    if (fallback && fallback[value]) {
        return fallback[value]
    }
    for (var i = 0; i < (list || []).length; i++) {
        if (list[i] && list[i].value === value) {
            return String(list[i].label || value)
        }
    }
    return String(value || "")
}

/** [{value,label}] for a picker: /meta list when loaded, else the known values; labels as in labelOf. */
function options(metaList, values, fallback) {
    if (Array.isArray(metaList) && metaList.length) {
        return metaList.map(function(o) {
            return { value: String(o.value), label: labelOf(metaList, String(o.value), fallback) }
        })
    }
    return values.map(function(v) { return { value: v, label: (fallback && fallback[v]) || v } })
}
