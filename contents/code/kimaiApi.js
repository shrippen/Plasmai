.pragma library
.import "./timesheetFields.js" as Fields
.import "./workContractAdjust.js" as WorkAdjust
.import "./providerUtil.js" as ProviderUtil
.import "./dateTimeFormat.js" as DTF

/**
 * Internal builds only: a route answers one address itself instead of the network,
 * { handles(url), request(), token }. Published builds register none, so this stays null.
 */
var urlRoute = null

function setUrlRoute(route) {
    urlRoute = route || null
}

/** The fixed token of a routed address, or "" (the keychain is used then). */
function routeToken(url) {
    return urlRoute && urlRoute.handles(url) ? urlRoute.token : ""
}

function createRequest(method, kimaiUrl, endpoint, apiToken, isJson) {
    var xhr = urlRoute && urlRoute.handles(kimaiUrl) ? urlRoute.request() : ProviderUtil.newXhr()
    xhr.open(method, ProviderUtil.normalizeUrl(kimaiUrl) + endpoint, true)
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken)
    xhr.setRequestHeader("Accept", "application/json")
    if (isJson) {
        xhr.setRequestHeader("Content-Type", "application/json")
    }
    return xhr
}

function runRequest(xhr, body, callback) {
    ProviderUtil.runRequest(xhr, body, function(status, responseText, statusText) {
        callback(status, responseText, statusText, xhr)
    })
}

function collectFormErrors(errors, prefix) {
    var out = []
    if (!errors) {
        return out
    }
    var i
    if (errors.errors && errors.errors.length) {
        for (i = 0; i < errors.errors.length; i++) {
            out.push(prefix ? (prefix + ": " + errors.errors[i]) : String(errors.errors[i]))
        }
    }
    var children = errors.children
    if (children) {
        for (var key in children) {
            if (!children.hasOwnProperty(key)) {
                continue
            }
            var nested = collectFormErrors(children[key], key)
            for (i = 0; i < nested.length; i++) {
                out.push(nested[i])
            }
        }
    }
    return out
}

/** ProviderUtil.parseApiError, with Kimai's form errors as the detail when present. */
function parseApiError(status, statusText, responseText) {
    var err = ProviderUtil.parseApiError(status, statusText, responseText)
    var formBits = collectFormErrors(ProviderUtil.parseJson(responseText, {}).errors)
    if (formBits.length) {
        err.detail = formBits.join("; ")
    }
    return err
}

/** Kimai PATCH may return HTTP 200 with a form-error body instead of 400. */
function isFormErrorBody(body) {
    if (!body || typeof body !== "object") {
        return false
    }
    if (body.message === "Validation Failed" || body.code === 400) {
        return true
    }
    if (body.errors && (body.errors.children || body.errors.errors) && body.id === undefined) {
        return true
    }
    return false
}

function getJson(kimaiUrl, apiToken, endpoint, emptyValue, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    var xhr = createRequest("GET", kimaiUrl, endpoint, apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, emptyValue)))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

/**
 * Load a whole Kimai collection (customers / projects / activities).
 * These endpoints have no page/size parameters in Kimai 2.x and always
 * return the full list, so one request is enough; paging them only
 * duplicated the list when it had 500+ entries.
 */
function getJsonAllPages(kimaiUrl, apiToken, endpointBase, callback) {
    getJson(kimaiUrl, apiToken, endpointBase, [], function(result) {
        if (result.ok && !Array.isArray(result.data)) {
            result.data = []
        }
        callback(result)
    })
}

function testConnection(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/version", {}, callback)
}

function fetchActiveTimesheet(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/timesheets/active", [], callback)
}

/** One timesheet by id (the offline replay checks it before changing it). */
function fetchTimesheet(kimaiUrl, apiToken, timesheetId, callback) {
    getJson(kimaiUrl, apiToken, "/api/timesheets/" + encodeURIComponent(timesheetId), null, callback)
}

function fetchRecentTimesheets(kimaiUrl, apiToken, size, callback) {
    getJson(kimaiUrl, apiToken, "/api/timesheets/recent?size=" + (size || 10), [], callback)
}

function loadProjects(kimaiUrl, apiToken, callback) {
    getJsonAllPages(kimaiUrl, apiToken, "/api/projects?visible=3&order=ASC&orderBy=name", callback)
}

function loadCustomers(kimaiUrl, apiToken, callback) {
    getJsonAllPages(kimaiUrl, apiToken, "/api/customers?visible=3&order=ASC&orderBy=name", callback)
}

function loadActivities(kimaiUrl, apiToken, projectId, callback) {
    if (!projectId) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "projectId is required" }))
        return
    }
    getJsonAllPages(kimaiUrl, apiToken,
        "/api/activities?project=" + encodeURIComponent(projectId) + "&visible=3&order=ASC&orderBy=name",
        callback)
}

function loadAllActivities(kimaiUrl, apiToken, callback) {
    getJsonAllPages(kimaiUrl, apiToken, "/api/activities?visible=3&order=ASC&orderBy=name", callback)
}

function customerCreateDefaults(customers) {
    var list = customers || []
    var i
    for (i = 0; i < list.length; i++) {
        var c = list[i] || {}
        if (c.country && c.currency && c.timezone) {
            return {
                country: c.country,
                currency: c.currency,
                timezone: c.timezone
            }
        }
    }
    return { country: "DE", currency: "EUR", timezone: "UTC" }
}

function createCustomer(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "name is required" }))
        return
    }
    var defaults = customerCreateDefaults(f.customers)
    var data = {
        name: name,
        visible: true,
        billable: true,
        country: f.country || defaults.country,
        currency: f.currency || defaults.currency,
        timezone: f.timezone || defaults.timezone
    }
    var xhr = createRequest("POST", kimaiUrl, "/api/customers", apiToken, true)
    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function createProject(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name || !f.customer) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "name and customer are required" }))
        return
    }
    var data = {
        name: name,
        customer: f.customer,
        visible: true,
        billable: true
    }
    var xhr = createRequest("POST", kimaiUrl, "/api/projects", apiToken, true)
    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function createActivity(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "name is required" }))
        return
    }
    var data = {
        name: name,
        visible: true,
        billable: true
    }
    if (f.project) {
        data.project = f.project
    }
    var xhr = createRequest("POST", kimaiUrl, "/api/activities", apiToken, true)
    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function setSession(/* session */) {
    // Kimai needs no extra session context (url + token suffice).
}

function startTracking(kimaiUrl, apiToken, projectId, activityId, description, callback, extras) {
    var extra = extras || {}
    // No begin: Kimai stamps "now" in the user's Kimai timezone, which the
    // desktop clock/timezone may not match (and punch-in mode rejects begin).
    var fields = {
        project: projectId,
        activity: activityId,
        description: description || "",
        tags: Fields.resolveTags(extra)
    }
    if (extra.billable !== undefined && extra.billable !== null) {
        fields.billable = !!extra.billable
    }
    createTimesheet(kimaiUrl, apiToken, fields, callback)
}

function writeEntityId(value) {
    if (value === null || value === undefined || value === "") {
        return undefined
    }
    if (typeof value === "object") {
        return writeEntityId(value.id)
    }
    var n = Number(value)
    return isNaN(n) ? value : n
}

/**
 * Kimai TimesheetApiEditForm: tags is a text field (comma-separated),
 * billable is a boolean, project/activity are integers. Sending a JSON
 * array for tags yields "Validation Failed".
 * fields: { begin, end?, project, activity, description?, billable?, tags? }
 * `exported` is never sent: it needs the edit_export permission and Kimai
 * answers "This form should not contain extra fields" without it.
 */
function serializeTimesheetWrite(fields) {
    var f = fields || {}
    var data = {}
    if (f.begin) {
        data.begin = String(f.begin)
    }
    if (f.end) {
        data.end = String(f.end)
    }
    var pid = writeEntityId(f.project)
    if (pid !== undefined) {
        data.project = pid
    }
    var aid = writeEntityId(f.activity)
    if (aid !== undefined) {
        data.activity = aid
    }
    if (f.description !== undefined) {
        data.description = String(f.description || "")
    }
    if (f.billable !== undefined && f.billable !== null) {
        data.billable = Fields.resolveBillable(f)
    }
    if (f.tags !== undefined) {
        data.tags = Fields.formatTagString(f.tags)
    }
    return data
}

/**
 * Timesheet fields Kimai only accepts with an extra permission
 * (edit_billable_*). Without it the API form lacks the field and the whole
 * write fails with "This form should not contain extra fields".
 */
var PERMISSION_FIELDS = ["billable"]

/** Fields a server/token pair rejected before: { "<url>|<token>": { billable: true } } */
var deniedWriteFields = {}

function resetDeniedWriteFields() {
    deniedWriteFields = {}
}

function deniedFieldsKey(kimaiUrl, apiToken) {
    return ProviderUtil.normalizeUrl(kimaiUrl) + "|" + String(apiToken || "")
}

/**
 * Permission fields to drop after an "extra fields" 400: Kimai lists the
 * form's allowed fields in errors.children, so a sent permission field
 * that is missing there was rejected.
 */
function rejectedPermissionFields(responseText, data) {
    var body = ProviderUtil.parseJson(responseText, null)
    if (!body || !body.errors || !body.errors.children || !body.errors.errors) {
        return []
    }
    var extra = false
    for (var i = 0; i < body.errors.errors.length; i++) {
        if (String(body.errors.errors[i]).indexOf("extra fields") >= 0) {
            extra = true
        }
    }
    if (!extra) {
        return []
    }
    var out = []
    for (i = 0; i < PERMISSION_FIELDS.length; i++) {
        var key = PERMISSION_FIELDS[i]
        if (data.hasOwnProperty(key) && !body.errors.children.hasOwnProperty(key)) {
            out.push(key)
        }
    }
    return out
}

function withoutFields(data, keys) {
    var out = {}
    for (var k in data) {
        if (data.hasOwnProperty(k) && keys.indexOf(k) < 0) {
            out[k] = data[k]
        }
    }
    return out
}

/**
 * POST/PATCH a timesheet. Drops permission fields this token is known not
 * to have; otherwise retries once without them after an "extra fields" 400.
 * A successful result lists the dropped fields in result.droppedFields.
 */
function sendTimesheetWrite(method, kimaiUrl, apiToken, endpoint, data, callback) {
    var key = deniedFieldsKey(kimaiUrl, apiToken)
    var denied = deniedWriteFields[key] || {}
    var dropped = []
    for (var i = 0; i < PERMISSION_FIELDS.length; i++) {
        if (denied[PERMISSION_FIELDS[i]] && data.hasOwnProperty(PERMISSION_FIELDS[i])) {
            dropped.push(PERMISSION_FIELDS[i])
        }
    }
    var payload = dropped.length ? withoutFields(data, dropped) : data

    function done(result) {
        if (result.ok && dropped.length) {
            result.droppedFields = dropped
        }
        callback(result)
    }

    function send(body, allowRetry) {
        var xhr = createRequest(method, kimaiUrl, endpoint, apiToken, true)
        runRequest(xhr, JSON.stringify(body), function(status, responseText, statusText) {
            if (allowRetry && (status === 400 || status === 200)) {
                var rejected = rejectedPermissionFields(responseText, body)
                if (rejected.length) {
                    var mark = deniedWriteFields[key] || {}
                    for (var r = 0; r < rejected.length; r++) {
                        mark[rejected[r]] = true
                        dropped.push(rejected[r])
                    }
                    deniedWriteFields[key] = mark
                    send(withoutFields(body, rejected), false)
                    return
                }
            }
            finishTimesheetWrite(status, responseText, statusText, done)
        })
    }

    send(payload, true)
}

function finishTimesheetWrite(status, responseText, statusText, callback) {
    var body = ProviderUtil.parseJson(responseText, null)
    if (status >= 200 && status < 300 && !isFormErrorBody(body)) {
        callback(ProviderUtil.ok(body))
        return
    }
    callback(ProviderUtil.fail(parseApiError(status >= 200 && status < 300 ? 400 : status, statusText, responseText)))
}

/**
 * Create a timesheet (running if end omitted).
 * fields: { begin, end?, project, activity, description, billable?, tags? }
 */
function createTimesheet(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    // begin may only be omitted for a running entry (Kimai then uses "now").
    if ((!f.begin && f.end) || !f.project || !f.activity) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "begin, project and activity are required" }))
        return
    }

    var writeFields = {
        begin: f.begin,
        end: f.end,
        project: f.project,
        activity: f.activity,
        description: f.description || "",
        tags: Fields.resolveTags(f)
    }
    if (f.billable !== undefined && f.billable !== null) {
        writeFields.billable = !!f.billable
    }
    var data = serializeTimesheetWrite(writeFields)
    sendTimesheetWrite("POST", kimaiUrl, apiToken, "/api/timesheets", data, callback)
}

function stopTracking(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    if (!timesheetId) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "timesheetId is required" }))
        return
    }

    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId + "/stop", apiToken, true)
    runRequest(xhr, "{}", function(status, responseText, statusText) {
        if (status === 200) {
            callback(ProviderUtil.ok(null))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function restartTimesheet(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    if (!timesheetId) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "timesheetId is required" }))
        return
    }

    // copy=all carries description, tags, rates and meta fields over; with {}
    // Kimai restarts with an empty description.
    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId + "/restart", apiToken, true)
    runRequest(xhr, JSON.stringify({ copy: "all" }), function(status, responseText, statusText) {
        if (status === 200 || status === 201) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function patchTimesheet(kimaiUrl, apiToken, timesheetId, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    if (!timesheetId) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "timesheetId is required" }))
        return
    }

    var data = serializeTimesheetWrite(fields)
    sendTimesheetWrite("PATCH", kimaiUrl, apiToken, "/api/timesheets/" + timesheetId, data, callback)
}

function deleteTimesheet(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }
    if (!timesheetId) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "timesheetId is required" }))
        return
    }

    var xhr = createRequest("DELETE", kimaiUrl, "/api/timesheets/" + timesheetId, apiToken, false)
    runRequest(xhr, "", function(status, responseText, statusText) {
        if (status >= 200 && status < 300) {
            callback(ProviderUtil.ok(null))
        } else {
            callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function fetchCurrentUser(kimaiUrl, apiToken, callback) {
    getJson(kimaiUrl, apiToken, "/api/users/me", {}, callback)
}

/** kimai-holiday-bundle: approved absences for a calendar year. */
function fetchHolidayAbsences(kimaiUrl, apiToken, year, callback) {
    var y = year || new Date().getFullYear()
    getJson(kimaiUrl, apiToken, "/api/holiday/absences?year=" + encodeURIComponent(String(y)), [], callback)
}

/** kimai-holiday-bundle: public holidays for the user's assigned group. */
function fetchHolidayPublicHolidays(kimaiUrl, apiToken, year, callback) {
    var y = year || new Date().getFullYear()
    getJson(kimaiUrl, apiToken, "/api/holiday/public-holidays?year=" + encodeURIComponent(String(y)), [], callback)
}

function probeGet(kimaiUrl, apiToken, endpoint, callback) {
    getJson(kimaiUrl, apiToken, endpoint, [], function(result) {
        if (result.ok) {
            callback({ status: 200, ok: true })
            return
        }
        var status = result.error && result.error.status
        callback({ status: status || 0, ok: false })
    })
}

function probeTransient(status) {
    return status === 0 || status >= 500
}

var holidayPluginByUrl = {}

function resetHolidayPluginCache() {
    holidayPluginByUrl = {}
}

function rememberHolidayPlugin(kimaiUrl, source, atMs) {
    holidayPluginByUrl[ProviderUtil.normalizeUrl(kimaiUrl)] = WorkAdjust.holidayPluginCacheEntry(source, atMs)
}

function holidaySourceFromProbes(holidayTypesStatus, workContractTypesStatus) {
    return WorkAdjust.holidaySourceFromProbes(holidayTypesStatus, workContractTypesStatus)
}

function cachedHolidayPlugin(kimaiUrl, nowMs) {
    return WorkAdjust.holidayPluginCacheSource(holidayPluginByUrl[ProviderUtil.normalizeUrl(kimaiUrl)], nowMs)
}

function storeHolidayPlugin(kimaiUrl, source) {
    rememberHolidayPlugin(kimaiUrl, source, Date.now())
}

/** Detect kimai-holiday-bundle vs WorkContractBundle. Cached per server URL for one hour. */
function detectHolidayPlugin(kimaiUrl, apiToken, callback) {
    var key = ProviderUtil.normalizeUrl(kimaiUrl)
    var cached = cachedHolidayPlugin(key)
    if (cached) {
        callback(cached)
        return
    }
    probeGet(kimaiUrl, apiToken, "/api/holiday/absences/types", function(holidayProbe) {
        if (probeTransient(holidayProbe.status)) {
            callback(WorkAdjust.SOURCE_NONE)
            return
        }
        if (WorkAdjust.pluginPresentFromStatus(holidayProbe.status)) {
            storeHolidayPlugin(key, WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
            callback(WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
            return
        }
        var year = new Date().getFullYear()
        probeGet(kimaiUrl, apiToken, "/api/holiday/absences?year=" + encodeURIComponent(String(year)), function(holidayList) {
            if (probeTransient(holidayList.status)) {
                callback(WorkAdjust.SOURCE_NONE)
                return
            }
            if (WorkAdjust.pluginPresentFromStatus(holidayList.status)) {
                storeHolidayPlugin(key, WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
                callback(WorkAdjust.SOURCE_HOLIDAY_BUNDLE)
                return
            }
            probeGet(kimaiUrl, apiToken, "/api/absences/types", function(wcProbe) {
                if (probeTransient(wcProbe.status)) {
                    callback(WorkAdjust.SOURCE_NONE)
                    return
                }
                if (WorkAdjust.pluginPresentFromStatus(wcProbe.status)) {
                    storeHolidayPlugin(key, WorkAdjust.SOURCE_WORK_CONTRACT)
                    callback(WorkAdjust.SOURCE_WORK_CONTRACT)
                    return
                }
                probeGet(kimaiUrl, apiToken, "/api/absences", function(wcList) {
                    if (probeTransient(wcList.status)) {
                        callback(WorkAdjust.SOURCE_NONE)
                        return
                    }
                    var source = WorkAdjust.holidaySourceFromProbes(404, wcList.status)
                    storeHolidayPlugin(key, source)
                    callback(source)
                })
            })
        })
    })
}

// ── Plugin detection (generic, persistent per-profile cache) ──────────────
//
// detectPlugin() probes one GET path and returns a state:
//   "present"   200 (and options.accept(body) is true, if given)
//   "absent"    404, or 200 that options.accept() rejects
//   "forbidden" 403 (plugin there, the token owner lacks the permission)
//   "unknown"   network error, timeout, 401 or 5xx without a cached answer
// Transient failures never overwrite a cached answer: an offline device keeps
// the last known state (so the film day does not flip to local mode). The
// cache is a plain map the caller persists (shared.json pluginProbesJson);
// detectPlugin never writes it, it hands back `cacheEntry` to store.

var PLUGIN_PROBE_TTL_MS = 24 * 3600 * 1000

var PluginState = {
    PRESENT: "present",
    ABSENT: "absent",
    FORBIDDEN: "forbidden",
    UNKNOWN: "unknown"
}

/** Cache key: profile + server URL + plugin, so an edited profile URL re-probes. */
function pluginCacheKey(profileId, kimaiUrl, plugin) {
    return String(profileId || "") + "|" + ProviderUtil.normalizeUrl(kimaiUrl) + "|" + String(plugin || "")
}

/** State from one probe answer, or null when the answer is transient. */
function pluginStateFromProbe(status, data, accept) {
    if (status === 200) {
        if (typeof accept === "function" && !accept(data)) {
            return PluginState.ABSENT
        }
        return PluginState.PRESENT
    }
    if (status === 404) {
        return PluginState.ABSENT
    }
    if (status === 403) {
        return PluginState.FORBIDDEN
    }
    return null
}

function parsePluginCache(jsonStr) {
    if (!jsonStr) {
        return {}
    }
    var data = ProviderUtil.parseJson(jsonStr, {})
    return (data && typeof data === "object" && !Array.isArray(data)) ? data : {}
}

/** Returns a copy of `cache` with `key` set (does not mutate the input). */
function storePluginCache(cache, key, entry) {
    var next = {}
    for (var k in (cache || {})) {
        next[k] = cache[k]
    }
    next[key] = entry
    return next
}

/** { state, data, at, fresh } for a cached key, or null. */
function cachedPluginState(cache, key, nowMs, ttlMs) {
    var entry = cache ? cache[key] : null
    if (!entry || typeof entry !== "object" || !entry.state) {
        return null
    }
    var ttl = typeof ttlMs === "number" ? ttlMs : PLUGIN_PROBE_TTL_MS
    var now = typeof nowMs === "number" ? nowMs : Date.now()
    var at = Number(entry.at) || 0
    return { state: entry.state, data: entry.data === undefined ? null : entry.data, at: at, fresh: now - at < ttl && now >= at }
}

/**
 * options: { cache, key, nowMs, ttlMs, force, accept(body) -> bool }
 * callback({ state, data, status, fromCache, cacheEntry })
 * cacheEntry is non-null when the caller should store it under options.key.
 */
function detectPlugin(kimaiUrl, apiToken, path, options, callback) {
    var o = options || {}
    var now = typeof o.nowMs === "number" ? o.nowMs : Date.now()
    var cached = o.key ? cachedPluginState(o.cache, o.key, now, o.ttlMs) : null
    if (cached && cached.fresh && !o.force) {
        callback({ state: cached.state, data: cached.data, status: 0, fromCache: true, cacheEntry: null })
        return
    }
    getJson(kimaiUrl, apiToken, path, null, function(result) {
        var status = result.ok ? 200 : ((result.error && result.error.status) || 0)
        var data = result.ok ? result.data : null
        var state = pluginStateFromProbe(status, data, o.accept)
        if (state === null) {
            if (cached) {
                callback({ state: cached.state, data: cached.data, status: status, fromCache: true, cacheEntry: null })
            } else {
                callback({ state: PluginState.UNKNOWN, data: null, status: status, fromCache: false, cacheEntry: null })
            }
            return
        }
        var entry = { state: state, at: now, data: state === PluginState.PRESENT ? data : null }
        callback({ state: state, data: entry.data, status: status, fromCache: false, cacheEntry: entry })
    })
}

// ── kimai-drehzettel-bundle (/api/drehzettel) ─────────────────────────────
// Only the token owner's data: the `user` parameter is never sent.

var DREHZETTEL_PING_PATH = "/api/drehzettel/ping"
var DREHZETTEL_PLUGIN = "drehzettel"

/** ping answers v1 → usable. Older/newer plugins without v1 count as absent. */
function drehzettelPingAccepts(data) {
    return !!data && Array.isArray(data.apiVersions) && data.apiVersions.indexOf("v1") >= 0
}

/** Feature list of a ping body ("engagements", "defaults", "extraPay", …). */
function drehzettelHasFeature(ping, feature) {
    return !!ping && Array.isArray(ping.features) && ping.features.indexOf(feature) >= 0
}

/** permissions.view from ping; true when the plugin predates the permissions key. */
function drehzettelCanView(ping) {
    if (!ping || !ping.permissions || typeof ping.permissions !== "object") {
        return true
    }
    return ping.permissions.view !== false
}

function detectDrehzettel(kimaiUrl, apiToken, options, callback) {
    var o = {}
    for (var k in (options || {})) {
        o[k] = options[k]
    }
    o.accept = drehzettelPingAccepts
    detectPlugin(kimaiUrl, apiToken, DREHZETTEL_PING_PATH, o, callback)
}

/** parseApiError plus the plugin's {error, code} body (code: no_engagement, …). */
function drehzettelError(status, statusText, responseText) {
    var err = parseApiError(status, statusText, responseText)
    var body = ProviderUtil.parseJson(responseText, {})
    err.code = (body && typeof body.code === "string") ? body.code : ""
    if (body && typeof body.error === "string" && body.error) {
        err.detail = body.error
    }
    return err
}

function drehzettelQuery(projectId, dateStr) {
    var q = []
    if (projectId !== null && projectId !== undefined && projectId !== "") {
        q.push("project=" + encodeURIComponent(String(projectId)))
    }
    if (dateStr) {
        q.push("date=" + encodeURIComponent(String(dateStr)))
    }
    return q.length ? "?" + q.join("&") : ""
}

function drehzettelRequest(method, kimaiUrl, apiToken, endpoint, body, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "", code: "" }))
        return
    }
    var xhr = createRequest(method, kimaiUrl, "/api/drehzettel" + endpoint, apiToken, body !== undefined)
    runRequest(xhr, body === undefined ? undefined : JSON.stringify(body), function(status, responseText, statusText) {
        if (status === 200) {
            callback(ProviderUtil.ok(ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(drehzettelError(status, statusText, responseText)))
        }
    })
}

function isValidDateString(dateStr) {
    return /^\d{4}-\d{2}-\d{2}$/.test(String(dateStr || ""))
}

/** D1: engagements active on dateStr: [{engagementId, projectId, projectName, rulesetName, …}]. */
function fetchDrehzettelEngagements(kimaiUrl, apiToken, dateStr, callback) {
    drehzettelRequest("GET", kimaiUrl, apiToken, "/v1/engagements" + drehzettelQuery(null, dateStr), undefined, function(result) {
        if (result.ok && !Array.isArray(result.data)) {
            result.data = []
        }
        callback(result)
    })
}

/** {active, engagementId, toggleDefault, rulesetName}; no engagement is active:false, not 404. */
function fetchEngagementStatus(kimaiUrl, apiToken, projectId, dateStr, callback) {
    drehzettelRequest("GET", kimaiUrl, apiToken, "/v1/engagement-status" + drehzettelQuery(projectId, dateStr), undefined, callback)
}

function filmDayEndpoint(projectId, dateStr) {
    return "/v1/film-days/" + encodeURIComponent(String(dateStr)) + drehzettelQuery(projectId, null)
}

function fetchFilmDay(kimaiUrl, apiToken, projectId, dateStr, callback) {
    if (!isValidDateString(dateStr)) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "invalid date", code: "invalid_date" }))
        return
    }
    drehzettelRequest("GET", kimaiUrl, apiToken, filmDayEndpoint(projectId, dateStr), undefined, callback)
}

/** Partial update: only the keys in `patch` change on the server. Answers like GET. */
function putFilmDay(kimaiUrl, apiToken, projectId, dateStr, patch, callback) {
    if (!isValidDateString(dateStr)) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "invalid date", code: "invalid_date" }))
        return
    }
    drehzettelRequest("PUT", kimaiUrl, apiToken, filmDayEndpoint(projectId, dateStr), patch || {}, callback)
}

/** D5: calculated day (workMinutes, overtime, payCents, currency, …). */
function fetchDaySummary(kimaiUrl, apiToken, projectId, dateStr, callback) {
    if (!isValidDateString(dateStr)) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "invalid date", code: "invalid_date" }))
        return
    }
    drehzettelRequest("GET", kimaiUrl, apiToken,
        "/v1/days/" + encodeURIComponent(String(dateStr)) + "/summary" + drehzettelQuery(projectId, null),
        undefined, callback)
}

// ── MileageBundle / kimai-anfahrten (/api/mileage) ───────────────────────
// Trips of the token owner only: the `user` parameter is never sent.
// Form/body helpers live in mileage.js.

var MILEAGE_PING_PATH = "/api/mileage/ping"
var MILEAGE_PLUGIN = "mileage"

/** ping answers v1 → usable. */
function mileagePingAccepts(data) {
    return !!data && Array.isArray(data.apiVersions) && data.apiVersions.indexOf("v1") >= 0
}

/** permissions.view of the ping (ping needs only API access, so 200 does not mean "may use"). */
function mileageCanView(ping) {
    return !!ping && !!ping.permissions && ping.permissions.view === true
}

function detectMileage(kimaiUrl, apiToken, options, callback) {
    var o = {}
    for (var k in (options || {})) {
        o[k] = options[k]
    }
    o.accept = mileagePingAccepts
    detectPlugin(kimaiUrl, apiToken, MILEAGE_PING_PATH, o, callback)
}

/**
 * parseApiError plus the plugin's bodies: 400 {"errors": {field: message}}
 * (err.fields, detail "field: message; …"), 409 {"error": "…"}.
 */
function mileageError(status, statusText, responseText) {
    var err = parseApiError(status, statusText, responseText)
    var body = ProviderUtil.parseJson(responseText, {})
    err.fields = {}
    if (body && body.errors && typeof body.errors === "object" && !Array.isArray(body.errors)
            && !body.errors.children && !body.errors.errors) {
        var bits = []
        for (var field in body.errors) {
            err.fields[field] = String(body.errors[field])
            bits.push(field + ": " + String(body.errors[field]))
        }
        if (bits.length) {
            err.detail = bits.join("; ")
        }
    }
    if (body && typeof body.error === "string" && body.error) {
        err.detail = body.error
    }
    return err
}

function mileageRequest(method, kimaiUrl, apiToken, endpoint, body, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "", fields: {} }))
        return
    }
    var xhr = createRequest(method, kimaiUrl, "/api/mileage" + endpoint, apiToken, body !== undefined)
    runRequest(xhr, body === undefined ? undefined : JSON.stringify(body), function(status, responseText, statusText) {
        if (status >= 200 && status < 300) {
            callback(ProviderUtil.ok(status === 204 ? null : ProviderUtil.parseJson(responseText, null)))
        } else {
            callback(ProviderUtil.fail(mileageError(status, statusText, responseText)))
        }
    })
}

function mileageRangeQuery(range) {
    var r = range || {}
    var q = []
    if (r.from && r.to) {
        q.push("from=" + encodeURIComponent(String(r.from)))
        q.push("to=" + encodeURIComponent(String(r.to)))
    } else {
        if (r.year) {
            q.push("year=" + encodeURIComponent(String(r.year)))
        }
        if (r.month) {
            q.push("month=" + encodeURIComponent(String(r.month)))
        }
    }
    return q.length ? "?" + q.join("&") : ""
}

function listOrEmpty(callback) {
    return function(result) {
        if (result.ok && !Array.isArray(result.data)) {
            result.data = []
        }
        callback(result)
    }
}

/** {purposes, vehicles, taxProfiles}: [{value, label}] in the user's language. */
function fetchMileageMeta(kimaiUrl, apiToken, callback) {
    mileageRequest("GET", kimaiUrl, apiToken, "/meta", undefined, callback)
}

/**
 * range: {from, to} ("YYYY-MM-DD", needs the dateRange feature, at most
 * 366 days) or {year, month}.
 */
function fetchTrips(kimaiUrl, apiToken, range, callback) {
    mileageRequest("GET", kimaiUrl, apiToken, "/trips" + mileageRangeQuery(range), undefined, listOrEmpty(callback))
}

function createTrip(kimaiUrl, apiToken, body, callback) {
    mileageRequest("POST", kimaiUrl, apiToken, "/trips", body || {}, callback)
}

function patchTrip(kimaiUrl, apiToken, tripId, body, callback) {
    if (tripId === null || tripId === undefined || tripId === "") {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "tripId is required", fields: {} }))
        return
    }
    mileageRequest("PATCH", kimaiUrl, apiToken, "/trips/" + encodeURIComponent(String(tripId)), body || {}, callback)
}

function deleteTrip(kimaiUrl, apiToken, tripId, callback) {
    if (tripId === null || tripId === undefined || tripId === "") {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.InvalidInput, status: 0, detail: "tripId is required", fields: {} }))
        return
    }
    mileageRequest("DELETE", kimaiUrl, apiToken, "/trips/" + encodeURIComponent(String(tripId)), undefined, callback)
}

function fetchVehicles(kimaiUrl, apiToken, callback) {
    mileageRequest("GET", kimaiUrl, apiToken, "/vehicles", undefined, listOrEmpty(callback))
}

/** Open suggestions (Dawarich), optionally within range {from, to} (dateRange feature). */
function fetchTripSuggestions(kimaiUrl, apiToken, range, callback) {
    mileageRequest("GET", kimaiUrl, apiToken, "/suggestions" + mileageRangeQuery(range), undefined, listOrEmpty(callback))
}

/** Creates the trip (201 → trip JSON); 409 when the suggestion is no longer open. */
function acceptTripSuggestion(kimaiUrl, apiToken, suggestionId, body, callback) {
    mileageRequest("POST", kimaiUrl, apiToken, "/suggestions/" + encodeURIComponent(String(suggestionId)) + "/accept",
                   body || {}, callback)
}

function dismissTripSuggestion(kimaiUrl, apiToken, suggestionId, callback) {
    mileageRequest("POST", kimaiUrl, apiToken, "/suggestions/" + encodeURIComponent(String(suggestionId)) + "/dismiss",
                   {}, callback)
}

function fetchWorkContractAbsences(kimaiUrl, apiToken, beginDate, endDate, callback) {
    var begin = encodeURIComponent(DTF.localDateString(beginDate))
    var end = encodeURIComponent(DTF.localDateString(endDate))
    getJson(kimaiUrl, apiToken, "/api/absences?begin=" + begin + "&end=" + end, [], callback)
}

function fetchWorkContractPublicHolidays(kimaiUrl, apiToken, beginDate, endDate, prefs, callback) {
    var begin = encodeURIComponent(DTF.localDateString(beginDate))
    var end = encodeURIComponent(DTF.localDateString(endDate))
    var endpoint = "/api/public-holidays?begin=" + begin + "&end=" + end
    var group = prefs && prefs.public_holiday_group
    if (group !== undefined && group !== null && String(group).length > 0) {
        endpoint += "&group=" + encodeURIComponent(String(group))
    }
    getJson(kimaiUrl, apiToken, endpoint, [], callback)
}

function emptyContractAdjustments(source) {
    return {
        source: source || WorkAdjust.SOURCE_NONE,
        absences: [],
        publicHolidays: []
    }
}

/**
 * Absences + public holidays for the current week, from whichever Kimai
 * plugin is installed. Callback receives ProviderUtil.ok({ source, absences, publicHolidays }).
 */
function fetchContractAdjustments(kimaiUrl, apiToken, now, prefs, callback) {
    var when = now || new Date()
    detectHolidayPlugin(kimaiUrl, apiToken, function(source) {
        if (source === WorkAdjust.SOURCE_NONE) {
            callback(ProviderUtil.ok(emptyContractAdjustments(source)))
            return
        }
        var absencesLoaded = false
        var holidaysLoaded = false
        var absencesRaw = []
        var holidaysRaw = []

        function finish() {
            if (!absencesLoaded || !holidaysLoaded) {
                return
            }
            callback(ProviderUtil.ok({
                source: source,
                absences: absencesRaw,
                publicHolidays: holidaysRaw
            }))
        }

        function takeAbsences(result) {
            absencesRaw = (result && result.ok) ? result.data : []
            absencesLoaded = true
            finish()
        }

        function takeHolidays(result) {
            holidaysRaw = (result && result.ok) ? result.data : []
            holidaysLoaded = true
            finish()
        }

        if (source === WorkAdjust.SOURCE_WORK_CONTRACT) {
            var weekBegin = WorkAdjust.startOfWeekMonday(when)
            var weekEnd = WorkAdjust.endOfWeekSunday(when)
            fetchWorkContractAbsences(kimaiUrl, apiToken, weekBegin, weekEnd, takeAbsences)
            fetchWorkContractPublicHolidays(kimaiUrl, apiToken, weekBegin, weekEnd, prefs, takeHolidays)
            return
        }

        var year = when.getFullYear()
        fetchHolidayAbsences(kimaiUrl, apiToken, year, takeAbsences)
        fetchHolidayPublicHolidays(kimaiUrl, apiToken, year, takeHolidays)
    })
}

/** Kimai tag catalog for autocomplete (/api/tags/find). Requires `name` query param. */
function tagsFindEndpoint(term) {
    return "/api/tags/find?name=" + encodeURIComponent(String(term || "").trim())
}

function loadTags(kimaiUrl, apiToken, term, callback) {
    getJson(kimaiUrl, apiToken, tagsFindEndpoint(term), [], callback)
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
        var start = WorkAdjust.startOfWeekMonday(date)
        var total = 0
        for (var i = 0; i < 7; i++) {
            var day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            total += workDaySecondsFromPrefs(prefs, day)
        }
        return total
    }
    return 0
}

/**
 * Timesheets from beginDate to endDate (all pages). filters: optional
 * { project, activity } ids (Kimai's `project` / `activity` query filters).
 */
function fetchTimesheetsRange(kimaiUrl, apiToken, beginDate, endDate, callback, filters) {
    if (!kimaiUrl || !apiToken) {
        callback(ProviderUtil.fail({ type: ProviderUtil.ErrorType.NotConfigured, status: 0, detail: "" }))
        return
    }

    var begin = encodeURIComponent(DTF.localQueryString(beginDate))
    var end = encodeURIComponent(DTF.localQueryString(endDate))
    var page = 1
    var size = 100
    var collected = []
    var filterQuery = ""
    if (filters && filters.project !== undefined && filters.project !== null && filters.project !== "") {
        filterQuery += "&project=" + encodeURIComponent(String(filters.project))
    }
    if (filters && filters.activity !== undefined && filters.activity !== null && filters.activity !== "") {
        filterQuery += "&activity=" + encodeURIComponent(String(filters.activity))
    }

    function fetchPage() {
        var endpoint = "/api/timesheets?begin=" + begin + "&end=" + end
            + "&page=" + page + "&size=" + size + "&orderBy=begin&order=ASC&full=1"
            + filterQuery
        var xhr = createRequest("GET", kimaiUrl, endpoint, apiToken, false)
        runRequest(xhr, undefined, function(status, responseText, statusText) {
            // Kimai answers 404 for a page past the end (e.g. exactly 100 entries).
            if (status === 404 && page > 1) {
                callback(ProviderUtil.ok(collected))
                return
            }
            if (status !== 200) {
                callback(ProviderUtil.fail(parseApiError(status, statusText, responseText)))
                return
            }
            var batch = ProviderUtil.parseJson(responseText, [])
            if (!Array.isArray(batch)) {
                batch = []
            }
            for (var i = 0; i < batch.length; i++) {
                collected.push(batch[i])
            }
            var totalPages = parseInt(xhr.getResponseHeader("X-Total-Pages"), 10)
            var more = (!isNaN(totalPages) && totalPages > 0)
                ? page < totalPages
                : batch.length >= size
            if (more && page < 20) {
                page++
                fetchPage()
            } else {
                callback(ProviderUtil.ok(collected))
            }
        })
    }

    fetchPage()
}

