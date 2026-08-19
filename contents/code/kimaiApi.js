.pragma library
.import "./colorDistinct.js" as ColorDistinct
.import "./timesheetFields.js" as Fields
.import "./workContractAdjust.js" as WorkAdjust

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
        callback(xhr.status, xhr.responseText, xhr.statusText, xhr)
    }
    xhr.onerror = function() {
        callback(0, "", "Network error", xhr)
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

function parseApiError(status, statusText, responseText) {
    var body = parseJson(responseText, {})
    var formBits = collectFormErrors(body.errors)
    var detail = formBits.length
        ? formBits.join("; ")
        : (body.title || body.detail || body.message || body["hydra:description"] || "")

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

/** True when Kimai provided an explicit color (non-empty). */
function hasExplicitColor(value) {
    return String(value || "").trim().length > 0
}

/**
 * Kimai display color cascade:
 *   activity → project → customer → default
 */
function activityColor(activity) {
    if (activity && typeof activity === "object" && hasExplicitColor(activity.color)) {
        return normalizeCustomerColor(activity.color)
    }
    return ""
}

function projectColor(project) {
    if (project && typeof project === "object" && hasExplicitColor(project.color)) {
        return normalizeCustomerColor(project.color)
    }
    return ""
}

function customerColorOnly(project, customersById) {
    if (!project || typeof project !== "object") {
        return ""
    }
    if (project.customer && typeof project.customer === "object" && hasExplicitColor(project.customer.color)) {
        return normalizeCustomerColor(project.customer.color)
    }
    var cid = customerIdOfProject(project)
    if (cid && customersById) {
        var cust = customersById[cid] || customersById[String(cid)]
        if (cust && hasExplicitColor(cust.color)) {
            return normalizeCustomerColor(cust.color)
        }
    }
    return ""
}

/** Customer-category bar color (shifted), for section headers and customer pills. */
function customerBarColor(project, customersById) {
    var cid = customerIdOfProject(project)
    var raw = customerColorOnly(project, customersById) || DEFAULT_CUSTOMER_COLOR
    return ColorDistinct.adjust("customer", cid, raw)
}

/**
 * Resolve the hierarchy color for a bar: activity → project → customer → default,
 * each adjusted within its category. Returns { color, category, id }.
 */
function barColorInfo(activity, project, customersById) {
    var ac = activityColor(activity)
    if (ac && activity && activity.id !== null && activity.id !== undefined) {
        return {
            color: ColorDistinct.adjust("activity", activity.id, ac),
            category: "activity",
            id: activity.id
        }
    }
    var pc = projectColor(project)
    if (pc && project && project.id !== null && project.id !== undefined) {
        return {
            color: ColorDistinct.adjust("project", project.id, pc),
            category: "project",
            id: project.id
        }
    }
    var cid = customerIdOfProject(project)
    var cc = customerColorOnly(project, customersById) || DEFAULT_CUSTOMER_COLOR
    return {
        color: ColorDistinct.adjust("customer", cid, cc),
        category: "customer",
        id: cid || null
    }
}

function barColorInfoFromTimesheet(timesheet, customersById) {
    if (!timesheet) {
        return { color: DEFAULT_CUSTOMER_COLOR, category: "", id: null }
    }
    var activity = (typeof timesheet.activity === "object" && timesheet.activity) ? timesheet.activity : null
    var project = (typeof timesheet.project === "object" && timesheet.project) ? timesheet.project : null
    return barColorInfo(activity, project, customersById)
}

/**
 * Customer / project colors for compact panel pills.
 * Project falls back to the customer color when Kimai has no project color.
 */
function panelPillInfo(timesheet, projects, customersById) {
    var empty = {
        customerColor: DEFAULT_CUSTOMER_COLOR,
        customerId: null,
        projectColor: DEFAULT_CUSTOMER_COLOR,
        projectId: null
    }
    if (!timesheet) {
        return empty
    }
    var project = (typeof timesheet.project === "object" && timesheet.project)
        ? timesheet.project
        : null
    if (!project) {
        var pid = projectId(timesheet)
        var byId = indexById(projects)
        project = byId[pid] || byId[String(pid)] || null
    }
    var cid = customerIdOfProject(project)
    var cc = customerColorOnly(project, customersById) || DEFAULT_CUSTOMER_COLOR
    var pc = projectColor(project) || cc
    return {
        customerColor: cc,
        customerId: cid || null,
        projectColor: pc,
        projectId: projectId(timesheet) || null
    }
}

function effectiveColorFromProject(project, customersById) {
    return barColorInfo(null, project, customersById).color
}

function effectiveColorFromActivity(activity, project, customersById) {
    return barColorInfo(activity, project, customersById).color
}

function effectiveColorFromTimesheet(timesheet, customersById) {
    return barColorInfoFromTimesheet(timesheet, customersById).color
}

function customerColorOfProject(project, customersById) {
    return effectiveColorFromProject(project, customersById)
}

function customerColorFromTimesheet(timesheet, customersById) {
    return effectiveColorFromTimesheet(timesheet, customersById)
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

/**
 * Fetch every page of a Kimai collection (default page size is 50).
 * endpointBase: path + query without page/size (e.g. "/api/activities?visible=3").
 */
function getJsonAllPages(kimaiUrl, apiToken, endpointBase, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var page = 1
    var size = 500
    var collected = []
    var sep = String(endpointBase).indexOf("?") >= 0 ? "&" : "?"

    function fetchPage() {
        var endpoint = endpointBase + sep + "page=" + page + "&size=" + size
        var xhr = createRequest("GET", kimaiUrl, endpoint, apiToken, false)
        runRequest(xhr, undefined, function(status, responseText, statusText) {
            if (status !== 200) {
                callback(fail(parseApiError(status, statusText, responseText)))
                return
            }
            var batch = parseJson(responseText, [])
            if (!Array.isArray(batch)) {
                batch = []
            }
            for (var i = 0; i < batch.length; i++) {
                collected.push(batch[i])
            }
            var totalPages = parseInt(xhr.getResponseHeader("X-Total-Pages"), 10)
            var more = false
            if (!isNaN(totalPages) && totalPages > 0) {
                more = page < totalPages
            } else {
                more = batch.length >= size
            }
            if (more && page < 40) {
                page++
                fetchPage()
            } else {
                callback(ok(collected))
            }
        })
    }

    fetchPage()
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
    getJsonAllPages(kimaiUrl, apiToken, "/api/projects?visible=3&order=ASC&orderBy=name", callback)
}

function loadCustomers(kimaiUrl, apiToken, callback) {
    getJsonAllPages(kimaiUrl, apiToken, "/api/customers?visible=3&order=ASC&orderBy=name", callback)
}

function loadActivities(kimaiUrl, apiToken, projectId, callback) {
    if (!projectId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
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
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name) {
        callback(fail({ type: "config", status: 0, detail: "name is required" }))
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
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function createProject(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name || !f.customer) {
        callback(fail({ type: "config", status: 0, detail: "name and customer are required" }))
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
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function createActivity(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    var name = String(f.name || "").trim()
    if (!name) {
        callback(fail({ type: "config", status: 0, detail: "name is required" }))
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
            callback(ok(parseJson(responseText, null)))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
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
        } else if (String(pid) === String(projectId)) {
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
                // Section bars always use the customer-category shifted color
                color: customerBarColor(project, customersById),
                customerId: customerIdOfProject(project),
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
            var proj = list[p]
            var bar = barColorInfo(null, proj, customersById)
            rows.push({
                customerName: customerName,
                customerId: group.customerId,
                customerColor: group.color,
                colorCategory: bar.category,
                entityId: bar.id,
                projectColor: bar.color,
                project: proj
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
        var projectName = (row.project && row.project.name) || ""
        items.push({
            label: projectName,
            searchText: customerName + " " + projectName,
            section: customerName,
            // Section header uses customer-category color; row uses project cascade
            color: row.customerColor,
            colorCategory: "customer",
            entityId: row.customerId,
            rowColor: row.projectColor,
            rowColorCategory: row.colorCategory,
            rowEntityId: row.entityId,
            value: row.project
        })
    }
    return items
}

function activityPickerItems(activities, projectId, project, customersById) {
    var rows = activitiesListModel(activities, projectId)
    var items = []
    for (var i = 0; i < rows.length; i++) {
        var activity = rows[i].activity
        var bar = barColorInfo(activity, project || null, customersById || {})
        items.push({
            label: activity.name || activity.title || ("#" + activity.id),
            searchText: (activity.name || activity.title || "") + " " + activity.id,
            section: rows[i].section,
            color: bar.color,
            colorCategory: bar.category,
            entityId: bar.id,
            value: activity
        })
    }
    return items
}

function setSession(/* session */) {
    // Kimai needs no extra session context (url + token suffice).
}

function startTracking(kimaiUrl, apiToken, projectId, activityId, description, callback, extras) {
    var extra = extras || {}
    var fields = {
        begin: localDateTimeString(new Date()),
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
 * fields: { begin, end?, project, activity, description?, billable?, tags?, exported? }
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
    if (f.exported !== undefined && f.exported !== null) {
        data.exported = !!f.exported
    }
    return data
}

function finishTimesheetWrite(status, responseText, statusText, callback) {
    var body = parseJson(responseText, null)
    if (status >= 200 && status < 300 && !isFormErrorBody(body)) {
        callback(ok(body))
        return
    }
    callback(fail(parseApiError(status >= 200 && status < 300 ? 400 : status, statusText, responseText)))
}

/**
 * Create a timesheet (running if end omitted).
 * fields: { begin, end?, project, activity, description, billable?, tags? }
 */
function createTimesheet(kimaiUrl, apiToken, fields, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }
    var f = fields || {}
    if (!f.begin || !f.project || !f.activity) {
        callback(fail({ type: "config", status: 0, detail: "begin, project and activity are required" }))
        return
    }

    var writeFields = {
        begin: f.begin,
        end: f.end,
        project: f.project,
        activity: f.activity,
        description: f.description || "",
        exported: false,
        tags: Fields.resolveTags(f)
    }
    if (f.billable !== undefined && f.billable !== null) {
        writeFields.billable = !!f.billable
    }
    var data = serializeTimesheetWrite(writeFields)

    var xhr = createRequest("POST", kimaiUrl, "/api/timesheets", apiToken, true)
    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        finishTimesheetWrite(status, responseText, statusText, callback)
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

    var data = serializeTimesheetWrite(fields)
    var xhr = createRequest("PATCH", kimaiUrl, "/api/timesheets/" + timesheetId, apiToken, true)
    runRequest(xhr, JSON.stringify(data), function(status, responseText, statusText) {
        finishTimesheetWrite(status, responseText, statusText, callback)
    })
}

function deleteTimesheet(kimaiUrl, apiToken, timesheetId, callback) {
    if (!kimaiUrl || !apiToken || !timesheetId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("DELETE", kimaiUrl, "/api/timesheets/" + timesheetId, apiToken, false)
    runRequest(xhr, "", function(status, responseText, statusText) {
        if (status >= 200 && status < 300) {
            callback(ok(null))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
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

function localDateString(date) {
    return WorkAdjust.dateKey(date)
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
    holidayPluginByUrl[normalizeUrl(kimaiUrl)] = WorkAdjust.holidayPluginCacheEntry(source, atMs)
}

function holidaySourceFromProbes(holidayTypesStatus, workContractTypesStatus) {
    return WorkAdjust.holidaySourceFromProbes(holidayTypesStatus, workContractTypesStatus)
}

function cachedHolidayPlugin(kimaiUrl, nowMs) {
    return WorkAdjust.holidayPluginCacheSource(holidayPluginByUrl[normalizeUrl(kimaiUrl)], nowMs)
}

function storeHolidayPlugin(kimaiUrl, source) {
    rememberHolidayPlugin(kimaiUrl, source, Date.now())
}

/** Detect kimai-holiday-bundle vs WorkContractBundle. Cached per server URL for one hour. */
function detectHolidayPlugin(kimaiUrl, apiToken, callback) {
    var key = normalizeUrl(kimaiUrl)
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

function fetchWorkContractAbsences(kimaiUrl, apiToken, beginDate, endDate, callback) {
    var begin = encodeURIComponent(localDateString(beginDate))
    var end = encodeURIComponent(localDateString(endDate))
    getJson(kimaiUrl, apiToken, "/api/absences?begin=" + begin + "&end=" + end, [], callback)
}

function fetchWorkContractPublicHolidays(kimaiUrl, apiToken, beginDate, endDate, prefs, callback) {
    var begin = encodeURIComponent(localDateString(beginDate))
    var end = encodeURIComponent(localDateString(endDate))
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
 * plugin is installed. Callback receives ok({ source, absences, publicHolidays }).
 */
function fetchContractAdjustments(kimaiUrl, apiToken, now, prefs, callback) {
    var when = now || new Date()
    detectHolidayPlugin(kimaiUrl, apiToken, function(source) {
        if (source === WorkAdjust.SOURCE_NONE) {
            callback(ok(emptyContractAdjustments(source)))
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
            callback(ok({
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
            var weekBegin = startOfWeekMonday(when)
            var weekEnd = endOfWeekSunday(when)
            fetchWorkContractAbsences(kimaiUrl, apiToken, weekBegin, weekEnd, takeAbsences)
            fetchWorkContractPublicHolidays(kimaiUrl, apiToken, weekBegin, weekEnd, prefs, takeHolidays)
            return
        }

        var year = when.getFullYear()
        fetchHolidayAbsences(kimaiUrl, apiToken, year, takeAbsences)
        fetchHolidayPublicHolidays(kimaiUrl, apiToken, year, takeHolidays)
    })
}

function effectiveWeekTargetSeconds(prefs, date, absences, publicHolidays) {
    return WorkAdjust.effectiveWeekTargetSeconds(prefs, date || new Date(), absences, publicHolidays, workDaySecondsFromPrefs)
}

function effectiveDayTargetSeconds(prefs, date, absences, publicHolidays) {
    return WorkAdjust.effectiveDayTargetSeconds(prefs, date || new Date(), absences, publicHolidays, workDaySecondsFromPrefs)
}

function absenceCreditSeconds(prefs, date, absences, publicHolidays, entries, nowMs) {
    return WorkAdjust.absenceCreditSeconds(
        prefs, date || new Date(), absences, publicHolidays, entries, nowMs, workDaySecondsFromPrefs)
}

function dayAbsenceCreditSeconds(prefs, date, absences, publicHolidays, entries, nowMs) {
    return WorkAdjust.dayAbsenceCreditSeconds(
        prefs, date || new Date(), absences, publicHolidays, entries, nowMs, workDaySecondsFromPrefs)
}

/** Kimai tag catalog for autocomplete (/api/tags/find). Requires `name` query param. */
function tagsFindEndpoint(term) {
    return "/api/tags/find?name=" + encodeURIComponent(String(term || "").trim())
}

function tagEntityName(item) {
    if (typeof item === "string") {
        return String(item).trim()
    }
    return String(item && (item.name || item.tag || item.title) || "").trim()
}

/** Resolved display color from Kimai TagEntity (`color-safe` when explicit color is absent). */
function tagEntityColor(item) {
    if (!item || typeof item !== "object") {
        return DEFAULT_CUSTOMER_COLOR
    }
    var raw = item["color-safe"] || item.color || ""
    if (raw === null || raw === undefined || String(raw).trim().length === 0) {
        var name = tagEntityName(item)
        return name ? colorFromTagName(name) : DEFAULT_CUSTOMER_COLOR
    }
    return normalizeCustomerColor(raw)
}

/** Deterministic accent when Kimai has not assigned an explicit tag color yet. */
function colorFromTagName(name) {
    var s = String(name || "")
    var hash = 0
    for (var i = 0; i < s.length; i++) {
        hash = ((hash << 5) - hash + s.charCodeAt(i)) | 0
    }
    var hue = Math.abs(hash) % 360
    var sNorm = 0.52
    var lNorm = 0.54
    var c = (1 - Math.abs(2 * lNorm - 1)) * sNorm
    var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
    var m = lNorm - c / 2
    var r = 0
    var g = 0
    var b = 0
    if (hue < 60) {
        r = c; g = x; b = 0
    } else if (hue < 120) {
        r = x; g = c; b = 0
    } else if (hue < 180) {
        r = 0; g = c; b = x
    } else if (hue < 240) {
        r = 0; g = x; b = c
    } else if (hue < 300) {
        r = x; g = 0; b = c
    } else {
        r = c; g = 0; b = x
    }
    function hex(n) {
        var v = Math.round((n + m) * 255)
        if (v < 0) v = 0
        if (v > 255) v = 255
        var h = v.toString(16)
        return h.length === 1 ? "0" + h : h
    }
    return "#" + hex(r) + hex(g) + hex(b)
}

function loadTags(kimaiUrl, apiToken, term, callback) {
    getJson(kimaiUrl, apiToken, tagsFindEndpoint(term), [], callback)
}

function localDateTimeString(date) {
    return WorkAdjust.dateKey(date)
        + "T" + WorkAdjust.pad2(date.getHours()) + ":" + WorkAdjust.pad2(date.getMinutes())
        + ":" + WorkAdjust.pad2(date.getSeconds())
}

function startOfLocalDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0, 0)
}

function endOfLocalDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59, 0)
}

function startOfWeekMonday(date) {
    return WorkAdjust.mondayOfWeek(date)
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
            + "&page=" + page + "&size=" + size + "&orderBy=begin&order=ASC&full=1"
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

/** Panel taskbar: MM:SS under 1h, otherwise H:MM:SS with minimum hour digits. */
function formatDurationPanel(seconds) {
    var total = Math.max(0, Math.floor(seconds || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    var mm = (minutes < 10 ? "0" : "") + minutes
    var ss = (secs < 10 ? "0" : "") + secs
    if (hours === 0) {
        return mm + ":" + ss
    }
    return hours + ":" + mm + ":" + ss
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

/**
 * Kimai collection endpoints often return project/activity as bare IDs;
 * detail/recent endpoints embed objects. Accept both.
 */
function entityId(value) {
    if (value === null || value === undefined || value === "") {
        return 0
    }
    if (typeof value === "object") {
        return value.id || 0
    }
    return value
}

function entityName(value) {
    if (!value || typeof value !== "object") {
        return ""
    }
    return value.name || value.title || ""
}

function projectName(timesheet) {
    if (!timesheet) {
        return ""
    }
    return entityName(timesheet.project)
}

function activityName(timesheet) {
    if (!timesheet) {
        return ""
    }
    return entityName(timesheet.activity)
}

/**
 * Best-effort display name: embedded → catalog → empty (caller may show "#id").
 */
function displayActivityName(timesheet, activities, activitiesByProject) {
    if (!timesheet) {
        return ""
    }
    var n = activityName(timesheet)
    if (n) {
        return n
    }
    return resolveActivityName(timesheet, activitiesIndexFromCache(activities, activitiesByProject))
}

function displayProjectName(timesheet, projects) {
    if (!timesheet) {
        return ""
    }
    var n = projectName(timesheet)
    if (n) {
        return n
    }
    return resolveProjectName(timesheet, indexById(projects))
}

/**
 * Resolve a display name, preferring embedded entity name then an id→entity map.
 */
function resolveEntityName(value, byId) {
    var n = entityName(value)
    if (n) {
        return n
    }
    var id = entityId(value)
    if (id && byId) {
        var hit = byId[id] || byId[String(id)]
        if (hit) {
            return entityName(hit) || ""
        }
    }
    return ""
}

function resolveActivityName(timesheet, activitiesById) {
    if (!timesheet) {
        return ""
    }
    return resolveEntityName(timesheet.activity, activitiesById)
}

function resolveProjectName(timesheet, projectsById) {
    if (!timesheet) {
        return ""
    }
    return resolveEntityName(timesheet.project, projectsById)
}

function projectId(timesheet) {
    if (!timesheet) {
        return 0
    }
    return entityId(timesheet.project)
}

function activityId(timesheet) {
    if (!timesheet) {
        return 0
    }
    return entityId(timesheet.activity)
}

function indexById(list) {
    var map = {}
    for (var i = 0; i < (list || []).length; i++) {
        var item = list[i]
        if (!item || item.id === null || item.id === undefined) {
            continue
        }
        map[String(item.id)] = item
    }
    return map
}

function activitiesIndexFromCache(activities, activitiesByProject) {
    var map = indexById(activities)
    var byProject = activitiesByProject || {}
    for (var key in byProject) {
        if (!byProject.hasOwnProperty(key)) {
            continue
        }
        var list = byProject[key] || []
        for (var i = 0; i < list.length; i++) {
            var act = list[i]
            if (act && act.id !== null && act.id !== undefined) {
                map[String(act.id)] = act
            }
        }
    }
    return map
}

/** Shallow-merge cached entity fields onto a partial API object (names/colors). */
function mergeEntity(partial, cached) {
    if (!cached) {
        return partial
    }
    if (!partial) {
        return cached
    }
    var out = {}
    var k
    for (k in partial) {
        if (partial.hasOwnProperty(k)) {
            out[k] = partial[k]
        }
    }
    for (k in cached) {
        if (!cached.hasOwnProperty(k)) {
            continue
        }
        if (out[k] === null || out[k] === undefined || out[k] === "") {
            out[k] = cached[k]
        }
    }
    return out
}

/**
 * Expand bare project/activity IDs on timesheets using local caches so
 * stats grouping and legends get real names/colors.
 * Never replaces an embedded name with a blank cached name.
 */
function hydrateTimesheets(entries, projects, activities, activitiesByProject) {
    var projectsById = indexById(projects)
    var activitiesById = activitiesIndexFromCache(activities, activitiesByProject)
    var out = []
    for (var i = 0; i < (entries || []).length; i++) {
        var ts = entries[i]
        if (!ts) {
            continue
        }
        var pid = projectId(ts)
        var aid = activityId(ts)
        var projectObj = (typeof ts.project === "object" && ts.project) ? ts.project : null
        var activityObj = (typeof ts.activity === "object" && ts.activity) ? ts.activity : null

        if (pid && projectsById[String(pid)]) {
            var cachedProject = projectsById[String(pid)]
            if (!projectObj) {
                projectObj = cachedProject
            } else {
                projectObj = mergeEntity(projectObj, cachedProject)
            }
        }
        if (aid && activitiesById[String(aid)]) {
            var cachedActivity = activitiesById[String(aid)]
            if (!activityObj) {
                activityObj = cachedActivity
            } else {
                activityObj = mergeEntity(activityObj, cachedActivity)
            }
        }

        // Normalize scalar IDs into stub objects so callers always see .name/.id
        if (!projectObj && pid) {
            projectObj = { id: pid, name: "" }
        }
        if (!activityObj && aid) {
            activityObj = { id: aid, name: "" }
        }
        if (projectObj && !entityName(projectObj) && projectsById[String(pid)]) {
            projectObj = mergeEntity(projectObj, projectsById[String(pid)])
        }
        if (activityObj && !entityName(activityObj) && activitiesById[String(aid)]) {
            activityObj = mergeEntity(activityObj, activitiesById[String(aid)])
        }

        var changed = projectObj !== ts.project || activityObj !== ts.activity
            || (typeof ts.project !== "object") || (typeof ts.activity !== "object")
        if (changed) {
            var copy = {}
            for (var k in ts) {
                if (ts.hasOwnProperty(k)) {
                    copy[k] = ts[k]
                }
            }
            if (projectObj) {
                copy.project = projectObj
            }
            if (activityObj) {
                copy.activity = activityObj
            }
            Fields.attachKimaiShape(copy, ts)
            out.push(copy)
        } else {
            Fields.attachKimaiShape(ts, ts)
            out.push(ts)
        }
    }
    return out
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
