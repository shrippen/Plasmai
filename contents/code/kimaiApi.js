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

function testConnection(kimaiUrl, apiToken, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("GET", kimaiUrl, "/api/version", apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, {})))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function fetchActiveTimesheet(kimaiUrl, apiToken, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("GET", kimaiUrl, "/api/timesheets/active", apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, [])))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function fetchRecentTimesheets(kimaiUrl, apiToken, size, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var count = size || 10
    var xhr = createRequest("GET", kimaiUrl, "/api/timesheets/recent?size=" + count, apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, [])))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function loadProjects(kimaiUrl, apiToken, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("GET", kimaiUrl, "/api/projects?visible=3&order=ASC&orderBy=name", apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, [])))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function loadCustomers(kimaiUrl, apiToken, callback) {
    if (!kimaiUrl || !apiToken) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("GET", kimaiUrl, "/api/customers?visible=3&order=ASC&orderBy=name", apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, [])))
        } else {
            callback(fail(parseApiError(status, statusText, responseText)))
        }
    })
}

function loadActivities(kimaiUrl, apiToken, projectId, callback) {
    if (!kimaiUrl || !apiToken || !projectId) {
        callback(fail({ type: "config", status: 0, detail: "" }))
        return
    }

    var xhr = createRequest("GET", kimaiUrl, "/api/activities?project=" + projectId + "&visible=3&order=ASC&orderBy=name", apiToken, false)
    runRequest(xhr, undefined, function(status, responseText, statusText) {
        if (status === 200) {
            callback(ok(parseJson(responseText, [])))
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
            color: customer.color || "#d2d6de"
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
        return "#d2d6de"
    }
    if (typeof project.customer === "object" && project.customer && project.customer.color) {
        return project.customer.color
    }
    var cid = customerIdOfProject(project)
    if (cid && customersById && customersById[cid] && customersById[cid].color) {
        return customersById[cid].color
    }
    return "#d2d6de"
}

function customerColorFromTimesheet(timesheet, customersById) {
    if (!timesheet || !timesheet.project) {
        return "#d2d6de"
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
    var customersById = buildCustomersById(customers)
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
            color: row.customerColor || "#d2d6de",
            value: row.project
        })
    }
    return items
}

function activityPickerItems(activities, projectId) {
    var split = splitActivitiesForProject(activities, projectId)
    var items = []
    var i
    for (i = 0; i < split.projectSpecific.length; i++) {
        var specific = split.projectSpecific[i]
        items.push({
            label: specific.name,
            searchText: specific.name,
            section: "project",
            color: "",
            value: specific
        })
    }
    for (i = 0; i < split.global.length; i++) {
        var globalAct = split.global[i]
        items.push({
            label: globalAct.name,
            searchText: globalAct.name,
            section: "global",
            color: "",
            value: globalAct
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

function formatDuration(seconds) {
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    var secs = seconds % 60
    return (hours < 10 ? "0" : "") + hours + ":" +
           (minutes < 10 ? "0" : "") + minutes + ":" +
           (secs < 10 ? "0" : "") + secs
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
